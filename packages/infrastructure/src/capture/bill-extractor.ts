import {
  type LlmAttachment,
  type LlmProvider,
  type LlmToolParameter,
} from '@cashdeck/application'
import {
  type BillKind,
  billKindFor,
  decodePaymentCode,
  type LocalDate,
  parseBrCode,
} from '@cashdeck/domain'

export type ExtractedBill = {
  barcode: string | null
  pixCode: string | null
  payee: string | null
  amountCents: number | null
  dueDate: LocalDate | null
  kind: BillKind | null
}

const DIGIT_RUN = /\d[\d.\s-]{42,62}\d/g
const BR_CODE = /000201[\x20-\x7E]+?6304[0-9A-Fa-f]{4}/g
const DATE = /^\d{4}-\d{2}-\d{2}$/

type Candidate = { barcode: string | null; pixCode: string | null }

function validBarcode(raw: string, today: LocalDate): string | null {
  const digits = raw.replace(/\D/g, '')
  try {
    const decoded = decodePaymentCode(digits, today)
    return decoded.type === 'PIX' ? null : digits
  } catch {
    return null
  }
}

// The checksum rejects a code the model misread, so a Pix code is only kept
// when it is exact.
function validPixCode(raw: string): string | null {
  try {
    return parseBrCode(raw.trim()).payload
  } catch {
    return null
  }
}

export function findCodesInText(text: string, today: LocalDate): Candidate {
  const flat = text.replace(/\r?\n/g, '')
  const barcode =
    (text.match(DIGIT_RUN) ?? [])
      .map(run => validBarcode(run, today))
      .find(code => code !== null) ?? null
  const pixCode =
    (flat.match(BR_CODE) ?? []).map(validPixCode).find(code => code !== null) ??
    null
  return { barcode, pixCode }
}

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
  constructor(private readonly llm: LlmProvider) {}

  async fromAttachment(
    attachment: LlmAttachment,
    today: LocalDate,
  ): Promise<ExtractedBill | null> {
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
    const answer = (result.object ?? {}) as LlmAnswer
    const candidate = {
      barcode: answer.barcode ? validBarcode(answer.barcode, today) : null,
      pixCode: answer.pixCode ? validPixCode(answer.pixCode) : null,
    }
    const amount = Number(answer.amount)
    return toExtracted(candidate, today, {
      payee: answer.payee,
      amountCents:
        Number.isFinite(amount) && amount > 0 ? Math.round(amount * 100) : null,
      dueDate: answer.dueDate,
    })
  }
}
