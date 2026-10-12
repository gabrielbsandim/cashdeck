import { createHash, createHmac, timingSafeEqual } from 'node:crypto'
import { type Actor, sessionActorId } from '@cashdeck/application'
import { type NextResponse } from 'next/server'
import { type ApiErrorBody, fail } from '@/server/api/respond'
import { readEnv } from '@/server/env'

// Hashing first gives both sides the same length, so the comparison never
// leaks the token length.
function sameSecret(given: string, expected: string): boolean {
  const digest = (value: string) => createHash('sha256').update(value).digest()
  return timingSafeEqual(digest(given), digest(expected))
}

export function apiToken(): string | null {
  return readEnv().CASHDECK_API_TOKEN ?? null
}

export function notConfigured(): NextResponse<ApiErrorBody> {
  return fail('NOT_CONFIGURED', 'The server has no API token configured.', 503)
}

export function bearerToken(request: Request): string {
  const header = request.headers.get('authorization') ?? ''
  return header.startsWith('Bearer ') ? header.slice('Bearer '.length) : ''
}

// The static token only signs a device in; every other route takes the
// session that exchange returns. No token configured is a server problem
// (503), a wrong token is the caller's (401).
export function authorizeStatic(
  request: Request,
): NextResponse<ApiErrorBody> | null {
  const token = apiToken()
  if (!token) {
    return notConfigured()
  }
  const header = request.headers.get('authorization') ?? ''
  if (!sameSecret(header, `Bearer ${token}`)) {
    return fail('UNAUTHORIZED', 'Missing or invalid API token.', 401)
  }
  return null
}

const requestIdOf = (request: Request) =>
  request.headers.get('x-request-id') ?? request.headers.get('x-vercel-id')

// Whoever holds the static token, named by its hash prefix so the audit log
// never stores it; rotating it shows up as a new actor.
export function staticTokenActor(request: Request): Actor {
  const token = apiToken() ?? ''
  const id = createHash('sha256').update(token).digest('hex').slice(0, 12)
  return { kind: 'USER', id: `token:${id}`, requestId: requestIdOf(request) }
}

export function sessionActor(request: Request, sessionId: string): Actor {
  return {
    kind: 'USER',
    id: sessionActorId(sessionId),
    requestId: requestIdOf(request),
  }
}

const STATE_TTL_MS = 10 * 60 * 1000

type StatePayload = { tenantId: string; entity: string; exp: number }

const sign = (body: string, token: string) =>
  createHmac('sha256', token).update(body).digest('base64url')

export function signState(
  payload: Omit<StatePayload, 'exp'>,
  now: Date,
): string {
  const token = apiToken() ?? ''
  const body = Buffer.from(
    JSON.stringify({ ...payload, exp: now.getTime() + STATE_TTL_MS }),
  ).toString('base64url')
  return `${body}.${sign(body, token)}`
}

export function verifyState(state: string, now: Date): StatePayload | null {
  const token = apiToken()
  const [body = '', signature = ''] = state.split('.')
  if (!token || !sameSecret(signature, sign(body, token))) {
    return null
  }
  const payload = JSON.parse(
    Buffer.from(body, 'base64url').toString(),
  ) as StatePayload
  return payload.exp > now.getTime() ? payload : null
}
