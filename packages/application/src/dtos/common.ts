import { z } from 'zod'
import { ENTITY_KINDS, type Money } from '@cashdeck/domain'

// The format alone lets 2026-13-01 or 2026-02-30 through, and those reach the
// database as an Invalid Date; a real day reads back unchanged.
function isCalendarDay(value: string): boolean {
  const instant = Date.parse(`${value}T00:00:00Z`)
  if (Number.isNaN(instant)) {
    return false
  }
  return new Date(instant).toISOString().slice(0, 10) === value
}

export const isoDate = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/, 'Expected YYYY-MM-DD')
  .refine(isCalendarDay, 'Expected a calendar day')

export const isoMonth = z.string().regex(/^\d{4}-\d{2}$/, 'Expected YYYY-MM')

export const entityKindSchema = z.enum(ENTITY_KINDS)

export const moneyViewSchema = z.object({
  cents: z.int(),
  currency: z.string().length(3),
})

export type MoneyView = z.infer<typeof moneyViewSchema>

export const money = (value: Money): MoneyView => value.toJSON()

export const uploadSchema = z.object({
  fileName: z.string().trim().min(1).max(200),
  mimeType: z.string().trim().min(1).max(100),
  base64: z.string().min(1),
})

export type Upload = z.infer<typeof uploadSchema>

export const pageQuerySchema = z.object({
  cursor: z.string().min(1).optional(),
  limit: z.coerce.number().int().min(1).max(100).default(50),
})
