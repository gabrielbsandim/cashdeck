import { type PrismaClient } from '@prisma/client'
import { describe, expect, it, vi } from 'vitest'
import {
  ASSISTED_STEP,
  createAccount,
  createBill,
  createFinancialEntity,
  createPaymentPlan,
  Money,
  type PaymentAttempt,
} from '@cashdeck/domain'
import {
  accountToRow,
  attemptToRow,
  billToRow,
  entityToRow,
} from '@/repositories/mappers'
import {
  createPrismaRepositories,
  saoPauloDayRange,
} from '@/repositories/prisma-repositories'

const TENANT = 't1'
const NOW = new Date('2026-10-08T12:00:00.000Z')

const DELEGATES = [
  'financialEntity',
  'account',
  'bill',
  'paymentPlan',
  'paymentAttempt',
  'payee',
  'paymentSettings',
  'auditEvent',
  'idempotencyRecord',
  'secret',
] as const
const METHODS = [
  'upsert',
  'findFirst',
  'findUnique',
  'findMany',
  'create',
  'aggregate',
  'deleteMany',
] as const

type Delegate = Record<(typeof METHODS)[number], ReturnType<typeof vi.fn>>

function mockClient() {
  const db = Object.fromEntries(
    DELEGATES.map(name => [
      name,
      Object.fromEntries(METHODS.map(method => [method, vi.fn()])),
    ]),
  ) as Record<(typeof DELEGATES)[number], Delegate>
  const settings = {
    killSwitch: false,
    enabledRails: [],
    dailyCapCents: {},
    confirmAboveCents: null,
  }
  return {
    db,
    settings,
    repos: createPrismaRepositories(db as unknown as PrismaClient, settings),
  }
}

const entity = createFinancialEntity({
  id: 'company',
  tenantId: TENANT,
  kind: 'PJ',
  name: 'Company',
  taxId: '11222333000181',
  taxRegime: 'SIMPLES_NACIONAL',
})

const account = createAccount({
  id: 'a1',
  tenantId: TENANT,
  entityId: 'company',
  institutionId: 'bank',
  name: 'Checking',
  type: 'CHECKING',
  origin: 'MANUAL',
  balance: Money.of(5000),
})

const bill = createBill({
  id: 'b1',
  tenantId: TENANT,
  entityId: 'company',
  kind: 'BOLETO',
  source: 'MANUAL',
  payee: 'Supplier',
  amount: Money.of(12345),
  dueDate: '2026-10-20',
  code: '00199160500000123450000002800012345678901217',
  createdAt: NOW,
})

const attempt: PaymentAttempt = {
  id: 'p1',
  billId: 'b1',
  stepIndex: 0,
  rail: 'INTER_EMPRESAS',
  mode: 'AUTOMATIC',
  method: 'BOLETO',
  amount: Money.of(12345),
  outcome: 'PAID',
  reason: null,
  externalId: 'ext',
  idempotencyKey: 'b1:0',
  at: NOW,
}

describe('PrismaFinancialEntityRepository', () => {
  it('upserts scoped by tenant and rebuilds the entity', async () => {
    const { db, repos } = mockClient()
    await repos.entities.save(entity)
    expect(db.financialEntity.upsert).toHaveBeenCalledWith(
      expect.objectContaining({ where: { id: 'company', tenantId: TENANT } }),
    )
    db.financialEntity.findFirst.mockResolvedValueOnce(entityToRow(entity))
    expect(await repos.entities.findById(TENANT, 'company')).toEqual(entity)
    expect(db.financialEntity.findFirst).toHaveBeenCalledWith({
      where: { tenantId: TENANT, id: 'company' },
    })
    db.financialEntity.findFirst.mockResolvedValueOnce(null)
    expect(await repos.entities.findById(TENANT, 'missing')).toBeNull()
  })
})

describe('PrismaAccountRepository', () => {
  it('stores balances as bigint cents and reads them back', async () => {
    const { db, repos } = mockClient()
    await repos.accounts.save(account)
    expect(db.account.upsert.mock.calls[0]?.[0].create.balanceCents).toBe(5000n)
    db.account.findFirst.mockResolvedValueOnce(accountToRow(account))
    expect(await repos.accounts.findById(TENANT, 'a1')).toEqual(account)
    db.account.findFirst.mockResolvedValueOnce(null)
    expect(await repos.accounts.findById(TENANT, 'a2')).toBeNull()
    db.account.findMany.mockResolvedValueOnce([accountToRow(account)])
    expect(await repos.accounts.listByEntity(TENANT, 'company')).toEqual([
      account,
    ])
    expect(db.account.findMany.mock.calls[0]?.[0].where).toEqual({
      tenantId: TENANT,
      entityId: 'company',
    })
  })
})

