import {
  addDays,
  type EntityKind,
  type FinancialEntity,
  localDate,
  type LocalDate,
  Money,
  toLocalDate,
  ValidationError,
} from '@cashdeck/domain'
import { NotFoundError } from '@/errors/errors'
import { type Invoice } from '@/ports/records'
import {
  type FinancialEntityRepository,
  type Page,
  type PageRequest,
} from '@/ports/repositories'

export async function requireEntity(
  entities: FinancialEntityRepository,
  tenantId: string,
  kind: EntityKind,
): Promise<FinancialEntity> {
  const entity = await entities.findByKind(tenantId, kind)
  if (!entity) {
    throw new NotFoundError('Entity')
  }
  return entity
}

export async function requireEntityById(
  entities: FinancialEntityRepository,
  tenantId: string,
  id: string,
): Promise<FinancialEntity> {
  const entity = await entities.findById(tenantId, id)
  if (!entity) {
    throw new NotFoundError('Entity')
  }
  return entity
}

export function required<T>(value: T | null, resource: string): T {
  if (value === null) {
    throw new NotFoundError(resource)
  }
  return value
}

export function monthOf(day: LocalDate): string {
  return day.slice(0, 7)
}

export function addMonths(month: string, months: number): string {
  const [year, value] = month.split('-').map(Number) as [number, number]
  return monthOf(localDate(year, value + months, 1))
}

export function firstDay(month: string): LocalDate {
  return `${month}-01`
}

export function lastDay(month: string): LocalDate {
  return addDays(firstDay(addMonths(month, 1)), -1)
}

// Brazil has had no daylight saving since 2019: a local day starts at 03:00 UTC.
export function startOfDay(day: LocalDate): Date {
  return new Date(`${day}T00:00:00.000-03:00`)
}

export function monthInstants(month: string): { from: Date; to: Date } {
  return {
    from: startOfDay(firstDay(month)),
    to: startOfDay(firstDay(addMonths(month, 1))),
  }
}

export function today(now: Date): LocalDate {
  return toLocalDate(now)
}

const MAX_UPLOAD_BYTES = 5 * 1024 * 1024

function fromBase64(base64: string): Uint8Array {
  try {
    return Uint8Array.from(atob(base64), char => char.charCodeAt(0))
  } catch {
    throw new ValidationError('The file is not valid base64.')
  }
}

export function decodeUpload(base64: string): Uint8Array {
  const bytes = fromBase64(base64)
  if (bytes.length === 0) {
    throw new ValidationError('The file is empty.')
  }
  if (bytes.length > MAX_UPLOAD_BYTES) {
    throw new ValidationError('The file is larger than 5 MB.')
  }
  return bytes
}

const PAGE_LIMIT = 100

export async function allPages<T>(
  load: (page: PageRequest) => Promise<Page<T>>,
): Promise<T[]> {
  const items: T[] = []
  let cursor: string | null = null
  do {
    const page = await load({ cursor, limit: PAGE_LIMIT })
    items.push(...page.items)
    cursor = page.nextCursor
  } while (cursor)
  return items
}

export function brlOf(invoice: Invoice): Money {
  if (invoice.amount.currency === 'BRL') {
    return invoice.amount
  }
  return Money.of(Math.round(invoice.amount.cents * (invoice.fxRate ?? 0)))
}
