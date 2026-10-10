import { z } from 'zod'
import { entityKindSchema, isoDate, moneyViewSchema } from '@/dtos/common'
import { INVESTMENT_KINDS, MOVEMENT_KINDS } from '@/ports/investments'

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

export const INVESTMENT_PERIODS = ['WEEK', 'MONTH', 'YEAR'] as const
export type InvestmentPeriod = (typeof INVESTMENT_PERIODS)[number]

const periodSchema = z.enum(INVESTMENT_PERIODS).default('MONTH')

export const investmentPerformanceQuerySchema = z.object({
  entity: entityKindSchema.optional(),
  period: periodSchema,
})

export type InvestmentPerformanceQuery = z.infer<
  typeof investmentPerformanceQuerySchema
>

export const investmentDetailQuerySchema = z.object({ period: periodSchema })

export const investmentPeriodViewSchema = z.object({
  period: z.enum(INVESTMENT_PERIODS),
  from: isoDate,
  to: isoDate,
  start: moneyViewSchema,
  end: moneyViewSchema,
  contributions: moneyViewSchema,
  withdrawals: moneyViewSchema,
  yield: moneyViewSchema,
  yieldPercent: z.number().nullable(),
  cdiPercent: z.number().nullable(),
  estimated: z.boolean(),
  series: z.array(z.object({ day: isoDate, value: moneyViewSchema })),
})

export type InvestmentPeriodView = z.infer<typeof investmentPeriodViewSchema>

export const investmentPositionYieldViewSchema = z.object({
  id: z.string(),
  start: moneyViewSchema,
  end: moneyViewSchema,
  yield: moneyViewSchema,
  yieldPercent: z.number().nullable(),
})

export const investmentPerformanceViewSchema =
  investmentPeriodViewSchema.extend({
    positions: z.array(investmentPositionYieldViewSchema),
  })

export type InvestmentPerformanceView = z.infer<
  typeof investmentPerformanceViewSchema
>

export const investmentMovementViewSchema = z.object({
  id: z.string(),
  kind: z.enum(MOVEMENT_KINDS),
  occurredOn: isoDate,
  amount: moneyViewSchema,
  quantity: z.number().nullable(),
  unitPrice: z.number().nullable(),
})

export const investmentDetailViewSchema = z.object({
  position: investmentPositionViewSchema,
  performance: investmentPeriodViewSchema,
  movements: z.array(investmentMovementViewSchema),
})

export type InvestmentDetailView = z.infer<typeof investmentDetailViewSchema>
