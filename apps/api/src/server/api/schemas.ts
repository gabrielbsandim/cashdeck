import { z } from 'zod'

export const payBillSchema = z.object({ confirmed: z.boolean().optional() })

export const markPaidSchema = z.object({
  attachmentId: z.string().min(1).optional(),
  proof: z.string().max(500).optional(),
})
