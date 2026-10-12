import { BUDGET_LEVELS } from '@cashdeck/domain'
import { z } from 'zod'
import { entityKindSchema, isoMonth, moneyViewSchema } from '@/dtos/common'

export const budgetMonthQuerySchema = z.object({
  entity: entityKindSchema.default('PF'),
  // The current month when left out.
  month: isoMonth.optional(),
})

export type BudgetMonthQuery = z.infer<typeof budgetMonthQuerySchema>

export const createBudgetSchema = z.object({
  entity: entityKindSchema.default('PF'),
  categoryId: z.string().min(1),
  month: isoMonth.optional(),
  limitCents: z.int().positive(),
  rollover: z.boolean().default(false),
})

export type CreateBudgetInput = z.infer<typeof createBudgetSchema>

export const updateBudgetSchema = z.object({
  limitCents: z.int().positive().optional(),
  rollover: z.boolean().optional(),
})

export type UpdateBudgetInput = z.infer<typeof updateBudgetSchema>

export const copyBudgetsSchema = z.object({
  entity: entityKindSchema.default('PF'),
  // The month copied from; its budgets land on the month after.
  month: isoMonth,
})

export type CopyBudgetsInput = z.infer<typeof copyBudgetsSchema>

export const acceptSuggestionsSchema = z.object({
  entity: entityKindSchema.default('PF'),
  month: isoMonth.optional(),
  items: z
    .array(
      z.object({
        categoryId: z.string().min(1),
        limitCents: z.int().positive(),
      }),
    )
    .min(1)
    .max(100),
})

export type AcceptSuggestionsInput = z.infer<typeof acceptSuggestionsSchema>

const categoryFields = {
  categoryId: z.string(),
  key: z.string().nullable(),
  name: z.string(),
  icon: z.string().nullable(),
}

const usageFields = {
  // The limit plus what a rollover carried.
  available: moneyViewSchema,
  spent: moneyViewSchema,
  // Negative past the limit.
  remaining: moneyViewSchema,
  percent: z.int().min(0),
  level: z.enum(BUDGET_LEVELS),
}

export const budgetItemSchema = z.object({
  id: z.string(),
  ...categoryFields,
  limit: moneyViewSchema,
  carried: moneyViewSchema,
  rollover: z.boolean(),
  ...usageFields,
})

export type BudgetItemView = z.infer<typeof budgetItemSchema>

export const budgetMonthSchema = z.object({
  month: isoMonth,
  entity: entityKindSchema,
  total: z.object(usageFields),
  // Highest share of the limit first.
  items: z.array(budgetItemSchema),
  // Spending in categories without a budget, largest first.
  unbudgeted: z.array(z.object({ ...categoryFields, spent: moneyViewSchema })),
})

export type BudgetMonthView = z.infer<typeof budgetMonthSchema>

export const budgetSuggestionsSchema = z.object({
  month: isoMonth,
  entity: entityKindSchema,
  // The complete months the suggestion reads, oldest first.
  basedOn: z.array(isoMonth),
  total: moneyViewSchema,
  items: z.array(
    z.object({
      ...categoryFields,
      months: z.array(moneyViewSchema),
      suggested: moneyViewSchema,
      // The limit the month already has for the category.
      current: moneyViewSchema.nullable(),
    }),
  ),
})

export type BudgetSuggestionsView = z.infer<typeof budgetSuggestionsSchema>
