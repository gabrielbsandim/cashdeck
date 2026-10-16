import { describe, expect, it } from 'vitest'
import { seenToday, timeOfDay } from '@/openfinance/time-of-day'

describe('time of day', () => {
  it('keeps a real time and drops a date sent as midnight', () => {
    expect(timeOfDay('2026-10-15T21:40:12.000Z')).toBe(
      '2026-10-15T21:40:12.000Z',
    )
    expect(timeOfDay('2026-10-15T03:00:00.000Z')).toBeNull()
    expect(timeOfDay('2026-10-15T00:00:00.000Z')).toBeNull()
    expect(timeOfDay('not a date')).toBeNull()
  })

  it('stands the read time in only on the day itself', () => {
    const now = new Date('2026-10-16T01:30:00.000Z')
    expect(seenToday('2026-10-15', now)).toBe(now.toISOString())
    expect(seenToday('2026-10-14', now)).toBeNull()
  })
})
