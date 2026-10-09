import {
  type Account,
  type Bill,
  committedCentsOn,
  type EntityKind,
  type FinancialEntity,
  isSettled,
  type LocalDate,
  type Money,
  type PaymentAttempt,
  type PaymentPlan,
  type RailId,
  type ReserveFunding,
} from '@cashdeck/domain'
import {
  type AccountRepository,
  type AuditEvent,
  type AuditLog,
  type BillFilter,
  type BillRepository,
  DEFAULT_SAFETY_SETTINGS,
  type FinancialEntityRepository,
  type FundingRepository,
  type IdempotencyStore,
  type Page,
  type PageRequest,
  type PayeeDirectory,
  type PaymentRepository,
  type PaymentSettings,
  type PaymentSettingsProvider,
  type SecretStore,
} from '@/ports/repositories'

const key = (tenantId: string, id: string) => `${tenantId}:${id}`

export class InMemoryBillRepository implements BillRepository {
  private readonly rows = new Map<string, Bill>()

  async save(bill: Bill): Promise<void> {
    this.rows.set(key(bill.tenantId, bill.id), bill)
  }

  async findById(tenantId: string, id: string): Promise<Bill | null> {
    return this.rows.get(key(tenantId, id)) ?? null
  }

  private owned(tenantId: string, entityId: string): Bill[] {
    return [...this.rows.values()].filter(
      bill => bill.tenantId === tenantId && bill.entityId === entityId,
    )
  }

  async findByCode(
    tenantId: string,
    entityId: string,
    code: string,
  ): Promise<Bill | null> {
    const match = this.owned(tenantId, entityId).find(
      bill => bill.code === code && bill.status !== 'CANCELLED',
    )
    return match ?? null
  }

  async findByPixCode(
    tenantId: string,
    entityId: string,
    pixCode: string,
  ): Promise<Bill | null> {
    const match = this.owned(tenantId, entityId).find(
      bill => bill.pixCode === pixCode && bill.status !== 'CANCELLED',
    )
    return match ?? null
  }

  async listUnsettledByAmount(
    tenantId: string,
    entityId: string,
    amount: Money,
  ): Promise<Bill[]> {
    return this.owned(tenantId, entityId).filter(
      bill => bill.amount.equals(amount) && !isSettled(bill),
    )
  }

  async list(
    tenantId: string,
    filter: BillFilter,
    page: PageRequest,
  ): Promise<Page<Bill>> {
    const matching = [...this.rows.values()]
      .filter(bill => bill.tenantId === tenantId)
      .filter(bill => !filter.entityId || bill.entityId === filter.entityId)
      .filter(bill => !filter.status || bill.status === filter.status)
      .sort(
        (a, b) =>
          a.dueDate.localeCompare(b.dueDate) || a.id.localeCompare(b.id),
      )
    const start = Number(page.cursor ?? 0)
    const items = matching.slice(start, start + page.limit)
    const end = start + items.length
    return { items, nextCursor: end < matching.length ? String(end) : null }
  }

  async listRecentPaid(
    tenantId: string,
    entityId: string,
    limit: number,
  ): Promise<Bill[]> {
    const paidAt = (bill: Bill) => bill.paidAt?.getTime() ?? 0
    return [...this.rows.values()]
      .filter(bill => bill.tenantId === tenantId && bill.entityId === entityId)
      .filter(bill => bill.status === 'PAID')
      .sort((a, b) => paidAt(b) - paidAt(a))
      .slice(0, limit)
  }
}

// Attempts carry no entity, so the entity of each is read from the bills the
// repository was given; without bills every attempt counts.
export class InMemoryPaymentRepository implements PaymentRepository {
  private readonly plans = new Map<string, PaymentPlan>()
  private readonly attempts: Array<{
    tenantId: string
    attempt: PaymentAttempt
  }> = []

  constructor(private readonly bills?: BillRepository) {}

  async savePlan(tenantId: string, plan: PaymentPlan): Promise<void> {
    this.plans.set(key(tenantId, plan.billId), plan)
  }

  async findPlan(
    tenantId: string,
    billId: string,
  ): Promise<PaymentPlan | null> {
    return this.plans.get(key(tenantId, billId)) ?? null
  }

  async addAttempt(tenantId: string, attempt: PaymentAttempt): Promise<void> {
    this.attempts.push({ tenantId, attempt })
  }

  async claimAttempt(
    tenantId: string,
    attempt: PaymentAttempt,
  ): Promise<boolean> {
    const taken = this.attempts.some(
      row => row.tenantId === tenantId && row.attempt.id === attempt.id,
    )
    if (taken) {
      return false
    }
    this.attempts.push({ tenantId, attempt })
    return true
  }

  async listAttempts(
    tenantId: string,
    billId: string,
  ): Promise<PaymentAttempt[]> {
    return this.attempts
      .filter(row => row.tenantId === tenantId && row.attempt.billId === billId)
      .map(row => row.attempt)
  }

  async committedCents(
    tenantId: string,
    entityId: string,
    day: LocalDate,
    rail?: RailId,
  ): Promise<number> {
    const rows: PaymentAttempt[] = []
    for (const row of this.attempts) {
      const owner = await this.bills?.findById(tenantId, row.attempt.billId)
      const sameEntity = !this.bills || owner?.entityId === entityId
      const sameRail = rail === undefined || row.attempt.rail === rail
      if (row.tenantId === tenantId && sameEntity && sameRail) {
        rows.push(row.attempt)
      }
    }
    return committedCentsOn(rows, day)
  }
}

