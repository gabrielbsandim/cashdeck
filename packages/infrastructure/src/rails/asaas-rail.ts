import {
  type PaymentRail,
  type PaymentRequest,
  type ProviderCheck,
  type RailResult,
  type RailStatus,
  type RailStatusReader,
  type RailStatusScope,
} from '@cashdeck/application'
import {
  type Bill,
  type BillKind,
  type EntityKind,
  type PaymentMethod,
} from '@cashdeck/domain'
import {
  type Credentials,
  type CredentialScope,
  optionalCredential,
  requireCredentials,
} from '@/credentials/credential-resolver'
import {
  type Call,
  isAuthError,
  isClientError,
  isSuccess,
  ProviderHttpError,
  readJson,
  send,
  toCents,
  toDecimal,
  type Transport,
} from '@/http/transport'
import {
  decodePix,
  normalizePixKey,
  paymentDescription,
  pixKeyType,
  pixPayloadOf,
  staticAmountMismatch,
} from '@/rails/pix'
import {
  checkWith,
  type Coverage,
  covers,
  failed,
  outcomeFrom,
  scopeOf,
  splitExternalId,
  statusResult,
} from '@/rails/rail-support'

const PROVIDER = 'Asaas'

export const ASAAS_URLS = {
  production: 'https://api.asaas.com/v3',
  sandbox: 'https://api-sandbox.asaas.com/v3',
} as const

const COVERAGE: Coverage = {
  entityKinds: ['PF', 'PJ'],
  billKinds: ['BOLETO', 'PIX_QR', 'PIX_KEY'],
}

const PIX_OUTCOME = {
  DONE: 'PAID',
  REFUSED: 'FAILED',
  CANCELLED: 'FAILED',
} as const

const TRANSFER_OUTCOME = {
  DONE: 'PAID',
  CANCELLED: 'FAILED',
  FAILED: 'FAILED',
} as const

const BILL_OUTCOME = {
  PAID: 'PAID',
  FAILED: 'FAILED',
  CANCELLED: 'FAILED',
  REFUNDED: 'FAILED',
} as const

type AsaasErrors = { errors?: Array<{ code?: string; description?: string }> }

type AsaasDecodedQr = {
  value?: number
  totalValue?: number
  canBePaid?: boolean
  cannotBePaidReason?: string | null
}

type AsaasOperation = {
  id: string
  status?: string
  externalReference?: string | null
  refusalReason?: string | null
  failReason?: string | null
  endToEndIdentifier?: string | null
  effectiveDate?: string | null
  paymentDate?: string | null
}

type AsaasList = { data?: AsaasOperation[] }

type AsaasBalance = { balance?: number }

type Answer<T> = { ok: true; data: T } | { ok: false; reason: string }

// The resources a payment of each method may have created, in lookup order.
const RESOURCES_BY_METHOD: Record<PaymentMethod, readonly string[]> = {
  PIX: ['pix', 'transfer'],
  BOLETO: ['bill'],
}

type Config = { apiKey: string; baseUrl: string }

export type AsaasRailDeps = { credentials: Credentials; transport: Transport }

export class AsaasRail implements PaymentRail, RailStatusReader {
  readonly id = 'ASAAS' as const

  constructor(private readonly deps: AsaasRailDeps) {}

  supports(kind: BillKind, entityKind: EntityKind): boolean {
    return covers(COVERAGE, kind, entityKind)
  }

  async pay(request: PaymentRequest): Promise<RailResult> {
    const { bill } = request
    const config = await this.config(scopeOf(bill))
    const pix = pixPayloadOf(bill, request.method)
    if (pix) {
      return this.payPixCode(config, bill, pix, request.idempotencyKey)
    }
    if (bill.kind === 'PIX_KEY') {
      return this.transfer(config, bill, request.idempotencyKey)
    }
    return this.payBoleto(config, bill, request.idempotencyKey)
  }

