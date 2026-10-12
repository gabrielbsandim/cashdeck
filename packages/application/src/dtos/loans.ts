import { z } from 'zod'
import { AMORTIZATION_SYSTEMS } from '@cashdeck/domain'
import {
  entityKindSchema,
  isoDate,
  moneyViewSchema,
  uploadSchema,
} from '@/dtos/common'

export const importLoanSchema = uploadSchema.extend({
  entity: entityKindSchema.default('PF'),
})

export const prepaymentQuerySchema = z.object({
  amount: z.coerce.number().int().positive(),
})

export const loanInstallmentViewSchema = z.object({
  number: z.int(),
  dueOn: isoDate,
  total: moneyViewSchema,
  principal: moneyViewSchema,
  interest: moneyViewSchema,
  fees: moneyViewSchema,
})

const totalsSchema = z.object({
  count: z.int(),
  total: moneyViewSchema,
  interest: moneyViewSchema,
  principal: moneyViewSchema,
})

export const loanViewSchema = z.object({
  id: z.string(),
  entity: entityKindSchema,
  name: z.string(),
  lender: z.string(),
  contract: z.string(),
  system: z.enum(AMORTIZATION_SYSTEMS),
  indexer: z.string(),
  // Percent a year.
  effectiveRate: z.number(),
  cet: z.number(),
  principal: moneyViewSchema,
  propertyValue: moneyViewSchema.nullable(),
  signedOn: isoDate,
  termMonths: z.int(),
  paidCount: z.int(),
  // Owed after the last installment due, before the next one.
  balance: moneyViewSchema,
  lastDueOn: isoDate.nullable(),
  next: loanInstallmentViewSchema.nullable(),
  upcoming: z.array(loanInstallmentViewSchema),
  remaining: totalsSchema.extend({ fees: moneyViewSchema }),
  paid: totalsSchema.extend({ lateFees: moneyViewSchema }),
  importedAt: z.iso.datetime(),
})

export const loansViewSchema = z.object({ items: z.array(loanViewSchema) })

export const prepaymentViewSchema = z.object({
  amount: moneyViewSchema,
  interestSaved: moneyViewSchema,
  feesSaved: moneyViewSchema,
  monthsCut: z.int(),
  lastDueOn: isoDate.nullable(),
  balanceAfter: moneyViewSchema,
})

export type ImportLoanInput = z.infer<typeof importLoanSchema>
export type LoanView = z.infer<typeof loanViewSchema>
export type LoansView = z.infer<typeof loansViewSchema>
export type PrepaymentView = z.infer<typeof prepaymentViewSchema>
