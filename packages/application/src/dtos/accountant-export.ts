import { z } from 'zod'
import { isoDate } from '@/dtos/common'

export const EXPORT_PERIODS = ['LAST_MONTH', 'LAST_QUARTER', 'CUSTOM'] as const
export const EXPORT_ITEM_KINDS = [
  'STATEMENTS',
  'INVOICES',
  'TAX_GUIDES',
  'EXPENSES',
  'PAYROLL',
  'RECONCILIATION',
] as const
export const EXPORT_UNITS = ['ACCOUNTS', 'DOCUMENTS', 'MONTHS'] as const

export type ExportItemKind = (typeof EXPORT_ITEM_KINDS)[number]
export type ExportUnit = (typeof EXPORT_UNITS)[number]

type PeriodInput = { period: string; from?: string; to?: string }

const hasCustomRange = (input: PeriodInput) =>
  input.period !== 'CUSTOM' ||
  (input.from !== undefined && input.to !== undefined && input.from <= input.to)

const CUSTOM_RANGE = { message: 'A custom period needs from and to, in order.' }

export const exportPeriodQuerySchema = z
  .object({
    period: z.enum(EXPORT_PERIODS),
    from: isoDate.optional(),
    to: isoDate.optional(),
  })
  .refine(hasCustomRange, CUSTOM_RANGE)

export type ExportPeriodQuery = z.infer<typeof exportPeriodQuerySchema>

export const generateExportSchema = z
  .object({
    period: z.enum(EXPORT_PERIODS),
    from: isoDate.optional(),
    to: isoDate.optional(),
    items: z.array(z.enum(EXPORT_ITEM_KINDS)).min(1),
    sentTo: z.email().optional(),
  })
  .refine(hasCustomRange, CUSTOM_RANGE)

export type GenerateExportInput = z.infer<typeof generateExportSchema>

export const exportPlanViewSchema = z.object({
  from: isoDate,
  to: isoDate,
  items: z.array(
    z.object({
      kind: z.enum(EXPORT_ITEM_KINDS),
      count: z.int(),
      unit: z.enum(EXPORT_UNITS),
      files: z.int(),
      bytes: z.int(),
      selectedByDefault: z.boolean(),
    }),
  ),
})

export type ExportPlanView = z.infer<typeof exportPlanViewSchema>

export const exportRecordViewSchema = z.object({
  id: z.string(),
  month: isoDate,
  sentOn: isoDate,
  to: z.string().nullable(),
  downloadPath: z.string(),
})

export type ExportRecordView = z.infer<typeof exportRecordViewSchema>
