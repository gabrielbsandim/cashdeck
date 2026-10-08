import {
  type PaymentRail,
  type PaymentRequest,
  type ProviderCheck,
  type RailResult,
  type RailStatus,
  type RailStatusReader,
  type RailStatusScope,
} from '@cashdeck/application'
import { type Bill, type BillKind, type EntityKind } from '@cashdeck/domain'
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
  refusalReason?: string | null
  failReason?: string | null
  endToEndIdentifier?: string | null
  effectiveDate?: string | null
  paymentDate?: string | null
}

type Answer<T> = { ok: true; data: T } | { ok: false; reason: string }

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
    const pix = pixPayloadOf(bill)
    if (pix) {
      return this.payPixCode(config, bill, pix)
    }
    if (bill.kind === 'PIX_KEY') {
      return this.transfer(config, bill, request.idempotencyKey)
    }
    return this.payBoleto(config, bill)
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
    const op = answer.data
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
    const paid = await this.call<AsaasOperation>(config, {
      method: 'POST',
      url: `${config.baseUrl}/pix/qrCodes/pay`,
      json: {
        qrCode: { payload: pix.payload },
        value: toDecimal(cents),
        description: paymentDescription(bill),
      },
    })
    return this.result(paid, 'pix', PIX_OUTCOME)
  }

  private async transfer(
    config: Config,
    bill: Bill,
    idempotencyKey: string,
  ): Promise<RailResult> {
    const key = bill.code ?? ''
    const answer = await this.call<AsaasOperation>(config, {
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
    })
    return this.result(answer, 'transfer', TRANSFER_OUTCOME)
  }

  private async payBoleto(config: Config, bill: Bill): Promise<RailResult> {
    const answer = await this.call<AsaasOperation>(config, {
      method: 'POST',
      url: `${config.baseUrl}/bill`,
      json: {
        identificationField: bill.code,
        description: paymentDescription(bill),
      },
    })
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

  private async call<T>(config: Config, call: Call): Promise<Answer<T>> {
    const response = await send(this.deps.transport, {
      ...call,
      headers: { access_token: config.apiKey, 'user-agent': 'cashdeck' },
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
