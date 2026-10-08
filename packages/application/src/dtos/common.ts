import { z } from 'zod'
import { ENTITY_KINDS, type Money } from '@cashdeck/domain'

export const isoDate = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/, 'Expected YYYY-MM-DD')

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
