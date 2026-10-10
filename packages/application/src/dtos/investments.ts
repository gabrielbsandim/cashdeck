import { z } from 'zod'
import { entityKindSchema, isoDate, moneyViewSchema } from '@/dtos/common'
import { INVESTMENT_KINDS } from '@/ports/investments'

const logoViewSchema = z
  .object({ imageUrl: z.string(), color: z.string().nullable() })
  .nullable()

export const investmentPositionViewSchema = z.object({
  id: z.string(),
  entityKind: entityKindSchema,
  institutionId: z.string(),
  institution: z.string(),
  logo: logoViewSchema,
  name: z.string(),
  kind: z.enum(INVESTMENT_KINDS),
  subtype: z.string().nullable(),
  issuer: z.string().nullable(),
  status: z.enum(['ACTIVE', 'PENDING']),
  balance: moneyViewSchema,
  invested: moneyViewSchema.nullable(),
  profit: moneyViewSchema.nullable(),
  profitPercent: z.number().nullable(),
  quantity: z.number().nullable(),
  rate: z
    .object({
      percent: z.number().nullable(),
      index: z.string().nullable(),
      fixedAnnual: z.number().nullable(),
    })
    .nullable(),
  lastMonthRate: z.number().nullable(),
  lastTwelveMonthsRate: z.number().nullable(),
  dueOn: isoDate.nullable(),
  valuedOn: isoDate.nullable(),
})

export type InvestmentPositionView = z.infer<
  typeof investmentPositionViewSchema
>

export const investmentInstitutionViewSchema = z.object({
  institutionId: z.string(),
  institution: z.string(),
  logo: logoViewSchema,
  total: moneyViewSchema,
  count: z.int(),
})

export const investmentKindViewSchema = z.object({
  kind: z.enum(INVESTMENT_KINDS),
  total: moneyViewSchema,
  count: z.int(),
})

export const investmentsViewSchema = z.object({
  total: moneyViewSchema,
  invested: moneyViewSchema,
  profit: moneyViewSchema,
  syncedAt: z.string().nullable(),
  institutions: z.array(investmentInstitutionViewSchema),
  kinds: z.array(investmentKindViewSchema),
  positions: z.array(investmentPositionViewSchema),
})

export type InvestmentsView = z.infer<typeof investmentsViewSchema>
