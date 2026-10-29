import {
  type PaymentRail,
  type PaymentRequest,
  type RecipientDirectory,
  type RecipientDirectoryScope,
  type VerifiedPayee,
  type ProviderCheck,
  type RailResult,
  type RailStatus,
  type RailStatusReader,
  type RailStatusScope,
} from '@cashdeck/application'
import {
  type Bill,
  type BillKind,
  decodePaymentCode,
  type EntityKind,
  type PaymentMethod,
  type PixKey,
} from '@cashdeck/domain'
import {
  type Credentials,
  type CredentialScope,
  optionalCredential,
  requireCredentials,
} from '@/credentials/credential-resolver'
import {
  bodySummary,
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

// Asaas reads only the digitable line, so a scanned 44 digit barcode, as on
// utility bills, is rewritten; a code that does not decode goes as is.
export function identificationFieldOf(bill: Bill): string {
  const code = bill.code ?? ''
  try {
    const decoded = decodePaymentCode(code, bill.dueDate)
    return 'digitableLine' in decoded ? decoded.digitableLine : code
  } catch {
    return code
  }
}

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

type AsaasReceiver = {
  name?: string | null
  tradingName?: string | null
  cpfCnpj?: string | null
  ispbName?: string | null
}

type AsaasDecodedQr = {
  value?: number
  totalValue?: number
  canBePaid?: boolean
  cannotBePaidReason?: string | null
  receiver?: AsaasReceiver | null
}

type AsaasKeyOwner = {
  ispbName?: string | null
  financialInstitution?: { bank?: { name?: string | null } | null } | null
  owner?: { name?: string | null; cpfCnpj?: string | null } | null
}

type AsaasBillSimulation = {
  bankSlipInfo?: {
    beneficiaryName?: string | null
    beneficiaryCpfCnpj?: string | null
    companyName?: string | null
    bank?: string | null
  } | null
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

export type AsaasConfig = { apiKey: string; baseUrl: string }

export async function asaasConfig(
  credentials: Credentials,
  scope: CredentialScope,
): Promise<AsaasConfig> {
  const { ASAAS_API_KEY } = await requireCredentials(
    credentials,
    PROVIDER,
    ['ASAAS_API_KEY'],
    scope,
  )
  const environment = await optionalCredential(
    credentials,
    'ASAAS_ENVIRONMENT',
    'production',
    scope,
  )
  const baseUrl =
    environment === 'sandbox' ? ASAAS_URLS.sandbox : ASAAS_URLS.production
  return { apiKey: ASAAS_API_KEY, baseUrl }
}

export const asaasHeaders = (config: AsaasConfig) => ({
  access_token: config.apiKey,
  'user-agent': 'cashdeck',
})

export type AsaasRailDeps = { credentials: Credentials; transport: Transport }

export class AsaasRail
  implements PaymentRail, RailStatusReader, RecipientDirectory
{
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

  async ownerOfKey(
    key: PixKey,
    scope: RecipientDirectoryScope,
  ): Promise<VerifiedPayee | null> {
    const config = await this.config(scope)
    const query = `type=${key.type}&key=${encodeURIComponent(key.value)}`
    const answer = await this.call<AsaasKeyOwner>(config, {
      method: 'GET',
      url: `${config.baseUrl}/pix/addressKeys/external?${query}`,
    })
    if (!answer.ok) {
      return null
    }
    const { owner, financialInstitution, ispbName } = answer.data
    return payee(
      owner?.name,
      owner?.cpfCnpj,
      financialInstitution?.bank?.name ?? ispbName,
    )
  }

  async receiverOfCode(
    payload: string,
    scope: RecipientDirectoryScope,
  ): Promise<VerifiedPayee | null> {
    const config = await this.config(scope)
    const answer = await this.call<AsaasDecodedQr>(config, {
      method: 'POST',
      url: `${config.baseUrl}/pix/qrCodes/decode`,
      json: { payload },
    })
    if (!answer.ok) {
      return null
    }
    const receiver = answer.data.receiver
    return payee(
      receiver?.name ?? receiver?.tradingName,
      receiver?.cpfCnpj,
      receiver?.ispbName,
    )
  }

  async beneficiaryOfBoleto(
    line: string,
    scope: RecipientDirectoryScope,
  ): Promise<VerifiedPayee | null> {
    const config = await this.config(scope)
    const answer = await this.call<AsaasBillSimulation>(config, {
      method: 'POST',
      url: `${config.baseUrl}/bill/simulate`,
      json: { identificationField: line },
    })
    if (!answer.ok) {
      return null
    }
    const slip = answer.data.bankSlipInfo
    return payee(
      slip?.beneficiaryName ?? slip?.companyName,
      slip?.beneficiaryCpfCnpj,
      slip?.bank,
    )
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
    config: AsaasConfig,
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
    config: AsaasConfig,
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
    config: AsaasConfig,
    bill: Bill,
    idempotencyKey: string,
  ): Promise<RailResult> {
    const answer = await this.call<AsaasOperation>(
      config,
      {
        method: 'POST',
        url: `${config.baseUrl}/bill`,
        json: {
          identificationField: identificationFieldOf(bill),
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

  private config(scope: CredentialScope): Promise<AsaasConfig> {
    return asaasConfig(this.deps.credentials, scope)
  }

  // Asaas documents no idempotency header; it is sent anyway so a retry is
  // deduplicated if the API honours it, and the body carries the same key.
  private async call<T>(
    config: AsaasConfig,
    call: Call,
    idempotencyKey?: string,
  ): Promise<Answer<T>> {
    const headers: Record<string, string> = asaasHeaders(config)
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
    throw new ProviderHttpError(
      PROVIDER,
      response.status,
      bodySummary(response.text),
    )
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
  const settled = op.effectiveDate ?? op.paymentDate
  return settled ? brasiliaInstant(settled) : null
}

// Asaas writes Brasília wall-clock time with no offset, and Brazil keeps -03:00.
function brasiliaInstant(text: string): string {
  if (text.includes('T')) {
    return text
  }
  const [day, time = '00:00:00'] = text.split(' ')
  return `${day}T${time}-03:00`
}

function payee(
  name: string | null | undefined,
  taxId: string | null | undefined,
  bank: string | null | undefined,
): VerifiedPayee | null {
  if (!name) {
    return null
  }
  return { name, taxId: maskTaxId(taxId), bank: bank || null }
}

// A person's CPF is shown the way the directory itself masks it; a company's
// CNPJ is public and stays whole.
function maskTaxId(taxId: string | null | undefined): string | null {
  const digits = taxId?.replace(/\D/g, '') ?? ''
  if (!taxId || taxId.includes('*') || digits.length !== 11) {
    return taxId || null
  }
  return `***.${digits.slice(3, 6)}.${digits.slice(6, 9)}-**`
}

function errorDescription(text: string): string {
  try {
    const body = JSON.parse(text) as AsaasErrors
    return body.errors?.[0]?.description ?? 'Asaas refused the payment.'
  } catch {
    return 'Asaas refused the payment.'
  }
}
