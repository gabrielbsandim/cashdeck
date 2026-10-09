import { describe, expect, it } from 'vitest'
import { createPaymentPlan, Money, type PaymentAttempt } from '@cashdeck/domain'
import { type RailStatusScope } from '@/ports/rail-status'
import { bill, fullDeps } from '@/testing/deps.test-helpers'
import { FakeRailStatusReader } from '@/testing/rail-status'
import { NOW, TENANT } from '@/testing/scenario.test-helpers'
import {
  IN_FLIGHT_GRACE_MS,
  makeReconcilePayments,
  referenceMatches,
} from '@/use-cases/reconcile-payments'

const attempt = (
  overrides: Partial<PaymentAttempt> & { billId: string },
): PaymentAttempt => ({
  id: `att-${overrides.billId}`,
  stepIndex: 0,
  rail: 'INTER_EMPRESAS',
  mode: 'AUTOMATIC',
  method: 'PIX',
  amount: Money.of(12345),
  outcome: 'SUBMITTED',
  reason: null,
  externalId: `pix:${overrides.billId}`,
  idempotencyKey: `${overrides.billId}:0:PIX`,
  at: NOW,
  ...overrides,
})

const reported = (outcome: 'PAID' | 'FAILED' | 'SUBMITTED', extra = {}) => ({
  outcome,
  endToEndId: null,
  settledAt: null,
  ...extra,
})

class FlakyReader extends FakeRailStatusReader {
  override async status(externalId: string, scope: RailStatusScope) {
    if (externalId === 'pix:boom') {
      throw new Error('timeout')
    }
    return super.status(externalId, scope)
  }
}

