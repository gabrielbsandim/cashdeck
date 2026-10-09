import {
  type DocumentTextReader,
  type LlmAttachment,
  type LlmProvider,
  type LlmToolParameter,
} from '@cashdeck/application'
import {
  type BillKind,
  billKindFor,
  decodePaymentCode,
  findPaymentCodes,
  type FoundCodes,
  type LocalDate,
  validBarcode,
  validBrCode,
} from '@cashdeck/domain'

export type ExtractedBill = {
  barcode: string | null
  pixCode: string | null
  payee: string | null
  amountCents: number | null
  dueDate: LocalDate | null
  kind: BillKind | null
}

const DATE = /^\d{4}-\d{2}-\d{2}$/

type Candidate = FoundCodes

function kindOf(candidate: Candidate, today: LocalDate): BillKind | null {
  if (candidate.barcode) {
    return billKindFor(decodePaymentCode(candidate.barcode, today))
  }
  return candidate.pixCode ? 'PIX_QR' : null
}

type CodeFacts = { amountCents: number | null; dueDate: LocalDate | null }

function factsFromCodes(candidate: Candidate, today: LocalDate): CodeFacts {
  const code = candidate.barcode ?? candidate.pixCode
  if (!code) {
    return { amountCents: null, dueDate: null }
  }
  const decoded = decodePaymentCode(code, today)
  const dueDate = decoded.type === 'BOLETO' ? decoded.dueDate : null
  return { amountCents: decoded.amount?.cents ?? null, dueDate }
}

export function toExtracted(
  candidate: Candidate,
  today: LocalDate,
  hints: {
    payee?: string | null
    amountCents?: number | null
    dueDate?: string | null
  } = {},
): ExtractedBill | null {
  if (!candidate.barcode && !candidate.pixCode) {
    return null
  }
  const facts = factsFromCodes(candidate, today)
  const hinted =
    hints.dueDate && DATE.test(hints.dueDate) ? hints.dueDate : null
  return {
    ...candidate,
    payee: hints.payee?.trim() || null,
    amountCents: facts.amountCents ?? hints.amountCents ?? null,
    dueDate: facts.dueDate ?? hinted,
    kind: kindOf(candidate, today),
  }
}

const SCHEMA: LlmToolParameter = {
  type: 'object',
  properties: {
    barcode: {
      type: 'string',
      description:
        'The boleto or tax guide digitable line or barcode digits exactly as printed, or empty.',
    },
    pixCode: {
      type: 'string',
      description:
        'The Pix copy and paste code (starts with 000201) printed or encoded in the QR code, or empty.',
    },
    payee: { type: 'string', description: 'Who receives the payment.' },
    amount: {
      type: 'string',
      description: 'Amount due as a decimal, like 123.45.',
    },
    dueDate: { type: 'string', description: 'Due date as YYYY-MM-DD.' },
  },
  required: ['barcode', 'pixCode'],
}

const SYSTEM =
  'You read Brazilian bills (boleto, bolepix, DARF, DAS, card bills). ' +
  'Return the payment codes exactly as printed; never invent or complete digits. ' +
  'Leave a field empty when it is not on the document.'

type LlmAnswer = {
  barcode?: string
  pixCode?: string
  payee?: string
  amount?: string
  dueDate?: string
}

export class BillExtractor {
  constructor(
    private readonly llm: LlmProvider,
    private readonly text?: DocumentTextReader,
  ) {}

  // Codes in the text layer are exact; the model only fills what it lacks, so
  // a 150 character Pix code no longer depends on the model copying it.
  async fromAttachment(
    attachment: LlmAttachment,
    today: LocalDate,
  ): Promise<ExtractedBill | null> {
    const local = await this.localCodes(attachment, today)
    const answer = await this.ask(attachment)
    const candidate = {
      barcode:
        local.barcode ??
        (answer.barcode ? validBarcode(answer.barcode, today) : null),
      pixCode:
        local.pixCode ?? (answer.pixCode ? validBrCode(answer.pixCode) : null),
    }
    const amount = Number(answer.amount)
    return toExtracted(candidate, today, {
      payee: answer.payee,
      amountCents:
        Number.isFinite(amount) && amount > 0 ? Math.round(amount * 100) : null,
      dueDate: answer.dueDate,
    })
  }

  private async localCodes(
    attachment: LlmAttachment,
    today: LocalDate,
  ): Promise<Candidate> {
    const text = await this.text?.read({
      mimeType: attachment.mimeType,
      bytes: Buffer.from(attachment.dataBase64, 'base64'),
    })
    return findPaymentCodes(text ?? '', today)
  }

  private async ask(attachment: LlmAttachment): Promise<LlmAnswer> {
    const result = await this.llm.chat({
      system: SYSTEM,
      messages: [
        {
          role: 'user',
          content: 'Extract the payment data of this bill.',
          attachments: [attachment],
        },
      ],
      tools: [],
      maxInputTokens: 32_000,
      maxOutputTokens: 1_024,
      temperature: 0,
      responseSchema: SCHEMA,
    })
    return (result.object ?? {}) as LlmAnswer
  }
}
