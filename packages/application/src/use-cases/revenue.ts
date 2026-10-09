import { annexFor, issRate, Money, type SimplesAnnex } from '@cashdeck/domain'
import { type z } from 'zod'
import { money } from '@/dtos/common'
import { type RevenueSheetView, type saveRevenueSchema } from '@/dtos/revenue'
import { type Deps } from '@/use-cases/deps'
import {
  declaredAnnex,
  payrollTotal,
  payrollWindow,
  REVENUE_COLLECTION,
  type RevenueEntry,
  revenueMonths,
  sum,
} from '@/use-cases/payroll'
import {
  addMonths,
  firstDay,
  monthOf,
  requireEntity,
  today,
} from '@/use-cases/shared'

export type IssQuote = {
  domesticRbt12: Money
  exportRbt12: Money
  annex: SimplesAnnex
  // The accountant's declared annex wins, since they file the DAS; without
  // it the rate waits for twelve months of payroll to compute Fator R.
  ratePercent: number | null
}

const MONTHS = 12

const previousYear = (month: string) => ({
  from: addMonths(month, -MONTHS),
  to: addMonths(month, -1),
})

export async function issQuote(
  deps: Pick<Deps, 'invoices' | 'documents'>,
  tenantId: string,
  entityId: string,
  competence: string,
): Promise<IssQuote> {
  const range = previousYear(competence)
  const months = await revenueMonths(deps, tenantId, entityId, range)
  const domesticRbt12 = sum(months.map(month => month.domestic))
  const exportRbt12 = sum(months.map(month => month.exports))
  const payroll = await payrollWindow(deps, tenantId, range.to)
  const complete = payroll.length >= MONTHS
  const declared = await declaredAnnex(deps, tenantId, entityId)
  const annex =
    declared ??
    annexFor(
      Money.of(
        payroll.reduce((total, entry) => total + payrollTotal(entry), 0),
      ),
      domesticRbt12.add(exportRbt12),
    )
  const known = complete || declared !== null
  const rate = known ? issRate(annex, domesticRbt12) : null
  return {
    domesticRbt12,
    exportRbt12,
    annex,
    ratePercent: rate === null ? null : Math.round(rate * 10_000) / 100,
  }
}

export function makeRevenue(
  deps: Pick<Deps, 'entities' | 'documents' | 'invoices' | 'clock'>,
) {
  async function sheet(tenantId: string): Promise<RevenueSheetView> {
    const entity = await requireEntity(deps.entities, tenantId, 'PJ')
    const month = monthOf(today(deps.clock.now()))
    const months = await revenueMonths(
      deps,
      tenantId,
      entity.id,
      previousYear(month),
    )
    const quote = await issQuote(deps, tenantId, entity.id, month)
    return {
      months: months.map(entry => ({
        month: firstDay(entry.month),
        domestic: money(entry.domestic),
        exports: money(entry.exports),
        entered: entry.entered,
      })),
      domesticRbt12: money(quote.domesticRbt12),
      exportRbt12: money(quote.exportRbt12),
      annex: quote.annex,
      issRatePercent: quote.ratePercent,
    }
  }

  async function save(
    tenantId: string,
    month: string,
    input: z.infer<typeof saveRevenueSchema>,
  ): Promise<RevenueSheetView> {
    await requireEntity(deps.entities, tenantId, 'PJ')
    await deps.documents.put<RevenueEntry>(
      tenantId,
      REVENUE_COLLECTION,
      month,
      { month, ...input },
    )
    return sheet(tenantId)
  }

  return { sheet, save }
}
