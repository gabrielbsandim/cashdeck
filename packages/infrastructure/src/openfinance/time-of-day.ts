import { toLocalDate } from '@cashdeck/domain'

// Banks that know only the date send midnight, in UTC or in Brazil.
const DATE_ONLY = new Set(['00:00:00.000', '03:00:00.000'])

export function timeOfDay(date: string): string | null {
  const instant = new Date(date)
  if (Number.isNaN(instant.getTime())) {
    return null
  }
  const iso = instant.toISOString()
  return DATE_ONLY.has(iso.slice(11, 23)) ? null : iso
}

// A statement that sends only the date is read within the hour, so the first
// read of a same-day entry stands in for its time; later reads keep that one.
export function seenToday(bookedOn: string, now: Date): string | null {
  return toLocalDate(now) === bookedOn ? now.toISOString() : null
}
