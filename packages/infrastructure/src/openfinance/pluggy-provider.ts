import {
  type InvestmentKind,
  type InvestmentStatus,
  type OpenFinanceConnection,
  type OpenFinanceProvider,
  type ProviderAccount,
  type ProviderBill,
  type ProviderConnector,
  type ProviderCreditLine,
  type ProviderInstallment,
  type ProviderItem,
  type ProviderInvestment,
  type ProviderItemStatus,
  type ProviderTransaction,
} from '@cashdeck/application'
import { toLocalDate } from '@cashdeck/domain'
import {
  type Credentials,
  requireCredentials,
} from '@/credentials/credential-resolver'
import { TokenCache } from '@/http/token-cache'
import {
  type HttpResponse,
  isSuccess,
  ProviderHttpError,
  readJson,
  send,
  toCents,
  type Transport,
} from '@/http/transport'

const PROVIDER = 'Pluggy'
export const PLUGGY_URL = 'https://api.pluggy.ai'

// API keys from POST /auth live for two hours.
const API_KEY_SECONDS = 2 * 60 * 60

const ITEM_STATUSES: readonly ProviderItemStatus[] = [
  'UPDATED',
  'UPDATING',
  'LOGIN_ERROR',
  'OUTDATED',
  'WAITING_USER_INPUT',
]

const ACCOUNT_TYPES: Record<string, ProviderAccount['type']> = {
  CHECKING_ACCOUNT: 'CHECKING',
  SAVINGS_ACCOUNT: 'SAVINGS',
  CREDIT_CARD: 'CREDIT_CARD',
}

const INVESTMENT_KINDS: Record<string, InvestmentKind> = {
  FIXED_INCOME: 'FIXED_INCOME',
  MUTUAL_FUND: 'FUND',
  EQUITY: 'EQUITY',
  ETF: 'ETF',
  SECURITY: 'PENSION',
  COE: 'STRUCTURED',
}

const INVESTMENT_STATUSES: Record<string, InvestmentStatus> = {
  ACTIVE: 'ACTIVE',
  PENDING: 'PENDING',
  TOTAL_WITHDRAWAL: 'CLOSED',
}

type PluggyConnector = {
  id?: number
  name?: string
  imageUrl?: string | null
  primaryColor?: string | null
}

type PluggyItem = {
  id: string
  status?: string
  lastUpdatedAt?: string | null
  connector?: PluggyConnector
}

type PluggyCreditData = {
  brand?: string | null
  balanceCloseDate?: string | null
  balanceDueDate?: string | null
  availableCreditLimit?: number | null
  creditLimit?: number | null
}

type PluggyAccount = {
  id: string
  type?: string
  subtype?: string
  name?: string
  number?: string | null
  balance?: number
  currencyCode?: string
  creditData?: PluggyCreditData | null
}

type PluggyTransaction = {
  id: string
  accountId?: string
  description?: string
  amount?: number
  amountInAccountCurrency?: number | null
  date?: string
  currencyCode?: string
  type?: 'DEBIT' | 'CREDIT'
  status?: 'PENDING' | 'POSTED'
  operationType?: string | null
  merchant?: { name?: string | null; businessName?: string | null } | null
  creditCardMetadata?: {
    billId?: string | null
    installmentNumber?: number | null
    totalInstallments?: number | null
    purchaseDate?: string | null
  } | null
}

type PluggyBill = {
  id: string
  dueDate?: string | null
  billClosingDate?: string | null
  totalAmount?: number | null
  totalAmountCurrencyCode?: string | null
  minimumPaymentAmount?: number | null
}

type PluggyInvestment = {
  id: string
  name?: string | null
  code?: string | null
  type?: string | null
  subtype?: string | null
  issuer?: string | null
  status?: string | null
  balance?: number | null
  amountOriginal?: number | null
  amountProfit?: number | null
  currencyCode?: string | null
  quantity?: number | null
  rate?: number | null
  rateType?: string | null
  fixedAnnualRate?: number | null
  lastMonthRate?: number | null
  lastTwelveMonthsRate?: number | null
  dueDate?: string | null
  date?: string | null
}

