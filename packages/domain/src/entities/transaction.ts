import { type Money } from '@/money/money'
import { ValidationError } from '@/shared/domain-error'
import { guard } from '@/shared/guard'

export type TransactionKind = 'INCOME' | 'EXPENSE' | 'TRANSFER'

export const CATEGORIZED_BY = ['RULE', 'AI', 'USER'] as const
export type CategorizedBy = (typeof CATEGORIZED_BY)[number]

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
  readonly note: string | null
  readonly categorizedBy: CategorizedBy | null
  // 0 to 1; how sure the source was, so a weak AI guess can be told apart.
  readonly categoryConfidence: number | null
}

export type CreateTransactionInput = Omit<
  Transaction,
  | 'categoryId'
  | 'transferGroupId'
  | 'externalId'
  | 'invoiceId'
  | 'note'
  | 'categorizedBy'
  | 'categoryConfidence'
> & {
  categoryId?: string | null
  transferGroupId?: string | null
  externalId?: string | null
  invoiceId?: string | null
  note?: string | null
  categorizedBy?: CategorizedBy | null
  categoryConfidence?: number | null
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
    note: input.note ?? null,
    categorizedBy: input.categorizedBy ?? null,
    categoryConfidence: input.categoryConfidence ?? null,
  }
}

export type CategoryAssignment = {
  categoryId: string | null
  by: CategorizedBy
  confidence: number
}

export function categorize(
  transaction: Transaction,
  assignment: CategoryAssignment,
): Transaction {
  if (assignment.confidence < 0 || assignment.confidence > 1) {
    throw new ValidationError('Confidence must be between 0 and 1.')
  }
  // A cleared category keeps who cleared it, so a rule or the model does not
  // fill it back in.
  if (assignment.categoryId === null) {
    return {
      ...transaction,
      categoryId: null,
      categorizedBy: assignment.by,
      categoryConfidence: null,
    }
  }
  return {
    ...transaction,
    categoryId: assignment.categoryId,
    categorizedBy: assignment.by,
    categoryConfidence: assignment.confidence,
  }
}

const MAX_NOTE_LENGTH = 500

export function withNote(
  transaction: Transaction,
  note: string | null,
): Transaction {
  const trimmed = note?.trim() ?? ''
  if (trimmed.length > MAX_NOTE_LENGTH) {
    throw new ValidationError('A note has at most 500 characters.')
  }
  return { ...transaction, note: trimmed === '' ? null : trimmed }
}

export function transactionKind(transaction: Transaction): TransactionKind {
  if (transaction.transferGroupId !== null) {
    return 'TRANSFER'
  }
  return transaction.amount.isPositive() ? 'INCOME' : 'EXPENSE'
}
