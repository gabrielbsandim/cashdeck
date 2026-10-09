import { createHash, createHmac, timingSafeEqual } from 'node:crypto'
import { type Actor } from '@cashdeck/application'
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

// One guard for every protected route: no token configured is a server
// problem (503), a wrong token is the caller's (401).
export function authorize(request: Request): NextResponse<ApiErrorBody> | null {
  const token = apiToken()
  if (!token) {
    return fail(
      'NOT_CONFIGURED',
      'The server has no API token configured.',
      503,
    )
  }
  const header = request.headers.get('authorization') ?? ''
  if (!sameSecret(header, `Bearer ${token}`)) {
    return fail('UNAUTHORIZED', 'Missing or invalid API token.', 401)
  }
  return null
}

// One token stands for the app user, so its hash prefix names the actor in the
// audit log without storing the token; rotating it shows up as a new actor.
export function requestActor(request: Request): Actor {
  const token = apiToken() ?? ''
  const id = createHash('sha256').update(token).digest('hex').slice(0, 12)
  const requestId =
    request.headers.get('x-request-id') ?? request.headers.get('x-vercel-id')
  return { kind: 'USER', id: `token:${id}`, requestId }
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