export class InMemoryFundingRepository implements FundingRepository {
  readonly rows: ReserveFunding[] = []

  async listByDay(
    tenantId: string,
    entityId: string,
    day: LocalDate,
  ): Promise<ReserveFunding[]> {
    return this.rows
      .filter(row => row.tenantId === tenantId && row.entityId === entityId)
      .filter(row => row.day === day)
      .sort((a, b) => a.round - b.round)
  }

  async create(funding: ReserveFunding): Promise<void> {
    const taken = this.rows.some(
      row =>
        row.tenantId === funding.tenantId &&
        row.entityId === funding.entityId &&
        row.day === funding.day &&
        row.round === funding.round,
    )
    if (taken) {
      throw new Error(`Funding round ${funding.idempotencyKey} exists.`)
    }
    this.rows.push(funding)
  }

  async update(funding: ReserveFunding): Promise<void> {
    const index = this.rows.findIndex(row => row.id === funding.id)
    this.rows.splice(index, 1, funding)
  }
}

export class InMemoryEntityRepository implements FinancialEntityRepository {
  private readonly rows = new Map<string, FinancialEntity>()

  constructor(entities: FinancialEntity[] = []) {
    for (const entity of entities) {
      this.rows.set(key(entity.tenantId, entity.id), entity)
    }
  }

  async save(entity: FinancialEntity): Promise<void> {
    this.rows.set(key(entity.tenantId, entity.id), entity)
  }

  async findById(
    tenantId: string,
    id: string,
  ): Promise<FinancialEntity | null> {
    return this.rows.get(key(tenantId, id)) ?? null
  }

  async findByKind(
    tenantId: string,
    kind: EntityKind,
  ): Promise<FinancialEntity | null> {
    const all = await this.list(tenantId)
    return all.find(entity => entity.kind === kind) ?? null
  }

  async list(tenantId: string): Promise<FinancialEntity[]> {
    return [...this.rows.values()].filter(
      entity => entity.tenantId === tenantId,
    )
  }
}

export class InMemoryAccountRepository implements AccountRepository {
  private readonly rows = new Map<string, Account>()

  async save(account: Account): Promise<void> {
    this.rows.set(key(account.tenantId, account.id), account)
  }

  async findById(tenantId: string, id: string): Promise<Account | null> {
    return this.rows.get(key(tenantId, id)) ?? null
  }

  async listByEntity(tenantId: string, entityId: string): Promise<Account[]> {
    const all = await this.list(tenantId)
    return all.filter(account => account.entityId === entityId)
  }

  async list(tenantId: string): Promise<Account[]> {
    return [...this.rows.values()].filter(
      account => account.tenantId === tenantId,
    )
  }
}

export class InMemoryIdempotencyStore implements IdempotencyStore {
  private readonly rows = new Map<string, unknown>()

  async find<T>(tenantId: string, idempotencyKey: string): Promise<T | null> {
    const stored = this.rows.get(key(tenantId, idempotencyKey))
    return stored === undefined ? null : (stored as T)
  }

  async save<T>(
    tenantId: string,
    idempotencyKey: string,
    _scope: string,
    result: T,
  ): Promise<void> {
    this.rows.set(key(tenantId, idempotencyKey), result)
  }
}

export class InMemorySecretStore implements SecretStore {
  private readonly rows = new Map<string, string>()

  async put(tenantId: string, name: string, sealed: string): Promise<void> {
    this.rows.set(key(tenantId, name), sealed)
  }

  async get(tenantId: string, name: string): Promise<string | null> {
    return this.rows.get(key(tenantId, name)) ?? null
  }

  async delete(tenantId: string, name: string): Promise<void> {
    this.rows.delete(key(tenantId, name))
  }
}

export class InMemoryPayeeDirectory implements PayeeDirectory {
  private readonly known = new Set<string>()

  async isKnown(
    tenantId: string,
    entityId: string,
    payeeKey: string,
  ): Promise<boolean> {
    return this.known.has(`${tenantId}:${entityId}:${payeeKey}`)
  }

  async remember(
    tenantId: string,
    entityId: string,
    payeeKey: string,
  ): Promise<void> {
    this.known.add(`${tenantId}:${entityId}:${payeeKey}`)
  }
}

export const DEFAULT_PAYMENT_SETTINGS: PaymentSettings = {
  killSwitch: false,
  enabledRails: [],
  dailyCapCents: {},
  confirmAboveCents: null,
  ...DEFAULT_SAFETY_SETTINGS,
}

// Every entity starts from the same defaults until its own settings are saved.
export class StaticPaymentSettings implements PaymentSettingsProvider {
  private readonly saved = new Map<string, PaymentSettings>()

  constructor(public settings: PaymentSettings = DEFAULT_PAYMENT_SETTINGS) {}

  async get(tenantId?: string, entityId?: string): Promise<PaymentSettings> {
    return this.saved.get(`${tenantId}:${entityId}`) ?? this.settings
  }

  async save(
    tenantId: string,
    entityId: string,
    settings: PaymentSettings,
  ): Promise<void> {
    this.saved.set(key(tenantId, entityId), settings)
  }
}

export class InMemoryAuditLog implements AuditLog {
  readonly events: AuditEvent[] = []

  async record(event: AuditEvent): Promise<void> {
    this.events.push(event)
  }
}
