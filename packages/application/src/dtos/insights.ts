import { z } from 'zod'
import { entityKindSchema, isoDate, moneyViewSchema } from '@/dtos/common'

export const INSIGHT_PERIODS = ['1w', '1m', '6m', '1y'] as const
export type InsightPeriod = (typeof INSIGHT_PERIODS)[number]

export const insightsOverviewQuerySchema = z.object({
  entity: entityKindSchema.optional(),
  period: z.enum(INSIGHT_PERIODS).default('1m'),
})

export type InsightsOverviewQuery = z.infer<typeof insightsOverviewQuerySchema>

const rangeSchema = z.object({ from: isoDate, to: isoDate })

const pointSchema = z.object({ day: isoDate, cumulative: moneyViewSchema })

export const insightsOverviewSchema = z.object({
  period: z.enum(INSIGHT_PERIODS),
  range: rangeSchema,
  previousRange: rangeSchema,
  spend: z.object({
    total: moneyViewSchema,
    // The previous period up to the same day, so the comparison is fair.
    previous: moneyViewSchema,
    changePercent: z.int().nullable(),
    series: z.array(pointSchema),
    previousSeries: z.array(pointSchema),
    topMerchants: z.array(
      z.object({ name: z.string(), total: moneyViewSchema, count: z.int() }),
    ),
  }),
  categories: z.object({
    total: moneyViewSchema,
    items: z.array(
      z.object({
        categoryId: z.string().nullable(),
        key: z.string().nullable(),
        name: z.string().nullable(),
        icon: z.string().nullable(),
        total: moneyViewSchema,
        sharePercent: z.int(),
        changePercent: z.int().nullable(),
      }),
    ),
  }),
  flow: z.object({
    income: moneyViewSchema,
    expenses: moneyViewSchema,
    result: moneyViewSchema,
  }),
  cards: z
    .object({
      bill: moneyViewSchema,
      dueOn: isoDate.nullable(),
      count: z.int(),
      limit: moneyViewSchema.nullable(),
      used: moneyViewSchema.nullable(),
      usedPercent: z.int().nullable(),
    })
    .nullable(),
  billsDue: z.object({
    days: z.int(),
    total: moneyViewSchema,
    count: z.int(),
  }),
})

export type InsightsOverview = z.infer<typeof insightsOverviewSchema>
