import { createSign } from 'node:crypto'
import {
  type PaymentRail,
  type PaymentRequest,
  type ProviderCheck,
  ProviderNotConfiguredError,
  type RailResult,
  type RailStatus,
  type RailStatusReader,
  type RailStatusScope,
} from '@cashdeck/application'
import { type BillKind, type EntityKind } from '@cashdeck/domain'
import {
  type Credentials,
  type CredentialScope,
  optionalCredential,
  requireCredentials,
} from '@/credentials/credential-resolver'
import {
  isAuthError,
  isClientError,
  isSuccess,
  ProviderHttpError,
  readJson,
  safeJson,
  send,
  toDecimal,
  type Transport,
} from '@/http/transport'
import { normalizePixKey, paymentDescription, pixKeyType } from '@/rails/pix'
import {
  checkWith,
  type Coverage,
  covers,
  failed,
  outcomeFrom,
  scopeOf,
  statusResult,
} from '@/rails/rail-support'

const PROVIDER = 'Mercado Pago Payouts'
const BASE_URL = 'https://api.mercadopago.com'

// Payouts send Pix to a key or a bank account only; a BR Code is not accepted,
// so a bolepix falls to the next rail.
const COVERAGE: Coverage = { entityKinds: ['PF'], billKinds: ['PIX_KEY'] }

const TRANSACTION_OUTCOME = {
  success: 'PAID',
  error: 'FAILED',
  canceled: 'FAILED',
  cancelled: 'FAILED',
} as const

type Config = {
  accessToken: string
  signingKey: string | null
  sandbox: boolean
}

type Payout = {
  id: string
  status?: string
  transactions?: Array<{ id: string; status?: string }>
}

type PayoutTransaction = {
  id: string
  status?: string
  status_detail?: string | null
  last_update_date?: string | null
}

export type PayoutInput = {
  scope: CredentialScope
  pixKey: string
  amountCents: number
  description: string
  idempotencyKey: string
}

export type PayloadSigner = (body: string, privateKey: string) => string

// The docs describe the signature only as the base64 body signed with the
// integrator key pair; RSA-SHA256 is the assumption until the spike confirms it.
export const rsaSha256Signer: PayloadSigner = (body, privateKey) =>
  createSign('RSA-SHA256').update(body).sign(privateKey, 'base64')

export type MercadoPagoRailDeps = {
  credentials: Credentials
  transport: Transport
  signer?: PayloadSigner
}

export class MercadoPagoPayoutsRail implements PaymentRail, RailStatusReader {
  readonly id = 'MERCADO_PAGO_PAYOUTS' as const

  constructor(private readonly deps: MercadoPagoRailDeps) {}

  supports(kind: BillKind, entityKind: EntityKind): boolean {
    return covers(COVERAGE, kind, entityKind)
  }

  async pay(request: PaymentRequest): Promise<RailResult> {
    const { bill } = request
    if (bill.kind !== 'PIX_KEY' || !bill.code) {
      return failed('UNSUPPORTED_KIND')
    }
    return this.payout({
      scope: scopeOf(bill),
      pixKey: bill.code,
      amountCents: bill.amount.cents,
      description: paymentDescription(bill),
      idempotencyKey: request.idempotencyKey,
    })
  }

  // A Pix payout to a key, shared by bill payments and the reserve funding
  // transfer; the idempotency key makes a resend return the first payout.
  async payout(input: PayoutInput): Promise<RailResult> {
    const config = await this.config(input.scope)
    const reference = input.idempotencyKey.replace(/[^A-Za-z0-9]/g, '')
    const body = JSON.stringify({
      external_reference: reference,
      description: input.description,
      transactions: [
        {
          type: 'pix',
          pix: {
            type: pixKeyType(input.pixKey),
            chave: normalizePixKey(input.pixKey),
          },
          amount: { currency: 'BRL', value: toDecimal(input.amountCents) },
          external_reference: reference,
        },
      ],
    })
    const response = await this.deps.transport({
      method: 'POST',
      url: `${BASE_URL}/v1/payouts`,
      headers: {
        ...this.headers(config),
        'content-type': 'application/json',
        'x-idempotency-key': input.idempotencyKey,
        ...this.signature(config, body),
      },
      body,
    })
    if (!isSuccess(response)) {
      return failed(this.refusal(response.status, response.text))
    }
    const payout = readJson<Payout>(response)
    const transaction = payout.transactions?.[0]
    return {
      outcome: outcomeFrom(TRANSACTION_OUTCOME, transaction?.status),
      externalId: `${payout.id}/${transaction?.id ?? ''}`,
      reason: null,
    }
  }

