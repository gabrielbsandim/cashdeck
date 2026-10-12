import {
  createDeviceSession,
  type DeviceSession,
  isSessionActive,
  revokeSession,
  touchSession,
} from '@cashdeck/domain'
import {
  type CreatedSession,
  type CreateSessionInput,
  type SessionView,
  toSessionView,
} from '@/dtos/sessions'
import { NotFoundError, UnauthorizedError } from '@/errors/errors'
import { type Actor, type AuditLog } from '@/ports/repositories'
import {
  type DeviceSessionRepository,
  type SessionTokens,
} from '@/ports/sessions'
import { type Clock, type IdGenerator } from '@/ports/system'

export type DeviceSessionDeps = {
  sessions: DeviceSessionRepository
  sessionTokens: SessionTokens
  audit: AuditLog
  clock: Clock
  ids: IdGenerator
}

// The audit trail names a device by its session, never by any token.
export const sessionActorId = (sessionId: string) => `session:${sessionId}`

export function makeDeviceSessions(deps: DeviceSessionDeps) {
  async function audit(
    session: DeviceSession,
    action: string,
    actor: Actor,
  ): Promise<void> {
    await deps.audit.record({
      id: deps.ids.next(),
      tenantId: session.tenantId,
      actor: actor.kind,
      actorId: actor.id,
      requestId: actor.requestId,
      action,
      subjectId: session.id,
      rail: null,
      result: 'OK',
      details: { deviceName: session.deviceName, platform: session.platform },
      at: deps.clock.now(),
    })
  }

  async function create(
    tenantId: string,
    input: CreateSessionInput,
    actor: Actor,
  ): Promise<CreatedSession> {
    const token = deps.sessionTokens.issue()
    const session = createDeviceSession({
      id: deps.ids.next(),
      tenantId,
      tokenHash: deps.sessionTokens.hash(token),
      deviceName: input.deviceName,
      platform: input.platform,
      now: deps.clock.now(),
    })
    await deps.sessions.save(session)
    await audit(session, 'session.create', actor)
    return {
      token,
      expiresAt: session.expiresAt.toISOString(),
      session: toSessionView(session, session.id),
    }
  }

  async function authenticate(
    tenantId: string,
    token: string,
  ): Promise<DeviceSession> {
    const now = deps.clock.now()
    const session = await deps.sessions.findByTokenHash(
      tenantId,
      deps.sessionTokens.hash(token),
    )
    if (!session || !isSessionActive(session, now)) {
      throw new UnauthorizedError('Missing, expired or revoked session.')
    }
    const touched = touchSession(session, now)
    if (!touched) {
      return session
    }
    await deps.sessions.save(touched)
    return touched
  }

  async function list(
    tenantId: string,
    currentId: string,
  ): Promise<SessionView[]> {
    const active = await deps.sessions.listActive(tenantId, deps.clock.now())
    return active.map(session => toSessionView(session, currentId))
  }

  async function revoke(
    tenantId: string,
    id: string,
    actor: Actor,
  ): Promise<{ id: string }> {
    const now = deps.clock.now()
    const session = await deps.sessions.findById(tenantId, id)
    if (!session || !isSessionActive(session, now)) {
      throw new NotFoundError('Session')
    }
    const revoked = revokeSession(session, now)
    await deps.sessions.save(revoked)
    await audit(revoked, 'session.revoke', actor)
    return { id }
  }

  return { create, authenticate, list, revoke }
}

export type DeviceSessions = ReturnType<typeof makeDeviceSessions>
