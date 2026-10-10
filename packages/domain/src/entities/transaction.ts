import { type LocalDate } from '@/calendar/local-date'
import { type Money } from '@/money/money'
import { ValidationError } from '@/shared/domain-error'
import { onlyDigits } from '@/shared/digits'
import { guard } from '@/shared/guard'

export type TransactionKind = 'INCOME' | 'EXPENSE' | 'TRANSFER'

export const CATEGORIZED_BY = ['RULE', 'AI', 'USER'] as const
export type CategorizedBy = (typeof CATEGORIZED_BY)[number]

// One charge of a card purchase split over several bills.
export type Installment = {
  readonly number: number
  readonly count: number
  readonly purchaseOn: LocalDate | null
}

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
  readonly merchant: string | null
  // CPF or CNPJ digits of the other side of a payment, when the bank says.
  readonly counterparty: string | null
  readonly installment: Installment | null
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
  | 'merchant'
  | 'counterparty'
  | 'installment'
> & {
  categoryId?: string | null
  transferGroupId?: string | null
  externalId?: string | null
  invoiceId?: string | null
  note?: string | null
  categorizedBy?: CategorizedBy | null
  categoryConfidence?: number | null
  merchant?: string | null
  counterparty?: string | null
  installment?: Installment | null
}

// A masked or partial document would match strangers, so only a whole CPF or
// CNPJ counts.
export function toCounterparty(value: string | null): string | null {
  const digits = onlyDigits(value ?? '')
  return digits.length === 11 || digits.length === 14 ? digits : null
}

function checkInstallment(installment: Installment): Installment {
  const { number, count } = installment
  const whole = Number.isInteger(number) && Number.isInteger(count)
  if (!whole || count < 2 || number < 1 || number > count) {
    throw new ValidationError('An installment is 1 to N of N, with N >= 2.')
  }
  return installment
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
    merchant: input.merchant?.trim() || null,
    counterparty: toCounterparty(input.counterparty ?? null),
    installment: input.installment ? checkInstallment(input.installment) : null,
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
