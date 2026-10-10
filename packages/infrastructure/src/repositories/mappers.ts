import {
  createAccount,
  createFinancialEntity,
  createTransaction,
  Money,
  type Account,
  type AccountOrigin,
  type AccountType,
  type Bill,
  type BillKind,
  type BillSource,
  type BillStatus,
  type CategorizedBy,
  type CreditLine,
  type EntityKind,
  type FinancialEntity,
  type FundingStatus,
  type LocalDate,
  type PaidBy,
  type PaymentMethod,
  type PaymentAttempt,
  type AttemptOutcome,
  type RailId,
  type ReserveFunding,
  type StepMode,
  type TaxRegime,
  type Transaction,
} from '@cashdeck/domain'

export type EntityRow = {
  id: string
  tenantId: string
  kind: EntityKind
  name: string
  taxId: string
  taxRegime: TaxRegime | null
}

export type AccountRow = {
  id: string
  tenantId: string
  entityId: string
  institutionId: string
  name: string
  type: AccountType
  origin: AccountOrigin
  isReserve: boolean
  balanceCents: bigint
  currency: string
  connectionId: string | null
  externalId: string | null
  cdiPercent: number | null
  numberSuffix: string | null
  creditLimitCents: bigint | null
  creditAvailableCents: bigint | null
  creditClosesOn: Date | null
  creditDueOn: Date | null
  creditBrand: string | null
  creditOpenBillCents: bigint | null
}

export type TransactionRow = {
  id: string
  tenantId: string
  accountId: string
  externalId: string | null
  amountCents: bigint
  currency: string
  bookedOn: Date
  description: string
  categoryId: string | null
  transferGroupId: string | null
  invoiceId: string | null
  note: string | null
  categorizedBy: CategorizedBy | null
  categoryConfidence: number | null
  merchant: string | null
  counterparty: string | null
  installmentNumber: number | null
  installmentCount: number | null
  purchaseOn: Date | null
  provisional: boolean
}

export type BillRow = {
  id: string
  tenantId: string
  entityId: string
  kind: BillKind
  status: BillStatus
  source: BillSource
  payee: string | null
  amountCents: bigint
  currency: string
  dueDate: Date
  code: string | null
  pixCode: string | null
  createdAt: Date
  paidAt: Date | null
  paidBy: PaidBy | null
}

export type AttemptRow = {
  id: string
  tenantId: string
  billId: string
  stepIndex: number
  rail: RailId
  mode: StepMode
  method: PaymentMethod
  amountCents: bigint
  outcome: AttemptOutcome
  reason: string | null
  externalId: string | null
  idempotencyKey: string
  at: Date
}

export type FundingRow = {
  id: string
  tenantId: string
  entityId: string
  day: Date
  round: number
  billIds: string[]
  billsTotalCents: bigint
  availableCents: bigint | null
  amountCents: bigint
  currency: string
  status: FundingStatus
  reason: string | null
  externalId: string | null
  idempotencyKey: string
  at: Date
}

export function toDbDate(day: LocalDate): Date {
  return new Date(`${day}T00:00:00.000Z`)
}

export function fromDbDate(value: Date): LocalDate {
  return value.toISOString().slice(0, 10)
}

const optionalDate = (value: Date | null) => (value ? fromDbDate(value) : null)

const optionalDbDate = (day: LocalDate | null) => (day ? toDbDate(day) : null)

function creditFromRow(row: AccountRow): CreditLine | null {
  if (row.creditLimitCents === null) {
    return null
  }
  return {
    limit: Money.of(Number(row.creditLimitCents), row.currency),
    available: Money.of(Number(row.creditAvailableCents ?? 0), row.currency),
    closesOn: optionalDate(row.creditClosesOn),
    dueOn: optionalDate(row.creditDueOn),
    brand: row.creditBrand,
    openBill:
      row.creditOpenBillCents === null
        ? null
        : Money.of(Number(row.creditOpenBillCents), row.currency),
  }
}

function installmentFromRow(row: TransactionRow) {
  if (row.installmentNumber === null || row.installmentCount === null) {
    return null
  }
  return {
    number: row.installmentNumber,
    count: row.installmentCount,
    purchaseOn: optionalDate(row.purchaseOn),
  }
}

export function entityFromRow(row: EntityRow): FinancialEntity {
  return createFinancialEntity(row)
}

export function entityToRow(entity: FinancialEntity): EntityRow {
  return {
    id: entity.id,
    tenantId: entity.tenantId,
    kind: entity.kind,
    name: entity.name,
    taxId: entity.taxId.value,
    taxRegime: entity.taxRegime,
  }
}

export function accountFromRow(row: AccountRow): Account {
  return createAccount({
    id: row.id,
    tenantId: row.tenantId,
    entityId: row.entityId,
    institutionId: row.institutionId,
    name: row.name,
    type: row.type,
    origin: row.origin,
    isReserve: row.isReserve,
    balance: Money.of(Number(row.balanceCents), row.currency),
    connectionId: row.connectionId,
    externalId: row.externalId,
    cdiPercent: row.cdiPercent,
    numberSuffix: row.numberSuffix,
    credit: creditFromRow(row),
  })
}

