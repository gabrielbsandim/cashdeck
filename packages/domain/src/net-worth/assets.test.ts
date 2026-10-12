import { describe, expect, it } from 'vitest'
import {
  assetValueOn,
  type ValuedAsset,
  withValuation,
} from '@/net-worth/assets'

const car: ValuedAsset = {
  kind: 'VEHICLE',
  acquiredOn: '2024-05-20',
  soldOn: null,
  valuations: [
    { day: '2026-10-01', cents: 8900000 },
    { day: '2026-08-01', cents: 9100000 },
  ],
}

describe('assetValueOn', () => {
  it('reads the last price on or before the day, the first one before it', () => {
    expect(assetValueOn(car, '2026-10-12').cents).toBe(8900000)
    expect(assetValueOn(car, '2026-09-30').cents).toBe(9100000)
    expect(assetValueOn(car, '2025-01-31').cents).toBe(9100000)
  })

  it('is worth nothing before it was bought, once sold or with no price', () => {
    expect(assetValueOn(car, '2024-04-30').cents).toBe(0)
    const sold = { ...car, soldOn: '2026-09-15' }
    expect(assetValueOn(sold, '2026-09-14').cents).toBe(9100000)
    expect(assetValueOn(sold, '2026-09-15').cents).toBe(0)
    expect(assetValueOn({ ...car, valuations: [] }, '2026-10-12').cents).toBe(0)
  })
})

describe('withValuation', () => {
  it('keeps one price a day, in order', () => {
    expect(
      withValuation(car.valuations, { day: '2026-08-01', cents: 9000000 }),
    ).toEqual([
      { day: '2026-08-01', cents: 9000000 },
      { day: '2026-10-01', cents: 8900000 },
    ])
  })
})
