import { z } from 'zod'
import { entityKindSchema, isoDate, moneyViewSchema } from '@/dtos/common'

export const netWorthQuerySchema = z.object({
  entity: entityKindSchema.optional(),
  months: z.coerce.number().int().min(1).max(24).default(12),
})

export type NetWorthQuery = z.infer<typeof netWorthQuerySchema>

const compositionSchema = z.object({
  cash: moneyViewSchema,
  investments: moneyViewSchema,
  realEstate: moneyViewSchema,
  vehicles: moneyViewSchema,
  otherAssets: moneyViewSchema,
  cardDebt: moneyViewSchema,
  // What loans still owe, read from their schedules.
  loanDebt: moneyViewSchema,
  assets: moneyViewSchema,
  liabilities: moneyViewSchema,
  total: moneyViewSchema,
})

const changeSchema = z.object({
  amount: moneyViewSchema,
  percent: z.number().nullable(),
})

export const netWorthViewSchema = z.object({
  asOf: isoDate,
  current: compositionSchema,
  fromLastMonth: changeSchema,
  fromYearAgo: changeSchema,
  entities: z.array(
    z.object({ kind: entityKindSchema, current: compositionSchema }),
  ),
  // One point per month end, oldest first, then today.
  series: z.array(
    z.object({
      on: isoDate,
      assets: moneyViewSchema,
      liabilities: moneyViewSchema,
      total: moneyViewSchema,
    }),
  ),
})

export type NetWorthView = z.infer<typeof netWorthViewSchema>
