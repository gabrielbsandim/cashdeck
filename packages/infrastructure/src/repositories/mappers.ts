import {
  createAccount,
  createFinancialEntity,
  Money,
  type Account,
  type AccountOrigin,
  type AccountType,
  type Bill,
  type BillKind,
  type BillSource,
  type BillStatus,
  type EntityKind,
  type FinancialEntity,
  type LocalDate,
  type PaidBy,
  type PaymentMethod,
  type PaymentAttempt,
  type AttemptOutcome,
  type RailId,
  type StepMode,
  type TaxRegime,
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

export function toDbDate(day: LocalDate): Date {
  return new Date(`${day}T00:00:00.000Z`)
}

export function fromDbDate(value: Date): LocalDate {
  return value.toISOString().slice(0, 10)
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
  })
}

export function accountToRow(account: Account): AccountRow {
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
