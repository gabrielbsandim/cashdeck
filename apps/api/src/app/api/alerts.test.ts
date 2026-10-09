import { generateKeyPairSync } from 'node:crypto'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { resetContainer } from '@/server/container'
import { POST as captureBill } from '@/app/api/v1/bills/route'
import { POST as payBill } from '@/app/api/v1/bills/[id]/pay/route'
import { GET as listAlerts } from '@/app/api/v1/alerts/route'
import { GET as unreadCount } from '@/app/api/v1/alerts/unread-count/route'
import { POST as markRead } from '@/app/api/v1/alerts/[id]/read/route'
import { POST as readAll } from '@/app/api/v1/alerts/read-all/route'
import {
  GET as alertSettings,
  PATCH as updateAlertSettings,
} from '@/app/api/v1/alerts/settings/route'
import { POST as registerDevice } from '@/app/api/v1/devices/route'
import { DELETE as removeDevice } from '@/app/api/v1/devices/[token]/route'
import { GET as alertsCron } from '@/app/api/cron/alerts/route'

const TOKEN = 'test-token-0123456789'
const AUTH = { authorization: `Bearer ${TOKEN}` }
const TAX_BARCODE = '85600000001500003282026102000000000000123000'
const DEVICE = 'fcm:device-token_1'

type Handler = (request: Request, context: never) => Promise<Response>

async function call(
  handler: unknown,
  method: string,
  options: {
    body?: unknown
    params?: Record<string, string>
    query?: string
  } = {},
) {
  const request = new Request(
    `http://localhost/api/v1/test${options.query ?? ''}`,
    {
      method,
      headers: AUTH,
      body:
        options.body === undefined ? undefined : JSON.stringify(options.body),
    },
  )
  const context = { params: Promise.resolve(options.params ?? {}) }
  const response = await (handler as Handler)(request, context as never)
  return { status: response.status, body: await response.json() }
}

async function captureAndPay() {
  const created = await call(captureBill, 'POST', {
    body: {
      entityId: 'company',
      paymentCode: TAX_BARCODE,
      dueDate: '2026-10-20',
    },
  })
  const id = created.body.data.id as string
  await call(payBill, 'POST', { params: { id } })
  await call(payBill, 'POST', { params: { id }, body: { confirmed: true } })
  return id
}

beforeEach(() => {
  vi.stubEnv('CASHDECK_API_TOKEN', TOKEN)
})

afterEach(() => {
  resetContainer()
  vi.unstubAllEnvs()
  vi.unstubAllGlobals()
})

describe('alerts api', () => {
  it('fills the inbox from capture and the ladder, then reads it', async () => {
    const billId = await captureAndPay()
    const inbox = await call(listAlerts, 'GET', { query: '?limit=10' })
    expect(inbox.status).toBe(200)
    expect(
      inbox.body.data.map((alert: { type: string }) => alert.type),
    ).toEqual([
      'PAYMENT_ASSISTED',
      'PAYMENT_NEEDS_CONFIRMATION',
      'BILL_CAPTURED',
    ])
    expect(inbox.body.data[0]).toMatchObject({
      billId,
      title: 'Pague manualmente',
      data: { hasPixCode: 'false', method: 'BARCODE' },
      readAt: null,
    })
    expect(inbox.body.nextCursor).toBeNull()

    const first = inbox.body.data[0].id as string
    const read = await call(markRead, 'POST', { params: { id: first } })
    expect(read.body.data.readAt).not.toBeNull()
    expect((await call(unreadCount, 'GET')).body.data).toEqual({ unread: 2 })
    const unread = await call(listAlerts, 'GET', { query: '?unread=true' })
    expect(unread.body.data).toHaveLength(2)
    expect((await call(readAll, 'POST')).body.data).toEqual({ updated: 2 })
    expect(
      (await call(markRead, 'POST', { params: { id: 'nope' } })).status,
    ).toBe(404)
    expect(
      (await call(listAlerts, 'GET', { query: '?unread=maybe' })).status,
    ).toBe(422)
  })

  it('mutes alert types', async () => {
    const initial = await call(alertSettings, 'GET')
    expect(
      initial.body.data.types.every((type: { muted: boolean }) => !type.muted),
    ).toBe(true)
    const updated = await call(updateAlertSettings, 'PATCH', {
      body: { muted: { BILL_DUE_SOON: true } },
    })
    expect(updated.body.data.types).toContainEqual({
      type: 'BILL_DUE_SOON',
      muted: true,
    })
    const invalid = await call(updateAlertSettings, 'PATCH', {
      body: { muted: { NOT_A_TYPE: true } },
    })
    expect(invalid.status).toBe(422)
  })

  it('registers and removes a device token', async () => {
    const created = await call(registerDevice, 'POST', {
      body: { token: DEVICE, platform: 'ANDROID' },
    })
    expect(created.status).toBe(201)
    expect(created.body.data).toMatchObject({ token: DEVICE })
    const removed = await call(removeDevice, 'DELETE', {
      params: { token: encodeURIComponent(DEVICE) },
    })
    expect(removed.body.data).toEqual({ removed: true })
    const again = await call(removeDevice, 'DELETE', {
      params: { token: DEVICE },
    })
    expect(again.body.data).toEqual({ removed: false })
    const invalid = await call(registerDevice, 'POST', {
      body: { token: '', platform: 'PHONE' },
    })
    expect(invalid.status).toBe(422)
  })

  it('pushes through FCM and drops a token it reports unregistered', async () => {
    const { privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 })
    vi.stubEnv(
      'FCM_SERVICE_ACCOUNT_JSON',
      JSON.stringify({
        project_id: 'cashdeck-test',
        client_email: 'push@cashdeck-test.iam.gserviceaccount.com',
        private_key: privateKey.export({ type: 'pkcs8', format: 'pem' }),
      }),
    )
    const sent: string[] = []
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string) => {
        sent.push(url)
        if (url.includes('oauth2')) {
          return Response.json({ access_token: 'access', expires_in: 3600 })
        }
        return Response.json(
          {
            error: {
              status: 'NOT_FOUND',
              details: [{ errorCode: 'UNREGISTERED' }],
            },
          },
          { status: 404 },
        )
      }),
    )
    await call(registerDevice, 'POST', {
      body: { token: DEVICE, platform: 'ANDROID' },
    })
    await call(captureBill, 'POST', {
      body: {
        entityId: 'company',
        paymentCode: TAX_BARCODE,
        dueDate: '2026-10-20',
      },
    })
    expect(sent.some(url => url.includes('messages:send'))).toBe(true)
    const removed = await call(removeDevice, 'DELETE', {
      params: { token: DEVICE },
    })
    expect(removed.body.data).toEqual({ removed: false })
  })

  it('runs the daily alerts from the cron route', async () => {
    vi.stubEnv('CRON_SECRET', 'secret')
    const request = new Request('http://localhost/api/cron/alerts', {
      headers: { authorization: 'Bearer secret' },
    })
    const response = await alertsCron(request)
    expect((await response.json()).data).toMatchObject({
      source: 'alerts',
      dueSoon: 0,
      lowBalance: 0,
    })
  })
})
