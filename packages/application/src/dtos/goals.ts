import {
  GOAL_NAME_MAX,
  GOAL_SOURCES,
  GOAL_STATUSES,
  type GoalContribution,
} from '@cashdeck/domain'
import { z } from 'zod'
import {
  entityKindSchema,
  isoDate,
  money,
  moneyViewSchema,
} from '@/dtos/common'

const tagSchema = z.string().trim().min(1).max(40)

export const goalQuerySchema = z.object({
  entity: entityKindSchema.optional(),
  archived: z.enum(['true', 'false']).optional(),
})

export type GoalQuery = z.infer<typeof goalQuerySchema>

const goalFields = {
  name: z.string().trim().min(1).max(GOAL_NAME_MAX),
  targetCents: z.int().positive(),
  deadline: isoDate.nullable().optional(),
  // A goal follows one account or one investment, or neither and adds up
  // what the user puts in by hand.
  accountId: z.string().min(1).nullable().optional(),
  investmentId: z.string().min(1).nullable().optional(),
  icon: tagSchema.nullable().optional(),
  color: tagSchema.nullable().optional(),
}

export const createGoalSchema = z.object({
  entity: entityKindSchema.default('PF'),
  ...goalFields,
  // What is already saved, as the first contribution of a manual goal.
  initialCents: z.int().positive().optional(),
})

export type CreateGoalInput = z.infer<typeof createGoalSchema>

export const updateGoalSchema = z
  .object(goalFields)
  .partial()
  .extend({ archived: z.boolean().optional() })

export type UpdateGoalInput = z.infer<typeof updateGoalSchema>

export const contributionInputSchema = z.object({
  amountCents: z
    .int()
    .refine(value => value !== 0, 'A contribution needs an amount'),
  on: isoDate.optional(),
  note: tagSchema.nullable().optional(),
})

export type ContributionInput = z.infer<typeof contributionInputSchema>

export const contributionViewSchema = z.object({
  id: z.string(),
  amount: moneyViewSchema,
  on: isoDate,
  note: z.string().nullable(),
  createdAt: z.string(),
})

export type ContributionView = z.infer<typeof contributionViewSchema>

export const goalViewSchema = z.object({
  id: z.string(),
  entity: entityKindSchema,
  name: z.string(),
  icon: z.string().nullable(),
  color: z.string().nullable(),
  target: moneyViewSchema,
  saved: moneyViewSchema,
  remaining: moneyViewSchema,
  percent: z.int().min(0).max(100),
  status: z.enum(GOAL_STATUSES),
  deadline: isoDate.nullable(),
  // What each month still needs to meet the deadline.
  requiredMonthly: moneyViewSchema.nullable(),
  // Saved per month lately; null while the goal is too new to tell.
  monthlyPace: moneyViewSchema.nullable(),
  projectedOn: isoDate.nullable(),
  source: z.enum(GOAL_SOURCES),
  accountId: z.string().nullable(),
  investmentId: z.string().nullable(),
  // The account or investment the goal follows.
  linkedName: z.string().nullable(),
  createdAt: z.string(),
  archivedAt: z.string().nullable(),
})

export type GoalView = z.infer<typeof goalViewSchema>

export const goalDetailSchema = goalViewSchema.extend({
  contributions: z.array(contributionViewSchema),
})

export type GoalDetail = z.infer<typeof goalDetailSchema>

export const toContributionView = (
  contribution: GoalContribution,
): ContributionView => ({
  id: contribution.id,
  amount: money(contribution.amount),
  on: contribution.on,
  note: contribution.note,
  createdAt: contribution.createdAt.toISOString(),
})
