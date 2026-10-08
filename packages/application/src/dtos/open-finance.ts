import { z } from 'zod'
import { entityKindSchema, isoDate, moneyViewSchema } from '@/dtos/common'

const itemId = z
  .string()
  .trim()
  .toLowerCase()
  .regex(
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
    'Expected an item id (UUID).',
  )

export const lookupItemSchema = z.object({ itemId })

export const connectItemSchema = z.object({
  itemId,
  entity: entityKindSchema,
  accountIds: z.array(z.string().min(1)).min(1),
})

export const itemLookupViewSchema = z.discriminatedUnion('status', [
  z.object({
    status: z.literal('FOUND'),
    institution: z.string(),
    consentUntil: isoDate.nullable(),
    accounts: z.array(
      z.object({ id: z.string(), name: z.string(), balance: moneyViewSchema }),
    ),
  }),
  z.object({ status: z.literal('NOT_FOUND') }),
  z.object({ status: z.literal('ALREADY_CONNECTED'), owner: entityKindSchema }),
])

export type ItemLookupView = z.infer<typeof itemLookupViewSchema>

export const connectionViewSchema = z.object({
  id: z.string(),
  itemId: z.string(),
  institution: z.string(),
  entityKind: entityKindSchema,
  status: z.string(),
  lastSyncAt: z.string().nullable(),
  accountCount: z.int(),
})

export type ConnectionView = z.infer<typeof connectionViewSchema>

export const syncResultSchema = z.object({
  accounts: z.int(),
  transactions: z.int(),
  syncedAt: z.string(),
})
