import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

type VercelConfig = { crons: Array<{ path: string; schedule: string }> }

const config = JSON.parse(
  readFileSync(new URL('../../../../vercel.json', import.meta.url), 'utf8'),
) as VercelConfig

const scheduleOf = (path: string) =>
  config.crons.find(cron => cron.path === path)?.schedule

describe('cron schedule', () => {
  // Pluggy collects MeuPluggy items once a day, the C6 one around 14:01 UTC.
  it('runs the open finance backstop daily, after the provider collects', () => {
    const [minute, hour, ...daily] = (
      scheduleOf('/api/cron/open-finance-sync') ?? ''
    ).split(' ')
    expect(daily).toEqual(['*', '*', '*'])
    expect(Number(hour) * 60 + Number(minute)).toBeGreaterThan(14 * 60 + 30)
  })
})
