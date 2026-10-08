import { createHmac, timingSafeEqual } from 'node:crypto'
import {
  type InvoiceDraft,
  type InvoiceIssuer,
  type IssuedInvoice,
  type ProviderCheck,
} from '@cashdeck/application'
import { toLocalDate, ValidationError } from '@cashdeck/domain'
import {
  type Credentials,
  optionalCredential,
  requireCredentials,
} from '@/credentials/credential-resolver'
import {
  type Call,
  isSuccess,
  ProviderHttpError,
  readJson,
  safeJson,
  send,
  toDecimal,
  type Transport,
} from '@/http/transport'
import { checkWith } from '@/rails/rail-support'

const PROVIDER = 'Notaas'
export const NOTAAS_URL = 'https://platform.notaas.com.br/api/v1'

// BACEN currency codes for the export block; others are refused until mapped.
const BACEN_CURRENCY: Record<string, string> = { USD: '220', EUR: '978' }

const STATUS: Record<string, IssuedInvoice['status']> = {
  queued: 'PROCESSING',
  processing: 'PROCESSING',
  issued: 'ISSUED',
  error: 'REJECTED',
  cancelled: 'CANCELLED',
}

type StatusAnswer = {
  invoiceId?: string
  status?: string
  numeroNfe?: string | number | null
  pdfUrl?: string | null
  xmlUrl?: string | null
  errorMessage?: string | null
}

export type NotaasIssuerDeps = {
  credentials: Credentials
  transport: Transport
  now?: () => Date
}

export class NotaasIssuer implements InvoiceIssuer {
  readonly id = 'notaas'

  constructor(private readonly deps: NotaasIssuerDeps) {}

  async issue(
    draft: InvoiceDraft,
    idempotencyKey: string,
  ): Promise<IssuedInvoice> {
    const scope = { tenantId: draft.tenantId, entityId: draft.entityId }
    const body = await this.emission(draft, idempotencyKey, scope)
    const answer = await this.call<StatusAnswer>(
      { method: 'POST', url: `${NOTAAS_URL}/emitir`, json: body },
      scope,
    )
    return toIssued(answer)
  }

  async get(externalId: string): Promise<IssuedInvoice> {
    const answer = await this.call<StatusAnswer>({
      method: 'GET',
      url: `${NOTAAS_URL}/invoices/${encodeURIComponent(externalId)}/status`,
    })
    return toIssued({ invoiceId: externalId, ...answer })
  }

  async cancel(externalId: string, reason: string): Promise<IssuedInvoice> {
    const motivo = reason.trim()
    if (motivo.length < 15 || motivo.length > 255) {
      throw new ValidationError(
        'A cancellation reason needs 15 to 255 characters.',
      )
    }
    await this.call<unknown>({
      method: 'POST',
      url: `${NOTAAS_URL}/cancelar`,
      json: { invoiceId: externalId, motivo },
    })
    return this.get(externalId)
  }

  async check(): Promise<ProviderCheck> {
    return checkWith(PROVIDER, async () => {
      await this.call<unknown>({
        method: 'GET',
        url: `${NOTAAS_URL}/webhooks/endpoints`,
      })
    })
  }

  private async emission(
    draft: InvoiceDraft,
    idempotencyKey: string,
    scope: { tenantId: string; entityId: string },
  ): Promise<Record<string, unknown>> {
    const now = (this.deps.now ?? (() => new Date()))()
    const servico: Record<string, unknown> = {
      descricao: draft.description,
      codigo: draft.serviceCode,
    }
    const local = await this.deps.credentials.get(
      'NOTAAS_LOCAL_PRESTACAO',
      scope,
    )
    if (local) {
      servico.localPrestacao = local
    }
    return {
      tomador: await this.tomador(draft, scope),
      servico,
      valores: await this.valores(draft, scope),
      competencia: toLocalDate(now).slice(0, 7),
      // Notaas documents no idempotency header; the reference ties retries to one key.
      referencia: idempotencyKey,
    }
  }

