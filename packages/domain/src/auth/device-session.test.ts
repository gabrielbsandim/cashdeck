import { describe, expect, it } from 'vitest'
import {
  createDeviceSession,
  type DeviceSession,
  deviceName,
  isSessionActive,
  revokeSession,
  SESSION_TOUCH_INTERVAL_MS,
  SESSION_TTL_MS,
  touchSession,
} from '@/auth/device-session'
import { ValidationError } from '@/shared/domain-error'

const NOW = new Date('2026-10-11T12:00:00Z')
const later = (ms: number) => new Date(NOW.getTime() + ms)

function session(overrides: Partial<DeviceSession> = {}): DeviceSession {
  return {
    ...createDeviceSession({
      id: 's1',
      tenantId: 't1',
      tokenHash: 'hash',
      deviceName: '  Pixel   phone ',
      platform: 'ANDROID',
      now: NOW,
    }),
    ...overrides,
  }
}

describe('device session', () => {
  it('starts active for thirty days with a tidy name', () => {
    expect(session()).toEqual({
      id: 's1',
      tenantId: 't1',
      tokenHash: 'hash',
      deviceName: 'Pixel phone',
      platform: 'ANDROID',
      createdAt: NOW,
      lastUsedAt: NOW,
      expiresAt: later(SESSION_TTL_MS),
      revokedAt: null,
    })
  })

  it('refuses an empty or overlong device name', () => {
    expect(() => deviceName('   ')).toThrow(ValidationError)
    expect(() => deviceName('x'.repeat(81))).toThrow(ValidationError)
    expect(deviceName('x'.repeat(80))).toHaveLength(80)
  })

  it('is inactive once expired or revoked', () => {
    expect(isSessionActive(session(), NOW)).toBe(true)
    expect(isSessionActive(session(), later(SESSION_TTL_MS))).toBe(false)
    expect(isSessionActive(revokeSession(session(), NOW), NOW)).toBe(false)
  })

  it('slides the expiry at most once an hour', () => {
    expect(touchSession(session(), later(SESSION_TOUCH_INTERVAL_MS - 1))).toBe(
      null,
    )
    const at = later(SESSION_TOUCH_INTERVAL_MS)
    expect(touchSession(session(), at)).toMatchObject({
      lastUsedAt: at,
      expiresAt: new Date(at.getTime() + SESSION_TTL_MS),
    })
  })

  it('records when it was revoked', () => {
    expect(revokeSession(session(), later(5)).revokedAt).toEqual(later(5))
  })
})
