import { PIX_KEY_TYPES, type PixContact } from '@cashdeck/domain'
import { z } from 'zod'

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