  private async tomador(
    draft: InvoiceDraft,
    scope: { tenantId: string; entityId: string },
  ): Promise<Record<string, unknown>> {
    const digits = (draft.clientTaxId ?? '').replace(/\D/g, '')
    if (!draft.export && digits.length === 11) {
      return { cpf: digits, nome: draft.clientName }
    }
    if (!draft.export && digits.length === 14) {
      return { cnpj: digits, nome: draft.clientName }
    }
    if (!draft.export) {
      throw new ValidationError(
        'A domestic invoice needs the client CPF or CNPJ.',
      )
    }
    const country = await this.exportCountry(scope)
    return {
      nome: draft.clientName,
      ...(draft.clientTaxId ? { nif: draft.clientTaxId } : {}),
      endereco: { pais: country, uf: 'EX' },
    }
  }

  private async valores(
    draft: InvoiceDraft,
    scope: { tenantId: string; entityId: string },
  ): Promise<Record<string, unknown>> {
    const brlCents = brlTotal(draft)
    if (!draft.export) {
      const { NOTAAS_ALIQUOTA_ISS } = await requireCredentials(
        this.deps.credentials,
        PROVIDER,
        ['NOTAAS_ALIQUOTA_ISS'],
        scope,
      )
      return {
        total: toDecimal(brlCents),
        aliquotaIss: Number(NOTAAS_ALIQUOTA_ISS),
      }
    }
    const exportacao: Record<string, unknown> = {
      paisResultado: await this.exportCountry(scope),
    }
    if (draft.currency !== 'BRL') {
      const code = BACEN_CURRENCY[draft.currency]
      if (!code) {
        throw new ValidationError(
          `Notaas has no currency code for ${draft.currency}.`,
        )
      }
      exportacao.codigoMoeda = code
      exportacao.valorServicoMoeda = toDecimal(draft.amountCents)
    }
    return { total: toDecimal(brlCents), aliquotaIss: 0, exportacao }
  }

  private async exportCountry(scope: {
    tenantId: string
    entityId: string
  }): Promise<string> {
    return optionalCredential(
      this.deps.credentials,
      'NOTAAS_EXPORT_COUNTRY',
      'US',
      scope,
    )
  }

  private async call<T>(
    request: Call,
    scope: { tenantId?: string; entityId?: string } = {},
  ): Promise<T> {
    const { NOTAAS_API_KEY } = await requireCredentials(
      this.deps.credentials,
      PROVIDER,
      ['NOTAAS_API_KEY'],
      scope,
    )
    const response = await send(this.deps.transport, {
      ...request,
      headers: { 'x-api-key': NOTAAS_API_KEY },
    })
    if (!isSuccess(response)) {
      const body = safeJson(response.text) as {
        message?: string
        error?: string
      } | null
      throw new ProviderHttpError(
        PROVIDER,
        response.status,
        body?.message ?? body?.error ?? 'request refused',
      )
    }
    return readJson<T>(response)
  }
}

function brlTotal(draft: InvoiceDraft): number {
  if (draft.currency === 'BRL') {
    return draft.amountCents
  }
  if (!draft.brlAmountCents) {
    throw new ValidationError('A foreign currency invoice needs its BRL total.')
  }
  return draft.brlAmountCents
}

function toIssued(answer: StatusAnswer): IssuedInvoice {
  return {
    externalId: answer.invoiceId ?? '',
    number:
      answer.numeroNfe === null || answer.numeroNfe === undefined
        ? null
        : String(answer.numeroNfe),
    status: STATUS[answer.status ?? ''] ?? 'PROCESSING',
    pdfUrl: answer.pdfUrl ?? null,
    xmlUrl: answer.xmlUrl ?? null,
  }
}

// X-Notaas-Signature is `sha256=` plus the hex HMAC-SHA256 of the raw body.
export function verifyNotaasSignature(
  rawBody: string,
  header: string | null,
  secret: string,
): boolean {
  if (!header?.startsWith('sha256=')) {
    return false
  }
  const expected = createHmac('sha256', secret).update(rawBody).digest()
  const given = Buffer.from(header.slice('sha256='.length), 'hex')
  return given.length === expected.length && timingSafeEqual(given, expected)
}
