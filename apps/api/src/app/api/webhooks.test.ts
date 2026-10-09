import { createHmac } from 'node:crypto'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { Money } from '@cashdeck/domain'
import { getContainer, resetContainer } from '@/server/container'
import { POST as asaas } from '@/app/api/webhooks/asaas/route'
import { POST as inter } from '@/app/api/webhooks/inter/route'
import { POST as mercadoPago } from '@/app/api/webhooks/mercado-pago/route'
import { POST as pluggy } from '@/app/api/webhooks/pluggy/route'
import { POST as notaas } from '@/app/api/webhooks/notaas/route'
import { POST as cancel } from '@/app/api/v1/invoices/[id]/cancel/route'
import { GET as pdf } from '@/app/api/v1/invoices/[id]/pdf/route'
import { GET as xml } from '@/app/api/v1/invoices/[id]/xml/route'
import {
  GET as listTemplates,
  POST as createTemplate,
} from '@/app/api/v1/invoices/templates/route'
import {
  DELETE as deleteTemplate,
  GET as getTemplate,
  PATCH as updateTemplate,
} from '@/app/api/v1/invoices/templates/[id]/route'
import { GET as homeCompany } from '@/app/api/v1/home/company/route'
import { GET as invoicesCron } from '@/app/api/cron/invoices/route'

const TOKEN = 'test-token-0123456789'

function hook(
  path: string,
  body: unknown,
  headers: Record<string, string> = {},
) {
  return new Request(`http://localhost/api/webhooks/${path}`, {
    method: 'POST',
    headers,
    body: typeof body === 'string' ? body : JSON.stringify(body),
  })
}

type Handler = (request: Request, context: never) => Promise<Response>

async function call(
  handler: unknown,
  method: string,
  options: { body?: unknown; params?: Record<string, string> } = {},
) {
  const request = new Request('http://localhost/api/v1/test', {
    method,
    headers: { authorization: `Bearer ${TOKEN}` },
    body: options.body === undefined ? undefined : JSON.stringify(options.body),
  })
  const context = { params: Promise.resolve(options.params ?? {}) }
  const response = await (handler as Handler)(request, context as never)
  const type = response.headers.get('content-type') ?? ''
  const body = type.includes('json')
    ? await response.json()
    : Buffer.from(await response.arrayBuffer())
  return { status: response.status, body, headers: response.headers }
}

async function json(response: Response) {
  return { status: response.status, body: await response.json() }
}

beforeEach(() => {
  vi.stubEnv('CASHDECK_API_TOKEN', TOKEN)
  vi.stubEnv('CRON_SECRET', 'cron-secret')
  vi.stubEnv('ASAAS_WEBHOOK_TOKEN', 'asaas-token')
  vi.stubEnv('MERCADO_PAGO_WEBHOOK_SECRET', 'mp-secret')
  vi.stubEnv('INTER_WEBHOOK_TOKEN', 'inter-token')
  vi.stubEnv('PLUGGY_WEBHOOK_SECRET', 'pluggy-secret')
  vi.stubEnv('NOTAAS_WEBHOOK_SECRET', 'notaas-secret')
})

afterEach(() => {
  resetContainer()
  vi.unstubAllEnvs()
  vi.restoreAllMocks()
})

