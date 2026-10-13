import { z } from 'zod'
import {
  MILESTONE_METRICS,
  PLAN_GOAL_KINDS,
  PLAN_PAYMENTS,
  PLAN_STATUSES,
} from '@cashdeck/domain'
import { isoMonth, moneyViewSchema } from '@/dtos/common'

const nameSchema = z.string().trim().min(1).max(60)
const iconSchema = z.string().trim().min(1).max(40).nullable().default(null)

// Amounts in cents and in today's money.
const purchaseSchema = z
  .object({
    kind: z.literal('PURCHASE'),
    name: nameSchema,
    icon: iconSchema,
    price: z.int().positive(),
    tradeIn: z.int().min(0).default(0),
    // An asset sold to pay for it; its value less its loan replaces tradeIn.
    tradeInAssetId: z.string().min(1).nullable().default(null),
    financed: z.int().min(0).default(0),
    monthlyCost: z.int().default(0),
    keepsValue: z.boolean().default(false),
    // On the card the cash leaves with the next bills, one per installment.
    payment: z.enum(PLAN_PAYMENTS).default('CASH'),
    installments: z.int().min(1).max(24).default(1),
    // The caixinha that saves for it.
    goalId: z.string().min(1).nullable().default(null),
    notBefore: isoMonth.nullable().default(null),
    by: isoMonth.nullable().default(null),
  })
  .refine(
    input =>
      input.notBefore === null ||
      input.by === null ||
      input.notBefore <= input.by,
    { message: 'notBefore must not come after by.', path: ['by'] },
  )

const yearlySchema = z.object({
  kind: z.literal('YEARLY'),
  name: nameSchema,
  icon: iconSchema,
  yearly: z.int().positive(),
})

const milestoneSchema = z.object({
  kind: z.literal('MILESTONE'),
  name: nameSchema,
  icon: iconSchema,
  metric: z.enum(MILESTONE_METRICS),
  target: z.int().positive(),
  by: isoMonth.nullable().default(null),
})

export const planGoalInputSchema = z.discriminatedUnion('kind', [
  purchaseSchema,
  yearlySchema,
  milestoneSchema,
])

export type PlanGoalInput = z.infer<typeof planGoalInputSchema>

export const planOrderSchema = z.object({
  ids: z.array(z.string().min(1)).max(100),
})

export type PlanOrderInput = z.infer<typeof planOrderSchema>

export const planSettingsSchema = z.object({
  // Months of spending kept aside before anything is bought.
  reserveMonths: z.int().min(0).max(24),
  // Real yield a year, in percent: above inflation, after tax.
  yearlyYield: z.number().min(0).max(20),
  // Percent of the savings a month's purchases must leave invested.
  keepInvested: z.int().min(0).max(100).default(0),
  // Null follows the savings target of the monthly plan.
  monthlySavings: z.int().min(0).nullable(),
})

export type PlanSettings = z.infer<typeof planSettingsSchema>

const delayViewSchema = z.object({
  milestoneId: z.string(),
  name: z.string(),
  // Null when the goal keeps the milestone out of reach.
  months: z.int().nullable(),
})

// One shape for every kind; the fields of the other kinds come back null.
export const planGoalViewSchema = z.object({
  id: z.string(),
  kind: z.enum(PLAN_GOAL_KINDS),
  name: z.string(),
  icon: z.string().nullable(),
  status: z.enum(PLAN_STATUSES),
  // When it happens or is reached.
  month: isoMonth.nullable(),
  // What leaves savings: once for a purchase, every month for a yearly goal.
  cash: moneyViewSchema,
  delays: z.array(delayViewSchema),
  price: moneyViewSchema.nullable(),
  tradeIn: moneyViewSchema.nullable(),
  tradeInAssetId: z.string().nullable(),
  tradeInAssetName: z.string().nullable(),
  financed: moneyViewSchema.nullable(),
  monthlyCost: moneyViewSchema.nullable(),
  keepsValue: z.boolean().nullable(),
  payment: z.enum(PLAN_PAYMENTS).nullable(),
  installments: z.int().nullable(),
  // Null once the caixinha is archived or deleted.
  goalId: z.string().nullable(),
  notBefore: isoMonth.nullable(),
  by: isoMonth.nullable(),
  yearly: moneyViewSchema.nullable(),
  metric: z.enum(MILESTONE_METRICS).nullable(),
  target: moneyViewSchema.nullable(),
  // Where a milestone stands today.
  current: moneyViewSchema.nullable(),
})

export type PlanGoalView = z.infer<typeof planGoalViewSchema>

export const planViewSchema = z.object({
  asOf: isoMonth,
  monthlySavings: moneyViewSchema,
  savingsFromBudget: z.boolean(),
  monthlySpending: moneyViewSchema,
  reserveMonths: z.int(),
  reserve: moneyViewSchema,
  yearlyYield: z.number(),
  keepInvested: z.int(),
  netWorth: moneyViewSchema,
  invested: moneyViewSchema,
  yearlyProvision: moneyViewSchema,
  // The savings left once the yearly goals take their share.
  free: moneyViewSchema,
  goals: z.array(planGoalViewSchema),
  timeline: z.array(
    z.object({
      month: isoMonth,
      netWorth: moneyViewSchema,
      invested: moneyViewSchema,
    }),
  ),
})

export type PlanView = z.infer<typeof planViewSchema>

export const planAdviceInputSchema = z.object({
  // The goal to place among the others; the whole plan when null.
  goalId: z.string().min(1).nullable().default(null),
})

export type PlanAdviceInput = z.infer<typeof planAdviceInputSchema>

export const planAdviceGoalSchema = z.object({
  id: z.string(),
  kind: z.enum(PLAN_GOAL_KINDS),
  name: z.string(),
  // The wait the advice sets; always null for a goal that is not a purchase.
  notBefore: isoMonth.nullable(),
  reason: z.string().nullable(),
  month: isoMonth.nullable(),
  status: z.enum(PLAN_STATUSES),
  // Where the goal lands once the advice is applied.
  proposedMonth: isoMonth.nullable(),
  proposedStatus: z.enum(PLAN_STATUSES),
})

// The goals come in the order the advice proposes.
export const planAdviceSchema = z.object({
  goalId: z.string().nullable(),
  summary: z.string(),
  goals: z.array(planAdviceGoalSchema),
})

export type PlanAdvice = z.infer<typeof planAdviceSchema>

export const planArrangementSchema = z.object({
  goals: z
    .array(
      z.object({
        id: z.string().min(1),
        notBefore: isoMonth.nullable(),
      }),
    )
    .max(100),
})

export type PlanArrangement = z.infer<typeof planArrangementSchema>
