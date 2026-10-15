import { describe, expect, it } from 'vitest'
import { Money, type PaymentAttempt } from '@cashdeck/domain'
import { NotFoundError, UnauthorizedError } from '@/errors/errors'
import { type WebhookDelivery, type WithdrawalCheck } from '@/ports/webhooks'
import { bill, fullDeps } from '@/testing/deps.test-helpers'
import { NOW, TENANT } from '@/testing/scenario.test-helpers'
import { FakeWebhookReader } from '@/testing/webhooks'
import { makeValidateWithdrawal } from '@/use-cases/withdrawal-validation'

const delivery = (token = 'test-token'): WebhookDelivery => ({
  provider: 'asaas',
  headers: { 'x-test-token': token },
  query: {},
  rawBody: '{}',
})

const attempt = (overrides: Partial<PaymentAttempt> = {}): PaymentAttempt => ({
  id: 'att-1',
  billId: 'b1',
  stepIndex: 0,
  rail: 'ASAAS',
  mode: 'AUTOMATIC',
  method: 'PIX',
  amount: Money.of(12345),
  outcome: 'SUBMITTED',
  reason: null,
  externalId: 'transfer:tr-1',
  idempotencyKey: 'b1:0:PIX',
  at: NOW,
  ...overrides,
})

const check = (overrides: Partial<WithdrawalCheck> = {}): WithdrawalCheck => ({
  rail: 'ASAAS',
  operation: 'TRANSFER',
  externalId: 'transfer:tr-1',
  amountCents: 12345,
  ...overrides,
})

async function setup(
  withdrawal: WithdrawalCheck,
  attempts: PaymentAttempt[] = [attempt()],
  killSwitch = false,
) {
  const deps = fullDeps({
    webhooks: [new FakeWebhookReader('asaas', [], 'test-token', withdrawal)],
    settings: { killSwitch },
  })
  await deps.bills.save(bill({ id: 'b1', status: 'PROCESSING' }))
  for (const row of attempts) {
    await deps.payments.addAttempt(TENANT, row)
  }
  return { deps, validate: makeValidateWithdrawal(deps) }
}

describe('validateWithdrawal', () => {
  it('approves a submitted attempt for the same amount and audits it', async () => {
    const { deps, validate } = await setup(check())
    expect(await validate(TENANT, delivery())).toEqual({ approved: true })
    expect(deps.audit.events.at(-1)).toMatchObject({
      action: 'payment.withdrawal_check',
      subjectId: 'b1',
      rail: 'ASAAS',
      result: 'APPROVED',
      details: {
        operation: 'TRANSFER',
        externalId: 'transfer:tr-1',
        amountCents: 12345,
        reason: null,
      },
    })
  })

  it.each([
    ['no id', check({ externalId: null }), [attempt()], 'UNKNOWN_OPERATION'],
    [
      'an unknown id',
      check({ externalId: 'transfer:x' }),
      [attempt()],
      'UNKNOWN_OPERATION',
    ],
    [
      'another rail',
      check({ rail: 'INTER_EMPRESAS' }),
      [attempt()],
      'UNKNOWN_OPERATION',
    ],
    [
      'a different amount',
      check({ amountCents: 12346 }),
      [attempt()],
      'AMOUNT_MISMATCH',
    ],
    ['no amount', check({ amountCents: null }), [attempt()], 'AMOUNT_MISMATCH'],
    [
      'a settled attempt',
      check(),
      [attempt(), attempt({ id: 'att-2', outcome: 'FAILED' })],
      'NOT_PENDING',
    ],
    [
      'a missing bill',
      check(),
      [attempt({ billId: 'gone' })],
      'UNKNOWN_OPERATION',
    ],
  ] as const)('refuses %s', async (_name, withdrawal, attempts, reason) => {
    const { deps, validate } = await setup(withdrawal, [...attempts])
    expect(await validate(TENANT, delivery())).toEqual({
      approved: false,
      reason,
    })
    expect(deps.audit.events.at(-1)).toMatchObject({
      result: 'REFUSED',
      details: { reason },
    })
  })

  it('names the operation when nothing else identifies it', async () => {
    const { deps, validate } = await setup(
      check({ externalId: null, operation: 'MOBILE_PHONE_RECHARGE' }),
    )
    await validate(TENANT, delivery())
    expect(deps.audit.events.at(-1)?.subjectId).toBe('MOBILE_PHONE_RECHARGE')
  })

  it('refuses everything while the kill switch is on', async () => {
    const { validate } = await setup(check(), [attempt()], true)
    expect(await validate(TENANT, delivery())).toEqual({
      approved: false,
      reason: 'KILL_SWITCH',
    })
  })

  it('rejects a forged delivery and a provider without validation', async () => {
    const { validate } = await setup(check())
    await expect(validate(TENANT, delivery('forged'))).rejects.toThrow(
      UnauthorizedError,
    )
    await expect(
      validate(TENANT, { ...delivery(), provider: 'pluggy' }),
    ).rejects.toThrow(NotFoundError)
    const plain = fullDeps({
      webhooks: [{ provider: 'asaas', read: async () => [] }],
    })
    await expect(
      makeValidateWithdrawal(plain)(TENANT, delivery()),
    ).rejects.toThrow(NotFoundError)
  })
})