describe('webhook routes', () => {
  it('reject unauthenticated calls with 401 and ignore the bearer token', async () => {
    const bearer = { authorization: `Bearer ${TOKEN}` }
    for (const handler of [asaas, inter, mercadoPago, pluggy, notaas]) {
      const anonymous = await json(await handler(hook('x', {})))
      expect([anonymous.status, anonymous.body.error.code]).toEqual([
        401,
        'UNAUTHORIZED',
      ])
      expect((await handler(hook('x', {}, bearer))).status).toBe(401)
    }
    vi.stubEnv('ASAAS_WEBHOOK_TOKEN', '')
    const unset = hook('asaas', {}, { 'asaas-access-token': '' })
    expect((await asaas(unset)).status).toBe(401)
  })

  it('accepts authentic deliveries once and answers replays with 200', async () => {
    const body = {
      id: 'evt_1',
      event: 'TRANSFER_DONE',
      transfer: { id: 'tr-1' },
    }
    const auth = { 'asaas-access-token': 'asaas-token' }
    expect(await json(await asaas(hook('asaas', body, auth)))).toEqual({
      status: 200,
      body: { data: { received: 1, duplicates: 0 } },
    })
    expect(
      (await json(await asaas(hook('asaas', body, auth)))).body.data,
    ).toEqual({ received: 0, duplicates: 1 })
    expect((await asaas(hook('asaas', '{', auth))).status).toBe(400)
  })

  it('verifies each provider and runs the work', async () => {
    const ts = '1704908010'
    const signature = createHmac('sha256', 'mp-secret')
      .update(`id:pay-1;request-id:req-1;ts:${ts};`)
      .digest('hex')
    const mp = new Request(
      'http://localhost/api/webhooks/mercado-pago?data.id=PAY-1',
      {
        method: 'POST',
        headers: {
          'x-signature': `ts=${ts},v1=${signature}`,
          'x-request-id': 'req-1',
        },
        body: JSON.stringify({
          id: 1,
          action: 'payout.updated',
          data: { id: 'PAY-1' },
        }),
      },
    )
    expect((await mercadoPago(mp)).status).toBe(200)
    const interCall = new Request(
      'http://localhost/api/webhooks/inter?token=inter-token',
      {
        method: 'POST',
        body: JSON.stringify([{ codigoSolicitacao: 's1', status: 'PAGO' }]),
      },
    )
    expect((await inter(interCall)).status).toBe(200)
    const sync = { event: 'item/updated', eventId: 'ev-1', itemId: 'item-1' }
    const synced = await pluggy(
      hook('pluggy', sync, { 'x-cashdeck-webhook-token': 'pluggy-secret' }),
    )
    expect(synced.status).toBe(200)

    const deps = getContainer().deps
    await deps.invoices.save(
      invoice({ id: 'inv', status: 'PROCESSING', externalId: 'nf-1' }),
    )
    vi.spyOn(deps.issuer, 'get').mockResolvedValue({
      externalId: 'nf-1',
      number: '12',
      status: 'ISSUED',
      pdfUrl: null,
      xmlUrl: null,
    })
    const raw = JSON.stringify({
      event: 'nfse.issued',
      data: { invoiceId: 'nf-1' },
    })
    const sig = createHmac('sha256', 'notaas-secret').update(raw).digest('hex')
    const issued = await notaas(
      hook('notaas', raw, {
        'x-notaas-signature': `sha256=${sig}`,
        'x-notaas-delivery': 'd1',
      }),
    )
    expect(issued.status).toBe(200)
    expect((await deps.invoices.findById('local', 'inv'))?.status).toBe(
      'ISSUED',
    )
  })

  it('reports events that fail after the answer', async () => {
    const container = getContainer()
    vi.spyOn(container, 'processWebhookEvents').mockResolvedValue([
      { eventId: 'e1', kind: 'PAYMENT', outcome: 'FAILED', reason: 'down' },
      { eventId: 'e2', kind: 'IGNORED', outcome: 'IGNORED', reason: null },
    ])
    const logged = vi
      .spyOn(console, 'error')
      .mockImplementation(() => undefined)
    const body = { id: 'evt_2', transfer: { id: 'tr-2' } }
    const answer = await asaas(
      hook('asaas', body, { 'asaas-access-token': 'asaas-token' }),
    )
    expect(answer.status).toBe(200)
    expect(logged).toHaveBeenCalledWith('[webhook:asaas] Error: e1: down')
    expect(logged).toHaveBeenCalledOnce()
  })
})

