import { z } from 'zod'
import { RAIL_IDS } from '@cashdeck/domain'
import { entityKindSchema, isoDate, uploadSchema } from '@/dtos/common'

export const RAIL_KINDS = [
  'PIX_API',
  'BOLETO_API',
  'TAX_API',
  'RESERVE_FUNDING',
  'BANK_APPROVAL',
  'ASSISTED',
] as const
export type RailKind = (typeof RAIL_KINDS)[number]

export const RAIL_STATUSES = [
  'ACTIVE',
  'NEEDS_AUTHORIZATION',
  'UNAVAILABLE',
  'ALWAYS',
] as const
export type RailViewStatus = (typeof RAIL_STATUSES)[number]

export const railViewSchema = z.object({
  id: z.string(),
  railId: z.enum(RAIL_IDS).nullable(),
  kind: z.enum(RAIL_KINDS),
  owner: entityKindSchema,
  step: z.int(),
  institution: z.string(),
  status: z.enum(RAIL_STATUSES),
  configurable: z.boolean(),
})

export type RailView = z.infer<typeof railViewSchema>

export const listRailsQuerySchema = z.object({ entity: entityKindSchema })

export const railCredentialsViewSchema = z.object({
  certificateName: z.string().nullable(),
  certificateValidUntil: isoDate.nullable(),
  apiKeyHint: z.string().nullable(),
  lastTestAt: z.string().nullable(),
})

export type RailCredentialsView = z.infer<typeof railCredentialsViewSchema>

export const saveRailCredentialsSchema = z
  .object({
    certificate: uploadSchema.optional(),
    privateKey: uploadSchema.optional(),
    certificateValidUntil: isoDate.optional(),
    apiKey: z.string().trim().min(4).max(500).optional(),
    clientId: z.string().trim().min(1).max(200).optional(),
    clientSecret: z.string().trim().min(1).max(500).optional(),
  })
  .refine(input => Object.values(input).some(value => value !== undefined), {
    message: 'Send at least one credential.',
  })

export const RAIL_CHECK_KINDS = [
  'CERTIFICATE',
  'API_KEY',
  'SCOPE',
  'PAYER_ACCOUNT',
] as const

export const railTestViewSchema = z.object({
  checks: z.array(
    z.object({
      kind: z.enum(RAIL_CHECK_KINDS),
      passed: z.boolean(),
      millis: z.int().nullable(),
    }),
  ),
  testedAt: z.string(),
})

export const automationViewSchema = z.object({
  pausedSince: z.string().nullable(),
  entities: z.array(
    z.object({
      entity: entityKindSchema,
      confirmAboveCents: z.int().nullable(),
      dailyCapCents: z.record(z.string(), z.int()),
    }),
  ),
})

export type AutomationView = z.infer<typeof automationViewSchema>

export const updateAutomationSchema = z.object({
  entity: entityKindSchema,
  confirmAboveCents: z.int().positive().nullable().optional(),
  dailyCapCents: z.partialRecord(z.enum(RAIL_IDS), z.int().min(0)).optional(),
})
