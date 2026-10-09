import { randomUUID } from 'node:crypto'
import { afterAll, describe, expect, it } from 'vitest'
import {
  ASSISTED_STEP,
  createAccount,
  createBill,
  createFinancialEntity,
  createPaymentPlan,
  Money,
} from '@cashdeck/domain'
import { DEFAULT_SAFETY_SETTINGS } from '@cashdeck/application'
import { createPrismaClient } from '@/database/client'
import { createPrismaRepositories } from '@/repositories/prisma-repositories'

const url = process.env.DATABASE_TEST_URL

describe.skipIf(!url)('Prisma repositories against a database', () => {
  const db = createPrismaClient(url ?? '')
  const repos = createPrismaRepositories(db, {
    killSwitch: false,
    enabledRails: [],
    dailyCapCents: {},
    confirmAboveCents: null,
    ...DEFAULT_SAFETY_SETTINGS,
  })
  const tenantId = `it-${randomUUID()}`
  const other = `it-${randomUUID()}`
  const at = new Date()
  const today = at.toISOString().slice(0, 10)

  const entity = createFinancialEntity({
    id: `${tenantId}-pj`,
    tenantId,
    kind: 'PJ',
    name: 'Integration Co',
    taxId: '11222333000181',
    taxRegime: 'SIMPLES_NACIONAL',
  })
  const bill = createBill({
    id: `${tenantId}-bill`,
    tenantId,
    entityId: entity.id,
    kind: 'BOLETO',
    source: 'MANUAL',
    payee: 'Supplier',
    amount: Money.of(12345),
    dueDate: '2026-10-20',
    code: '00199160500000123450000002800012345678901217',
    createdAt: at,
  })

  afterAll(async () => {
    const where = { tenantId: { in: [tenantId, other] } }
    await db.paymentAttempt.deleteMany({ where })
    await db.paymentPlan.deleteMany({ where })
    await db.bill.deleteMany({ where })
    await db.account.deleteMany({ where })
    await db.financialEntity.deleteMany({ where })
    await db.payee.deleteMany({ where })
    await db.auditEvent.deleteMany({ where })
    await db.idempotencyRecord.deleteMany({ where })
    await db.secret.deleteMany({ where })
    await db.$disconnect()
  })

  it('persists the payment flow scoped to one tenant', async () => {
    await repos.entities.save(entity)
    await repos.accounts.save(
      createAccount({
        id: `${tenantId}-acc`,
        tenantId,
        entityId: entity.id,
        institutionId: 'bank',
        name: 'Checking',
        type: 'CHECKING',
        origin: 'MANUAL',
        balance: Money.of(9000),
      }),
    )
    await repos.bills.save(bill)
    await repos.payments.savePlan(
      tenantId,
      createPaymentPlan(bill.id, [
        { mode: 'AUTOMATIC', rail: 'ASAAS', method: 'BOLETO' },
        ASSISTED_STEP,
      ]),
    )
    await repos.payments.addAttempt(tenantId, {
      id: `${tenantId}-att`,
      billId: bill.id,
      stepIndex: 0,
      rail: 'ASAAS',
      mode: 'AUTOMATIC',
      method: 'BOLETO',
      amount: bill.amount,
      outcome: 'PAID',
      reason: null,
      externalId: 'ext',
      idempotencyKey: `${bill.id}:0:BOLETO`,
      at,
    })

    expect(await repos.entities.findById(tenantId, entity.id)).toEqual(entity)
    expect(await repos.entities.findById(other, entity.id)).toBeNull()
    expect(await repos.accounts.listByEntity(tenantId, entity.id)).toHaveLength(
      1,
    )
    expect(await repos.bills.findById(tenantId, bill.id)).toEqual(bill)
    expect(await repos.bills.findById(other, bill.id)).toBeNull()
    expect(
      await repos.bills.findByCode(tenantId, entity.id, bill.code ?? ''),
    ).toEqual(bill)
    expect((await repos.bills.list(tenantId, {}, { limit: 10 })).items).toEqual(
      [bill],
    )
    expect(
      (await repos.payments.findPlan(tenantId, bill.id))?.steps,
    ).toHaveLength(2)
    expect(await repos.payments.listAttempts(tenantId, bill.id)).toHaveLength(1)
    expect(
      await repos.payments.committedCents(tenantId, entity.id, today, 'ASAAS'),
    ).toBeGreaterThanOrEqual(0)
  })

  it('keeps payees, idempotency, audit and secrets per tenant', async () => {
    await repos.payees.remember(tenantId, entity.id, 'supplier')
    await repos.payees.remember(tenantId, entity.id, 'supplier')
    expect(await repos.payees.isKnown(tenantId, entity.id, 'supplier')).toBe(
      true,
    )
    expect(await repos.payees.isKnown(other, entity.id, 'supplier')).toBe(false)

    await repos.idempotency.save(tenantId, 'k', 'payment', { outcome: 'PAID' })
    await repos.idempotency.save(tenantId, 'k', 'payment', {
      outcome: 'FAILED',
    })
    expect(await repos.idempotency.find(tenantId, 'k')).toEqual({
      outcome: 'PAID',
    })
    expect(await repos.idempotency.find(other, 'k')).toBeNull()

    await repos.secrets.put(tenantId, 'inter', 'v1.a')
    await repos.secrets.put(tenantId, 'inter', 'v1.b')
    expect(await repos.secrets.get(tenantId, 'inter')).toBe('v1.b')
    expect(await repos.secrets.get(other, 'inter')).toBeNull()

    await repos.audit.record({
      id: `${tenantId}-audit`,
      tenantId,
      actor: 'SYSTEM',
      action: 'payment.attempt',
      subjectId: bill.id,
      rail: 'ASAAS',
      result: 'PAID',
      details: { step: 0 },
      at,
    })
    expect(await db.auditEvent.count({ where: { tenantId } })).toBe(1)
    expect(await repos.settings.get(tenantId, entity.id)).toMatchObject({
      killSwitch: false,
    })
  })
})
