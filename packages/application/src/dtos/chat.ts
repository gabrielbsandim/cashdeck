import { z } from 'zod'
import { entityKindSchema, moneyViewSchema, uploadSchema } from '@/dtos/common'
import {
  CHAT_ACTION_STATUSES,
  CHAT_ACTION_TOOLS,
  CHAT_NOTICES,
  CHAT_ROLES,
  CHAT_SCOPES,
} from '@/ports/chat'

export const chatScopeSchema = z.enum(CHAT_SCOPES)

export const createThreadSchema = z.object({
  scope: chatScopeSchema.default('ALL'),
})

export const threadViewSchema = z.object({
  id: z.string(),
  scope: chatScopeSchema,
  title: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
})

export type ThreadView = z.infer<typeof threadViewSchema>

const ATTACHMENT_TYPES =
  /^(image\/(jpeg|png|heic|heif|webp)|application\/pdf|audio\/(mpeg|mp4|m4a|x-m4a|aac|ogg|wav|x-wav|webm))$/

// Vercel caps a request body at 4.5 MB; 4 MB of base64 is 3 MB of files.
export const MAX_CHAT_UPLOAD_BASE64 = 4_000_000

export const chatUploadSchema = uploadSchema.extend({
  mimeType: z
    .string()
    .trim()
    .toLowerCase()
    .regex(ATTACHMENT_TYPES, 'Only images, PDF and audio can be attached.'),
})

export const sendMessageSchema = z
  .object({
    text: z.string().max(4000).default(''),
    attachments: z.array(chatUploadSchema).max(3).default([]),
  })
  .refine(
    input => input.text.trim().length > 0 || input.attachments.length > 0,
    { message: 'Send a text or an attachment.', path: ['text'] },
  )
  .refine(
    input =>
      input.attachments.reduce(
        (total, file) => total + file.base64.length,
        0,
      ) <= MAX_CHAT_UPLOAD_BASE64,
    { message: 'The attachments are larger than 3 MB.', path: ['attachments'] },
  )

export type SendMessageInput = z.infer<typeof sendMessageSchema>

export const chatAttachmentViewSchema = z.object({
  id: z.string(),
  fileName: z.string(),
  mimeType: z.string(),
  size: z.int(),
})

export const chatActionViewSchema = z.object({
  id: z.string(),
  threadId: z.string(),
  tool: z.enum(CHAT_ACTION_TOOLS),
  status: z.enum(CHAT_ACTION_STATUSES),
  entity: entityKindSchema.nullable(),
  needsEntity: z.boolean(),
  details: z.object({
    payee: z.string().nullable(),
    amount: moneyViewSchema.nullable(),
    dueDate: z.string().nullable(),
    fileName: z.string().nullable(),
    pattern: z.string().nullable(),
    category: z.string().nullable(),
    payer: z.string().nullable(),
  }),
  result: z
    .object({
      billId: z.string().nullable(),
      invoiceId: z.string().nullable(),
      ruleId: z.string().nullable(),
      updated: z.int().nullable(),
    })
    .nullable(),
  error: z.string().nullable(),
  createdAt: z.string(),
})

export type ChatActionView = z.infer<typeof chatActionViewSchema>

export const chatMessageViewSchema = z.object({
  id: z.string(),
  threadId: z.string(),
  role: z.enum(CHAT_ROLES),
  text: z.string(),
  notice: z.enum(CHAT_NOTICES).nullable(),
  attachments: z.array(chatAttachmentViewSchema),
  actions: z.array(chatActionViewSchema),
  createdAt: z.string(),
})

export type ChatMessageView = z.infer<typeof chatMessageViewSchema>

export const sendMessageResultSchema = z.object({
  messages: z.array(chatMessageViewSchema),
})

export const confirmActionSchema = z.object({
  entity: entityKindSchema.optional(),
})
