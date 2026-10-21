import { describe, expect, it } from 'vitest'
import {
  createBill,
  createPaymentPlan,
  Money,
  recipientKeys,
  type Bill,
} from '@cashdeck/domain'
import { RecordingAlertEmitter } from '@/testing/alerts'
import { FakePaymentRail } from '@/testing/providers'
import {
  BOLETO_BARCODE,
  NOW,
  scenario,
  TENANT,
  trust,
} from '@/testing/scenario.test-helpers'
import { AUTO_DEBIT_COLLECTION } from '@/use-cases/auto-debit'
import { makeRequestConfirmations } from '@/use-cases/request-confirmations'

function bill(overrides: Partial<Bill> & { id: string }): Bill {
  return {
    ...createBill({
      id: overrides.id,
      tenantId: TENANT,
      entityId: 'pj',
      kind: 'BOLETO',
      source: 'MANUAL',
      payee: 'New supplier',
      amount: Money.of(12345),
      dueDate: '2026-10-10',
      code: BOLETO_BARCODE,
      createdAt: NOW,
    }),
    ...overrides,
  }
}

function setup(
  settings: Parameters<typeof scenario>[1] = {},
  rails = [new FakePaymentRail('INTER_EMPRESAS')],
) {
  const deps = {
    ...scenario(rails, settings),
    alerts: new RecordingAlertEmitter(),
  }
  return { deps, request: makeRequestConfirmations(deps) }
}

describe('requestConfirmations', () => {
  it('asks for a new payee within three days of the due date', async () => {
    const { deps, request } = setup()
    const bills = [
      bill({ id: 'soon' }),
      bill({ id: 'today', dueDate: '2026-10-08' }),
      bill({ id: 'edge', dueDate: '2026-10-11' }),
      bill({ id: 'later', dueDate: '2026-10-12' }),
      bill({ id: 'overdue', dueDate: '2026-10-07' }),
      bill({ id: 'asked', status: 'NEEDS_CONFIRMATION' }),
    ]
    for (const item of bills) {
      await deps.bills.save(item)
    }

    expect(await request(TENANT)).toEqual({ requested: 3 })
    expect((await deps.bills.findById(TENANT, 'soon'))?.status).toBe(
      'NEEDS_CONFIRMATION',
    )
    expect((await deps.bills.findById(TENANT, 'later'))?.status).toBe('OPEN')
    expect(deps.alerts.emitted.map(alert => alert.type)).toEqual(
      Array(3).fill('PAYMENT_NEEDS_CONFIRMATION'),
    )
    expect(deps.alerts.emitted.map(alert => alert.billId).sort()).toEqual([
      'edge',
      'soon',
      'today',
    ])
    expect(
      deps.audit.events.find(event => event.subjectId === 'soon'),
    ).toMatchObject({
      actor: 'SYSTEM',
      action: 'payment.confirmation_requested',
      result: 'NEEDS_CONFIRMATION',
      details: { reasons: ['NEW_PAYEE'], ahead: true },
    })
  })

  it('leaves a known payee to the payment run', async () => {
    const { deps, request } = setup()
    const known = bill({ id: 'known' })
    await deps.bills.save(known)
    await trust(deps.payees, known)
    expect(await request(TENANT)).toEqual({ requested: 0 })
    expect(deps.alerts.emitted).toEqual([])
  })

  it('asks nothing when no automatic step would pay the bill', async () => {
    const paused = setup({ killSwitch: true })
    await paused.deps.bills.save(bill({ id: 'paused' }))
    expect(await paused.request(TENANT)).toEqual({ requested: 0 })

    const manual = setup({}, [])
    await manual.deps.bills.save(bill({ id: 'manual' }))
    expect(await manual.request(TENANT)).toEqual({ requested: 0 })

    const debit = setup()
    const debited = bill({ id: 'debit' })
    await debit.deps.bills.save(debited)
    for (const key of recipientKeys(debited)) {
      await debit.deps.documents.put(
        TENANT,
        AUTO_DEBIT_COLLECTION,
        `pj|${key}`,
        { entityId: 'pj', key },
      )
    }
    expect(await debit.request(TENANT)).toEqual({ requested: 0 })
  })

  it('asks nothing once a payment was tried', async () => {
    const { deps, request } = setup()
    await deps.bills.save(bill({ id: 'b1' }))
    await deps.payments.addAttempt(TENANT, {
      id: 'b1:0:BOLETO:claim',
      billId: 'b1',
      stepIndex: 0,
      rail: 'INTER_EMPRESAS',
      mode: 'AUTOMATIC',
      method: 'BOLETO',
      amount: Money.of(12345),
      outcome: 'FAILED',
      reason: 'RAIL_ERROR',
      externalId: null,
      idempotencyKey: 'b1:0:BOLETO',
      at: NOW,
    })
    expect(await request(TENANT)).toEqual({ requested: 0 })
  })

  it('reads the stored plan before routing a new one', async () => {
    const { deps, request } = setup()
    await deps.bills.save(bill({ id: 'b1' }))
    await deps.payments.savePlan(
      TENANT,
      createPaymentPlan('b1', [
        { rail: 'ASSISTED', mode: 'ASSISTED', method: 'BOLETO' },
      ]),
    )
    expect(await request(TENANT)).toEqual({ requested: 0 })
  })
})