  // Asks each resource the method could have created for the operation that
  // carries the key; the match is checked here too, in case the filter is ignored.
  async findByReference(
    reference: { idempotencyKey: string; method: PaymentMethod },
    scope: RailStatusScope,
  ): Promise<RailStatus | null> {
    const config = await this.config(scope)
    const key = reference.idempotencyKey
    for (const resource of RESOURCES_BY_METHOD[reference.method]) {
      const answer = await this.call<AsaasList>(config, {
        method: 'GET',
        url: `${config.baseUrl}${STATUS_PATHS[resource]}?externalReference=${encodeURIComponent(key)}&limit=10`,
      })
      const data = answer.ok ? (answer.data.data ?? []) : []
      const op = data.find(item => item.externalReference === key)
      if (op) {
        return this.statusOf(resource, op)
      }
    }
    return null
  }

  async balanceCents(scope: RailStatusScope): Promise<number> {
    const config = await this.config(scope)
    const answer = await this.call<AsaasBalance>(config, {
      method: 'GET',
      url: `${config.baseUrl}/finance/balance`,
    })
    if (!answer.ok) {
      throw new Error(answer.reason)
    }
    return toCents(answer.data.balance)
  }

  async status(
    externalId: string,
    scope: RailStatusScope,
  ): Promise<RailStatus> {
    const [resource, id] = splitExternalId(externalId, PROVIDER)
    const config = await this.config(scope)
    const path = STATUS_PATHS[resource]
    if (!path) {
      throw new Error(`${PROVIDER} does not know the payment "${externalId}".`)
    }
    const answer = await this.call<AsaasOperation>(config, {
      method: 'GET',
      url: `${config.baseUrl}${path}/${id}`,
    })
    if (!answer.ok) {
      return statusResult('FAILED', externalId, { reason: answer.reason })
    }
    return this.statusOf(resource, answer.data, externalId)
  }

  private statusOf(
    resource: string,
    op: AsaasOperation,
    externalId = `${resource}:${op.id}`,
  ): RailStatus {
    const outcome = outcomeFrom(STATUS_TABLES[resource] ?? {}, op.status)
    return statusResult(outcome, externalId, {
      reason: op.refusalReason ?? op.failReason ?? null,
      endToEndId: op.endToEndIdentifier ?? null,
      settledAt: outcome === 'PAID' ? settledAt(op) : null,
    })
  }

  async check(): Promise<ProviderCheck> {
    return checkWith(PROVIDER, async () => {
      const config = await this.config({})
      const answer = await this.call<unknown>(config, {
        method: 'GET',
        url: `${config.baseUrl}/finance/balance`,
      })
      if (!answer.ok) {
        throw new Error(answer.reason)
      }
    })
  }

  private async payPixCode(
    config: Config,
    bill: Bill,
    payload: string,
    idempotencyKey: string,
  ): Promise<RailResult> {
    const pix = decodePix(payload)
    if (staticAmountMismatch(pix, bill)) {
      return failed('PIX_AMOUNT_MISMATCH')
    }
    const decoded = await this.call<AsaasDecodedQr>(config, {
      method: 'POST',
      url: `${config.baseUrl}/pix/qrCodes/decode`,
      json: { payload: pix.payload, expectedPaymentDate: bill.dueDate },
    })
    if (!decoded.ok) {
      return failed(decoded.reason)
    }
    if (decoded.data.canBePaid === false) {
      return failed(decoded.data.cannotBePaidReason ?? 'PIX_CANNOT_BE_PAID')
    }
    const quoted = toCents(decoded.data.totalValue ?? decoded.data.value)
    if (quoted > bill.amount.cents) {
      return failed('PIX_AMOUNT_ABOVE_BILL')
    }
    const cents = quoted > 0 ? quoted : bill.amount.cents
    const paid = await this.call<AsaasOperation>(
      config,
      {
        method: 'POST',
        url: `${config.baseUrl}/pix/qrCodes/pay`,
        json: {
          qrCode: { payload: pix.payload },
          value: toDecimal(cents),
          description: paymentDescription(bill),
          externalReference: idempotencyKey,
        },
      },
      idempotencyKey,
    )
    return this.result(paid, 'pix', PIX_OUTCOME)
  }

