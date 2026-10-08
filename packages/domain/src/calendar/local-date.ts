import { ValidationError } from '@/shared/domain-error'

export type LocalDate = string

export const DEFAULT_TIME_ZONE = 'America/Sao_Paulo'

const MS_PER_DAY = 86_400_000

function toUtc(date: LocalDate): number {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    throw new ValidationError(`"${date}" is not an ISO date.`)
  }
  return Date.parse(`${date}T00:00:00Z`)
}

function fromUtc(ms: number): LocalDate {
  return new Date(ms).toISOString().slice(0, 10)
}

export function toLocalDate(
  instant: Date,
  timeZone: string = DEFAULT_TIME_ZONE,
): LocalDate {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(instant)
}

export function addDays(date: LocalDate, days: number): LocalDate {
  return fromUtc(toUtc(date) + days * MS_PER_DAY)
}

export function daysBetween(from: LocalDate, to: LocalDate): number {
  return Math.round((toUtc(to) - toUtc(from)) / MS_PER_DAY)
}

export function weekday(date: LocalDate): number {
  return new Date(toUtc(date)).getUTCDay()
}

export function localDate(year: number, month: number, day: number): LocalDate {
  return fromUtc(Date.UTC(year, month - 1, day))
}
