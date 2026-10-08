import { describe, expect, it } from 'vitest'
import {
  addDays,
  daysBetween,
  localDate,
  toLocalDate,
  weekday,
} from '@/calendar/local-date'
import {
  addBusinessDays,
  bankHolidays,
  easterSunday,
  isBusinessDay,
  nextBusinessDay,
} from '@/calendar/business-days'

describe('local dates', () => {
  it('converts an instant to the Sao Paulo calendar day', () => {
    expect(toLocalDate(new Date('2026-10-09T02:30:00Z'))).toBe('2026-10-08')
    expect(toLocalDate(new Date('2026-10-09T02:30:00Z'), 'UTC')).toBe(
      '2026-10-09',
    )
  })

  it('does date arithmetic', () => {
    expect(addDays('2026-12-31', 1)).toBe('2027-01-01')
    expect(daysBetween('2026-10-01', '2026-10-08')).toBe(7)
    expect(weekday('2026-10-08')).toBe(4)
    expect(localDate(2026, 2, 29)).toBe('2026-03-01')
    expect(() => addDays('8/10/2026', 1)).toThrow('is not an ISO date')
  })
})

describe('business days', () => {
  it('computes Easter', () => {
    expect(easterSunday(2026)).toBe('2026-04-05')
    expect(easterSunday(2027)).toBe('2027-03-28')
  })

  it('lists national bank holidays including the movable ones', () => {
    const holidays = bankHolidays(2026)
    expect(holidays.has('2026-02-16')).toBe(true)
    expect(holidays.has('2026-02-17')).toBe(true)
    expect(holidays.has('2026-04-03')).toBe(true)
    expect(holidays.has('2026-06-04')).toBe(true)
    expect(holidays.has('2026-11-20')).toBe(true)
    expect(bankHolidays(2026)).toBe(holidays)
  })

  it('skips weekends and holidays', () => {
    expect(isBusinessDay('2026-10-08')).toBe(true)
    expect(isBusinessDay('2026-10-10')).toBe(false)
    expect(isBusinessDay('2026-10-12')).toBe(false)
    expect(nextBusinessDay('2026-10-10')).toBe('2026-10-13')
    expect(nextBusinessDay('2026-10-08')).toBe('2026-10-08')
    expect(addBusinessDays('2026-10-09', 1)).toBe('2026-10-13')
    expect(addBusinessDays('2026-10-10', 0)).toBe('2026-10-13')
  })
})
