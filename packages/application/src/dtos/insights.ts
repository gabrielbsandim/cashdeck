import { z } from 'zod'
import {
  entityKindSchema,
  isoDate,
  isoMonth,
  moneyViewSchema,
} from '@/dtos/common'

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

export const insightsScopeQuerySchema = z.object({
  entity: entityKindSchema.optional(),
})

export const installmentPlanViewSchema = z.object({
  key: z.string(),
  accountId: z.string(),
  card: z.string(),
  cardSuffix: z.string().nullable(),
  entityKind: entityKindSchema,
  name: z.string(),
  categoryId: z.string().nullable(),
  number: z.int(),
  count: z.int(),
  amount: moneyViewSchema,
  paid: moneyViewSchema,
  remaining: moneyViewSchema,
  total: moneyViewSchema,
  purchaseOn: isoDate.nullable(),
  lastBilledOn: isoDate,
  finalMonth: isoMonth,
  transactionIds: z.array(z.string()),
})

export const installmentsViewSchema = z.object({
  months: z.array(z.object({ month: isoMonth, total: moneyViewSchema })),
  plans: z.array(installmentPlanViewSchema),
})

export type InstallmentsView = z.infer<typeof installmentsViewSchema>

export const SUBSCRIPTION_MONTH_STATUSES = ['PAID', 'UPCOMING', 'LATE'] as const

export const subscriptionViewSchema = z.object({
  id: z.string().nullable(),
  key: z.string(),
  entityKind: entityKindSchema,
  name: z.string(),
  amount: moneyViewSchema,
  previousAmount: moneyViewSchema.nullable(),
  priceChanged: z.boolean(),
  dayOfMonth: z.int(),
  lastChargeOn: isoDate.nullable(),
  thisMonth: z.enum(SUBSCRIPTION_MONTH_STATUSES),
  accountId: z.string().nullable(),
  categoryId: z.string().nullable(),
  transactionIds: z.array(z.string()),
})

export type SubscriptionView = z.infer<typeof subscriptionViewSchema>

export const subscriptionsViewSchema = z.object({
  monthly: moneyViewSchema,
  yearly: moneyViewSchema,
  previousMonth: moneyViewSchema,
  changePercent: z.int().nullable(),
  items: z.array(subscriptionViewSchema),
  suggestions: z.array(subscriptionViewSchema),
})

export type SubscriptionsView = z.infer<typeof subscriptionsViewSchema>

export const subscriptionDecisionSchema = z.object({
  transactionId: z.string().min(1),
})
