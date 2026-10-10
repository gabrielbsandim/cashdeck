import { z } from 'zod'
import {
  ACCOUNT_ORIGINS,
  ACCOUNT_TYPES,
  CATEGORIZED_BY,
  TAX_REGIMES,
} from '@cashdeck/domain'
import {
  entityKindSchema,
  isoDate,
  isoMonth,
  moneyViewSchema,
  pageQuerySchema,
} from '@/dtos/common'
import { TRANSFER_KINDS } from '@/ports/records'

export const entityViewSchema = z.object({
  id: z.string(),
  kind: entityKindSchema,
  name: z.string(),
  taxId: z.string(),
  taxRegime: z.enum(TAX_REGIMES).nullable(),
})

export const updateEntitySchema = z.object({
  name: z.string().trim().min(1).max(120).optional(),
  taxId: z.string().trim().min(11).max(18).optional(),
  taxRegime: z.enum(TAX_REGIMES).nullable().optional(),
})

export const accountViewSchema = z.object({
  id: z.string(),
  entityKind: entityKindSchema,
  institution: z.string(),
  name: z.string(),
  type: z.enum(ACCOUNT_TYPES),
  origin: z.enum(ACCOUNT_ORIGINS),
  isReserve: z.boolean(),
  balance: moneyViewSchema,
  cdiPercent: z.int().nullable(),
  connectionId: z.string().nullable(),
  numberSuffix: z.string().nullable(),
  logo: z
    .object({ imageUrl: z.string(), color: z.string().nullable() })
    .nullable(),
  credit: z
    .object({
      limit: moneyViewSchema,
      available: moneyViewSchema,
      usedPercent: z.int().nullable(),
      closesOn: isoDate.nullable(),
      dueOn: isoDate.nullable(),
      brand: z.string().nullable(),
    })
    .nullable(),
  openBill: moneyViewSchema.nullable(),
  sync: z
    .object({ status: z.string(), lastSyncAt: z.string().nullable() })
    .nullable(),
})

export type AccountView = z.infer<typeof accountViewSchema>

export const listAccountsQuerySchema = z.object({
  entity: entityKindSchema.optional(),
})

export const createAccountSchema = z.object({
  entity: entityKindSchema,
  institution: z.string().trim().min(1).max(80),
  name: z.string().trim().min(1).max(80),
  type: z.enum(ACCOUNT_TYPES),
  currency: z
    .string()
    .regex(/^[A-Z]{3}$/)
    .default('BRL'),
  isReserve: z.boolean().default(false),
  balanceCents: z.int().default(0),
})

export const updateAccountSchema = z.object({
  name: z.string().trim().min(1).max(80).optional(),
  isReserve: z.boolean().optional(),
  cdiPercent: z.int().min(0).max(1000).nullable().optional(),
  balanceCents: z.int().optional(),
})

export const transactionViewSchema = z.object({
  id: z.string(),
  accountId: z.string(),
  entityKind: entityKindSchema,
  amount: moneyViewSchema,
  bookedOn: isoDate,
  description: z.string(),
  categoryId: z.string().nullable(),
  kind: z.enum(['INCOME', 'EXPENSE', 'TRANSFER']),
  transferId: z.string().nullable(),
  invoiceId: z.string().nullable(),
  note: z.string().nullable(),
  categorizedBy: z.enum(CATEGORIZED_BY).nullable(),
  categoryConfidence: z.number().min(0).max(1).nullable(),
  merchant: z.string().nullable(),
  installment: z
    .object({
      number: z.int(),
      count: z.int(),
      purchaseOn: isoDate.nullable(),
    })
    .nullable(),
  // Shown from the preview feed until the main provider confirms it.
  provisional: z.boolean(),
})

export type TransactionView = z.infer<typeof transactionViewSchema>

export const listTransactionsQuerySchema = pageQuerySchema.extend({
  entity: entityKindSchema.optional(),
  accountId: z.string().min(1).optional(),
  from: isoDate.optional(),
  to: isoDate.optional(),
  categoryId: z.string().min(1).optional(),
  uncategorized: z
    .enum(['true', 'false'])
    .transform(value => value === 'true')
    .optional(),
  search: z.string().trim().min(1).max(100).optional(),
})

export const updateTransactionSchema = z.object({
  categoryId: z.string().min(1).nullable().optional(),
  note: z.string().max(500).nullable().optional(),
  applyToSimilar: z.boolean().default(false),
})

export const updateTransactionResultSchema = z.object({
  transaction: transactionViewSchema,
  similarUpdated: z.int(),
})

export type UpdateTransactionResult = z.infer<
  typeof updateTransactionResultSchema
>

export const categoryViewSchema = z.object({
  id: z.string(),
  key: z.string().nullable(),
  name: z.string(),
  icon: z.string().nullable(),
  parentId: z.string().nullable(),
})

export type CategoryView = z.infer<typeof categoryViewSchema>

export const createCategoryRuleSchema = z.object({
  pattern: z.string().trim().min(1).max(100),
  categoryId: z.string().min(1),
  entity: entityKindSchema.nullable().default(null),
})

export const categoryRuleResultSchema = z.object({
  pattern: z.string(),
  categoryId: z.string(),
  updated: z.int(),
})

const transferPartySchema = z.object({
  owner: entityKindSchema,
  holder: z.string(),
  account: z.string(),
  accountId: z.string(),
})

export const transferViewSchema = z.object({
  id: z.string(),
  kind: z.enum(TRANSFER_KINDS),
  amount: moneyViewSchema,
  at: z.string(),
  rail: z.string(),
  from: transferPartySchema,
  to: transferPartySchema,
  document: z.string().nullable(),
  neutral: z.boolean(),
})

export type TransferView = z.infer<typeof transferViewSchema>

export const listTransfersQuerySchema = z.object({ month: isoMonth.optional() })

export const recordTransferSchema = z.object({
  kind: z.enum(TRANSFER_KINDS),
  amountCents: z.int().positive(),
  fromAccountId: z.string().min(1),
  toAccountId: z.string().min(1),
  at: z.iso.datetime().optional(),
  rail: z.string().trim().min(1).max(40).default('PIX'),
  document: z.string().trim().min(1).max(200).optional(),
})
