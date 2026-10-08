import { z } from 'zod'
import {
  entityKindSchema,
  isoDate,
  moneyViewSchema,
  uploadSchema,
} from '@/dtos/common'

export const importStatementSchema = uploadSchema.extend({
  entity: entityKindSchema,
})

export const cardStatementViewSchema = z.object({
  id: z.string(),
  entityKind: entityKindSchema,
  card: z.string(),
  issuer: z.string(),
  closing: isoDate,
  due: isoDate,
  rate: z.int(),
  iofBps: z.int(),
  paymentCode: z.string().nullable(),
  lines: z.array(
    z.object({
      id: z.string(),
      merchant: z.string(),
      date: isoDate,
      amount: moneyViewSchema,
      needsReview: z.boolean(),
    }),
  ),
  billId: z.string().nullable(),
})

export type CardStatementView = z.infer<typeof cardStatementViewSchema>

export const statementBillSchema = z.object({
  lineIds: z.array(z.string().min(1)).min(1),
  paymentCode: z.string().trim().min(1).optional(),
  pixKey: z.string().trim().min(1).optional(),
})

export const statementBillViewSchema = z.object({
  billId: z.string(),
  foreign: moneyViewSchema,
  subtotal: moneyViewSchema,
  iof: moneyViewSchema,
  total: moneyViewSchema,
})

// What the AI returns when it reads a card statement.
export const statementReadingSchema = z.object({
  card: z.string().min(1),
  issuer: z.string().min(1),
  closing: isoDate,
  due: isoDate,
  currency: z.string().regex(/^[A-Z]{3}$/),
  rate: z.number().positive(),
  iofPercent: z.number().min(0),
  paymentCode: z.string().nullable(),
  lines: z.array(
    z.object({
      merchant: z.string().min(1),
      date: isoDate,
      amount: z.number(),
      uncertain: z.boolean(),
    }),
  ),
})
