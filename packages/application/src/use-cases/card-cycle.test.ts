import { describe, expect, it } from 'vitest'
import { dueAfter } from '@/use-cases/card-cycle'

describe('card cycle', () => {
  it('keeps the due day and clamps it to short months', () => {
    expect(dueAfter('2026-09-15', '2026-10-09')).toBe('2026-10-15')
    expect(dueAfter('2026-09-15', '2026-10-16')).toBe('2026-11-15')
    expect(dueAfter('2026-01-31', '2026-02-01')).toBe('2026-02-28')
  })
})