describe('PrismaBillRepository', () => {
  it('round trips a bill through its row', async () => {
    const { db, repos } = mockClient()
    await repos.bills.save(bill)
    const row = db.bill.upsert.mock.calls[0]?.[0].create
    expect(row).toMatchObject({ amountCents: 12345n, tenantId: TENANT })
    expect(row.dueDate.toISOString()).toBe('2026-10-20T00:00:00.000Z')
    db.bill.findFirst.mockResolvedValueOnce(billToRow(bill))
    expect(await repos.bills.findById(TENANT, 'b1')).toEqual(bill)
    db.bill.findFirst.mockResolvedValueOnce(null)
    expect(await repos.bills.findById(TENANT, 'b2')).toBeNull()
  })

  it('dedupes by code ignoring cancelled bills', async () => {
    const { db, repos } = mockClient()
    db.bill.findFirst.mockResolvedValueOnce(billToRow(bill))
    expect(await repos.bills.findByCode(TENANT, 'company', 'x')).toEqual(bill)
    expect(db.bill.findFirst.mock.calls[0]?.[0].where).toEqual({
      tenantId: TENANT,
      entityId: 'company',
      code: 'x',
      status: { not: 'CANCELLED' },
    })
    db.bill.findFirst.mockResolvedValueOnce(null)
    expect(await repos.bills.findByCode(TENANT, 'company', 'y')).toBeNull()
  })

  it('dedupes by Pix code ignoring cancelled bills', async () => {
    const { db, repos } = mockClient()
    db.bill.findFirst.mockResolvedValueOnce(billToRow(bill))
    expect(await repos.bills.findByPixCode(TENANT, 'company', 'p')).toEqual(
      bill,
    )
    expect(db.bill.findFirst.mock.calls[0]?.[0].where).toEqual({
      tenantId: TENANT,
      entityId: 'company',
      pixCode: 'p',
      status: { not: 'CANCELLED' },
    })
    db.bill.findFirst.mockResolvedValueOnce(null)
    expect(await repos.bills.findByPixCode(TENANT, 'company', 'q')).toBeNull()
  })

  it('lists unsettled bills of one amount for pairing', async () => {
    const { db, repos } = mockClient()
    db.bill.findMany.mockResolvedValueOnce([billToRow(bill)])
    expect(
      await repos.bills.listUnsettledByAmount(
        TENANT,
        'company',
        Money.of(12345),
      ),
    ).toEqual([bill])
    expect(db.bill.findMany.mock.calls[0]?.[0].where).toEqual({
      tenantId: TENANT,
      entityId: 'company',
      amountCents: 12345n,
      currency: 'BRL',
      status: { notIn: ['PAID', 'CANCELLED'] },
    })
  })

  it('pages with an offset cursor', async () => {
    const { db, repos } = mockClient()
    const rows = [billToRow(bill), billToRow({ ...bill, id: 'b2' })]
    db.bill.findMany.mockResolvedValueOnce(rows)
    const first = await repos.bills.list(TENANT, {}, { limit: 1 })
    expect(first.items.map(item => item.id)).toEqual(['b1'])
    expect(first.nextCursor).toBe('1')
    expect(db.bill.findMany.mock.calls[0]?.[0]).toMatchObject({
      skip: 0,
      take: 2,
    })
    db.bill.findMany.mockResolvedValueOnce(rows.slice(1))
    const last = await repos.bills.list(
      TENANT,
      { status: 'OPEN' },
      { cursor: '1', limit: 1 },
    )
    expect(last.nextCursor).toBeNull()
    expect(db.bill.findMany.mock.calls[1]?.[0].where).toEqual({
      tenantId: TENANT,
      entityId: undefined,
      status: 'OPEN',
    })
  })
})

