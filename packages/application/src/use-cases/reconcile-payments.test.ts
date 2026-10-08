import { describe, expect, it } from 'vitest'
import { createPaymentPlan, Money, type PaymentAttempt } from '@cashdeck/domain'
import { type RailStatusScope } from '@/ports/rail-status'
import { bill, fullDeps } from '@/testing/deps.test-helpers'
import { FakeRailStatusReader } from '@/testing/rail-status'
import { NOW, TENANT } from '@/testing/scenario.test-helpers'
import { makeReconcilePayments } from '@/use-cases/reconcile-payments'

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
})
