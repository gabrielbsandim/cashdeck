import { z } from 'zod'
import {
  BILL_KINDS,
  BILL_SOURCES,
  BILL_STATUSES,
  ENTITY_KINDS,
  PAYMENT_METHODS,
  RAIL_IDS,
  STEP_MODES,
  type Bill,
  type EntityKind,
  type PaymentAttempt,
  type PaymentPlan,
} from '@cashdeck/domain'

const isoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Expected YYYY-MM-DD')

export const captureBillSchema = z
  .object({
    entityId: z.string().min(1),
    source: z.enum(BILL_SOURCES).default('MANUAL'),
    paymentCode: z.string().trim().min(1).optional(),
    pixCode: z.string().trim().min(1).optional(),
    pixKey: z.string().trim().min(1).optional(),
    darfWithoutBarcode: z.boolean().optional(),
    amountCents: z.int().positive().optional(),
    dueDate: isoDate.optional(),
    payee: z.string().trim().max(120).optional(),
  })
  .refine(
    input =>
      [
        input.paymentCode ?? input.pixCode,
        input.pixKey,
        input.darfWithoutBarcode,
      ].filter(Boolean).length === 1,
    {
      message:
        'Send a paymentCode (with an optional pixCode), a pixCode, a pixKey or darfWithoutBarcode.',
    },
  )

export type CaptureBillInput = z.infer<typeof captureBillSchema>

export const listBillsQuerySchema = z.object({
  entityId: z.string().min(1).optional(),
  status: z.enum(BILL_STATUSES).optional(),
  cursor: z.string().min(1).optional(),
  limit: z.coerce.number().int().min(1).max(100).default(50),
})

export const moneyViewSchema = z.object({
  cents: z.int(),
  currency: z.string().length(3),
})

export const billViewSchema = z.object({
  id: z.string(),
  entityId: z.string(),
  entityKind: z.enum(ENTITY_KINDS),
  kind: z.enum(BILL_KINDS),
  status: z.enum(BILL_STATUSES),
  source: z.enum(BILL_SOURCES),
  payee: z.string().nullable(),
  amount: moneyViewSchema,
  dueDate: isoDate,
  code: z.string().nullable(),
  pixCode: z.string().nullable(),
  createdAt: z.string(),
  paidAt: z.string().nullable(),
  paidBy: z.enum(['RAIL', 'USER']).nullable(),
})

export type BillView = z.infer<typeof billViewSchema>

export const paymentStepViewSchema = z.object({
  mode: z.enum(STEP_MODES),
  rail: z.enum(RAIL_IDS),
  method: z.enum(PAYMENT_METHODS),
})

export const paymentAttemptViewSchema = z.object({
  id: z.string(),
  stepIndex: z.int(),
  rail: z.enum(RAIL_IDS),
  mode: z.enum(STEP_MODES),
  method: z.enum(PAYMENT_METHODS),
  amount: moneyViewSchema,
  outcome: z.enum([
    'PAID',
    'SUBMITTED',
    'PENDING_APPROVAL',
    'ASSISTED',
    'FAILED',
  ]),
  reason: z.string().nullable(),
  externalId: z.string().nullable(),
  at: z.string(),
})

export const billDetailViewSchema = billViewSchema.extend({
  plan: z
    .object({ steps: z.array(paymentStepViewSchema), currentStep: z.int() })
    .nullable(),
  attempts: z.array(paymentAttemptViewSchema),
})

export type BillDetailView = z.infer<typeof billDetailViewSchema>

export function toBillView(bill: Bill, entityKind: EntityKind): BillView {
  return {
    id: bill.id,
    entityId: bill.entityId,
    entityKind,
    kind: bill.kind,
    status: bill.status,
    source: bill.source,
    payee: bill.payee,
    amount: bill.amount.toJSON(),
    dueDate: bill.dueDate,
    code: bill.code,
    pixCode: bill.pixCode,
    createdAt: bill.createdAt.toISOString(),
    paidAt: bill.paidAt?.toISOString() ?? null,
    paidBy: bill.paidBy,
  }
}

export function toBillDetailView(
  bill: Bill,
  entityKind: EntityKind,
  plan: PaymentPlan | null,
  attempts: PaymentAttempt[],
): BillDetailView {
  return {
    ...toBillView(bill, entityKind),
    plan: plan && { steps: [...plan.steps], currentStep: plan.currentStep },
    attempts: attempts.map(attempt => ({
      id: attempt.id,
      stepIndex: attempt.stepIndex,
      rail: attempt.rail,
      mode: attempt.mode,
      method: attempt.method,
      amount: attempt.amount.toJSON(),
      outcome: attempt.outcome,
      reason: attempt.reason,
      externalId: attempt.externalId,
      at: attempt.at.toISOString(),
    })),
  }
}
