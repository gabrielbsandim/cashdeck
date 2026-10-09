import { Prisma, type PrismaClient } from '@prisma/client'
import {
  type AccountRepository,
  type AuditEvent,
  type AuditLog,
  type BillFilter,
  type BillRepository,
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
} from '@cashdeck/application'
import {
  type Account,
  type Bill,
  committedCentsOn,
  type EntityKind,
  type FinancialEntity,
  type LocalDate,
  type Money,
  type PaymentAttempt,
  type PaymentPlan,
  type PaymentStep,
  type RailId,
  type ReserveFunding,
} from '@cashdeck/domain'
import {
  accountFromRow,
  accountToRow,
  attemptFromRow,
  attemptToRow,
  billFromRow,
  billToRow,
  entityFromRow,
  entityToRow,
  fundingFromRow,
  fundingToRow,
  toDbDate,
} from '@/repositories/mappers'

const json = (value: unknown) => value as Prisma.InputJsonValue

export class PrismaFinancialEntityRepository implements FinancialEntityRepository {
  constructor(private readonly db: PrismaClient) {}

  async save(entity: FinancialEntity): Promise<void> {
    const row = entityToRow(entity)
    await this.db.financialEntity.upsert({
      where: { id: row.id, tenantId: row.tenantId },
      create: row,
      update: row,
    })
  }

  async findById(
    tenantId: string,
    id: string,
  ): Promise<FinancialEntity | null> {
    const row = await this.db.financialEntity.findFirst({
      where: { tenantId, id },
    })
    return row ? entityFromRow(row) : null
  }

  async findByKind(
    tenantId: string,
    kind: EntityKind,
  ): Promise<FinancialEntity | null> {
    const row = await this.db.financialEntity.findFirst({
      where: { tenantId, kind },
      orderBy: { createdAt: 'asc' },
    })
    return row ? entityFromRow(row) : null
  }

  async list(tenantId: string): Promise<FinancialEntity[]> {
    const rows = await this.db.financialEntity.findMany({
      where: { tenantId },
      orderBy: { kind: 'asc' },
    })
    return rows.map(entityFromRow)
  }
}

export class PrismaAccountRepository implements AccountRepository {
  constructor(private readonly db: PrismaClient) {}

  async save(account: Account): Promise<void> {
    const row = accountToRow(account)
    await this.db.account.upsert({
      where: { id: row.id, tenantId: row.tenantId },
      create: row,
      update: row,
    })
  }

  async findById(tenantId: string, id: string): Promise<Account | null> {
    const row = await this.db.account.findFirst({ where: { tenantId, id } })
    return row ? accountFromRow(row) : null
  }

  async listByEntity(tenantId: string, entityId: string): Promise<Account[]> {
    const rows = await this.db.account.findMany({
      where: { tenantId, entityId },
      orderBy: { name: 'asc' },
    })
    return rows.map(accountFromRow)
  }

  async list(tenantId: string): Promise<Account[]> {
    const rows = await this.db.account.findMany({
      where: { tenantId },
      orderBy: { name: 'asc' },
    })
    return rows.map(accountFromRow)
  }
}

export class PrismaBillRepository implements BillRepository {
  constructor(private readonly db: PrismaClient) {}

  async save(bill: Bill): Promise<void> {
    const row = billToRow(bill)
    await this.db.bill.upsert({
      where: { id: row.id, tenantId: row.tenantId },
      create: row,
      update: row,
    })
  }

  async findById(tenantId: string, id: string): Promise<Bill | null> {
    const row = await this.db.bill.findFirst({ where: { tenantId, id } })
    return row ? billFromRow(row) : null
  }

  async findByCode(
    tenantId: string,
    entityId: string,
    code: string,
  ): Promise<Bill | null> {
    const row = await this.db.bill.findFirst({
      where: { tenantId, entityId, code, status: { not: 'CANCELLED' } },
      orderBy: { createdAt: 'asc' },
    })
    return row ? billFromRow(row) : null
  }

  async findByPixCode(
    tenantId: string,
    entityId: string,
    pixCode: string,
  ): Promise<Bill | null> {
    const row = await this.db.bill.findFirst({
      where: { tenantId, entityId, pixCode, status: { not: 'CANCELLED' } },
      orderBy: { createdAt: 'asc' },
    })
    return row ? billFromRow(row) : null
  }

  async listUnsettledByAmount(
    tenantId: string,
    entityId: string,
    amount: Money,
  ): Promise<Bill[]> {
    const rows = await this.db.bill.findMany({
      where: {
        tenantId,
        entityId,
        amountCents: BigInt(amount.cents),
        currency: amount.currency,
        status: { notIn: ['PAID', 'CANCELLED'] },
      },
      orderBy: { createdAt: 'asc' },
    })
    return rows.map(billFromRow)
  }

