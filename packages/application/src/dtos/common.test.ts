import { describe, expect, it } from 'vitest'
import { isoDate } from '@/dtos/common'

describe('isoDate', () => {
  it('accepts a calendar day, leap days included', () => {
    expect(isoDate.parse('2026-10-09')).toBe('2026-10-09')
    expect(isoDate.parse('2028-02-29')).toBe('2028-02-29')
  })

  it.each([
    '2026-13-01',
    '2026-02-30',
    '2027-02-29',
    '2026-00-10',
    '2026-10-32',
  ])('rejects %s, which has the shape of a day but is none', value => {
    expect(isoDate.safeParse(value).success).toBe(false)
  })

  it('rejects a value that is not shaped as YYYY-MM-DD', () => {
    expect(isoDate.safeParse('09/10/2026').success).toBe(false)
  })
})
