import { z } from 'zod'
import { OBLIGATION_KINDS, PLAN_LINE_KINDS } from '@cashdeck/domain'
import { entityKindSchema, isoDate, moneyViewSchema } from '@/dtos/common'

export const SAFE_TO_SPEND_LINE_KINDS = [
  ...OBLIGATION_KINDS,
  ...PLAN_LINE_KINDS,
  'BUDGET',
  'RESERVE',
] as const

// MONTH starts from the typical income and lasts to the month end; CASH
// starts from the checking balance and lasts until the next income.
export const SAFE_TO_SPEND_BASES = ['MONTH', 'CASH'] as const

export const safeToSpendViewSchema = z.object({
  asOf: isoDate,
  entity: entityKindSchema,
  basis: z.enum(SAFE_TO_SPEND_BASES),
  // The entity's checking accounts, the reserve left out.
  cash: moneyViewSchema,
  reserve: moneyViewSchema,
  total: moneyViewSchema,
  daily: moneyViewSchema,
  days: z.int(),
  until: isoDate,
  income: z.object({ on: isoDate, amount: moneyViewSchema }).nullable(),
  // The monthly plan, on the MONTH basis only. The income is the larger of
  // the typical one and what already came in this month.
  plan: z
    .object({
      income: moneyViewSchema,
      typical: moneyViewSchema,
      received: moneyViewSchema,
      savings: moneyViewSchema,
      // False while the target is what a typical month leaves over.
      savingsSet: z.boolean(),
      months: z.int(),
      // Payers chosen as income; none means every credit not own money.
      sources: z.int(),
    })
    .nullable(),
  shortBy: moneyViewSchema,
  // What checking and the reserve miss of what falls due in the next 30 days.
  cashShortBy: moneyViewSchema,
  // A deduction is negative; the share of the reserve covering bills is
  // positive. An empty label means the client names the line by its kind; a
  // BUDGET line names the category and keeps what its budget still allows.
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

const savingsSchema = z
  .object({ cents: z.int().min(0), currency: z.literal('BRL') })
  .nullable()

export const incomeSourceSchema = z.object({
  taxId: z.string().regex(/^(\d{11}|\d{14})$/, 'Expected CPF or CNPJ digits'),
  name: z.string().trim().min(1).max(120),
})

export type IncomeSource = z.infer<typeof incomeSourceSchema>

const incomeSourcesSchema = z.array(incomeSourceSchema).max(20)

// A field left out keeps what is stored.
export const spendingPlanInputSchema = z.object({
  savings: savingsSchema.optional(),
  incomeSources: incomeSourcesSchema.optional(),
})

export type SpendingPlanInput = z.infer<typeof spendingPlanInputSchema>

export const spendingPlanViewSchema = z.object({
  savings: savingsSchema,
  incomeSources: incomeSourcesSchema,
})

export type SpendingPlanView = z.infer<typeof spendingPlanViewSchema>

export const incomeSourcesViewSchema = z.object({
  items: z.array(
    incomeSourceSchema.extend({
      // Sent over the last six months, in how many of them, and last when.
      total: moneyViewSchema,
      months: z.int(),
      lastOn: isoDate,
      selected: z.boolean(),
    }),
  ),
})

export type IncomeSourcesView = z.infer<typeof incomeSourcesViewSchema>