type Page<T> = { results?: T[]; page?: number; totalPages?: number }

type CursorPage<T> = { results?: T[]; next?: string | null }

export type PluggyProviderDeps = {
  credentials: Credentials
  transport: Transport
  now?: () => number
}

export class PluggyProvider implements OpenFinanceProvider {
  private readonly tokens: TokenCache

  constructor(private readonly deps: PluggyProviderDeps) {
    this.tokens = new TokenCache(() => this.authenticate(), deps.now)
  }

  async getItem(itemId: string): Promise<ProviderItem> {
    const item = await this.get<PluggyItem>(`/items/${itemId}`)
    const status = ITEM_STATUSES.find(candidate => candidate === item.status)
    return {
      itemId: item.id,
      institutionName: item.connector?.name ?? 'Unknown institution',
      status: status ?? 'OUTDATED',
      lastUpdatedAt: item.lastUpdatedAt ?? null,
      connector: item.connector ? toConnector(item.connector) : null,
    }
  }

  async listAccounts(
    connection: OpenFinanceConnection,
  ): Promise<ProviderAccount[]> {
    const accounts = await this.pages<PluggyAccount>(
      `/accounts?itemId=${encodeURIComponent(connection.itemId)}`,
    )
    return accounts.map(toAccount)
  }

  async listBills(
    _connection: OpenFinanceConnection,
    accountExternalId: string,
  ): Promise<ProviderBill[]> {
    const bills = await this.pages<PluggyBill>(
      `/bills?accountId=${encodeURIComponent(accountExternalId)}`,
    )
    return bills.flatMap(toBill)
  }

  async listConnectors(): Promise<ProviderConnector[]> {
    const connectors = await this.pages<PluggyConnector>(
      '/connectors?countries=BR&sandbox=false',
    )
    return connectors.flatMap(connector =>
      connector.id === undefined || !connector.name
        ? []
        : [toConnector(connector)],
    )
  }

  async listInvestments(
    connection: OpenFinanceConnection,
  ): Promise<ProviderInvestment[]> {
    const investments = await this.pages<PluggyInvestment>(
      `/investments?itemId=${encodeURIComponent(connection.itemId)}`,
    )
    return investments.map(toInvestment)
  }

  async listTransactions(
    _connection: OpenFinanceConnection,
    accountExternalId: string,
    range: { from: string; to: string },
  ): Promise<ProviderTransaction[]> {
    const query = new URLSearchParams({
      accountId: accountExternalId,
      dateFrom: range.from,
      dateTo: range.to,
    })
    const transactions: PluggyTransaction[] = []
    let after: string | null = null
    do {
      const params = new URLSearchParams(query)
      if (after) {
        params.set('after', after)
      }
      const answer: CursorPage<PluggyTransaction> = await this.get(
        `/v2/transactions?${params.toString()}`,
      )
      transactions.push(...(answer.results ?? []))
      after = cursorOf(answer.next)
    } while (after)
    return transactions.map(tx => toTransaction(tx, accountExternalId))
  }

  private async pages<T>(path: string): Promise<T[]> {
    const rows: T[] = []
    for (let page = 1; ; page += 1) {
      const answer = await this.get<Page<T>>(`${path}&page=${page}`)
      rows.push(...(answer.results ?? []))
      if (page >= (answer.totalPages ?? 1)) {
        return rows
      }
    }
  }

  private async get<T>(path: string): Promise<T> {
    const response = await this.authorized(path)
    if (response.status !== 401) {
      return this.parse<T>(response)
    }
    this.tokens.invalidate()
    return this.parse<T>(await this.authorized(path))
  }

