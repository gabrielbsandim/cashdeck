import { z } from 'zod'
import { isoDate, moneyViewSchema } from '@/dtos/common'

export const revenueMonthViewSchema = z.object({
  month: isoDate,
  domestic: moneyViewSchema,
  exports: moneyViewSchema,
  entered: z.boolean(),
})

export const revenueSheetViewSchema = z.object({
  months: z.array(revenueMonthViewSchema),
  domesticRbt12: moneyViewSchema,
  exportRbt12: moneyViewSchema,
  annex: z.enum(['III', 'V']),
  issRatePercent: z.number().nullable(),
})

export type RevenueSheetView = z.infer<typeof revenueSheetViewSchema>

export const saveRevenueSchema = z.object({
  domesticCents: z.int().min(0),
  exportCents: z.int().min(0),
})