function invoice(overrides: Record<string, unknown>) {
  return {
    id: 'inv',
    tenantId: 'local',
    entityId: 'company',
    clientId: 'client',
    templateId: null,
    issuer: 'notaas',
    externalId: null,
    number: null,
    status: 'DRAFT',
    amount: Money.of(100000),
    fxRate: null,
    isExport: false,
    competence: '2026-10',
    issueOn: '2026-10-08',
    description: 'Software development',
    serviceCode: '01.01',
    pdfUrl: null,
    xmlUrl: null,
    createdAt: new Date('2026-10-08T12:00:00Z'),
    ...overrides,
  } as never
}

describe('invoice lifecycle routes', () => {
  it('cancels a draft and serves the stored documents', async () => {
    const deps = getContainer().deps
    await deps.invoices.saveClient({
      id: 'client',
      tenantId: 'local',
      entityId: 'company',
      name: 'Client',
      taxId: null,
      country: 'BR',
    })
    await deps.invoices.save(invoice({ id: 'draft' }))
    const cancelled = await call(cancel, 'POST', {
      body: { reason: 'Duplicated by mistake' },
      params: { id: 'draft' },
    })
    expect([cancelled.status, cancelled.body.data.status]).toEqual([
      200,
      'CANCELLED',
    ])
    const short = await call(cancel, 'POST', {
      body: { reason: 'no' },
      params: { id: 'draft' },
    })
    expect(short.status).toBe(422)

    await deps.invoices.save(
      invoice({ id: 'issued', status: 'ISSUED', number: '5' }),
    )
    await deps.invoices.saveFile({
      tenantId: 'local',
      invoiceId: 'issued',
      kind: 'PDF',
      fileName: 'nfse-5.pdf',
      mimeType: 'application/pdf',
      size: 4,
      bytes: new TextEncoder().encode('%PDF'),
      createdAt: new Date(),
    })
    const file = await call(pdf, 'GET', { params: { id: 'issued' } })
    expect(file.headers.get('content-type')).toBe('application/pdf')
    expect(file.headers.get('content-disposition')).toContain('nfse-5.pdf')
    expect(file.body.toString()).toBe('%PDF')
    expect((await call(xml, 'GET', { params: { id: 'issued' } })).status).toBe(
      404,
    )
  })

  it('manages templates and drafts them from the cron', async () => {
    const created = await call(createTemplate, 'POST', {
      body: {
        client: { name: 'Example Inc', country: 'US' },
        description: 'Software development',
        serviceCode: '01.01',
        amountCents: 500000,
        currency: 'USD',
        dayOfMonth: 1,
      },
    })
    expect(created.status).toBe(201)
    const id = created.body.data.id
    expect((await call(listTemplates, 'GET')).body.data).toHaveLength(1)
    expect(
      (await call(getTemplate, 'GET', { params: { id } })).body.data.id,
    ).toBe(id)
    const patched = await call(updateTemplate, 'PATCH', {
      body: { billing: 'HOURLY', hours: 100 },
      params: { id },
    })
    expect(patched.body.data.cycleAmount.cents).toBe(50000000)
    const invalid = await call(updateTemplate, 'PATCH', {
      body: { dayOfMonth: 32 },
      params: { id },
    })
    expect(invalid.status).toBe(422)

    const cron = await invoicesCron(
      new Request('http://localhost/api/cron/invoices', {
        headers: { authorization: 'Bearer cron-secret' },
      }),
    )
    expect((await cron.json()).data).toMatchObject({
      source: 'invoices',
      drafts: { templates: 1, created: 1 },
      poll: { checked: 0 },
    })
    const home = await call(homeCompany, 'GET')
    expect(home.body.data.drafts).toMatchObject([{ recurring: true }])
    const removed = await call(deleteTemplate, 'DELETE', { params: { id } })
    expect(removed.body.data).toEqual({ id })
    expect((await call(getTemplate, 'GET', { params: { id } })).status).toBe(
      404,
    )
  })
})
