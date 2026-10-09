import { type LocalDate } from '@/calendar/local-date'
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

// What a card issuer reports: the limit, what is left of it and the bill dates.
export type CreditLine = {
  readonly limit: Money
  readonly available: Money
  readonly closesOn: LocalDate | null
  readonly dueOn: LocalDate | null
  readonly brand: string | null
  // Charges not yet on a closed bill, when the issuer marks what it billed.
  readonly openBill: Money | null
}

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
  // Last digits of the account or card number, as the bank shows them.
  readonly numberSuffix: string | null
  readonly credit: CreditLine | null
}

export type CreateAccountInput = Omit<
  Account,
  | 'name'
  | 'isReserve'
  | 'connectionId'
  | 'externalId'
  | 'cdiPercent'
  | 'numberSuffix'
  | 'credit'
> & {
  name: string
  isReserve?: boolean
  connectionId?: string | null
  externalId?: string | null
  cdiPercent?: number | null
  numberSuffix?: string | null
  credit?: CreditLine | null
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
  const credit = input.credit ?? null
  if (credit && input.type !== 'CREDIT_CARD') {
    throw new ValidationError('Only a credit card has a credit line.')
  }
  return {
    ...input,
    name: guard.notEmpty(input.name, 'Account name'),
    isReserve,
    connectionId: input.connectionId ?? null,
    externalId: input.externalId ?? null,
    cdiPercent: input.cdiPercent ?? null,
    numberSuffix: input.numberSuffix ?? null,
    credit,
  }
}

// Share of the limit in use, 0 to 100, or null without a positive limit.
export function creditUsedPercent(credit: CreditLine): number | null {
  if (!credit.limit.isPositive()) {
    return null
  }
  const used = credit.limit.cents - credit.available.cents
  const percent = Math.round((used * 100) / credit.limit.cents)
  return Math.min(100, Math.max(0, percent))
}

// The open bill, else everything owed, which counts installments still ahead.
export function openBillOf(card: Account): Money {
  const owed = Money.of(Math.max(0, -card.balance.cents), card.balance.currency)
  return card.credit?.openBill ?? owed
}

export function availableToPay(account: Account): Money {
  if (account.type === 'CREDIT_CARD' || account.balance.isNegative()) {
    return Money.zero(account.balance.currency)
  }
  return account.balance
}
