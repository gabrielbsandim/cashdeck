import { PIX_KEY_TYPES, type PixContact } from '@cashdeck/domain'
import { z } from 'zod'
import { entityKindSchema } from '@/dtos/common'

export const pixKeyTypeSchema = z.enum(PIX_KEY_TYPES)

export const createPixContactSchema = z.object({
  name: z.string().trim().min(1).max(80),
  pixKey: z.string().trim().min(1).max(120),
  pixKeyType: pixKeyTypeSchema.optional(),
  handle: z.string().trim().min(1).max(31).optional(),
})

export type CreatePixContactInput = z.infer<typeof createPixContactSchema>

export const updatePixContactSchema = createPixContactSchema.partial()

export type UpdatePixContactInput = z.infer<typeof updatePixContactSchema>

export const pixContactQuerySchema = z.object({
  search: z.string().trim().max(80).optional(),
})

export const pixContactViewSchema = z.object({
  id: z.string(),
  name: z.string(),
  handle: z.string(),
  pixKey: z.string(),
  pixKeyType: pixKeyTypeSchema,
  timesPaid: z.int(),
  lastPaidAt: z.string().nullable(),
  createdAt: z.string(),
})

export type PixContactView = z.infer<typeof pixContactViewSchema>

export const toPixContactView = (contact: PixContact): PixContactView => ({
  id: contact.id,
  name: contact.name,
  handle: contact.handle,
  pixKey: contact.pixKey,
  pixKeyType: contact.pixKeyType,
  timesPaid: contact.timesPaid,
  lastPaidAt: contact.lastPaidAt?.toISOString() ?? null,
  createdAt: contact.createdAt.toISOString(),
})

const recipientFields = {
  contactId: z.string().min(1).optional(),
  name: createPixContactSchema.shape.name.optional(),
  pixKey: createPixContactSchema.shape.pixKey.optional(),
  pixKeyType: pixKeyTypeSchema.optional(),
  entity: entityKindSchema,
}

const namesSomeone = (input: {
  contactId?: string
  name?: string
  pixKey?: string
}) => Boolean(input.contactId ?? (input.name && input.pixKey))

const SOMEONE = { message: 'Choose a contact, or give a name and a Pix key.' }

export const previewPixSchema = z
  .object(recipientFields)
  .refine(namesSomeone, SOMEONE)

export type PreviewPixInput = z.infer<typeof previewPixSchema>

export const sendPixSchema = z
  .object({
    ...recipientFields,
    amountCents: z.int().positive().max(100_000_000),
  })
  .refine(namesSomeone, SOMEONE)

export type SendPixInput = z.infer<typeof sendPixSchema>

export const pixPreviewViewSchema = z.object({
  contact: z.object({
    id: z.string().nullable(),
    name: z.string(),
    handle: z.string(),
    pixKey: z.string(),
    pixKeyType: pixKeyTypeSchema,
    isNew: z.boolean(),
  }),
  recipient: z.object({
    name: z.string(),
    taxId: z.string().nullable(),
    bank: z.string().nullable(),
    verified: z.boolean(),
  }),
})

export type PixPreviewView = z.infer<typeof pixPreviewViewSchema>
