import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { type InMemoryAuditLog } from '@cashdeck/application'
import { STATIC_TOKEN } from '@/app/api/sign-in.test-helpers'
import { signState, staticTokenActor, verifyState } from '@/server/api/auth'
import { getContainer, resetContainer } from '@/server/container'
import { GET as authCheck } from '@/app/api/v1/auth/check/route'
import {
  GET as listSessions,
  POST as createSession,
} from '@/app/api/v1/sessions/route'
import { DELETE as revokeSession } from '@/app/api/v1/sessions/[id]/route'
import { DELETE as signOut } from '@/app/api/v1/sessions/current/route'

type Handler = (request: Request, context: never) => Promise<Response>

async function call(
  handler: unknown,
  method: string,
  options: { bearer?: string; body?: unknown; id?: string } = {},
) {
  const request = new Request('http://localhost/api/v1/sessions', {
    method,
    headers: {
      ...(options.bearer ? { authorization: `Bearer ${options.bearer}` } : {}),
      'x-request-id': 'req-1',
    },
    body: options.body === undefined ? undefined : JSON.stringify(options.body),
  })
  const context = { params: Promise.resolve({ id: options.id ?? '' }) }
  const response = await (handler as Handler)(request, context as never)
  return { status: response.status, body: await response.json() }
}

const phone = { deviceName: 'Test phone', platform: 'ANDROID' }

async function signIn(body: unknown = phone) {
  return call(createSession, 'POST', { bearer: STATIC_TOKEN, body })
}

const audit = () => getContainer().deps.audit as InMemoryAuditLog

beforeEach(() => {
  vi.stubEnv('CASHDECK_API_TOKEN', STATIC_TOKEN)
})

afterEach(() => {
  resetContainer()
  vi.unstubAllEnvs()
})

describe('device sessions api', () => {
  it('trades the static token for a session token', async () => {
    const created = await signIn()
    expect(created.status).toBe(201)
    const { token, expiresAt, session } = created.body.data
    expect(token).toMatch(/^[A-Za-z0-9_-]{43}$/)
    expect(session).toMatchObject({
      deviceName: 'Test phone',
      platform: 'ANDROID',
      current: true,
      expiresAt,
    })
    expect(audit().events.at(-1)).toMatchObject({
      action: 'session.create',
      subjectId: session.id,
      actorId: expect.stringMatching(/^token:[0-9a-f]{12}$/),
      requestId: 'req-1',
    })
    const check = await call(authCheck, 'GET', { bearer: token })
    expect(check.status).toBe(200)
  })

  it('refuses a wrong static token, a bad body and a missing config', async () => {
    const anonymous = await call(createSession, 'POST', { body: phone })
    expect(anonymous.status).toBe(401)
    const wrong = await call(createSession, 'POST', {
      bearer: 'nope',
      body: phone,
    })
    expect([wrong.status, wrong.body.error.code]).toEqual([401, 'UNAUTHORIZED'])
    expect((await signIn({ deviceName: '', platform: 'ANDROID' })).status).toBe(
      422,
    )
    expect((await signIn({ ...phone, platform: 'PALM' })).status).toBe(422)
    vi.stubEnv('CASHDECK_API_TOKEN', '')
    const unset = await signIn()
    expect([unset.status, unset.body.error.code]).toEqual([
      503,
      'NOT_CONFIGURED',
    ])
  })

  it('no longer accepts the static token on regular routes', async () => {
    const denied = await call(authCheck, 'GET', { bearer: STATIC_TOKEN })
    expect([denied.status, denied.body.error.code]).toEqual([
      401,
      'UNAUTHORIZED',
    ])
    expect((await call(listSessions, 'GET')).status).toBe(401)
  })

  it('lists devices, revokes another one and signs this one out', async () => {
    const phoneToken = (await signIn()).body.data.token as string
    const tablet = (await signIn({ deviceName: 'Tablet', platform: 'IOS' }))
      .body.data
    const listed = await call(listSessions, 'GET', { bearer: phoneToken })
    expect(
      listed.body.data.map((row: { deviceName: string; current: boolean }) => [
        row.deviceName,
        row.current,
      ]),
    ).toEqual(
      expect.arrayContaining([
        ['Test phone', true],
        ['Tablet', false],
      ]),
    )
    const phoneId = listed.body.data.find(
      (row: { current: boolean }) => row.current,
    ).id as string

    const revoked = await call(revokeSession, 'DELETE', {
      bearer: phoneToken,
      id: tablet.session.id,
    })
    expect(revoked.body.data).toEqual({ id: tablet.session.id })
    expect(audit().events.at(-1)).toMatchObject({
      action: 'session.revoke',
      subjectId: tablet.session.id,
      actorId: `session:${phoneId}`,
    })
    expect(
      (await call(listSessions, 'GET', { bearer: tablet.token })).status,
    ).toBe(401)
    expect(
      (
        await call(revokeSession, 'DELETE', {
          bearer: phoneToken,
          id: tablet.session.id,
        })
      ).status,
    ).toBe(404)

    const out = await call(signOut, 'DELETE', { bearer: phoneToken })
    expect(out.body.data).toEqual({ id: phoneId })
    expect(
      (await call(listSessions, 'GET', { bearer: phoneToken })).status,
    ).toBe(401)
  })

  it('names the static token holder and signs state only with a token', () => {
    const now = new Date('2026-10-11T12:00:00Z')
    const state = signState({ tenantId: 'local', entity: 'PF' }, now)
    expect(verifyState(state, now)).toMatchObject({ tenantId: 'local' })
    expect(verifyState(state, new Date(now.getTime() + 3_600_000))).toBeNull()
    vi.stubEnv('CASHDECK_API_TOKEN', '')
    const request = new Request('http://localhost', {
      headers: { 'x-vercel-id': 'vercel-1' },
    })
    expect(staticTokenActor(request)).toEqual({
      kind: 'USER',
      id: 'token:e3b0c44298fc',
      requestId: 'vercel-1',
    })
    expect(
      verifyState(signState({ tenantId: 'local', entity: 'PF' }, now), now),
    ).toBeNull()
  })
})
