import { BILL_PAYMENTS } from '@cashdeck/domain'
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

const subscriptionChargeSchema = z.object({
  transactionId: z.string(),
  bookedOn: isoDate,
  amount: moneyViewSchema,
})

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
  nextChargeOn: isoDate,
  thisMonth: z.enum(SUBSCRIPTION_MONTH_STATUSES),
  accountId: z.string().nullable(),
  categoryId: z.string().nullable(),
  transactionIds: z.array(z.string()),
  // Newest first, within the history the detector reads.
  charges: z.array(subscriptionChargeSchema),
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

export const monthlyInsightsQuerySchema = z.object({
  entity: entityKindSchema.optional(),
  month: isoMonth.optional(),
  months: z.coerce
    .number()
    .pipe(z.union([z.literal(6), z.literal(12)]))
    .default(6),
})

export type MonthlyInsightsQuery = z.infer<typeof monthlyInsightsQuerySchema>

const categoryChangeSchema = z.object({
  categoryId: z.string(),
  key: z.string().nullable(),
  name: z.string(),
  icon: z.string().nullable(),
  total: moneyViewSchema,
  average: moneyViewSchema,
  delta: moneyViewSchema,
})

const toneSchema = z.enum(['POSITIVE', 'NEGATIVE', 'NEUTRAL'])

export const insightSchema = z.discriminatedUnion('type', [
  z.object({
    type: z.literal('CATEGORY_ABOVE_AVERAGE'),
    tone: toneSchema,
    categoryId: z.string(),
    name: z.string(),
    percent: z.int(),
    amount: moneyViewSchema,
  }),
  z.object({
    type: z.literal('INSTALLMENTS_COMMITTED'),
    tone: toneSchema,
    month: isoMonth,
    amount: moneyViewSchema,
  }),
  z.object({
    type: z.literal('SAVINGS_RATE'),
    tone: toneSchema,
    percent: z.int(),
    averagePercent: z.int(),
  }),
  z.object({
    type: z.literal('SUBSCRIPTION_PRICE_UP'),
    tone: toneSchema,
    name: z.string(),
    amount: moneyViewSchema,
    previousAmount: moneyViewSchema,
  }),
])

export type Insight = z.infer<typeof insightSchema>

export const monthlyInsightsSchema = z.object({
  month: isoMonth,
  months: z.array(
    z.object({
      month: isoMonth,
      income: moneyViewSchema,
      expenses: moneyViewSchema,
      result: moneyViewSchema,
    }),
  ),
  savings: z.object({
    percent: z.int().nullable(),
    averagePercent: z.int().nullable(),
    trend: z.array(z.object({ month: isoMonth, percent: z.int().nullable() })),
  }),
  changes: z.object({
    rose: z.array(categoryChangeSchema),
    fell: z.array(categoryChangeSchema),
  }),
  fixedCost: z.object({
    subscriptions: moneyViewSchema,
    installments: moneyViewSchema,
    bills: moneyViewSchema,
    total: moneyViewSchema,
    income: moneyViewSchema,
    sharePercent: z.int().nullable(),
  }),
  leftThisMonth: z
    .object({
      balance: moneyViewSchema,
      billsDue: moneyViewSchema,
      cardBill: moneyViewSchema,
      left: moneyViewSchema,
    })
    .nullable(),
  companyToPersonal: z
    .object({ transfers: moneyViewSchema, taxes: moneyViewSchema })
    .nullable(),
  insights: z.array(insightSchema),
})

export type MonthlyInsights = z.infer<typeof monthlyInsightsSchema>

export const CARD_BILL_STATES = ['OPEN', 'CLOSED', 'PAST'] as const
export type CardBillState = (typeof CARD_BILL_STATES)[number]

export const cardBillViewSchema = z.object({
  closesOn: isoDate.nullable(),
  dueOn: isoDate,
  total: moneyViewSchema,
  minimum: moneyViewSchema.nullable(),
  state: z.enum(CARD_BILL_STATES),
  // The booking days whose charges this bill holds, for the list of charges.
  range: rangeSchema,
})

export const cardBillsViewSchema = z.object({
  cards: z.array(
    z.object({
      accountId: z.string(),
      name: z.string(),
      suffix: z.string().nullable(),
      entityKind: entityKindSchema,
      // Newest first; the open bill leads when the issuer reports its dates.
      bills: z.array(cardBillViewSchema),
    }),
  ),
})

export type CardBillsView = z.infer<typeof cardBillsViewSchema>

export const CARD_TIMELINE_STATES = [...CARD_BILL_STATES, 'FORECAST'] as const
export type CardTimelineState = (typeof CARD_TIMELINE_STATES)[number]

export const cardTimelineViewSchema = z.object({
  accountId: z.string(),
  name: z.string(),
  suffix: z.string().nullable(),
  entityKind: entityKindSchema,
  // Oldest first, so moving forward through the list moves ahead in time.
  bills: z.array(
    cardBillViewSchema.extend({
      state: z.enum(CARD_TIMELINE_STATES),
      // Whether a closed bill was paid; null on the open and forecast ones.
      payment: z.enum(BILL_PAYMENTS).nullable(),
      // The installments a forecast bill will carry that are not posted yet.
      installments: z.array(
        z.object({
          key: z.string(),
          name: z.string(),
          categoryId: z.string().nullable(),
          number: z.int(),
          count: z.int(),
          amount: moneyViewSchema,
        }),
      ),
    }),
  ),
  // The bill to show first: the open one, else the latest.
  current: z.int().nullable(),
})

export type CardTimelineView = z.infer<typeof cardTimelineViewSchema>
