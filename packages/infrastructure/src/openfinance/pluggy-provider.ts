import {
  type OpenFinanceConnection,
  type OpenFinanceProvider,
  type ProviderAccount,
  type ProviderItem,
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

type PluggyItem = {
  id: string
  status?: string
  lastUpdatedAt?: string | null
  connector?: { name?: string }
}

type PluggyAccount = {
  id: string
  type?: string
  subtype?: string
  name?: string
  balance?: number
  currencyCode?: string
}

type PluggyTransaction = {
  id: string
  accountId?: string
  description?: string
  amount?: number
  date?: string
  currencyCode?: string
  type?: 'DEBIT' | 'CREDIT'
}

type Page<T> = { results?: T[]; page?: number; totalPages?: number }

type CursorPage<T> = { results?: T[]; next?: string | null }

export type PluggyProviderDeps = {
  credentials: Credentials
  transport: Transport
  now?: () => number
  pageSize?: number
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
    }
  }

  async listAccounts(
    connection: OpenFinanceConnection,
  ): Promise<ProviderAccount[]> {
    const accounts: PluggyAccount[] = []
    for (let page = 1; ; page += 1) {
      const answer = await this.get<Page<PluggyAccount>>(
        `/accounts?itemId=${encodeURIComponent(connection.itemId)}&page=${page}`,
      )
      accounts.push(...(answer.results ?? []))
      if (page >= (answer.totalPages ?? 1)) {
        break
      }
    }
    return accounts.map(toAccount)
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
      pageSize: String(this.deps.pageSize ?? 500),
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

// `next` comes back as a URL whose `after` parameter is the cursor; a bare
// cursor is accepted too in case the format changes.
function cursorOf(next: string | null | undefined): string | null {
  if (!next) {
    return null
  }
  if (!next.startsWith('http')) {
    return next
  }
  return new URL(next).searchParams.get('after')
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
  }
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
  }
}
