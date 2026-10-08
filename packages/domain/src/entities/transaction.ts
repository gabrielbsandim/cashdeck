import { type Money } from '@/money/money'
import { ValidationError } from '@/shared/domain-error'
import { guard } from '@/shared/guard'

export type TransactionKind = 'INCOME' | 'EXPENSE' | 'TRANSFER'

export type Transaction = {
  readonly id: string
  readonly tenantId: string
  readonly accountId: string
  readonly amount: Money
  readonly bookedOn: string
  readonly description: string
  readonly categoryId: string | null
  readonly transferGroupId: string | null
  readonly externalId: string | null
  readonly invoiceId: string | null
}

export type CreateTransactionInput = Omit<
  Transaction,
  'categoryId' | 'transferGroupId' | 'externalId' | 'invoiceId'
> & {
  categoryId?: string | null
  transferGroupId?: string | null
  externalId?: string | null
  invoiceId?: string | null
}

export function createTransaction(input: CreateTransactionInput): Transaction {
  if (input.amount.isZero()) {
    throw new ValidationError('A transaction must move money.')
  }
  if (!/^\d{4}-\d{2}-\d{2}$/.test(input.bookedOn)) {
    throw new ValidationError('bookedOn must be an ISO date.')
  }
  return {
    ...input,
    description: guard.notEmpty(input.description, 'Description'),
    categoryId: input.categoryId ?? null,
    transferGroupId: input.transferGroupId ?? null,
    externalId: input.externalId ?? null,
    invoiceId: input.invoiceId ?? null,
  }
}

export function transactionKind(transaction: Transaction): TransactionKind {
  if (transaction.transferGroupId !== null) {
    return 'TRANSFER'
  }
  return transaction.amount.isPositive() ? 'INCOME' : 'EXPENSE'
}