  private async authorized(path: string): Promise<HttpResponse> {
    const apiKey = await this.tokens.get()
    return send(this.deps.transport, {
      method: 'GET',
      url: `${PLUGGY_URL}${path}`,
      headers: { 'x-api-key': apiKey },
    })
  }

  private parse<T>(response: HttpResponse): T {
    if (!isSuccess(response)) {
      throw new ProviderHttpError(PROVIDER, response.status, response.text)
    }
    return readJson<T>(response)
  }

  private async authenticate() {
    const { PLUGGY_CLIENT_ID, PLUGGY_CLIENT_SECRET } = await requireCredentials(
      this.deps.credentials,
      PROVIDER,
      ['PLUGGY_CLIENT_ID', 'PLUGGY_CLIENT_SECRET'],
    )
    const response = await send(this.deps.transport, {
      method: 'POST',
      url: `${PLUGGY_URL}/auth`,
      json: { clientId: PLUGGY_CLIENT_ID, clientSecret: PLUGGY_CLIENT_SECRET },
    })
    const answer = this.parse<{ apiKey?: string }>(response)
    if (!answer.apiKey) {
      throw new ProviderHttpError(PROVIDER, response.status, 'no apiKey')
    }
    return { accessToken: answer.apiKey, expiresInSeconds: API_KEY_SECONDS }
  }
}

// `next` comes back as a query string, or a URL, whose `after` parameter is
// the cursor; a bare cursor is accepted too in case the format changes.
function cursorOf(next: string | null | undefined): string | null {
  if (!next) {
    return null
  }
  if (!next.includes('after=')) {
    return next
  }
  return new URLSearchParams(next.slice(next.indexOf('?') + 1)).get('after')
}

// Bill and purchase dates are calendar days sent as midnight timestamps;
// converting them to the local zone would move them a day back.
function calendarDay(value: string | null | undefined): string | null {
  const day = value?.slice(0, 10) ?? ''
  return /^\d{4}-\d{2}-\d{2}$/.test(day) ? day : null
}

function toConnector(connector: PluggyConnector): ProviderConnector {
  return {
    id: connector.id ?? 0,
    name: connector.name ?? '',
    imageUrl: connector.imageUrl || null,
    primaryColor: connector.primaryColor || null,
  }
}

function numberSuffix(number: string | null | undefined): string | null {
  const digits = number?.replace(/\D/g, '') ?? ''
  return digits === '' ? null : digits.slice(-4)
}

function toCreditLine(
  data: PluggyCreditData | null | undefined,
): ProviderCreditLine | null {
  if (typeof data?.creditLimit !== 'number') {
    return null
  }
  return {
    limitCents: toCents(data.creditLimit),
    availableCents: toCents(data.availableCreditLimit ?? 0),
    closesOn: calendarDay(data.balanceCloseDate),
    dueOn: calendarDay(data.balanceDueDate),
    brand: data.brand || null,
  }
}

function toAccount(account: PluggyAccount): ProviderAccount {
  const type =
    ACCOUNT_TYPES[account.subtype ?? ''] ??
    (account.type === 'CREDIT' ? 'CREDIT_CARD' : 'CHECKING')
  const balance = toCents(account.balance)
  return {
    externalId: account.id,
    name: account.name ?? 'Account',
    type,
    // A card balance is what is owed, so it counts against net worth.
    balanceCents: type === 'CREDIT_CARD' ? -balance : balance,
    currency: account.currencyCode ?? 'BRL',
    numberSuffix: numberSuffix(account.number),
    credit: type === 'CREDIT_CARD' ? toCreditLine(account.creditData) : null,
  }
}

// A single charge also arrives as "1 of 1"; only a real split is kept.
function toInstallment(
  metadata: PluggyTransaction['creditCardMetadata'],
): ProviderInstallment | null {
  const number = metadata?.installmentNumber ?? 0
  const count = metadata?.totalInstallments ?? 0
  const valid =
    Number.isInteger(number) && Number.isInteger(count) && number >= 1
  if (!valid || count < 2 || number > count) {
    return null
  }
  return { number, count, purchaseOn: calendarDay(metadata?.purchaseDate) }
}

