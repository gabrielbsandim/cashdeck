import { ValidationError } from '@/shared/domain-error'

export const SESSION_PLATFORMS = ['ANDROID', 'IOS', 'WEB'] as const
export type SessionPlatform = (typeof SESSION_PLATFORMS)[number]

const HOUR_MS = 60 * 60 * 1000
export const SESSION_TTL_MS = 30 * 24 * HOUR_MS
export const SESSION_TOUCH_INTERVAL_MS = HOUR_MS
const MAX_DEVICE_NAME = 80

// One signed-in device. Only the hash of its bearer token is ever kept.
export type DeviceSession = {
  readonly id: string
  readonly tenantId: string
  readonly tokenHash: string
  readonly deviceName: string
  readonly platform: SessionPlatform
  readonly createdAt: Date
  readonly lastUsedAt: Date
  readonly expiresAt: Date
  readonly revokedAt: Date | null
}

export type NewDeviceSession = {
  id: string
  tenantId: string
  tokenHash: string
  deviceName: string
  platform: SessionPlatform
  now: Date
}

const expiryFrom = (now: Date) => new Date(now.getTime() + SESSION_TTL_MS)

export function deviceName(raw: string): string {
  const name = raw.trim().replace(/\s+/g, ' ')
  if (name.length === 0 || name.length > MAX_DEVICE_NAME) {
    throw new ValidationError(
      `A device name has 1 to ${MAX_DEVICE_NAME} characters.`,
    )
  }
  return name
}

export function createDeviceSession(input: NewDeviceSession): DeviceSession {
  return {
    id: input.id,
    tenantId: input.tenantId,
    tokenHash: input.tokenHash,
    deviceName: deviceName(input.deviceName),
    platform: input.platform,
    createdAt: input.now,
    lastUsedAt: input.now,
    expiresAt: expiryFrom(input.now),
    revokedAt: null,
  }
}

export function isSessionActive(session: DeviceSession, now: Date): boolean {
  return session.revokedAt === null && session.expiresAt > now
}

// Sliding expiry, written at most once an hour so a busy device does not turn
// every request into a write. Null means nothing changed.
export function touchSession(
  session: DeviceSession,
  now: Date,
): DeviceSession | null {
  const idle = now.getTime() - session.lastUsedAt.getTime()
  if (idle < SESSION_TOUCH_INTERVAL_MS) {
    return null
  }
  return { ...session, lastUsedAt: now, expiresAt: expiryFrom(now) }
}

export function revokeSession(
  session: DeviceSession,
  now: Date,
): DeviceSession {
  return { ...session, revokedAt: now }
}
