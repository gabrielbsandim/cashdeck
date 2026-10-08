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
  type HttpResponse,
  isClientError,
  isSuccess,
  ProviderHttpError,
  readJson,
  safeJson,
  toDecimal,
  toDecimalString,
} from '@/http/transport'
import { type BankClient, BankClients } from '@/rails/bank-client'
import {
  decodePix,
  normalizePixKey,
  paymentDescription,
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

const PROVIDER = 'Inter Empresas'

export const INTER_URLS = {
  production: 'https://cdpj.partners.bancointer.com.br',
  sandbox: 'https://cdpj-sandbox.partners.uatinter.co',
} as const

const SCOPES = [
  'extrato.read',
  'pagamento-boleto.read',
  'pagamento-boleto.write',
  'pagamento-darf.write',
  'pagamento-pix.read',
  'pagamento-pix.write',
].join(' ')

const COVERAGE: Coverage = {
  entityKinds: ['PJ'],
  billKinds: ['BOLETO', 'PIX_KEY', 'PIX_QR', 'TAX_BARCODE', 'DARF_NO_BARCODE'],
}

const PIX_SUBMIT_OUTCOME = {
  APROVACAO: 'PENDING_APPROVAL',
  PROCESSADO: 'SUBMITTED',
  AGENDADO: 'SUBMITTED',
} as const

const PIX_STATUS_OUTCOME = {
  PAGO: 'PAID',
  AGUARDANDO_APROVACAO: 'PENDING_APPROVAL',
  REPROVADO: 'FAILED',
  EXPIRADO: 'FAILED',
  CANCELADO: 'FAILED',
  FALHA: 'FAILED',
  CANCELADO_SEM_SALDO: 'FAILED',
  NAO_DEBITADO: 'FAILED',
  AGENDAMENTO_CANCELADO: 'FAILED',
} as const

const PAYMENT_OUTCOME = {
  REALIZADO: 'PAID',
  PAGO: 'PAID',
  AGUARDANDO_APROVACAO: 'PENDING_APPROVAL',
  ERRO: 'FAILED',
  ERRO_PAGAMENTO: 'FAILED',
  CANCELADO: 'FAILED',
  REPROVADO: 'FAILED',
  APROVACAO_EXPIRADA: 'FAILED',
  NAO_COMPENSADO: 'FAILED',
  AGENDADO_CANCELADO: 'FAILED',
  AGENDAMENTO_CANCELADO: 'FAILED',
} as const

const DARF_SUBMIT_OUTCOME = {
  PAGAMENTO: 'PAID',
  AGENDAMENTO: 'SUBMITTED',
  APROVACAO_PAGAMENTO: 'PENDING_APPROVAL',
  APROVACAO_AGENDAMENTO: 'PENDING_APPROVAL',
} as const

export type InterDarfDetails = {
  cnpjCpf: string
  codigoReceita: string
  periodoApuracao: string
  referencia: string
  nomeEmpresa: string
}

export type DarfDetailsLookup = (bill: Bill) => Promise<InterDarfDetails | null>

export type InterEmpresasRailDeps = {
  credentials: Credentials
  clients?: BankClients
  darfDetails?: DarfDetailsLookup
}

type Answer<T> = { ok: true; data: T } | { ok: false; reason: string }

type PixAnswer = { tipoRetorno?: string; codigoSolicitacao?: string }

type PixStatusAnswer = {
  transacaoPix?: {
    status?: string
    endToEnd?: string | null
    dataHoraMovimento?: string | null
  }
}

type PaymentAnswer = { statusPagamento?: string; codigoTransacao?: string }

type PaymentListItem = {
  statusPagamento?: string
  dataPagamento?: string | null
}

type DarfAnswer = { tipoRetorno?: string; codigoSolicitacao?: string }

export class InterEmpresasRail implements PaymentRail, RailStatusReader {
  readonly id = 'INTER_EMPRESAS' as const

  private readonly clients: BankClients

  constructor(private readonly deps: InterEmpresasRailDeps) {
    this.clients = deps.clients ?? new BankClients()
  }

  supports(kind: BillKind, entityKind: EntityKind): boolean {
    return covers(COVERAGE, kind, entityKind)
  }

  async pay(request: PaymentRequest): Promise<RailResult> {
    const { bill, idempotencyKey } = request
    const client = await this.client(scopeOf(bill))
    const pix = pixPayloadOf(bill, request.method)
    if (pix) {
      return this.payPixCode(client, bill, pix, idempotencyKey)
    }
    switch (bill.kind) {
      case 'PIX_KEY':
        return this.payPixKey(client, bill, idempotencyKey)
      case 'DARF_NO_BARCODE':
        return this.payDarf(client, bill, idempotencyKey)
      default:
        return this.payBarcode(client, bill, idempotencyKey)
    }
  }

  async status(
    externalId: string,
    scope: RailStatusScope,
  ): Promise<RailStatus> {
    const [resource, id] = splitExternalId(externalId, PROVIDER)
    const client = await this.client(scope)
    switch (resource) {
      case 'pix':
        return this.pixStatus(client, externalId, id)
      case 'pagamento':
        return this.listStatus(
          client,
          externalId,
          `/pagamento?codigoTransacao=${id}`,
        )
      case 'darf':
        return this.listStatus(
          client,
          externalId,
          `/pagamento/darf?codigoSolicitacao=${id}`,
        )
      default:
        throw new Error(
          `${PROVIDER} does not know the payment "${externalId}".`,
        )
    }
  }

  async check(): Promise<ProviderCheck> {
    return checkWith(PROVIDER, async () => {
      const client = await this.client({})
      const answer = await call<unknown>(client, {
        method: 'GET',
        url: '/saldo',
      })
      if (!answer.ok) {
        throw new Error(answer.reason)
      }
    })
  }

  private async payPixCode(
    client: Client,
    bill: Bill,
    payload: string,
    idempotencyKey: string,
  ): Promise<RailResult> {
    const pix = decodePix(payload)
    if (staticAmountMismatch(pix, bill)) {
      return failed('PIX_AMOUNT_MISMATCH')
    }
    return this.sendPix(client, bill, idempotencyKey, {
      tipo: 'PIX_COPIA_E_COLA',
      pixCopiaECola: pix.payload,
    })
  }

  private async payPixKey(
    client: Client,
    bill: Bill,
    idempotencyKey: string,
  ): Promise<RailResult> {
    return this.sendPix(client, bill, idempotencyKey, {
      tipo: 'CHAVE',
      chave: normalizePixKey(bill.code ?? ''),
    })
  }

  private async sendPix(
    client: Client,
    bill: Bill,
    idempotencyKey: string,
    destinatario: Record<string, string>,
  ): Promise<RailResult> {
    const answer = await call<PixAnswer>(client, {
      method: 'POST',
      url: '/pix',
      headers: { 'x-id-idempotente': idempotencyKey },
      json: {
        valor: toDecimal(bill.amount.cents),
        descricao: paymentDescription(bill),
        destinatario,
      },
    })
    if (!answer.ok) {
      return failed(answer.reason)
    }
    return {
      outcome: outcomeFrom(PIX_SUBMIT_OUTCOME, answer.data.tipoRetorno),
      externalId: `pix:${answer.data.codigoSolicitacao}`,
      reason: null,
    }
  }

  private async payBarcode(
    client: Client,
    bill: Bill,
    idempotencyKey: string,
  ): Promise<RailResult> {
    const answer = await call<PaymentAnswer>(client, {
      method: 'POST',
      url: '/pagamento',
      headers: { 'x-id-idempotente': idempotencyKey },
      json: {
        codBarraLinhaDigitavel: bill.code,
        valorPagar: toDecimalString(bill.amount.cents),
        dataVencimento: bill.dueDate,
      },
    })
    if (!answer.ok) {
      return failed(answer.reason)
    }
    return {
      outcome: outcomeFrom(PAYMENT_OUTCOME, answer.data.statusPagamento),
      externalId: `pagamento:${answer.data.codigoTransacao}`,
      reason: null,
    }
  }

  private async payDarf(
    client: Client,
    bill: Bill,
    idempotencyKey: string,
  ): Promise<RailResult> {
    const details = await this.deps.darfDetails?.(bill)
    if (!details) {
      return failed('DARF_DETAILS_MISSING')
    }
    const answer = await call<DarfAnswer>(client, {
      method: 'POST',
      url: '/pagamento/darf',
      headers: { 'x-id-idempotente': idempotencyKey },
      json: {
        ...details,
        dataVencimento: bill.dueDate,
        descricao: paymentDescription(bill),
        valorPrincipal: toDecimal(bill.amount.cents),
      },
    })
    if (!answer.ok) {
      return failed(answer.reason)
    }
    return {
      outcome: outcomeFrom(DARF_SUBMIT_OUTCOME, answer.data.tipoRetorno),
      externalId: `darf:${answer.data.codigoSolicitacao}`,
      reason: null,
    }
  }

  private async pixStatus(
    client: Client,
    externalId: string,
    id: string,
  ): Promise<RailStatus> {
    const answer = await call<PixStatusAnswer>(client, {
      method: 'GET',
      url: `/pix/${id}`,
    })
    if (!answer.ok) {
      return statusResult('FAILED', externalId, { reason: answer.reason })
    }
    const pix = answer.data.transacaoPix ?? {}
    const outcome = outcomeFrom(PIX_STATUS_OUTCOME, pix.status)
    return statusResult(outcome, externalId, {
      endToEndId: pix.endToEnd ?? null,
      settledAt: outcome === 'PAID' ? (pix.dataHoraMovimento ?? null) : null,
    })
  }

  private async listStatus(
    client: Client,
    externalId: string,
    path: string,
  ): Promise<RailStatus> {
    const answer = await call<PaymentListItem[]>(client, {
      method: 'GET',
      url: path,
    })
    if (!answer.ok) {
      return statusResult('FAILED', externalId, { reason: answer.reason })
    }
    const item = answer.data[0]
    const outcome = outcomeFrom(PAYMENT_OUTCOME, item?.statusPagamento)
    return statusResult(outcome, externalId, {
      settledAt: outcome === 'PAID' ? (item?.dataPagamento ?? null) : null,
    })
  }

  private async client(scope: CredentialScope): Promise<Client> {
    const credentials = await requireCredentials(
      this.deps.credentials,
      PROVIDER,
      ['INTER_CLIENT_ID', 'INTER_CLIENT_SECRET', 'INTER_CERT', 'INTER_KEY'],
      scope,
    )
    const environment = await optionalCredential(
      this.deps.credentials,
      'INTER_ENVIRONMENT',
      'production',
      scope,
    )
    const account = await this.deps.credentials.get('INTER_ACCOUNT', scope)
    const host =
      environment === 'sandbox' ? INTER_URLS.sandbox : INTER_URLS.production
    const bank = this.clients.for({
      provider: PROVIDER,
      tokenUrl: `${host}/oauth/v2/token`,
      clientId: credentials.INTER_CLIENT_ID,
      clientSecret: credentials.INTER_CLIENT_SECRET,
      scope: SCOPES,
      certificate: { cert: credentials.INTER_CERT, key: credentials.INTER_KEY },
      headers: account ? { 'x-conta-corrente': account } : {},
    })
    return { bank, baseUrl: `${host}/banking/v2` }
  }
}

type Client = { bank: BankClient; baseUrl: string }

async function call<T>(client: Client, request: Call): Promise<Answer<T>> {
  const response = await client.bank.call({
    ...request,
    url: `${client.baseUrl}${request.url}`,
  })
  if (isSuccess(response)) {
    return { ok: true, data: readJson<T>(response) }
  }
  if (isClientError(response)) {
    return { ok: false, reason: refusal(response) }
  }
  throw new ProviderHttpError(PROVIDER, response.status, response.text)
}

type InterProblem = {
  title?: string
  detail?: string
  violacoes?: Array<{ razao?: string }>
}

function refusal(response: HttpResponse): string {
  const body = safeJson(response.text) as InterProblem | null
  return (
    body?.violacoes?.[0]?.razao ??
    body?.detail ??
    body?.title ??
    `Inter refused the request (${response.status}).`
  )
}
