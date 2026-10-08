import { Money } from '@/money/money'
import { ValidationError } from '@/shared/domain-error'
import { guard } from '@/shared/guard'

export const ACCOUNT_TYPES = [
  'CHECKING',
  'SAVINGS',
  'CREDIT_CARD',
  'INVESTMENT',
  'WALLET',
] as const
export type AccountType = (typeof ACCOUNT_TYPES)[number]

export const ACCOUNT_ORIGINS = ['CONNECTED', 'MANUAL'] as const
export type AccountOrigin = (typeof ACCOUNT_ORIGINS)[number]

export type Account = {
  readonly id: string
  readonly tenantId: string
  readonly entityId: string
  readonly institutionId: string
  readonly name: string
  readonly type: AccountType
  readonly origin: AccountOrigin
  readonly isReserve: boolean
  readonly balance: Money
  readonly connectionId: string | null
  readonly externalId: string | null
  // Yield of a reserve account as a share of the CDI, in percent.
  readonly cdiPercent: number | null
}

export type CreateAccountInput = Omit<
  Account,
  'name' | 'isReserve' | 'connectionId' | 'externalId' | 'cdiPercent'
> & {
  name: string
  isReserve?: boolean
  connectionId?: string | null
  externalId?: string | null
  cdiPercent?: number | null
}

export const CASH_ACCOUNT_TYPES: readonly AccountType[] = [
  'CHECKING',
  'SAVINGS',
  'WALLET',
]

export function createAccount(input: CreateAccountInput): Account {
  const isReserve = input.isReserve ?? false
  if (isReserve && !CASH_ACCOUNT_TYPES.includes(input.type)) {
    throw new ValidationError('Only a cash account can be the reserve.')
  }
  return {
    ...input,
    name: guard.notEmpty(input.name, 'Account name'),
    isReserve,
    connectionId: input.connectionId ?? null,
    externalId: input.externalId ?? null,
    cdiPercent: input.cdiPercent ?? null,
  }
}

export function availableToPay(account: Account): Money {
  if (account.type === 'CREDIT_CARD' || account.balance.isNegative()) {
    return Money.zero(account.balance.currency)
  }
  return account.balance
}
