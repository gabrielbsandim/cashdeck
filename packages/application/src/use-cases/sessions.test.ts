import { describe, expect, it } from 'vitest'
import {
  SESSION_TOUCH_INTERVAL_MS,
  SESSION_TTL_MS,
  ValidationError,
} from '@cashdeck/domain'
import { NotFoundError, UnauthorizedError } from '@/errors/errors'
import { type Actor } from '@/ports/repositories'
import { InMemoryAuditLog } from '@/testing/repositories'
import {
  FakeSessionTokens,
  InMemoryDeviceSessionRepository,
} from '@/testing/sessions'
import { FixedClock, SequentialIdGenerator } from '@/testing/system'
import { makeDeviceSessions, sessionActorId } from '@/use-cases/sessions'

const NOW = new Date('2026-10-11T12:00:00.000Z')
const TENANT = 't1'
const ACTOR: Actor = { kind: 'USER', id: 'token:abc', requestId: 'req-1' }
const later = (ms: number) => new Date(NOW.getTime() + ms)

function setup() {
  const deps = {
    sessions: new InMemoryDeviceSessionRepository(),
    sessionTokens: new FakeSessionTokens(),
    audit: new InMemoryAuditLog(),
    clock: new FixedClock(NOW),
    ids: new SequentialIdGenerator('s'),
  }
  return { deps, sessions: makeDeviceSessions(deps) }
}

const phone = { deviceName: 'Pixel', platform: 'ANDROID' as const }

describe('device sessions', () => {
  it('issues a token and keeps only its hash', async () => {
    const { deps, sessions } = setup()
    const created = await sessions.create(TENANT, phone, ACTOR)
    expect(created).toEqual({
      token: 'session-token-1',
      expiresAt: later(SESSION_TTL_MS).toISOString(),
      session: {
        id: 's_1',
        deviceName: 'Pixel',
        platform: 'ANDROID',
        createdAt: NOW.toISOString(),
        lastUsedAt: NOW.toISOString(),
        expiresAt: later(SESSION_TTL_MS).toISOString(),
        current: true,
      },
    })
    const stored = await deps.sessions.findById(TENANT, 's_1')
    expect(stored?.tokenHash).toBe('hash(session-token-1)')
    expect(deps.audit.events).toEqual([
      expect.objectContaining({
        action: 'session.create',
        subjectId: 's_1',
        actor: 'USER',
        actorId: 'token:abc',
        requestId: 'req-1',
        result: 'OK',
        details: { deviceName: 'Pixel', platform: 'ANDROID' },
      }),
    ])
  })

  it('refuses a blank device name', async () => {
    const { sessions } = setup()
    await expect(
      sessions.create(TENANT, { ...phone, deviceName: ' ' }, ACTOR),
    ).rejects.toThrow(ValidationError)
  })

  it('authenticates a live token and slides it at most hourly', async () => {
    const { deps, sessions } = setup()
    const { token } = await sessions.create(TENANT, phone, ACTOR)
    expect((await sessions.authenticate(TENANT, token)).lastUsedAt).toEqual(NOW)
    const at = later(SESSION_TOUCH_INTERVAL_MS)
    deps.clock.set(at)
    const touched = await sessions.authenticate(TENANT, token)
    expect(touched.lastUsedAt).toEqual(at)
    expect((await deps.sessions.findById(TENANT, 's_1'))?.expiresAt).toEqual(
      new Date(at.getTime() + SESSION_TTL_MS),
    )
  })

  it('rejects unknown, foreign, expired and revoked tokens', async () => {
    const { deps, sessions } = setup()
    const { token } = await sessions.create(TENANT, phone, ACTOR)
    await expect(sessions.authenticate(TENANT, 'nope')).rejects.toThrow(
      UnauthorizedError,
    )
    await expect(sessions.authenticate('t2', token)).rejects.toThrow(
      UnauthorizedError,
    )
    deps.clock.set(later(SESSION_TTL_MS))
    await expect(sessions.authenticate(TENANT, token)).rejects.toThrow(
      UnauthorizedError,
    )
    deps.clock.set(NOW)
    await sessions.revoke(TENANT, 's_1', ACTOR)
    await expect(sessions.authenticate(TENANT, token)).rejects.toThrow(
      UnauthorizedError,
    )
  })

  it('lists active devices newest first and marks the current one', async () => {
    const { deps, sessions } = setup()
    await sessions.create(TENANT, phone, ACTOR)
    deps.clock.set(later(1000))
    await sessions.create(
      TENANT,
      { deviceName: 'iPad', platform: 'IOS' },
      ACTOR,
    )
    await sessions.create('t2', phone, ACTOR)
    const listed = await sessions.list(TENANT, 's_1')
    expect(listed.map(({ id, current }) => ({ id, current }))).toEqual([
      { id: 's_3', current: false },
      { id: 's_1', current: true },
    ])
  })

  it('revokes once, audits it, and hides the device', async () => {
    const { deps, sessions } = setup()
    await sessions.create(TENANT, phone, ACTOR)
    const actor = { ...ACTOR, id: sessionActorId('s_1') }
    expect(await sessions.revoke(TENANT, 's_1', actor)).toEqual({ id: 's_1' })
    expect(deps.audit.events.at(-1)).toMatchObject({
      action: 'session.revoke',
      subjectId: 's_1',
      actorId: 'session:s_1',
    })
    expect(await sessions.list(TENANT, 's_1')).toEqual([])
    await expect(sessions.revoke(TENANT, 's_1', actor)).rejects.toThrow(
      NotFoundError,
    )
    await expect(sessions.revoke(TENANT, 'missing', actor)).rejects.toThrow(
      NotFoundError,
    )
  })
})
