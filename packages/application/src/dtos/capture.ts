import { z } from 'zod'
import { entityKindSchema, uploadSchema } from '@/dtos/common'

export const captureSourcesViewSchema = z.object({
  mailboxes: z.array(
    z.object({
      id: z.string(),
      address: z.string(),
      owner: entityKindSchema,
      lastReadAt: z.string().nullable(),
      billsFound: z.int(),
      emailsScanned: z.int(),
    }),
  ),
  dda: z.array(
    z.object({
      owner: entityKindSchema,
      bank: z.string(),
      lastBatchAt: z.string().nullable(),
      boletos: z.int(),
      enabled: z.boolean(),
    }),
  ),
})

export type CaptureSourcesView = z.infer<typeof captureSourcesViewSchema>

export const captureFileSchema = uploadSchema.extend({
  entity: entityKindSchema,
})

export const fileReadingSchema = z.object({
  paymentCode: z.string(),
  pixCode: z.string(),
  payee: z.string(),
  amount: z.number(),
  dueDate: z.string(),
})

export const startMailboxSchema = z.object({ entity: entityKindSchema })

export const setDdaSchema = z.object({ enabled: z.boolean() })
