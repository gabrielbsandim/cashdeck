import {
  type PreviewAccount,
  type PreviewProvider,
  type ProviderAccount,
  type ProviderTransaction,
} from '@cashdeck/application'
import { toLocalDate } from '@cashdeck/domain'
import {
  type Credentials,
  requireCredentials,
} from '@/credentials/credential-resolver'
import {
  type HttpMethod,
  isSuccess,
  ProviderHttpError,
  readJson,
  send,
  toCents,
  type Transport,
} from '@/http/transport'
import { ACCOUNT_TYPES, toInstallment } from '@/openfinance/pluggy-provider'

const PROVIDER = 'Pierre'
export const PIERRE_URL = 'https://www.pierre.finance/tools/api'
// Pierre ids are its own, so they are kept apart from the main provider's.
export const PIERRE_ID_PREFIX = 'pierre:'
const ACCOUNT_KINDS = ['BANK', 'CREDIT'] as const

type PierreAccount = {
  id: string
  name?: string | null
  type?: string | null
  subtype?: string | null
  balance?: string | number | null
  connectorName?: string | null
}

type PierreParty = {
  documentNumber?: { value?: string | null } | null
}

type PierreTransaction = {
  id: string
  account_id?: string
  description?: string | null
  amount?: number
  currency_code?: string | null
  date?: string
  type?: 'DEBIT' | 'CREDIT'
  status?: 'PENDING' | 'POSTED'
  merchant?: { name?: string | null; businessName?: string | null } | null
  payment_data?: {
    payer?: PierreParty | null
    receiver?: PierreParty | null
  } | null
  credit_card_data?: {
    installmentNumber?: number | null
    totalInstallments?: number | null
    purchaseDate?: string | null
  } | null
}

type Answer<T> = { data?: T[] }

export type PierreProviderDeps = {
  credentials: Credentials
  transport: Transport
}

export class PierreProvider implements PreviewProvider {
  constructor(private readonly deps: PierreProviderDeps) {}

  async listAccounts(): Promise<PreviewAccount[]> {
    const answer = await this.call<Answer<PierreAccount>>('GET', 'get-accounts')
    return (answer.data ?? []).flatMap(toAccount)
  }

  async listTransactions(range: {
    from: string
    to: string
  }): Promise<ProviderTransaction[]> {
    const transactions: ProviderTransaction[] = []
    for (const accountType of ACCOUNT_KINDS) {
      const query = new URLSearchParams({
        accountType,
        startDate: range.from,
        endDate: range.to,
        format: 'raw',
      })
      const answer = await this.call<Answer<PierreTransaction>>(
        'GET',
        `get-transactions?${query.toString()}`,
      )
      transactions.push(...current(answer.data ?? []).flatMap(toTransaction))
    }
    return transactions
  }

  async requestRefresh(): Promise<void> {
    await this.call('POST', 'manual-update')
  }

  private async call<T>(method: HttpMethod, path: string): Promise<T> {
    const { PIERRE_API_KEY } = await requireCredentials(
      this.deps.credentials,
      PROVIDER,
      ['PIERRE_API_KEY'],
    )
    const response = await send(this.deps.transport, {
      method,
      url: `${PIERRE_URL}/${path}`,
      headers: { authorization: `Bearer ${PIERRE_API_KEY}` },
    })
    if (!isSuccess(response)) {
      throw new ProviderHttpError(PROVIDER, response.status, response.text)
    }
    return readJson<T>(response)
  }
}

// An account without a bank is one the user keeps by hand inside Pierre.
function toAccount(account: PierreAccount): PreviewAccount[] {
  if (!account.connectorName) {
    return []
  }
  const type: ProviderAccount['type'] =
    ACCOUNT_TYPES[account.subtype ?? ''] ??
    (account.type === 'CREDIT' ? 'CREDIT_CARD' : 'CHECKING')
  const balance = toCents(account.balance)
  return [
    {
      externalId: account.id,
      institutionName: account.connectorName,
      name: account.name ?? '',
      type,
      balanceCents: type === 'CREDIT_CARD' ? -balance : balance,
    },
  ]
}

function counterpartyOf(tx: PierreTransaction): string | null {
  const party =
    tx.type === 'CREDIT' ? tx.payment_data?.payer : tx.payment_data?.receiver
  return party?.documentNumber?.value ?? null
}

const DAY_MS = 24 * 60 * 60 * 1000

// A card payment shows up pending and again once posted, under another
// description; only the posted one is kept.
function current(transactions: readonly PierreTransaction[]) {
  const posted = transactions.filter(
    tx => tx.type === 'CREDIT' && tx.status === 'POSTED',
  )
  const superseded = (tx: PierreTransaction) =>
    tx.type === 'CREDIT' &&
    tx.status === 'PENDING' &&
    posted.some(
      other =>
        other.account_id === tx.account_id &&
        other.amount === tx.amount &&
        Math.abs(Date.parse(other.date ?? '') - Date.parse(tx.date ?? '')) <=
          2 * DAY_MS,
    )
  return transactions.filter(tx => !superseded(tx))
}

function toTransaction(tx: PierreTransaction): ProviderTransaction[] {
  if (!tx.account_id || !tx.date || !tx.amount) {
    return []
  }
  const cents = Math.abs(toCents(tx.amount))
  return [
    {
      externalId: `${PIERRE_ID_PREFIX}${tx.id}`,
      accountExternalId: tx.account_id,
      amountCents: tx.type === 'CREDIT' ? cents : -cents,
      currency: tx.currency_code ?? 'BRL',
      bookedOn: toLocalDate(new Date(tx.date)),
      description: tx.description || 'Transaction',
      merchant: tx.merchant?.name || tx.merchant?.businessName || null,
      counterparty: counterpartyOf(tx),
      installment: toInstallment(tx.credit_card_data),
    },
  ]
}
