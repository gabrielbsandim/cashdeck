import { z } from 'zod'
import { moneyViewSchema } from '@/dtos/common'

export const attachmentViewSchema = z.object({
  id: z.string(),
  fileName: z.string(),
  mimeType: z.string(),
  bytes: z.int(),
})

export type AttachmentView = z.infer<typeof attachmentViewSchema>

export const receiptViewSchema = z.object({
  billId: z.string(),
  proof: z
    .object({
      rail: z.string(),
      amount: moneyViewSchema,
      paidAt: z.string(),
      payer: z.string(),
      receiver: z.string(),
      transactionId: z.string().nullable(),
      authentication: z.string().nullable(),
    })
    .nullable(),
  attachments: z.array(attachmentViewSchema),
})

export type ReceiptView = z.infer<typeof receiptViewSchema>
