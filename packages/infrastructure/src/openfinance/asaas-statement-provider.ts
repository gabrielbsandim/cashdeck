import {
  entityOfRailItem,
  isRailAccountItem,
  NotFoundError,
  type OpenFinanceConnection,
  type OpenFinanceProvider,
  type ProviderAccount,
  type ProviderItem,
  type ProviderTransaction,
} from '@cashdeck/application'
import { type Credentials } from '@/credentials/credential-resolver'
import {
  bodySummary,
  isSuccess,
  ProviderHttpError,
  readJson,
  send,
  toCents,
  type Transport,
} from '@/http/transport'
import { seenToday } from '@/openfinance/time-of-day'
import { type AsaasConfig, asaasConfig, asaasHeaders } from '@/rails/asaas-rail'

const PROVIDER = 'Asaas'
const PAGE_SIZE = 100
// Statement ids are Asaas's own, so they are kept apart from the bank feeds'.
export const ASAAS_ID_PREFIX = 'asaas:'

type AsaasEntry = {
  id: string
  value?: number
  date?: string
  description?: string | null
}

type AsaasPage = { data?: AsaasEntry[]; hasMore?: boolean }

type AsaasAccountNumber = { account?: string; accountDigit?: string }

export type AsaasStatementProviderDeps = {
  credentials: Credentials
  transport: Transport
  now?: () => Date
}

// The Asaas account read as a bank account: its balance and statement. Each
// entity's item id names the entity whose credentials open it.
export class AsaasStatementProvider implements OpenFinanceProvider {
  constructor(private readonly deps: AsaasStatementProviderDeps) {}

  async getItem(itemId: string): Promise<ProviderItem> {
    if (!isRailAccountItem(itemId)) {
      throw new NotFoundError('Item')
    }
    return {
      itemId,
      institutionName: PROVIDER,
      status: 'UPDATED',
      lastUpdatedAt: null,
    }
  }

  async listAccounts(
    connection: OpenFinanceConnection,
  ): Promise<ProviderAccount[]> {
    const config = await this.config(connection)
    const balance = await this.get<{ balance?: number }>(
      config,
      '/finance/balance',
    )
    const number = await this.get<AsaasAccountNumber>(
      config,
      '/myAccount/accountNumber',
    ).catch(() => null)
    return [
      {
        externalId: connection.itemId,
        name: PROVIDER,
        type: 'CHECKING',
        balanceCents: toCents(balance.balance),
        currency: 'BRL',
        numberSuffix: suffixOf(number),
      },
    ]
  }

  async listTransactions(
    connection: OpenFinanceConnection,
    accountExternalId: string,
    range: { from: string; to: string },
  ): Promise<ProviderTransaction[]> {
    const config = await this.config(connection)
    const entries: AsaasEntry[] = []
    for (let offset = 0; ; offset += PAGE_SIZE) {
      const query = new URLSearchParams({
        startDate: range.from,
        finishDate: range.to,
        offset: String(offset),
        limit: String(PAGE_SIZE),
      })
      const page = await this.get<AsaasPage>(
        config,
        `/financialTransactions?${query.toString()}`,
      )
      entries.push(...(page.data ?? []))
      if (!page.hasMore) {
        break
      }
    }
    const now = this.deps.now?.() ?? new Date()
    return entries.flatMap(entry =>
      toTransaction(entry, accountExternalId, now),
    )
  }

  async listBills() {
    return []
  }

  async listConnectors() {
    return []
  }

  async listInvestments() {
    return []
  }

  async listInvestmentMovements() {
    return []
  }

  private config(connection: OpenFinanceConnection): Promise<AsaasConfig> {
    return asaasConfig(this.deps.credentials, {
      entityId: entityOfRailItem(connection.itemId),
    })
  }

  private async get<T>(config: AsaasConfig, path: string): Promise<T> {
    const response = await send(this.deps.transport, {
      method: 'GET',
      url: `${config.baseUrl}${path}`,
      headers: asaasHeaders(config),
    })
    if (!isSuccess(response)) {
      throw new ProviderHttpError(
        PROVIDER,
        response.status,
        bodySummary(response.text),
      )
    }
    return readJson<T>(response)
  }
}

// The bank shows the account number with its digit; the last four name it.
function suffixOf(number: AsaasAccountNumber | null): string | null {
  const digits = `${number?.account ?? ''}${number?.accountDigit ?? ''}`
  return digits === '' ? null : digits.slice(-4)
}

function toTransaction(
  entry: AsaasEntry,
  accountExternalId: string,
  now: Date,
): ProviderTransaction[] {
  if (typeof entry.value !== 'number' || !entry.date) {
    return []
  }
  return [
    {
      externalId: `${ASAAS_ID_PREFIX}${entry.id}`,
      accountExternalId,
      amountCents: toCents(entry.value),
      currency: 'BRL',
      bookedOn: entry.date,
      bookedAt: seenToday(entry.date, now),
      description: entry.description?.trim() || 'Asaas',
    },
  ]
}

// Asaas items go to the Asaas statement, every other one to the bank feed.
export class RailAccountRouter implements OpenFinanceProvider {
  constructor(
    private readonly banks: OpenFinanceProvider,
    private readonly asaas: OpenFinanceProvider,
  ) {}

  getItem(itemId: string) {
    return this.route(itemId).getItem(itemId)
  }

  listAccounts(connection: OpenFinanceConnection) {
    return this.route(connection.itemId).listAccounts(connection)
  }

  listTransactions(
    connection: OpenFinanceConnection,
    accountExternalId: string,
    range: { from: string; to: string },
  ) {
    return this.route(connection.itemId).listTransactions(
      connection,
      accountExternalId,
      range,
    )
  }

  listBills(connection: OpenFinanceConnection, accountExternalId: string) {
    return this.route(connection.itemId).listBills(
      connection,
      accountExternalId,
    )
  }

  listConnectors() {
    return this.banks.listConnectors()
  }

  listInvestments(connection: OpenFinanceConnection) {
    return this.route(connection.itemId).listInvestments(connection)
  }

  listInvestmentMovements(
    connection: OpenFinanceConnection,
    investmentExternalId: string,
  ) {
    return this.route(connection.itemId).listInvestmentMovements(
      connection,
      investmentExternalId,
    )
  }

  private route(itemId: string) {
    return isRailAccountItem(itemId) ? this.asaas : this.banks
  }
}