  async list(
    tenantId: string,
    filter: BillFilter,
    page: PageRequest,
  ): Promise<Page<Bill>> {
    const skip = Number(page.cursor ?? 0)
    const rows = await this.db.bill.findMany({
      where: { tenantId, entityId: filter.entityId, status: filter.status },
      orderBy: [{ dueDate: 'asc' }, { id: 'asc' }],
      skip,
      take: page.limit + 1,
    })
    const items = rows.slice(0, page.limit).map(billFromRow)
    const hasMore = rows.length > page.limit
    return { items, nextCursor: hasMore ? String(skip + items.length) : null }
  }

  async listRecentPaid(
    tenantId: string,
    entityId: string,
    limit: number,
  ): Promise<Bill[]> {
    const rows = await this.db.bill.findMany({
      where: { tenantId, entityId, status: 'PAID' },
      orderBy: [{ paidAt: 'desc' }, { id: 'asc' }],
      take: limit,
    })
    return rows.map(billFromRow)
  }
}

const isUniqueViolation = (error: unknown) =>
  error instanceof Prisma.PrismaClientKnownRequestError &&
  error.code === 'P2002'
const DAY_MS = 24 * 60 * 60 * 1000

// Brazil has had no daylight saving since 2019, so a Sao Paulo day is a fixed
// UTC-03:00 window; caps are counted per local banking day.
export function saoPauloDayRange(day: LocalDate): { gte: Date; lt: Date } {
  const gte = new Date(`${day}T00:00:00.000-03:00`)
  return { gte, lt: new Date(gte.getTime() + DAY_MS) }
}

type StoredStep = Omit<PaymentStep, 'method'> & {
  method?: PaymentStep['method']
}

// Plans stored before Pix-first routing carry no method; they paid barcodes.
const withMethod = (step: StoredStep): PaymentStep => ({
  ...step,
  method: step.method ?? 'BOLETO',
})

export class PrismaPaymentRepository implements PaymentRepository {
  constructor(private readonly db: PrismaClient) {}

  async savePlan(tenantId: string, plan: PaymentPlan): Promise<void> {
    const data = {
      tenantId,
      steps: json(plan.steps),
      currentStep: plan.currentStep,
    }
    await this.db.paymentPlan.upsert({
      where: { billId: plan.billId, tenantId },
      create: { billId: plan.billId, ...data },
      update: data,
    })
  }

  async findPlan(
    tenantId: string,
    billId: string,
  ): Promise<PaymentPlan | null> {
    const row = await this.db.paymentPlan.findFirst({
      where: { tenantId, billId },
    })
    if (!row) {
      return null
    }
    return {
      billId: row.billId,
      steps: (row.steps as unknown as StoredStep[]).map(withMethod),
      currentStep: row.currentStep,
    }
  }

  async addAttempt(tenantId: string, attempt: PaymentAttempt): Promise<void> {
    await this.db.paymentAttempt.create({
      data: attemptToRow(tenantId, attempt),
    })
  }

  async listAttempts(
    tenantId: string,
    billId: string,
  ): Promise<PaymentAttempt[]> {
    const rows = await this.db.paymentAttempt.findMany({
      where: { tenantId, billId },
      orderBy: [{ at: 'asc' }, { stepIndex: 'asc' }],
    })
    return rows.map(attemptFromRow)
  }

  async claimAttempt(
    tenantId: string,
    attempt: PaymentAttempt,
  ): Promise<boolean> {
    try {
      await this.addAttempt(tenantId, attempt)
      return true
    } catch (error) {
      if (isUniqueViolation(error)) {
        return false
      }
      throw error
    }
  }

  // Keys first tried that day, then every row of those keys, so the domain
  // counts each payment once by its latest state.
  async committedCents(
    tenantId: string,
    entityId: string,
    day: LocalDate,
    rail?: RailId,
  ): Promise<number> {
    const keys = await this.db.paymentAttempt.findMany({
      where: { tenantId, rail, bill: { entityId }, at: saoPauloDayRange(day) },
      select: { idempotencyKey: true },
      distinct: ['idempotencyKey'],
    })
    if (keys.length === 0) {
      return 0
    }
    const rows = await this.db.paymentAttempt.findMany({
      where: {
        tenantId,
        idempotencyKey: { in: keys.map(row => row.idempotencyKey) },
      },
      orderBy: [{ at: 'asc' }, { id: 'asc' }],
    })
    return committedCentsOn(rows.map(attemptFromRow), day)
  }
}

export class PrismaFundingRepository implements FundingRepository {
  constructor(private readonly db: PrismaClient) {}

  async listByDay(
    tenantId: string,
    entityId: string,
    day: LocalDate,
  ): Promise<ReserveFunding[]> {
    const rows = await this.db.reserveFunding.findMany({
      where: { tenantId, entityId, day: toDbDate(day) },
      orderBy: { round: 'asc' },
    })
    return rows.map(fundingFromRow)
  }

  async create(funding: ReserveFunding): Promise<void> {
    await this.db.reserveFunding.create({ data: fundingToRow(funding) })
  }

  async update(funding: ReserveFunding): Promise<void> {
    const { id, tenantId, ...data } = fundingToRow(funding)
    await this.db.reserveFunding.update({ where: { id, tenantId }, data })
  }
}

