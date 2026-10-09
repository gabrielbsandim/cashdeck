import { z } from 'zod'
import { isoDate, moneyViewSchema } from '@/dtos/common'

export const payrollMonthViewSchema = z.object({
  month: isoDate,
  proLabore: moneyViewSchema,
  salaries: moneyViewSchema,
  fgts: moneyViewSchema,
})

export const payrollSheetViewSchema = z.object({
  current: payrollMonthViewSchema,
  history: z.array(payrollMonthViewSchema),
  revenue12: moneyViewSchema,
  // Null when Fator R alone picks the annex.
  declaredAnnex: z.enum(['III', 'V']).nullable(),
})

export type PayrollSheetView = z.infer<typeof payrollSheetViewSchema>

export const savePayrollSchema = z.object({
  proLaboreCents: z.int().min(0),
  salariesCents: z.int().min(0),
  fgtsCents: z.int().min(0),
})

export const declareAnnexSchema = z.object({
  annex: z.enum(['III', 'V']).nullable(),
})
