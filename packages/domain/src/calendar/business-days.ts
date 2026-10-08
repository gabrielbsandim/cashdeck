import {
  addDays,
  localDate,
  type LocalDate,
  weekday,
} from '@/calendar/local-date'

const FIXED_HOLIDAYS = [
  '01-01',
  '04-21',
  '05-01',
  '09-07',
  '10-12',
  '11-02',
  '11-15',
  '11-20',
  '12-25',
]

const EASTER_OFFSETS = {
  carnivalMonday: -48,
  carnivalTuesday: -47,
  goodFriday: -2,
  corpusChristi: 60,
}

export function easterSunday(year: number): LocalDate {
  const a = year % 19
  const b = Math.floor(year / 100)
  const c = year % 100
  const d = Math.floor(b / 4)
  const e = b % 4
  const f = Math.floor((b + 8) / 25)
  const g = Math.floor((b - f + 1) / 3)
  const h = (19 * a + b - d - g + 15) % 30
  const i = Math.floor(c / 4)
  const k = c % 4
  const l = (32 + 2 * e + 2 * i - h - k) % 7
  const m = Math.floor((a + 11 * h + 22 * l) / 451)
  const month = Math.floor((h + l - 7 * m + 114) / 31)
  const day = ((h + l - 7 * m + 114) % 31) + 1
  return localDate(year, month, day)
}

const cache = new Map<number, ReadonlySet<LocalDate>>()

export function bankHolidays(year: number): ReadonlySet<LocalDate> {
  const cached = cache.get(year)
  if (cached) {
    return cached
  }
  const easter = easterSunday(year)
  const holidays = new Set<LocalDate>([
    ...FIXED_HOLIDAYS.map(monthDay => `${year}-${monthDay}`),
    ...Object.values(EASTER_OFFSETS).map(offset => addDays(easter, offset)),
  ])
  cache.set(year, holidays)
  return holidays
}

export function isBusinessDay(date: LocalDate): boolean {
  const day = weekday(date)
  if (day === 0 || day === 6) {
    return false
  }
  return !bankHolidays(Number(date.slice(0, 4))).has(date)
}

export function nextBusinessDay(date: LocalDate): LocalDate {
  let candidate = date
  while (!isBusinessDay(candidate)) {
    candidate = addDays(candidate, 1)
  }
  return candidate
}

export function addBusinessDays(date: LocalDate, days: number): LocalDate {
  let candidate = nextBusinessDay(date)
  for (let step = 0; step < days; step += 1) {
    candidate = nextBusinessDay(addDays(candidate, 1))
  }
  return candidate
}
