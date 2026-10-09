import { z } from 'zod'
import { isoDate, moneyViewSchema } from '@/dtos/common'
import { TRANSFER_KINDS } from '@/ports/records'

const syncSchema = z.object({
  accountCount: z.int(),
  syncedAt: z.string().nullable(),
})

const budgetSchema = z.object({
  category: z.string(),
  spent: moneyViewSchema,
  limit: moneyViewSchema,
})

export const personalSummarySchema = z.object({
  balance: moneyViewSchema,
  sync: syncSchema,
  reserve: z
    .object({
      accountId: z.string(),
      institution: z.string(),
      product: z.string(),
      balance: moneyViewSchema,
      monthYield: moneyViewSchema,
      coverDays: z.int(),
      cdiPercent: z.int().nullable(),
    })
    .nullable(),
  forecast: z.object({
    from: isoDate,
    balances: z.array(moneyViewSchema),
    floor: moneyViewSchema,
  }),
  budgets: z.array(budgetSchema),
  alerts: z.array(
    z.discriminatedUnion('type', [
      z.object({
        type: z.literal('ASSISTED_PAYMENT'),
        at: z.string(),
        billId: z.string(),
        payee: z.string(),
        reason: z.string(),
      }),
      z.object({
        type: z.literal('BUDGET_EXCEEDED'),
        at: z.string(),
        budget: budgetSchema,
      }),
    ]),
  ),
})

export type PersonalSummary = z.infer<typeof personalSummarySchema>

export const companySummarySchema = z.object({
  cash: moneyViewSchema,
  sync: syncSchema,
  billed: moneyViewSchema,
  invoiceCount: z.int(),
  dasEstimate: moneyViewSchema,
  dasDue: isoDate,
  inss: z.object({ estimate: moneyViewSchema, due: isoDate }).nullable(),
  annex: z.enum(['III', 'V']),
  drafts: z.array(
    z.object({
      id: z.string(),
      customer: z.string(),
      amount: moneyViewSchema,
      recurring: z.boolean(),
      issueOn: isoDate,
    }),
  ),
  unbilled: z.array(
    z.object({
      id: z.string(),
      payer: z.string(),
      amount: moneyViewSchema,
      receivedOn: isoDate,
    }),
  ),
})

export type CompanySummary = z.infer<typeof companySummarySchema>

export const consolidatedSummarySchema = z.object({
  personal: moneyViewSchema,
  company: moneyViewSchema,
  externalIn: moneyViewSchema,
  externalOut: moneyViewSchema,
  transfers: z.array(
    z.object({
      id: z.string(),
      kind: z.enum(TRANSFER_KINDS),
      amount: moneyViewSchema,
      on: isoDate,
    }),
  ),
})

export type ConsolidatedSummary = z.infer<typeof consolidatedSummarySchema>
