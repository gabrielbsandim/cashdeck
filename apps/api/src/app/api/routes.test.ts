import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { type InMemoryAuditLog } from '@cashdeck/application'
import { getContainer, resetContainer } from '@/server/container'
import { GET as health } from '@/app/api/v1/health/route'
import { GET as openapi } from '@/app/api/v1/openapi/route'
import { GET as listBills, POST as captureBill } from '@/app/api/v1/bills/route'
import { GET as getBill } from '@/app/api/v1/bills/[id]/route'
import { POST as payBill } from '@/app/api/v1/bills/[id]/pay/route'
import { POST as markPaid } from '@/app/api/v1/bills/[id]/mark-paid/route'
import { PUT as setAutoDebit } from '@/app/api/v1/bills/[id]/auto-debit/route'
import { GET as paymentCron } from '@/app/api/cron/payment-ladder/route'

const BOLETO_LINE = '00190000090280001234256789012178916050000012345'
const TAX_BARCODE = '85600000001500003282026102000000000000123000'

const TOKEN = 'test-token-0123456789'
const AUTH = { authorization: `Bearer ${TOKEN}` }

function get(path: string) {
  return new Request(`http://localhost/api/v1${path}`, { headers: AUTH })
}

function post(path: string, body?: unknown) {
  return new Request(`http://localhost/api/v1${path}`, {
    method: 'POST',
    headers: AUTH,
    body: body === undefined ? undefined : JSON.stringify(body),
  })
}

const params = (id: string) => ({ params: Promise.resolve({ id }) })

async function json(response: Response) {
  return { status: response.status, body: await response.json() }
}

beforeEach(() => {
  vi.stubEnv('CASHDECK_API_TOKEN', TOKEN)
})

afterEach(() => {
  resetContainer()
  vi.unstubAllEnvs()
})

describe('api routes', () => {
  it('reports health and serves the OpenAPI document', async () => {
    expect(await json(health())).toEqual({
      status: 200,
      body: { data: { status: 'ok' } },
    })
    expect((await openapi().json()).info.title).toBe('Cashdeck API')
  })

  it('captures, lists and reads a bill', async () => {
    const created = await json(
      await captureBill(
        post('/bills', { entityId: 'company', paymentCode: BOLETO_LINE }),
      ),
    )
    expect(created.status).toBe(201)
    expect(created.body.data).toMatchObject({
      kind: 'BOLETO',
      amount: { cents: 12345 },
    })

    const again = await captureBill(
      post('/bills', { entityId: 'company', paymentCode: BOLETO_LINE }),
    )
    expect(again.status).toBe(200)

    const list = await json(await listBills(get('/bills?entityId=company')))
    expect(list.body.data).toHaveLength(1)
    expect(list.body.nextCursor).toBeNull()

    const detail = await json(
      await getBill(get('/bills/x'), params(created.body.data.id)),
    )
    expect(detail.body.data).toMatchObject({ attempts: [], pixCode: null })
    expect(
      detail.body.data.plan.steps.map((step: { rail: string }) => step.rail),
    ).toEqual(['INTER_EMPRESAS', 'C6_EMPRESAS', 'ASSISTED'])
  })

  it('walks the ladder down to assisted while rails are unconfigured', async () => {
    const created = await json(
      await captureBill(
        post('/bills', {
          entityId: 'company',
          paymentCode: TAX_BARCODE,
          dueDate: '2026-10-20',
        }),
      ),
    )
    const id = created.body.data.id
    const pending = await json(
      await payBill(post(`/bills/${id}/pay`), params(id)),
    )
    expect(pending.body.data.status).toBe('NEEDS_CONFIRMATION')

    const confirm = post(`/bills/${id}/pay`, { confirmed: true })
    confirm.headers.set('x-request-id', 'req-42')
    const run = await json(await payBill(confirm, params(id)))
    expect(run.body.data.status).toBe('ASSISTED')
    const audit = getContainer().deps.audit as InMemoryAuditLog
    const attempts = audit.events.filter(e => e.action === 'payment.attempt')
    expect(attempts.at(-1)).toMatchObject({
      action: 'payment.attempt',
      actor: 'USER',
      actorId: expect.stringMatching(/^token:[0-9a-f]{12}$/),
      requestId: 'req-42',
    })
    expect(
      run.body.data.attempts.map((a: { reason: string | null }) => a.reason),
    ).toEqual(['NOT_CONFIGURED', null])
    expect(run.body.data.instructions.copyCode).toBe(TAX_BARCODE)

    const paid = await json(
      await markPaid(
        post(`/bills/${id}/mark-paid`, { proof: 'r.pdf' }),
        params(id),
      ),
    )
    expect(paid.body.data).toMatchObject({ status: 'PAID', paidBy: 'USER' })

    const flag = (enabled: unknown) =>
      new Request(`http://localhost/api/v1/bills/${id}/auto-debit`, {
        method: 'PUT',
        headers: { ...AUTH, 'content-type': 'application/json' },
        body: JSON.stringify({ enabled }),
      })
    const flagged = await json(await setAutoDebit(flag(true), params(id)))
    expect(flagged.body.data).toMatchObject({ id, autoDebit: true })
    expect((await setAutoDebit(flag('yes'), params(id))).status).toBe(422)
  })

  it('returns the error envelope', async () => {
    const invalid = await json(
      await captureBill(post('/bills', { entityId: 'company' })),
    )
    expect([invalid.status, invalid.body.error.code]).toEqual([
      422,
      'VALIDATION_ERROR',
    ])
    const broken = new Request('http://localhost/api/v1/bills', {
      method: 'POST',
      headers: AUTH,
      body: '{',
    })
    expect((await captureBill(broken)).status).toBe(400)
    expect((await listBills(get('/bills?limit=0'))).status).toBe(422)
    expect((await getBill(get('/bills/x'), params('nope'))).status).toBe(404)
    expect(
      (await payBill(post('/bills/nope/pay'), params('nope'))).status,
    ).toBe(404)
    expect(
      (await markPaid(post('/bills/nope/mark-paid'), params('nope'))).status,
    ).toBe(404)
  })

  it('guards every route with the API token', async () => {
    const anonymous = await json(
      await listBills(new Request('http://localhost/api/v1/bills')),
    )
    expect([anonymous.status, anonymous.body.error.code]).toEqual([
      401,
      'UNAUTHORIZED',
    ])
    const wrong = new Request('http://localhost/api/v1/bills', {
      headers: { authorization: 'Bearer nope' },
    })
    expect((await listBills(wrong)).status).toBe(401)
    vi.stubEnv('CASHDECK_API_TOKEN', '')
    const unset = await json(await listBills(get('/bills')))
    expect([unset.status, unset.body.error.code]).toEqual([
      503,
      'NOT_CONFIGURED',
    ])
    expect((await health()).status).toBe(200)
  })

  it('runs due payments from the cron route', async () => {
    vi.stubEnv('CRON_SECRET', 'secret')
    const request = new Request('http://localhost/api/cron/payment-ladder', {
      headers: { authorization: 'Bearer secret' },
    })
    const result = await json(await paymentCron(request))
    expect(result.body.data).toMatchObject({
      source: 'payment-ladder',
      checked: 0,
    })
  })
})