export class PrismaPayeeDirectory implements PayeeDirectory {
  constructor(private readonly db: PrismaClient) {}

  async isKnown(
    tenantId: string,
    entityId: string,
    payeeKey: string,
  ): Promise<boolean> {
    const row = await this.db.payee.findUnique({
      where: { tenantId_entityId_key: { tenantId, entityId, key: payeeKey } },
    })
    return row !== null
  }

  async remember(
    tenantId: string,
    entityId: string,
    payeeKey: string,
  ): Promise<void> {
    const id = { tenantId, entityId, key: payeeKey }
    await this.db.payee.upsert({
      where: { tenantId_entityId_key: id },
      create: id,
      update: {},
    })
  }
}

const toNumber = (value: bigint | null) =>
  value === null ? null : Number(value)
const toBigInt = (value: number | null) =>
  value === null ? null : BigInt(value)

export class PrismaPaymentSettings implements PaymentSettingsProvider {
  constructor(
    private readonly db: PrismaClient,
    private readonly fallback: PaymentSettings,
  ) {}

  async get(tenantId: string, entityId: string): Promise<PaymentSettings> {
    const row = await this.db.paymentSettings.findUnique({
      where: { tenantId_entityId: { tenantId, entityId } },
    })
    if (!row) {
      return this.fallback
    }
    return {
      killSwitch: row.killSwitch,
      enabledRails: row.enabledRails,
      dailyCapCents: row.dailyCapCents as PaymentSettings['dailyCapCents'],
      confirmAboveCents: toNumber(row.confirmAboveCents),
      entityDailyCapCents: toNumber(row.entityDailyCapCents),
      paymentCapCents: toNumber(row.paymentCapCents),
      maxDeviationPercent: row.maxDeviationPercent,
      approvalCutoff: row.approvalCutoff,
    }
  }

  async save(
    tenantId: string,
    entityId: string,
    settings: PaymentSettings,
  ): Promise<void> {
    const data = {
      killSwitch: settings.killSwitch,
      enabledRails: [...settings.enabledRails],
      dailyCapCents: json(settings.dailyCapCents),
      confirmAboveCents: toBigInt(settings.confirmAboveCents),
      entityDailyCapCents: toBigInt(settings.entityDailyCapCents),
      paymentCapCents: toBigInt(settings.paymentCapCents),
      maxDeviationPercent: settings.maxDeviationPercent,
      approvalCutoff: settings.approvalCutoff,
    }
    await this.db.paymentSettings.upsert({
      where: { tenantId_entityId: { tenantId, entityId } },
      create: { tenantId, entityId, ...data },
      update: data,
    })
  }
}

export class PrismaAuditLog implements AuditLog {
  constructor(private readonly db: PrismaClient) {}

  async record(event: AuditEvent): Promise<void> {
    await this.db.auditEvent.create({
      data: { ...event, details: json(event.details) },
    })
  }
}

export class PrismaIdempotencyStore implements IdempotencyStore {
  constructor(private readonly db: PrismaClient) {}

  async find<T>(tenantId: string, key: string): Promise<T | null> {
    const row = await this.db.idempotencyRecord.findUnique({
      where: { tenantId_key: { tenantId, key } },
    })
    return row ? (row.result as T) : null
  }

  // The first stored result wins, so a concurrent retry cannot overwrite it.
  async save<T>(
    tenantId: string,
    key: string,
    scope: string,
    result: T,
  ): Promise<void> {
    await this.db.idempotencyRecord.upsert({
      where: { tenantId_key: { tenantId, key } },
      create: { tenantId, key, scope, result: json(result) },
      update: {},
    })
  }
}

export class PrismaSecretStore implements SecretStore {
  constructor(private readonly db: PrismaClient) {}

  async put(tenantId: string, name: string, sealed: string): Promise<void> {
    await this.db.secret.upsert({
      where: { tenantId_name: { tenantId, name } },
      create: { tenantId, name, sealed },
      update: { sealed },
    })
  }

  async get(tenantId: string, name: string): Promise<string | null> {
    const row = await this.db.secret.findUnique({
      where: { tenantId_name: { tenantId, name } },
    })
    return row?.sealed ?? null
  }

  async delete(tenantId: string, name: string): Promise<void> {
    await this.db.secret.deleteMany({ where: { tenantId, name } })
  }
}

export function createPrismaRepositories(
  db: PrismaClient,
  settings: PaymentSettings,
) {
  return {
    entities: new PrismaFinancialEntityRepository(db),
    accounts: new PrismaAccountRepository(db),
    bills: new PrismaBillRepository(db),
    payments: new PrismaPaymentRepository(db),
    fundings: new PrismaFundingRepository(db),
    payees: new PrismaPayeeDirectory(db),
    settings: new PrismaPaymentSettings(db, settings),
    audit: new PrismaAuditLog(db),
    idempotency: new PrismaIdempotencyStore(db),
    secrets: new PrismaSecretStore(db),
  }
}
