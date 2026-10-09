import { describe, expect, it } from 'vitest'
import {
  type Bill,
  type BillStatus,
  Money,
  type PaymentAttempt,
  type PaymentPlan,
} from '@cashdeck/domain'
import { RecordingAlertEmitter } from '@/testing/alerts'
import { bill } from '@/testing/deps.test-helpers'
import { NOW } from '@/testing/scenario.test-helpers'
import { ladderAlerts, withLadderAlerts } from '@/use-cases/ladder-alerts'
import { type LadderRun } from '@/use-cases/run-payment-ladder'

const attempt = (
  outcome: PaymentAttempt['outcome'],
  reason: string | null = null,
): PaymentAttempt => ({
  id: `att-${outcome}`,
  billId: 'b1',
  stepIndex: 0,
  rail: 'INTER_EMPRESAS',
  mode: 'AUTOMATIC',
  method: 'PIX',
  amount: Money.of(12345),
  outcome,
  reason,
  externalId: null,
  idempotencyKey: 'b1:0:PIX',
  at: NOW,
})

function run(
  status: BillStatus,
  attempts: PaymentAttempt[],
  overrides: Partial<Bill> = {},
): LadderRun {
  return {
    bill: bill({ id: 'b1', status, ...overrides }),
    plan: {} as PaymentPlan,
    attempts,
    instructions: null,
  }
}

const types = (value: LadderRun) => ladderAlerts(value).map(a => a.type)

describe('ladder alerts', () => {
  it('says nothing for a run that did nothing', () => {
    expect(types(run('PAID', []))).toEqual([])
    expect(types(run('PROCESSING', [attempt('SUBMITTED')]))).toEqual([])
  })

  it('maps the final status to one alert', () => {
    expect(types(run('NEEDS_CONFIRMATION', []))).toEqual([
      'PAYMENT_NEEDS_CONFIRMATION',
    ])
    expect(types(run('PAID', [attempt('PAID')]))).toEqual(['PAYMENT_PAID'])
    expect(
      types(run('AWAITING_BANK_APPROVAL', [attempt('PENDING_APPROVAL')])),
    ).toEqual(['APPROVAL_PENDING'])
  })

  it('reports a rail that failed before the one that took it', () => {
    const alerts = ladderAlerts(
      run('PROCESSING', [
        attempt('FAILED', 'DAILY_CAP_EXCEEDED'),
        attempt('SUBMITTED'),
      ]),
    )
    expect(alerts).toEqual([
      expect.objectContaining({
        type: 'PAYMENT_MOVED_DOWN',
        data: expect.objectContaining({
          rail: 'Inter Empresas',
          reason: 'DAILY_CAP_EXCEEDED',
        }),
        dedupeKey: 'PAYMENT_MOVED_DOWN:b1:att-FAILED',
      }),
    ])
    expect(
      ladderAlerts(run('PAID', [attempt('FAILED'), attempt('PAID')])).map(
        alert => [alert.type, alert.data.reason],
      ),
    ).toEqual([
      ['PAYMENT_MOVED_DOWN', ''],
      ['PAYMENT_PAID', undefined],
    ])
  })

  it('folds a fall to assisted into one alert with the Pix hint', () => {
    const [assisted] = ladderAlerts(
      run(
        'ASSISTED',
        [attempt('FAILED', 'NOT_CONFIGURED'), attempt('ASSISTED')],
        {
          pixCode: 'pix-payload',
        },
      ),
    )
    expect(assisted).toMatchObject({
      type: 'PAYMENT_ASSISTED',
      data: { hasPixCode: 'true', method: 'PIX', reason: 'NOT_CONFIGURED' },
    })
    expect(
      ladderAlerts(run('ASSISTED', [attempt('ASSISTED')]))[0]?.data.reason,
    ).toBe('')
  })

  it('emits after the wrapped ladder runs', async () => {
    const recorder = new RecordingAlertEmitter()
    const calls: unknown[] = []
    const ladder = withLadderAlerts(async (...args) => {
      calls.push(args)
      return run('PAID', [attempt('PAID')])
    }, recorder)
    const result = await ladder('t1', 'b1', { confirmed: true })
    expect(result.bill.status).toBe('PAID')
    expect(calls).toEqual([['t1', 'b1', { confirmed: true }]])
    expect(recorder.types()).toEqual(['PAYMENT_PAID'])
  })
})
