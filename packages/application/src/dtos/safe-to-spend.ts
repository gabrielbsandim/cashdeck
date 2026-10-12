import { z } from 'zod'
import { OBLIGATION_KINDS } from '@cashdeck/domain'
import { isoDate, moneyViewSchema } from '@/dtos/common'

export const SAFE_TO_SPEND_LINE_KINDS = [
  ...OBLIGATION_KINDS,
  'RESERVE',
] as const

export const safeToSpendViewSchema = z.object({
  asOf: isoDate,
  // The personal checking accounts, the reserve left out.
  cash: moneyViewSchema,
  reserve: moneyViewSchema,
  total: moneyViewSchema,
  daily: moneyViewSchema,
  days: z.int(),
  until: isoDate,
  income: z.object({ on: isoDate, amount: moneyViewSchema }).nullable(),
  shortBy: moneyViewSchema,
  // A deduction is negative; the share of the reserve covering bills is
  // positive. An empty label means the client names the line by its kind.
  lines: z.array(
    z.object({
      kind: z.enum(SAFE_TO_SPEND_LINE_KINDS),
      label: z.string(),
      amount: moneyViewSchema,
      on: isoDate.nullable(),
    }),
  ),
})

export type SafeToSpendView = z.infer<typeof safeToSpendViewSchema>
