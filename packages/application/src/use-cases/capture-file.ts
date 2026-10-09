import {
  findPaymentCodes,
  type FoundCodes,
  type LocalDate,
  toLocalDate,
  validBarcode,
  validBrCode,
  ValidationError,
} from '@cashdeck/domain'
import { type z } from 'zod'
import { captureBillSchema } from '@/dtos/bill'
import { type captureFileSchema, fileReadingSchema } from '@/dtos/capture'
import { isoDate } from '@/dtos/common'
import { type LlmToolParameter } from '@/ports/llm-provider'
import {
  type CaptureBillResult,
  makeCaptureBill,
} from '@/use-cases/capture-bill'
import { type Deps } from '@/use-cases/deps'
import { decodeUpload, requireEntity } from '@/use-cases/shared'

type CaptureFileInput = z.infer<typeof captureFileSchema>
type FileReading = z.infer<typeof fileReadingSchema>

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

const filled = (value: string | undefined) => value?.trim() || undefined

// Codes the model misread are dropped like BillExtractor does, so a mistyped
// Pix code leaves the barcode bill instead of failing the upload.
function codesOf(
  local: FoundCodes,
  reading: FileReading | null,
  today: LocalDate,
): FoundCodes {
  return {
    barcode: local.barcode ?? validBarcode(reading?.paymentCode ?? '', today),
    pixCode: local.pixCode ?? validBrCode(reading?.pixCode ?? ''),
  }
}

function readAmount(input: CaptureFileInput, reading: FileReading | null) {
  if (input.amountCents) {
    return input.amountCents
  }
  const amount = reading?.amount ?? 0
  return amount > 0 ? Math.round(amount * 100) : undefined
}

function readDueDate(input: CaptureFileInput, reading: FileReading | null) {
  const printed = filled(reading?.dueDate)
  return (
    input.dueDate ?? (isoDate.safeParse(printed).success ? printed : undefined)
  )
}

export function makeCaptureFile(deps: Deps) {
  const captureBill = makeCaptureBill(deps)

  async function readWithModel(
    input: CaptureFileInput,
  ): Promise<FileReading | null> {
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
    return parsed.success ? parsed.data : null
  }

  // The text layer gives the exact codes; the model still reads the payee and
  // any code only drawn as an image. Without local codes its failure is final.
  async function readFile(
    input: CaptureFileInput,
    local: FoundCodes,
  ): Promise<FileReading | null> {
    const hasLocal = local.barcode !== null || local.pixCode !== null
    try {
      return await readWithModel(input)
    } catch (error) {
      if (!hasLocal) {
        throw error
      }
      return null
    }
  }

  return async function captureFile(
    tenantId: string,
    input: CaptureFileInput,
  ): Promise<CaptureBillResult> {
    const entity = await requireEntity(deps.entities, tenantId, input.entity)
    const bytes = decodeUpload(input.base64)
    const today = toLocalDate(deps.clock.now())
    const pageText = await deps.documentText.read({
      mimeType: input.mimeType,
      bytes,
    })
    const local = findPaymentCodes(pageText ?? '', today)
    const reading = await readFile(input, local)
    const codes = codesOf(local, reading, today)
    if (!reading && !codes.barcode && !codes.pixCode) {
      throw new ValidationError('The file could not be read.')
    }
    if (!codes.barcode && !codes.pixCode) {
      throw new ValidationError('No payment code was found in the file.')
    }
    const result = await captureBill(
      tenantId,
      captureBillSchema.parse({
        entityId: entity.id,
        source: 'SHARE',
        paymentCode: codes.barcode ?? undefined,
        pixCode: codes.pixCode ?? undefined,
        payee: filled(reading?.payee),
        amountCents: readAmount(input, reading),
        dueDate: readDueDate(input, reading),
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