describe('PrismaPaymentRepository', () => {
  it('stores plans as json and attempts as rows', async () => {
    const { db, repos } = mockClient()
    const plan = createPaymentPlan('b1', [
      { mode: 'AUTOMATIC', rail: 'INTER_EMPRESAS', method: 'PIX' },
      ASSISTED_STEP,
    ])
    await repos.payments.savePlan(TENANT, plan)
    expect(db.paymentPlan.upsert.mock.calls[0]?.[0].where).toEqual({
      billId: 'b1',
      tenantId: TENANT,
    })
    db.paymentPlan.findFirst.mockResolvedValueOnce({
      billId: 'b1',
      tenantId: TENANT,
      steps: plan.steps,
      currentStep: 0,
    })
    expect(await repos.payments.findPlan(TENANT, 'b1')).toEqual(plan)
    db.paymentPlan.findFirst.mockResolvedValueOnce({
      billId: 'b1',
      tenantId: TENANT,
      steps: [{ mode: 'ASSISTED', rail: 'ASSISTED' }],
      currentStep: 0,
    })
    expect((await repos.payments.findPlan(TENANT, 'b1'))?.steps).toEqual([
      ASSISTED_STEP,
    ])
    db.paymentPlan.findFirst.mockResolvedValueOnce(null)
    expect(await repos.payments.findPlan(TENANT, 'b2')).toBeNull()

    await repos.payments.addAttempt(TENANT, attempt)
    expect(db.paymentAttempt.create).toHaveBeenCalledWith({
      data: attemptToRow(TENANT, attempt),
    })
    db.paymentAttempt.findMany.mockResolvedValueOnce([
      attemptToRow(TENANT, attempt),
    ])
    expect(await repos.payments.listAttempts(TENANT, 'b1')).toEqual([attempt])
  })

  it('sums committed cents inside the Sao Paulo day', async () => {
    const { db, repos } = mockClient()
    db.paymentAttempt.aggregate.mockResolvedValueOnce({
      _sum: { amountCents: 700n },
    })
    expect(
      await repos.payments.committedCents(TENANT, 'ASAAS', '2026-10-08'),
    ).toBe(700)
    expect(db.paymentAttempt.aggregate.mock.calls[0]?.[0].where).toEqual({
      tenantId: TENANT,
      rail: 'ASAAS',
      outcome: { in: ['PAID', 'SUBMITTED', 'PENDING_APPROVAL'] },
      at: saoPauloDayRange('2026-10-08'),
    })
    db.paymentAttempt.aggregate.mockResolvedValueOnce({
      _sum: { amountCents: null },
    })
    expect(
      await repos.payments.committedCents(TENANT, 'ASAAS', '2026-10-08'),
    ).toBe(0)
  })

  it('maps a local day to its UTC window', () => {
    expect(saoPauloDayRange('2026-10-08')).toEqual({
      gte: new Date('2026-10-08T03:00:00.000Z'),
      lt: new Date('2026-10-09T03:00:00.000Z'),
    })
  })
})

describe('PrismaPayeeDirectory', () => {
  it('remembers payees per entity', async () => {
    const { db, repos } = mockClient()
    db.payee.findUnique.mockResolvedValueOnce(null)
    expect(await repos.payees.isKnown(TENANT, 'company', 'k')).toBe(false)
    db.payee.findUnique.mockResolvedValueOnce({ key: 'k' })
    expect(await repos.payees.isKnown(TENANT, 'company', 'k')).toBe(true)
    await repos.payees.remember(TENANT, 'company', 'k')
    expect(db.payee.upsert.mock.calls[0]?.[0].update).toEqual({})
  })
})

describe('PrismaPaymentSettings', () => {
  it('falls back to the defaults and converts the threshold', async () => {
    const { db, repos, settings } = mockClient()
    db.paymentSettings.findUnique.mockResolvedValueOnce(null)
    expect(await repos.settings.get(TENANT, 'company')).toBe(settings)
    const row = {
      killSwitch: true,
      enabledRails: ['ASAAS'],
      dailyCapCents: { ASAAS: 100 },
      confirmAboveCents: 5000n,
    }
    db.paymentSettings.findUnique.mockResolvedValueOnce(row)
    expect(await repos.settings.get(TENANT, 'company')).toEqual({
      ...row,
      confirmAboveCents: 5000,
    })
    db.paymentSettings.findUnique.mockResolvedValueOnce({
      ...row,
      confirmAboveCents: null,
    })
    expect(
      (await repos.settings.get(TENANT, 'company')).confirmAboveCents,
    ).toBeNull()
  })
})

