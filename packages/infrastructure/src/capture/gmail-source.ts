import {
  type BillSource,
  type CapturedBill,
  type LlmAttachment,
} from '@cashdeck/application'
import { findPaymentCodes, type LocalDate, toLocalDate } from '@cashdeck/domain'
import {
  type Credentials,
  requireCredentials,
} from '@/credentials/credential-resolver'
import {
  isSuccess,
  ProviderHttpError,
  readJson,
  send,
  type Transport,
} from '@/http/transport'
import {
  type BillExtractor,
  type ExtractedBill,
  toExtracted,
} from '@/capture/bill-extractor'

const PROVIDER = 'Gmail'
const TOKEN_URL = 'https://oauth2.googleapis.com/token'
const API = 'https://gmail.googleapis.com/gmail/v1/users/me'

export const GMAIL_QUERY =
  '{boleto fatura "linha digitavel" "linha digitável" "codigo de barras" "código de barras" DARF DAS "pix copia e cola" vencimento}'

const READABLE = /^(application\/pdf|image\/(png|jpe?g|webp))$/
const MAX_ATTACHMENT_BYTES = 10 * 1024 * 1024

type MessagePart = {
  partId?: string
  mimeType?: string
  filename?: string
  body?: { data?: string; attachmentId?: string; size?: number }
  parts?: MessagePart[]
}

type Message = {
  id: string
  payload?: MessagePart & { headers?: Array<{ name: string; value: string }> }
}

type ListAnswer = {
  messages?: Array<{ id: string }>
  nextPageToken?: string
}

export type GmailSourceDeps = {
  credentials: Credentials
  transport: Transport
  extractor?: BillExtractor
  now?: () => Date
  maxMessages?: number
}

type Session = { token: string }

export class GmailBillSource implements BillSource {
  readonly source = 'GMAIL' as const

  constructor(private readonly deps: GmailSourceDeps) {}

  async fetch(
    tenantId: string,
    entityId: string,
    since: Date,
  ): Promise<CapturedBill[]> {
    const session = await this.session(tenantId, entityId)
    const today = toLocalDate((this.deps.now ?? (() => new Date()))())
    const ids = await this.messageIds(session, since)
    const bills: CapturedBill[] = []
    for (const id of ids) {
      bills.push(...(await this.readMessage(session, id, today)))
    }
    return bills
  }

  private async session(tenantId: string, entityId: string): Promise<Session> {
    const values = await requireCredentials(
      this.deps.credentials,
      PROVIDER,
      ['GMAIL_CLIENT_ID', 'GMAIL_CLIENT_SECRET', 'GMAIL_REFRESH_TOKEN'],
      { tenantId, entityId },
    )
    const response = await send(this.deps.transport, {
      method: 'POST',
      url: TOKEN_URL,
      form: {
        client_id: values.GMAIL_CLIENT_ID,
        client_secret: values.GMAIL_CLIENT_SECRET,
        refresh_token: values.GMAIL_REFRESH_TOKEN,
        grant_type: 'refresh_token',
      },
    })
    if (!isSuccess(response)) {
      throw new ProviderHttpError(
        PROVIDER,
        response.status,
        'the refresh token was refused',
      )
    }
    const answer = readJson<{ access_token?: string }>(response)
    return { token: answer.access_token ?? '' }
  }

  private async get<T>(session: Session, path: string): Promise<T> {
    const response = await send(this.deps.transport, {
      method: 'GET',
      url: `${API}${path}`,
      headers: { authorization: `Bearer ${session.token}` },
    })
    if (!isSuccess(response)) {
      throw new ProviderHttpError(PROVIDER, response.status, response.text)
    }
    return readJson<T>(response)
  }

  private async messageIds(session: Session, since: Date): Promise<string[]> {
    const limit = this.deps.maxMessages ?? 50
    const after = Math.floor(since.getTime() / 1000)
    const ids: string[] = []
    let pageToken: string | undefined
    do {
      const params = new URLSearchParams({
        q: `after:${after} ${GMAIL_QUERY}`,
        maxResults: String(Math.min(limit, 100)),
      })
      if (pageToken) {
        params.set('pageToken', pageToken)
      }
      const answer = await this.get<ListAnswer>(
        session,
        `/messages?${params.toString()}`,
      )
      ids.push(...(answer.messages ?? []).map(message => message.id))
      pageToken = answer.nextPageToken
    } while (pageToken && ids.length < limit)
    return ids.slice(0, limit)
  }