  async status(
    externalId: string,
    scope: RailStatusScope,
  ): Promise<RailStatus> {
    const [payoutId, transactionId] = externalId.split('/')
    if (!payoutId || !transactionId) {
      throw new Error(`${PROVIDER} does not know the payment "${externalId}".`)
    }
    const config = await this.config(scope)
    const response = await send(this.deps.transport, {
      method: 'GET',
      url: `${BASE_URL}/v1/payouts/${payoutId}/transactions/${transactionId}`,
      headers: this.headers(config),
    })
    if (!isSuccess(response)) {
      return statusResult('FAILED', externalId, {
        reason: this.refusal(response.status, response.text),
      })
    }
    const transaction = readJson<PayoutTransaction>(response)
    const outcome = outcomeFrom(TRANSACTION_OUTCOME, transaction.status)
    return statusResult(outcome, externalId, {
      reason: transaction.status_detail ?? null,
      settledAt:
        outcome === 'PAID' ? (transaction.last_update_date ?? null) : null,
    })
  }

  async check(): Promise<ProviderCheck> {
    return checkWith(PROVIDER, async () => {
      const config = await this.config({})
      const response = await send(this.deps.transport, {
        method: 'GET',
        url: `${BASE_URL}/users/me`,
        headers: this.headers(config),
      })
      if (!isSuccess(response)) {
        throw new Error(this.refusal(response.status, response.text))
      }
    })
  }

  private headers(config: Config): Record<string, string> {
    const headers: Record<string, string> = {
      authorization: `Bearer ${config.accessToken}`,
      accept: 'application/json',
    }
    return config.sandbox ? { ...headers, 'x-test-token': 'true' } : headers
  }

  private signature(config: Config, body: string): Record<string, string> {
    if (config.sandbox || config.signingKey === null) {
      return { 'x-enforce-signature': 'false' }
    }
    const signer = this.deps.signer ?? rsaSha256Signer
    return { 'x-signature': signer(body, config.signingKey) }
  }

  private refusal(status: number, text: string): string {
    if (isAuthError({ status, headers: {}, text })) {
      return 'Mercado Pago rejected the access token.'
    }
    if (!isClientError({ status, headers: {}, text })) {
      throw new ProviderHttpError(PROVIDER, status, text)
    }
    const body = safeJson(text) as { message?: string } | null
    return body?.message ?? 'Mercado Pago refused the payout.'
  }

  private async config(scope: CredentialScope): Promise<Config> {
    const { MERCADO_PAGO_ACCESS_TOKEN } = await requireCredentials(
      this.deps.credentials,
      PROVIDER,
      ['MERCADO_PAGO_ACCESS_TOKEN'],
      scope,
    )
    const environment = await optionalCredential(
      this.deps.credentials,
      'MERCADO_PAGO_ENVIRONMENT',
      'production',
      scope,
    )
    const signingKey = await this.deps.credentials.get(
      'MERCADO_PAGO_SIGNING_KEY',
      scope,
    )
    const sandbox = environment === 'sandbox'
    if (!sandbox && signingKey === null) {
      throw new ProviderNotConfiguredError(PROVIDER)
    }
    return { accessToken: MERCADO_PAGO_ACCESS_TOKEN, signingKey, sandbox }
  }
}
