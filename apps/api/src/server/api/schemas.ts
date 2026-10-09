import { z } from 'zod'

export const payBillSchema = z.object({ confirmed: z.boolean().optional() })

export const autoDebitSchema = z.object({ enabled: z.boolean() })

export const markPaidSchema = z.object({
  attachmentId: z.string().min(1).optional(),
  proof: z.string().max(500).optional(),
})