export function accountToRow(account: Account): AccountRow {
  const credit = account.credit
  return {
    id: account.id,
    tenantId: account.tenantId,
    entityId: account.entityId,
    institutionId: account.institutionId,
    name: account.name,
    type: account.type,
    origin: account.origin,
    isReserve: account.isReserve,
    balanceCents: BigInt(account.balance.cents),
    currency: account.balance.currency,
    connectionId: account.connectionId,
    externalId: account.externalId,
    cdiPercent: account.cdiPercent,
    numberSuffix: account.numberSuffix,
    creditLimitCents: credit ? BigInt(credit.limit.cents) : null,
    creditAvailableCents: credit ? BigInt(credit.available.cents) : null,
    creditClosesOn: optionalDbDate(credit?.closesOn ?? null),
    creditDueOn: optionalDbDate(credit?.dueOn ?? null),
    creditBrand: credit?.brand ?? null,
    creditOpenBillCents: credit?.openBill
      ? BigInt(credit.openBill.cents)
      : null,
  }
}

export function transactionFromRow(row: TransactionRow): Transaction {
  return createTransaction({
    id: row.id,
    tenantId: row.tenantId,
    accountId: row.accountId,
    amount: Money.of(Number(row.amountCents), row.currency),
    bookedOn: fromDbDate(row.bookedOn),
    description: row.description,
    categoryId: row.categoryId,
    transferGroupId: row.transferGroupId,
    externalId: row.externalId,
    invoiceId: row.invoiceId,
    note: row.note,
    categorizedBy: row.categorizedBy,
    categoryConfidence: row.categoryConfidence,
    merchant: row.merchant,
    counterparty: row.counterparty,
    installment: installmentFromRow(row),
    provisional: row.provisional,
  })
}

export function transactionToRow(transaction: Transaction): TransactionRow {
  return {
    id: transaction.id,
    tenantId: transaction.tenantId,
    accountId: transaction.accountId,
    externalId: transaction.externalId,
    amountCents: BigInt(transaction.amount.cents),
    currency: transaction.amount.currency,
    bookedOn: toDbDate(transaction.bookedOn),
    description: transaction.description,
    categoryId: transaction.categoryId,
    transferGroupId: transaction.transferGroupId,
    invoiceId: transaction.invoiceId,
    note: transaction.note,
    categorizedBy: transaction.categorizedBy,
    categoryConfidence: transaction.categoryConfidence,
    merchant: transaction.merchant,
    counterparty: transaction.counterparty,
    installmentNumber: transaction.installment?.number ?? null,
    installmentCount: transaction.installment?.count ?? null,
    purchaseOn: optionalDbDate(transaction.installment?.purchaseOn ?? null),
    provisional: transaction.provisional,
  }
}

export function billFromRow(row: BillRow): Bill {
  return {
    id: row.id,
    tenantId: row.tenantId,
    entityId: row.entityId,
    kind: row.kind,
    status: row.status,
    source: row.source,
    payee: row.payee,
    amount: Money.of(Number(row.amountCents), row.currency),
    dueDate: fromDbDate(row.dueDate),
    code: row.code,
    pixCode: row.pixCode,
    createdAt: row.createdAt,
    paidAt: row.paidAt,
    paidBy: row.paidBy,
  }
}

export function billToRow(bill: Bill): BillRow {
  return {
    id: bill.id,
    tenantId: bill.tenantId,
    entityId: bill.entityId,
    kind: bill.kind,
    status: bill.status,
    source: bill.source,
    payee: bill.payee,
    amountCents: BigInt(bill.amount.cents),
    currency: bill.amount.currency,
    dueDate: toDbDate(bill.dueDate),
    code: bill.code,
    pixCode: bill.pixCode,
    createdAt: bill.createdAt,
    paidAt: bill.paidAt,
    paidBy: bill.paidBy,
  }
}

export function attemptFromRow(row: AttemptRow): PaymentAttempt {
  return {
    id: row.id,
    billId: row.billId,
    stepIndex: row.stepIndex,
    rail: row.rail,
    mode: row.mode,
    method: row.method,
    amount: Money.of(Number(row.amountCents)),
    outcome: row.outcome,
    reason: row.reason,
    externalId: row.externalId,
    idempotencyKey: row.idempotencyKey,
    at: row.at,
  }
}

export function attemptToRow(
  tenantId: string,
  attempt: PaymentAttempt,
): AttemptRow {
  return {
    id: attempt.id,
    tenantId,
    billId: attempt.billId,
    stepIndex: attempt.stepIndex,
    rail: attempt.rail,
    mode: attempt.mode,
    method: attempt.method,
    amountCents: BigInt(attempt.amount.cents),
    outcome: attempt.outcome,
    reason: attempt.reason,
    externalId: attempt.externalId,
    idempotencyKey: attempt.idempotencyKey,
    at: attempt.at,
  }
}

export function fundingFromRow(row: FundingRow): ReserveFunding {
  const money = (cents: bigint) => Money.of(Number(cents))
  return {
    id: row.id,
    tenantId: row.tenantId,
    entityId: row.entityId,
    day: fromDbDate(row.day),
    round: row.round,
    billIds: row.billIds,
    billsTotal: money(row.billsTotalCents),
    available: row.availableCents === null ? null : money(row.availableCents),
    amount: money(row.amountCents),
    status: row.status,
    reason: row.reason,
    externalId: row.externalId,
    idempotencyKey: row.idempotencyKey,
    at: row.at,
  }
}

export function fundingToRow(funding: ReserveFunding): FundingRow {
  return {
    id: funding.id,
    tenantId: funding.tenantId,
    entityId: funding.entityId,
    day: toDbDate(funding.day),
    round: funding.round,
    billIds: [...funding.billIds],
    billsTotalCents: BigInt(funding.billsTotal.cents),
    availableCents:
      funding.available === null ? null : BigInt(funding.available.cents),
    amountCents: BigInt(funding.amount.cents),
    currency: funding.amount.currency,
    status: funding.status,
    reason: funding.reason,
    externalId: funding.externalId,
    idempotencyKey: funding.idempotencyKey,
    at: funding.at,
  }
}