// Refunds and cashback lower the bill; a payment only settles the last one.
const BILL_CREDITS = ['ESTORNO', 'CASHBACK']

// A charge stays pending and unlinked until the issuer puts it on a bill.
function openBillCents(tx: PluggyTransaction): number | null {
  if (!tx.creditCardMetadata) {
    return null
  }
  if (tx.creditCardMetadata.billId || tx.status !== 'PENDING') {
    return 0
  }
  const cents = Math.abs(toCents(tx.amountInAccountCurrency ?? tx.amount))
  if (tx.type !== 'CREDIT') {
    return -cents
  }
  return BILL_CREDITS.includes(tx.operationType ?? '') ? cents : 0
}

function toTransaction(
  tx: PluggyTransaction,
  accountExternalId: string,
): ProviderTransaction {
  const cents = Math.abs(toCents(tx.amount))
  return {
    externalId: tx.id,
    accountExternalId: tx.accountId ?? accountExternalId,
    amountCents: tx.type === 'CREDIT' ? cents : -cents,
    currency: tx.currencyCode ?? 'BRL',
    bookedOn: tx.date ? toLocalDate(new Date(tx.date)) : '',
    description: tx.description ?? '',
    merchant: tx.merchant?.name || tx.merchant?.businessName || null,
    installment: toInstallment(tx.creditCardMetadata),
    openBillCents: openBillCents(tx),
  }
}

function toBill(bill: PluggyBill): ProviderBill[] {
  const dueOn = calendarDay(bill.dueDate)
  if (!dueOn) {
    return []
  }
  const currency = bill.totalAmountCurrencyCode ?? 'BRL'
  return [
    {
      externalId: bill.id,
      closesOn: calendarDay(bill.billClosingDate),
      dueOn,
      totalCents: toCents(bill.totalAmount ?? 0),
      minimumCents:
        typeof bill.minimumPaymentAmount === 'number'
          ? toCents(bill.minimumPaymentAmount)
          : null,
      currency,
    },
  ]
}

const optionalCents = (value: number | null | undefined) =>
  typeof value === 'number' ? toCents(value) : null

const optionalNumber = (value: number | null | undefined) =>
  typeof value === 'number' ? value : null

function toRate(investment: PluggyInvestment) {
  const percent = optionalNumber(investment.rate)
  const index = investment.rateType || null
  const fixedAnnual = optionalNumber(investment.fixedAnnualRate)
  if (percent === null && index === null && fixedAnnual === null) {
    return null
  }
  return { percent, index, fixedAnnual }
}

// A sold position stays listed with a zero balance and no status of its own.
function toInvestment(investment: PluggyInvestment): ProviderInvestment {
  const balanceCents = toCents(investment.balance ?? 0)
  return {
    externalId: investment.id,
    name: investment.name || investment.code || 'Investment',
    kind: INVESTMENT_KINDS[investment.type ?? ''] ?? 'OTHER',
    subtype: investment.subtype || null,
    issuer: investment.issuer || null,
    status:
      INVESTMENT_STATUSES[investment.status ?? ''] ??
      (balanceCents > 0 ? 'ACTIVE' : 'CLOSED'),
    balanceCents,
    investedCents: optionalCents(investment.amountOriginal),
    profitCents: optionalCents(investment.amountProfit),
    currency: investment.currencyCode ?? 'BRL',
    quantity: optionalNumber(investment.quantity),
    rate: toRate(investment),
    lastMonthRate: optionalNumber(investment.lastMonthRate),
    lastTwelveMonthsRate: optionalNumber(investment.lastTwelveMonthsRate),
    dueOn: calendarDay(investment.dueDate),
    valuedOn: calendarDay(investment.date),
  }
}
