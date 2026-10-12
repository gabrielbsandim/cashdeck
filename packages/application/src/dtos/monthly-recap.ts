import { z } from 'zod'
import { entityKindSchema, isoMonth, moneyViewSchema } from '@/dtos/common'
import { DEVICE_LOCALES } from '@/ports/alerts'

export const RECAP_STORY_SOURCES = ['AI', 'TEMPLATE'] as const
export type RecapStorySource = (typeof RECAP_STORY_SOURCES)[number]

export const monthlyRecapQuerySchema = z.object({
  entity: entityKindSchema.optional(),
  // Defaults to the language of the device seen last.
  locale: z.enum(DEVICE_LOCALES).optional(),
})

export type MonthlyRecapQuery = z.infer<typeof monthlyRecapQuerySchema>

export const recapMonthSchema = isoMonth

const flowSchema = z.object({
  income: moneyViewSchema,
  expenses: moneyViewSchema,
  net: moneyViewSchema,
})

const changeSchema = z.object({
  amount: moneyViewSchema,
  percent: z.int().nullable(),
})

const categoryRefSchema = z.object({
  categoryId: z.string(),
  key: z.string().nullable(),
  name: z.string(),
  icon: z.string().nullable(),
})

const categoryShiftSchema = categoryRefSchema.extend({
  total: moneyViewSchema,
  previous: moneyViewSchema,
  change: changeSchema,
})

const subscriptionRefSchema = z.object({
  key: z.string(),
  name: z.string(),
  amount: moneyViewSchema,
})

export const monthlyRecapSchema = z.object({
  month: isoMonth,
  entity: entityKindSchema.nullable(),
  flow: flowSchema,
  previousFlow: flowSchema,
  incomeChange: changeSchema,
  expensesChange: changeSchema,
  savings: z.object({
    percent: z.int().nullable(),
    previousPercent: z.int().nullable(),
  }),
  topCategory: categoryRefSchema
    .extend({ total: moneyViewSchema, sharePercent: z.int() })
    .nullable(),
  changes: z.object({
    rose: z.array(categoryShiftSchema),
    fell: z.array(categoryShiftSchema),
  }),
  subscriptions: z.object({
    started: z.array(subscriptionRefSchema),
    stopped: z.array(subscriptionRefSchema),
  }),
  // Null when the month end is beyond the net worth history.
  netWorth: z
    .object({ total: moneyViewSchema, change: changeSchema })
    .nullable(),
  // The AI only phrases the figures above; a template stands in when it fails.
  story: z.object({
    text: z.string(),
    locale: z.enum(DEVICE_LOCALES),
    source: z.enum(RECAP_STORY_SOURCES),
  }),
  generatedAt: z.iso.datetime(),
})

export type MonthlyRecap = z.infer<typeof monthlyRecapSchema>

export type MonthlyRecapRun = { month: string; sent: boolean }