  private async transfer(
    config: Config,
    bill: Bill,
    idempotencyKey: string,
  ): Promise<RailResult> {
    const key = bill.code ?? ''
    const answer = await this.call<AsaasOperation>(
      config,
      {
        method: 'POST',
        url: `${config.baseUrl}/transfers`,
        json: {
          value: toDecimal(bill.amount.cents),
          operationType: 'PIX',
          pixAddressKey: normalizePixKey(key),
          pixAddressKeyType: pixKeyType(key),
          description: paymentDescription(bill),
          externalReference: idempotencyKey,
        },
      },
      idempotencyKey,
    )
    return this.result(answer, 'transfer', TRANSFER_OUTCOME)
  }

  private async payBoleto(
    config: Config,
    bill: Bill,
    idempotencyKey: string,
  ): Promise<RailResult> {
    const answer = await this.call<AsaasOperation>(
      config,
      {
        method: 'POST',
        url: `${config.baseUrl}/bill`,
        json: {
          identificationField: bill.code,
          description: paymentDescription(bill),
          externalReference: idempotencyKey,
        },
      },
      idempotencyKey,
    )
    return this.result(answer, 'bill', BILL_OUTCOME)
  }

  private result(
    answer: Answer<AsaasOperation>,
    resource: string,
    table: Record<string, RailResult['outcome']>,
  ): RailResult {
    if (!answer.ok) {
      return failed(answer.reason)
    }
    const op = answer.data
    return {
      outcome: outcomeFrom(table, op.status),
      externalId: `${resource}:${op.id}`,
      reason: op.refusalReason ?? op.failReason ?? null,
    }
  }

  private async config(scope: CredentialScope): Promise<Config> {
    const { ASAAS_API_KEY } = await requireCredentials(
      this.deps.credentials,
      PROVIDER,
      ['ASAAS_API_KEY'],
      scope,
    )
    const environment = await optionalCredential(
      this.deps.credentials,
      'ASAAS_ENVIRONMENT',
      'production',
      scope,
    )
    const baseUrl =
      environment === 'sandbox' ? ASAAS_URLS.sandbox : ASAAS_URLS.production
    return { apiKey: ASAAS_API_KEY, baseUrl }
  }

  // Asaas documents no idempotency header; it is sent anyway so a retry is
  // deduplicated if the API honours it, and the body carries the same key.
  private async call<T>(
    config: Config,
    call: Call,
    idempotencyKey?: string,
  ): Promise<Answer<T>> {
    const headers: Record<string, string> = {
      access_token: config.apiKey,
      'user-agent': 'cashdeck',
    }
    const keyed = idempotencyKey
      ? { ...headers, 'idempotency-key': idempotencyKey }
      : headers
    const response = await send(this.deps.transport, {
      ...call,
      headers: keyed,
    })
    if (isSuccess(response)) {
      return { ok: true, data: readJson<T>(response) }
    }
    if (isAuthError(response)) {
      return { ok: false, reason: 'Asaas rejected the API key.' }
    }
    if (isClientError(response)) {
      return { ok: false, reason: errorDescription(response.text) }
    }
    throw new ProviderHttpError(PROVIDER, response.status, response.text)
  }
}

const STATUS_PATHS: Record<string, string> = {
  pix: '/pix/transactions',
  transfer: '/transfers',
  bill: '/bill',
}

const STATUS_TABLES: Record<string, Record<string, RailResult['outcome']>> = {
  pix: PIX_OUTCOME,
  transfer: TRANSFER_OUTCOME,
  bill: BILL_OUTCOME,
}

function settledAt(op: AsaasOperation): string | null {
  return op.effectiveDate ?? op.paymentDate ?? null
}

function errorDescription(text: string): string {
  try {
    const body = JSON.parse(text) as AsaasErrors
    return body.errors?.[0]?.description ?? 'Asaas refused the payment.'
  } catch {
    return 'Asaas refused the payment.'
  }
}