describe('reconcilePayments', () => {
  it('settles waiting payments from the rail status', async () => {
    const inter = new FlakyReader('INTER_EMPRESAS')
      .willReport(
        'pix:paid',
        reported('PAID', { settledAt: '2026-10-08T15:00:00Z' }),
      )
      .willReport('pix:late', reported('PAID'))
      .willReport('pix:failed', reported('FAILED', { reason: 'REFUSED' }))
      .willReport('pix:bare', reported('FAILED'))
    const deps = fullDeps({ railStatus: [inter] })
    const steps = [
      {
        mode: 'AUTOMATIC' as const,
        rail: 'INTER_EMPRESAS' as const,
        method: 'PIX' as const,
      },
      {
        mode: 'ASSISTED' as const,
        rail: 'ASSISTED' as const,
        method: 'PIX' as const,
      },
    ]
    for (const id of [
      'paid',
      'late',
      'failed',
      'bare',
      'waiting',
      'none',
      'c6',
    ]) {
      await deps.bills.save(bill({ id, entityId: 'pj', status: 'PROCESSING' }))
    }
    await deps.bills.save(
      bill({
        id: 'approval',
        entityId: 'pj',
        status: 'AWAITING_BANK_APPROVAL',
      }),
    )
    await deps.payments.savePlan(TENANT, createPaymentPlan('failed', steps))
    for (const id of ['paid', 'late', 'failed', 'bare', 'waiting']) {
      await deps.payments.addAttempt(TENANT, attempt({ billId: id }))
    }
    await deps.payments.addAttempt(
      TENANT,
      attempt({ billId: 'none', externalId: null }),
    )
    await deps.payments.addAttempt(
      TENANT,
      attempt({ billId: 'c6', rail: 'C6_EMPRESAS' }),
    )
    await deps.payments.addAttempt(
      TENANT,
      attempt({
        billId: 'approval',
        outcome: 'PENDING_APPROVAL',
        externalId: 'pix:boom',
      }),
    )
    const result = await makeReconcilePayments(deps)(TENANT)
    expect(result).toEqual({
      checked: 8,
      paid: 2,
      failed: 2,
      expired: 0,
      failures: [{ billId: 'approval', reason: 'Error: timeout' }],
    })
    expect(await deps.bills.findById(TENANT, 'paid')).toMatchObject({
      status: 'PAID',
      paidBy: 'RAIL',
      paidAt: new Date('2026-10-08T15:00:00Z'),
    })
    expect((await deps.bills.findById(TENANT, 'late'))?.paidAt).toEqual(NOW)
    expect((await deps.bills.findById(TENANT, 'failed'))?.status).toBe(
      'ASSISTED',
    )
    expect((await deps.payments.findPlan(TENANT, 'failed'))?.currentStep).toBe(
      1,
    )
    const failedAttempts = await deps.payments.listAttempts(TENANT, 'bare')
    expect(failedAttempts.at(-1)).toMatchObject({
      outcome: 'FAILED',
      reason: 'RAIL_FAILED',
    })
    expect((await deps.bills.findById(TENANT, 'waiting'))?.status).toBe(
      'PROCESSING',
    )
    expect(
      deps.audit.events.filter(event => event.action === 'payment.reconciled'),
    ).toHaveLength(4)
  })

  it('resolves a lost call by its idempotency key, never by paying again', async () => {
    const inter = new FakeRailStatusReader('INTER_EMPRESAS')
      .willFind('found:0:PIX', reported('SUBMITTED', { externalId: 'pix:9' }))
      .willFind('gone:0:PIX', reported('FAILED', { reason: 'REFUSED' }))
      .willFind('done:0:PIX', reported('PAID'))
    const deps = fullDeps({ railStatus: [inter] })
    const recent = new Date(NOW.getTime() - 60_000)
    const stale = new Date(NOW.getTime() - IN_FLIGHT_GRACE_MS)
    for (const [id, at] of [
      ['found', recent],
      ['gone', recent],
      ['done', recent],
      ['fresh', recent],
      ['stale', stale],
    ] as const) {
      await deps.bills.save(bill({ id, entityId: 'pj', status: 'PROCESSING' }))
      await deps.payments.addAttempt(
        TENANT,
        attempt({
          billId: id,
          outcome: 'IN_FLIGHT',
          externalId: null,
          idempotencyKey: `${id}:0:PIX`,
          at,
        }),
      )
    }
    const result = await makeReconcilePayments(deps)(TENANT)
    expect(result).toMatchObject({ paid: 1, failed: 1, expired: 1 })
    const latest = async (id: string) =>
      (await deps.payments.listAttempts(TENANT, id)).at(-1)
    expect(await latest('found')).toMatchObject({
      outcome: 'SUBMITTED',
      externalId: 'pix:9',
    })
    expect((await deps.bills.findById(TENANT, 'found'))?.status).toBe(
      'PROCESSING',
    )
    expect((await deps.bills.findById(TENANT, 'gone'))?.status).toBe('ASSISTED')
    expect((await deps.bills.findById(TENANT, 'done'))?.status).toBe('PAID')
    expect((await deps.bills.findById(TENANT, 'fresh'))?.status).toBe(
      'PROCESSING',
    )
    expect(await latest('stale')).toMatchObject({
      outcome: 'FAILED',
      reason: 'IN_FLIGHT_UNRESOLVED',
    })
    expect((await deps.bills.findById(TENANT, 'stale'))?.status).toBe(
      'ASSISTED',
    )

    const again = await makeReconcilePayments(deps)(TENANT)
    expect(again).toMatchObject({ checked: 2, paid: 0, failed: 0 })
    expect(inter.asked).toEqual(['pix:9'])
  })

  it('moves an unapproved batch to assisted after the cutoff', async () => {
    const c6 = new FakeRailStatusReader('C6_EMPRESAS')
    const deps = fullDeps({ railStatus: [c6] })
    const steps = [
      {
        mode: 'BANK_APPROVAL' as const,
        rail: 'C6_EMPRESAS' as const,
        method: 'BOLETO' as const,
      },
      {
        mode: 'ASSISTED' as const,
        rail: 'ASSISTED' as const,
        method: 'BOLETO' as const,
      },
    ]
    for (const [id, dueDate] of [
      ['late', '2026-10-07'],
      ['today', '2026-10-08'],
      ['bare', '2026-10-07'],
    ] as const) {
      await deps.bills.save(
        bill({ id, entityId: 'pj', status: 'AWAITING_BANK_APPROVAL', dueDate }),
      )
    }
    await deps.payments.savePlan(TENANT, createPaymentPlan('late', steps))
    for (const id of ['late', 'today']) {
      await deps.payments.addAttempt(
        TENANT,
        attempt({
          billId: id,
          rail: 'C6_EMPRESAS',
          mode: 'BANK_APPROVAL',
          outcome: 'PENDING_APPROVAL',
          externalId: `batch:${id}`,
        }),
      )
    }
    const result = await makeReconcilePayments(deps)(TENANT)
    expect(result).toMatchObject({ checked: 3, expired: 2 })
    expect(await deps.bills.findById(TENANT, 'late')).toMatchObject({
      status: 'ASSISTED',
    })
    expect((await deps.payments.findPlan(TENANT, 'late'))?.currentStep).toBe(1)
    expect(
      (await deps.payments.listAttempts(TENANT, 'late')).at(-1),
    ).toMatchObject({ outcome: 'FAILED', reason: 'APPROVAL_EXPIRED' })
    expect((await deps.bills.findById(TENANT, 'bare'))?.status).toBe('ASSISTED')
    expect((await deps.bills.findById(TENANT, 'today'))?.status).toBe(
      'AWAITING_BANK_APPROVAL',
    )
    expect(
      deps.audit.events.filter(e => e.action === 'payment.approval_expired'),
    ).toHaveLength(1)

    await deps.settings.save(TENANT, 'pj', {
      ...(await deps.settings.get(TENANT, 'pj')),
      approvalCutoff: '08:00',
    })
    expect((await makeReconcilePayments(deps)(TENANT)).expired).toBe(1)
  })

  it('reconciles only the payment a webhook names', async () => {
    const inter = new FakeRailStatusReader('INTER_EMPRESAS').willReport(
      'pix:one',
      reported('PAID'),
    )
    const deps = fullDeps({ railStatus: [inter] })
    for (const id of ['one', 'two', 'none']) {
      await deps.bills.save(bill({ id, entityId: 'pj', status: 'PROCESSING' }))
    }
    await deps.payments.addAttempt(TENANT, attempt({ billId: 'one' }))
    await deps.payments.addAttempt(TENANT, attempt({ billId: 'two' }))
    const reconcile = makeReconcilePayments(deps)
    const missed = await reconcile(TENANT, { rail: 'ASAAS', reference: 'one' })
    expect(missed.checked).toBe(0)
    const result = await reconcile(TENANT, {
      rail: 'INTER_EMPRESAS',
      reference: 'one',
    })
    expect(result).toMatchObject({ checked: 1, paid: 1 })
    expect(inter.asked).toEqual(['pix:one'])
  })

  it('matches provider ids against stored external ids', () => {
    expect(referenceMatches('pix:abc', 'abc')).toBe(true)
    expect(referenceMatches('pay-1/tx-2', 'pay-1')).toBe(true)
    expect(referenceMatches('plain', 'plain')).toBe(true)
    expect(referenceMatches('pix:abcd', 'abc')).toBe(false)
  })
})
