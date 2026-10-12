import { RULE_DIRECTIONS } from '@cashdeck/domain'
import { z } from 'zod'
import { entityKindSchema, isoDate, moneyViewSchema } from '@/dtos/common'

export const REVIEW_REASONS = [
  'UNCATEGORIZED',
  'LOW_CONFIDENCE',
  'INCONSISTENT',
] as const
export type ReviewReason = (typeof REVIEW_REASONS)[number]

const directionSchema = z.enum(RULE_DIRECTIONS)

export const categoryRuleViewSchema = z.object({
  id: z.string(),
  // Null applies to both entities.
  entityKind: entityKindSchema.nullable(),
  pattern: z.string(),
  counterparty: z.string().nullable(),
  direction: directionSchema.nullable(),
  categoryId: z.string(),
  priority: z.int(),
  createdAt: z.string(),
})

export type CategoryRuleView = z.infer<typeof categoryRuleViewSchema>

export const updateCategoryRuleSchema = z.object({
  pattern: z.string().trim().min(1).max(100).optional(),
  categoryId: z.string().min(1).optional(),
  direction: directionSchema.nullable().optional(),
})

export const categoryRuleUpdateResultSchema = z.object({
  rule: categoryRuleViewSchema,
  updated: z.int(),
})

export const reviewGroupViewSchema = z.object({
  id: z.string(),
  entityKind: entityKindSchema,
  merchant: z.string(),
  // The rule words; empty when the rule matches the payee document instead.
  pattern: z.string(),
  counterparty: z.string().nullable(),
  direction: directionSchema,
  count: z.int(),
  total: moneyViewSchema,
  reasons: z.array(z.enum(REVIEW_REASONS)),
  suggestedCategoryId: z.string().nullable(),
  confidence: z.number().min(0).max(1).nullable(),
  canCreateRule: z.boolean(),
  lastBookedOn: isoDate,
  transactionIds: z.array(z.string()),
})

export type ReviewGroupView = z.infer<typeof reviewGroupViewSchema>

export const ruleSuggestionViewSchema = z.object({
  id: z.string(),
  entityKind: entityKindSchema,
  merchant: z.string(),
  pattern: z.string(),
  counterparty: z.string().nullable(),
  direction: directionSchema,
  categoryId: z.string(),
  count: z.int(),
})

export type RuleSuggestionView = z.infer<typeof ruleSuggestionViewSchema>

export const reviewQueueViewSchema = z.object({
  // Transactions waiting across every group.
  pending: z.int(),
  groups: z.array(reviewGroupViewSchema),
  suggestions: z.array(ruleSuggestionViewSchema),
})

export type ReviewQueueView = z.infer<typeof reviewQueueViewSchema>

export const reviewQueueQuerySchema = z.object({
  entity: entityKindSchema.optional(),
})

export const categorizeGroupSchema = z.object({
  transactionIds: z.array(z.string().min(1)).min(1).max(500),
  categoryId: z.string().min(1),
  createRule: z.boolean().default(true),
})

export const categorizeGroupResultSchema = z.object({
  updated: z.int(),
  // Other transactions the new rule relabeled.
  similarUpdated: z.int(),
  rule: categoryRuleViewSchema.nullable(),
})

export type CategorizeGroupResult = z.infer<typeof categorizeGroupResultSchema>

export const ruleSuggestionDecisionSchema = z.object({
  id: z.string().min(1).max(400),
})