describe('audit, idempotency and secrets', () => {
  it('writes audit events with json details', async () => {
    const { db, repos } = mockClient()
    const event = {
      id: 'e1',
      tenantId: TENANT,
      actor: 'SYSTEM' as const,
      action: 'payment.attempt',
      subjectId: 'b1',
      rail: null,
      result: 'PAID',
      details: { step: 0 },
      at: NOW,
    }
    await repos.audit.record(event)
    expect(db.auditEvent.create).toHaveBeenCalledWith({ data: event })
  })

  it('keeps the first idempotent result', async () => {
    const { db, repos } = mockClient()
    db.idempotencyRecord.findUnique.mockResolvedValueOnce(null)
    expect(await repos.idempotency.find(TENANT, 'b1:0')).toBeNull()
    db.idempotencyRecord.findUnique.mockResolvedValueOnce({
      result: { outcome: 'PAID' },
    })
    expect(await repos.idempotency.find(TENANT, 'b1:0')).toEqual({
      outcome: 'PAID',
    })
    await repos.idempotency.save(TENANT, 'b1:0', 'payment', { outcome: 'PAID' })
    expect(db.idempotencyRecord.upsert.mock.calls[0]?.[0]).toMatchObject({
      where: { tenantId_key: { tenantId: TENANT, key: 'b1:0' } },
      update: {},
    })
  })

  it('stores sealed secrets per tenant', async () => {
    const { db, repos } = mockClient()
    await repos.secrets.put(TENANT, 'inter', 'v1.sealed')
    expect(db.secret.upsert.mock.calls[0]?.[0].update).toEqual({
      sealed: 'v1.sealed',
    })
    db.secret.findUnique.mockResolvedValueOnce({ sealed: 'v1.sealed' })
    expect(await repos.secrets.get(TENANT, 'inter')).toBe('v1.sealed')
    db.secret.findUnique.mockResolvedValueOnce(null)
    expect(await repos.secrets.get(TENANT, 'missing')).toBeNull()
  })
})

describe('lookups added for the API', () => {
  it('finds entities by kind and lists entities and accounts', async () => {
    const { db, repos } = mockClient()
    db.financialEntity.findFirst.mockResolvedValueOnce(entityToRow(entity))
    expect(await repos.entities.findByKind(TENANT, 'PJ')).toEqual(entity)
    expect(db.financialEntity.findFirst.mock.calls[0]?.[0].where).toEqual({
      tenantId: TENANT,
      kind: 'PJ',
    })
    db.financialEntity.findFirst.mockResolvedValueOnce(null)
    expect(await repos.entities.findByKind(TENANT, 'PF')).toBeNull()
    db.financialEntity.findMany.mockResolvedValueOnce([entityToRow(entity)])
    expect(await repos.entities.list(TENANT)).toEqual([entity])
    const linked = {
      ...account,
      connectionId: 'c1',
      externalId: 'x',
      cdiPercent: 100,
    }
    db.account.findMany.mockResolvedValueOnce([accountToRow(linked)])
    expect(await repos.accounts.list(TENANT)).toEqual([linked])
  })

  it('saves payment settings and deletes secrets', async () => {
    const { db, repos } = mockClient()
    await repos.settings.save(TENANT, 'company', {
      killSwitch: true,
      enabledRails: ['ASAAS'],
      dailyCapCents: { ASAAS: 100 },
      confirmAboveCents: 5000,
    })
    expect(db.paymentSettings.upsert.mock.calls[0]?.[0].update).toEqual({
      killSwitch: true,
      enabledRails: ['ASAAS'],
      dailyCapCents: { ASAAS: 100 },
      confirmAboveCents: 5000n,
    })
    await repos.settings.save(TENANT, 'company', {
      killSwitch: false,
      enabledRails: [],
      dailyCapCents: {},
      confirmAboveCents: null,
    })
    expect(
      db.paymentSettings.upsert.mock.calls[1]?.[0].create.confirmAboveCents,
    ).toBeNull()
    await repos.secrets.delete(TENANT, 'inter')
    expect(db.secret.deleteMany).toHaveBeenCalledWith({
      where: { tenantId: TENANT, name: 'inter' },
    })
  })
})
