import { ValidationError } from '@cashdeck/domain'
import { type z } from 'zod'
import { captureBillSchema } from '@/dtos/bill'
import { type captureFileSchema, fileReadingSchema } from '@/dtos/capture'
import { type LlmToolParameter } from '@/ports/llm-provider'
import {
  type CaptureBillResult,
  makeCaptureBill,
} from '@/use-cases/capture-bill'
import { type Deps } from '@/use-cases/deps'
import { decodeUpload, requireEntity } from '@/use-cases/shared'

const SYSTEM =
  'You read Brazilian bills: boletos, tax guides and Pix charges. Copy codes ' +
  'exactly as printed, digits only for a boleto line. Leave a field empty when ' +
  'the document does not show it.'

const text = (description: string): LlmToolParameter => ({
  type: 'string',
  description,
})

const READING_SCHEMA: LlmToolParameter = {
  type: 'object',
  properties: {
    paymentCode: text('Boleto or tax guide digitable line, or empty'),
    pixCode: text('Pix copy and paste code (BR Code), or empty'),
    payee: text('Who receives the payment, or empty'),
    amount: { type: 'number', description: 'Amount in BRL, 0 when absent' },
    dueDate: text('Due date, YYYY-MM-DD, or empty'),
  },
  required: ['paymentCode', 'pixCode', 'payee', 'amount', 'dueDate'],
}

const filled = (value: string) => value.trim() || undefined

export function makeCaptureFile(deps: Deps) {
  const captureBill = makeCaptureBill(deps)

  return async function captureFile(
    tenantId: string,
    input: z.infer<typeof captureFileSchema>,
  ): Promise<CaptureBillResult> {
    const entity = await requireEntity(deps.entities, tenantId, input.entity)
    const bytes = decodeUpload(input.base64)
    const reply = await deps.llm.chat({
      system: SYSTEM,
      messages: [
        {
          role: 'user',
          content: 'Read this bill.',
          attachments: [{ mimeType: input.mimeType, dataBase64: input.base64 }],
        },
      ],
      tools: [],
      maxInputTokens: 30_000,
      maxOutputTokens: 1_000,
      temperature: 0,
      responseSchema: READING_SCHEMA,
    })
    const parsed = fileReadingSchema.safeParse(reply.object)
    if (!parsed.success) {
      throw new ValidationError('The file could not be read.')
    }
    const reading = parsed.data
    if (!filled(reading.paymentCode) && !filled(reading.pixCode)) {
      throw new ValidationError('No payment code was found in the file.')
    }
    const result = await captureBill(
      tenantId,
      captureBillSchema.parse({
        entityId: entity.id,
        source: 'SHARE',
        paymentCode: filled(reading.paymentCode),
        pixCode: filled(reading.pixCode),
        payee: filled(reading.payee),
        amountCents:
          reading.amount > 0 ? Math.round(reading.amount * 100) : undefined,
        dueDate: filled(reading.dueDate),
      }),
    )
    if (result.duplicate) {
      return result
    }
    await deps.attachments.save({
      id: deps.ids.next(),
      tenantId,
      billId: result.bill.id,
      fileName: input.fileName,
      mimeType: input.mimeType,
      size: bytes.length,
      createdAt: deps.clock.now(),
      bytes,
    })
    return result
  }
}
