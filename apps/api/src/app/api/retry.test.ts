import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { signInTestDevice, STATIC_TOKEN } from '@/app/api/sign-in.test-helpers'
import { ASSISTED_STEP, Money, type PaymentAttempt } from '@cashdeck/domain'
import { getContainer, resetContainer } from '@/server/container'
import { POST as captureBill } from '@/app/api/v1/bills/route'
import { POST as retryBill } from '@/app/api/v1/bills/[id]/retry/route'

const BOLETO_LINE = '00190000090280001234256789012178916050000012345'
const TENANT = 'local'

let session = ''

function post(path: string) {
  return new Request(`http://localhost/api/v1${path}`, {
    method: 'POST',
    headers: { authorization: `Bearer ${session}` },
  })
}

const params = (id: string) => ({ params: Promise.resolve({ id }) })

async function json(response: Response) {
  return { status: response.status, body: await response.json() }
}

async function capture(): Promise<string> {
  const created = await json(
    await captureBill(
      new Request('http://localhost/api/v1/bills', {
        method: 'POST',
        headers: { authorization: `Bearer ${session}` },
        body: JSON.stringify({
          entityId: 'company',
          paymentCode: BOLETO_LINE,
        }),
      }),
    ),
  )
  return created.body.data.id
}

async function fallToAssisted(id: string): Promise<void> {
  const { deps } = getContainer()
  const bill = await deps.bills.findById(TENANT, id)
  if (!bill) {
    throw new Error('the captured bill is missing')
  }
  await deps.bills.save({ ...bill, status: 'ASSISTED' })
  await deps.payments.savePlan(TENANT, {
    billId: id,
    steps: [
      { mode: 'AUTOMATIC', rail: 'INTER_EMPRESAS', method: 'BOLETO' },
      ASSISTED_STEP,
    ],
    currentStep: 1,
    round: 0,
  })
  const failed: PaymentAttempt = {
    id: `${id}:0:BOLETO:claim`,
    billId: id,
    stepIndex: 0,
    rail: 'INTER_EMPRESAS',
    mode: 'AUTOMATIC',
    method: 'BOLETO',
    amount: bill.amount,
    outcome: 'FAILED',
    reason: 'Saldo insuficiente',
    externalId: null,
    idempotencyKey: `${id}:0:BOLETO`,
    at: new Date('2026-10-08T12:00:00Z'),
  }
  await deps.payments.addAttempt(TENANT, failed)
}

beforeEach(async () => {
  vi.stubEnv('CASHDECK_API_TOKEN', STATIC_TOKEN)
  session = await signInTestDevice()
})

afterEach(() => {
  resetContainer()
  vi.unstubAllEnvs()
})

describe('POST /v1/bills/{id}/retry', () => {
  it('answers 200 with the bill view and instructions after a retry', async () => {
    const id = await capture()
    await fallToAssisted(id)
    const retried = await json(
      await retryBill(post(`/bills/${id}/retry`), params(id)),
    )
    expect(retried.status).toBe(200)
    expect(retried.body.data).toHaveProperty('instructions')
    expect(retried.body.data.plan.round).toBe(1)
    expect(retried.body.data.attempts.length).toBeGreaterThan(1)
    expect(Money.of(retried.body.data.amount.cents).cents).toBe(12345)
  })

  it('answers 409 with the reason when the bill is not assisted', async () => {
    const id = await capture()
    const refused = await json(
      await retryBill(post(`/bills/${id}/retry`), params(id)),
    )
    expect(refused.status).toBe(409)
    expect(refused.body.error.code).toBe('CONFLICT')
    expect(JSON.stringify(refused.body.error)).toContain('NOT_ASSISTED')
  })

  it('answers 404 for an unknown bill', async () => {
    const missing = await retryBill(post('/bills/nope/retry'), params('nope'))
    expect(missing.status).toBe(404)
  })
})
