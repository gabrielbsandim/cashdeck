import {
  type Account,
  type Bill,
  type BillStatus,
  type EntityKind,
  type FinancialEntity,
  type LocalDate,
  type Money,
  type PaymentAttempt,
  type PaymentPlan,
  type RailId,
} from '@cashdeck/domain'

export type Page<T> = { items: T[]; nextCursor: string | null }

export type PageRequest = { cursor?: string | null; limit: number }

export type BillFilter = { entityId?: string; status?: BillStatus }

export interface BillRepository {
  save(bill: Bill): Promise<void>
  findById(tenantId: string, id: string): Promise<Bill | null>
  findByCode(
    tenantId: string,
    entityId: string,
    code: string,
  ): Promise<Bill | null>
  findByPixCode(
    tenantId: string,
    entityId: string,
    pixCode: string,
  ): Promise<Bill | null>
  // Bills not yet paid or cancelled, for pairing the two halves of a bolepix.
  listUnsettledByAmount(
    tenantId: string,
    entityId: string,
    amount: Money,
  ): Promise<Bill[]>
  list(
    tenantId: string,
    filter: BillFilter,
    page: PageRequest,
  ): Promise<Page<Bill>>
}

export interface PaymentRepository {
  savePlan(tenantId: string, plan: PaymentPlan): Promise<void>
  findPlan(tenantId: string, billId: string): Promise<PaymentPlan | null>
  addAttempt(tenantId: string, attempt: PaymentAttempt): Promise<void>
  listAttempts(tenantId: string, billId: string): Promise<PaymentAttempt[]>
  committedCents(
    tenantId: string,
    rail: RailId,
    day: LocalDate,
  ): Promise<number>
}

export interface FinancialEntityRepository {
  save(entity: FinancialEntity): Promise<void>
  findById(tenantId: string, id: string): Promise<FinancialEntity | null>
  findByKind(
    tenantId: string,
    kind: EntityKind,
  ): Promise<FinancialEntity | null>
  list(tenantId: string): Promise<FinancialEntity[]>
}

export interface AccountRepository {
  save(account: Account): Promise<void>
  findById(tenantId: string, id: string): Promise<Account | null>
  listByEntity(tenantId: string, entityId: string): Promise<Account[]>
  list(tenantId: string): Promise<Account[]>
}

export interface IdempotencyStore {
  find<T>(tenantId: string, key: string): Promise<T | null>
  save<T>(
    tenantId: string,
    key: string,
    scope: string,
    result: T,
  ): Promise<void>
}

export interface SecretStore {
  put(tenantId: string, name: string, sealed: string): Promise<void>
  get(tenantId: string, name: string): Promise<string | null>
  delete(tenantId: string, name: string): Promise<void>
}

export interface PayeeDirectory {
  isKnown(
    tenantId: string,
    entityId: string,
    payeeKey: string,
  ): Promise<boolean>
  remember(tenantId: string, entityId: string, payeeKey: string): Promise<void>
}

export type PaymentSettings = {
  killSwitch: boolean
  enabledRails: RailId[]
  dailyCapCents: Partial<Record<RailId, number>>
  confirmAboveCents: number | null
}

export interface PaymentSettingsProvider {
  get(tenantId: string, entityId: string): Promise<PaymentSettings>
  save(
    tenantId: string,
    entityId: string,
    settings: PaymentSettings,
  ): Promise<void>
}

export type AuditEvent = {
  id: string
  tenantId: string
  actor: 'SYSTEM' | 'USER'
  action: string
  subjectId: string
  rail: RailId | null
  result: string
  details: Record<string, unknown>
  at: Date
}

export interface AuditLog {
  record(event: AuditEvent): Promise<void>
}
