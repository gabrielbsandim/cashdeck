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
  type ReserveFunding,
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
  // Paid bills of the entity, the most recently paid first.
  listRecentPaid(
    tenantId: string,
    entityId: string,
    limit: number,
  ): Promise<Bill[]>
}

export interface PaymentRepository {
  savePlan(tenantId: string, plan: PaymentPlan): Promise<void>
  findPlan(tenantId: string, billId: string): Promise<PaymentPlan | null>
  addAttempt(tenantId: string, attempt: PaymentAttempt): Promise<void>
  // Inserts the attempt only when its id is new; false means another run
  // already holds it, so the caller must not call the rail.
  claimAttempt(tenantId: string, attempt: PaymentAttempt): Promise<boolean>
  listAttempts(tenantId: string, billId: string): Promise<PaymentAttempt[]>
  // Counted as `committedCentsOn` does; without a rail, across every rail.
  committedCents(
    tenantId: string,
    entityId: string,
    day: LocalDate,
    rail?: RailId,
  ): Promise<number>
}

export interface FundingRepository {
  listByDay(
    tenantId: string,
    entityId: string,
    day: LocalDate,
  ): Promise<ReserveFunding[]>
  // Fails when the round already exists, so two runs never fund twice.
  create(funding: ReserveFunding): Promise<void>
  update(funding: ReserveFunding): Promise<void>
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
  entityDailyCapCents: number | null
  paymentCapCents: number | null
  maxDeviationPercent: number | null
  // HH:MM in Sao Paulo time on the due date; a batch still unapproved after it
  // falls to assisted.
  approvalCutoff: string
}

export const DEFAULT_SAFETY_SETTINGS = {
  entityDailyCapCents: 1_000_000,
  paymentCapCents: 500_000,
  maxDeviationPercent: 30,
  approvalCutoff: '16:00',
} as const satisfies Partial<PaymentSettings>

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
  actorId?: string | null
  requestId?: string | null
}

// Who asked for a side effect: the app user behind the API token, or the
// scheduler when nobody did.
export type Actor = {
  kind: AuditEvent['actor']
  id: string | null
  requestId: string | null
}

export const SYSTEM_ACTOR: Actor = { kind: 'SYSTEM', id: null, requestId: null }

export interface AuditLog {
  record(event: AuditEvent): Promise<void>
}