  private async readMessage(
    session: Session,
    id: string,
    today: LocalDate,
  ): Promise<CapturedBill[]> {
    const message = await this.get<Message>(
      session,
      `/messages/${id}?format=full`,
    )
    const parts = flattenParts(message.payload)
    const payee = sender(message)
    const found: ExtractedBill[] = []
    for (const part of parts.filter(isReadableAttachment)) {
      const extracted = await this.readAttachment(session, id, part, today)
      if (extracted) {
        found.push(extracted)
      }
    }
    const text = parts.filter(isText).map(decodeBody).join('\n')
    const fromText = toExtracted(findPaymentCodes(text, today), today, {
      payee,
    })
    return withBody(found, fromText, today).map((bill, index) =>
      toCaptured(`${id}:${index}`, bill, payee),
    )
  }

  private async readAttachment(
    session: Session,
    messageId: string,
    part: MessagePart,
    today: LocalDate,
  ): Promise<ExtractedBill | null> {
    if (!this.deps.extractor) {
      return null
    }
    const attachment = await this.get<{ data?: string }>(
      session,
      `/messages/${messageId}/attachments/${part.body?.attachmentId}`,
    )
    const bytes = Buffer.from(attachment.data ?? '', 'base64url')
    const llmAttachment: LlmAttachment = {
      mimeType: part.mimeType ?? 'application/pdf',
      dataBase64: bytes.toString('base64'),
    }
    return this.deps.extractor.fromAttachment(llmAttachment, today)
  }
}

function flattenParts(part: MessagePart | undefined): MessagePart[] {
  if (!part) {
    return []
  }
  return [part, ...(part.parts ?? []).flatMap(flattenParts)]
}

function isReadableAttachment(part: MessagePart): boolean {
  return (
    Boolean(part.body?.attachmentId) &&
    READABLE.test(part.mimeType ?? '') &&
    (part.body?.size ?? 0) <= MAX_ATTACHMENT_BYTES
  )
}

function isText(part: MessagePart): boolean {
  return (
    (part.mimeType === 'text/plain' || part.mimeType === 'text/html') &&
    Boolean(part.body?.data)
  )
}

function decodeBody(part: MessagePart): string {
  const text = Buffer.from(part.body?.data ?? '', 'base64url').toString('utf8')
  return part.mimeType === 'text/html' ? text.replace(/<[^>]+>/g, ' ') : text
}

function sender(message: Message): string | null {
  const from = message.payload?.headers?.find(
    header => header.name.toLowerCase() === 'from',
  )?.value
  if (!from) {
    return null
  }
  return (
    from
      .replace(/<[^>]*>/g, '')
      .replace(/"/g, '')
      .trim() || null
  )
}

const differ = (a: string | null, b: string | null) =>
  a !== null && b !== null && a !== b

function conflicts(a: ExtractedBill, b: ExtractedBill): boolean {
  return differ(a.barcode, b.barcode) || differ(a.pixCode, b.pixCode)
}

function joined(
  bill: ExtractedBill,
  other: ExtractedBill,
  today: LocalDate,
): ExtractedBill {
  const codes = {
    barcode: bill.barcode ?? other.barcode,
    pixCode: bill.pixCode ?? other.pixCode,
  }
  const hints = {
    payee: bill.payee ?? other.payee,
    amountCents: bill.amountCents ?? other.amountCents,
    dueDate: bill.dueDate ?? other.dueDate,
  }
  return toExtracted(codes, today, hints) ?? bill
}

// A bolepix e-mail often attaches the PDF with the barcode and prints the Pix
// copy and paste in the body: the body completes the first bill it fits.
function withBody(
  found: ExtractedBill[],
  body: ExtractedBill | null,
  today: LocalDate,
): ExtractedBill[] {
  if (!body) {
    return found
  }
  const index = found.findIndex(bill => !conflicts(bill, body))
  if (index === -1) {
    return [...found, body]
  }
  return found.map((bill, at) =>
    at === index ? joined(bill, body, today) : bill,
  )
}

function toCaptured(
  externalId: string,
  bill: ExtractedBill,
  payee: string | null,
): CapturedBill {
  return {
    externalId,
    paymentCode: bill.barcode ?? bill.pixCode,
    pixCode: bill.pixCode,
    payee: bill.payee ?? payee,
    amountCents: bill.amountCents,
    dueDate: bill.dueDate,
    kind: bill.kind,
  }
}
