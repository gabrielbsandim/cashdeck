import { estimateCpp, Money, type SimplesAnnex } from '@cashdeck/domain'
import { type z } from 'zod'
import { money } from '@/dtos/common'
import {
  type declareAnnexSchema,
  type PayrollSheetView,
  type savePayrollSchema,
} from '@/dtos/payroll'
import { type Deps } from '@/use-cases/deps'
import {
  addMonths,
  brlOf,
  firstDay,
  monthOf,
  requireEntity,
  today,
} from '@/use-cases/shared'

export type PayrollEntry = {
  month: string
  proLaboreCents: number
  salariesCents: number
  fgtsCents: number
}

export const PAYROLL_COLLECTION = 'payroll'

export const REVENUE_COLLECTION = 'revenue-history'

// The annex the accountant reports, standing in for Fator R until a year of
// payroll exists to compute it.
export const ANNEX_COLLECTION = 'simples-annex'

type DeclaredAnnex = { annex: SimplesAnnex }

export async function declaredAnnex(
  deps: Pick<Deps, 'documents'>,
  tenantId: string,
  entityId: string,
): Promise<SimplesAnnex | null> {
  const found = await deps.documents.get<DeclaredAnnex>(
    tenantId,
    ANNEX_COLLECTION,
    entityId,
  )
  return found?.annex ?? null
}

export type RevenueEntry = {
  month: string
  domesticCents: number
  exportCents: number
}

export type RevenueMonth = {
  month: string
  domestic: Money
  exports: Money
  entered: boolean
}

export const sum = (values: readonly Money[]) =>
  values.reduce((total, value) => total.add(value), Money.zero())

export function payrollTotal(entry: PayrollEntry): number {
  return entry.proLaboreCents + entry.salariesCents + entry.fgtsCents
}

const empty = (month: string): PayrollEntry => ({
  month,
  proLaboreCents: 0,
  salariesCents: 0,
  fgtsCents: 0,
})

const toView = (entry: PayrollEntry) => ({
  month: firstDay(entry.month),
  proLabore: money(Money.of(entry.proLaboreCents)),
  salaries: money(Money.of(entry.salariesCents)),
  fgts: money(Money.of(entry.fgtsCents)),
})

// Payroll entries for the twelve months ending at `last`, newest first.
export async function payrollWindow(
  deps: Pick<Deps, 'documents'>,
  tenantId: string,
  last: string,
): Promise<PayrollEntry[]> {
  const first = addMonths(last, -11)
  const all = await deps.documents.list<PayrollEntry>(
    tenantId,
    PAYROLL_COLLECTION,
  )
  return all
    .filter(entry => entry.month >= first && entry.month <= last)
    .sort((a, b) => b.month.localeCompare(a.month))
}

const NOTHING_ENTERED: RevenueEntry = {
  month: '',
  domesticCents: 0,
  exportCents: 0,
}

// Revenue billed outside the app is entered by hand and adds to the invoices
// issued here, so a month can mix both.
export async function revenueMonths(
  deps: Pick<Deps, 'invoices' | 'documents'>,
  tenantId: string,
  entityId: string,
  range: { from: string; to: string },
): Promise<RevenueMonth[]> {
  const [stored, invoices] = await Promise.all([
    deps.documents.list<RevenueEntry>(tenantId, REVENUE_COLLECTION),
    deps.invoices.all(tenantId, {
      entityId,
      status: 'ISSUED',
      competenceFrom: range.from,
      competenceTo: range.to,
    }),
  ])
  const entered = new Map(stored.map(entry => [entry.month, entry]))
  const months: RevenueMonth[] = []
  for (
    let month = range.to;
    month >= range.from;
    month = addMonths(month, -1)
  ) {
    const entry = entered.get(month) ?? NOTHING_ENTERED
    const issued = invoices.filter(invoice => invoice.competence === month)
    months.push({
      month,
      domestic: sum(issued.filter(i => !i.isExport).map(brlOf)).add(
        Money.of(entry.domesticCents),
      ),
      exports: sum(issued.filter(i => i.isExport).map(brlOf)).add(
        Money.of(entry.exportCents),
      ),
      entered: entered.has(month),
    })
  }
  return months
}

// The CPP inside the DAS of these months, which Fator R counts as payroll. It
// uses the window's own RBT12, and Annex III when none is declared.
export function cppOf(
  months: readonly RevenueMonth[],
  annex: SimplesAnnex,
): Money {
  const domestic = sum(months.map(month => month.domestic))
  const exports = sum(months.map(month => month.exports))
  return estimateCpp({
    annex,
    domesticRbt12: domestic,
    exportRbt12: exports,
    domestic,
    exports,
  })
}

export function makePayroll(
  deps: Pick<Deps, 'entities' | 'documents' | 'invoices' | 'clock'>,
) {
  async function sheet(tenantId: string): Promise<PayrollSheetView> {
    const entity = await requireEntity(deps.entities, tenantId, 'PJ')
    const month = monthOf(today(deps.clock.now()))
    const window = await payrollWindow(deps, tenantId, month)
    const current = window.find(entry => entry.month === month) ?? empty(month)
    const months = await revenueMonths(deps, tenantId, entity.id, {
      from: addMonths(month, -11),
      to: month,
    })
    const declared = await declaredAnnex(deps, tenantId, entity.id)
    return {
      current: toView(current),
      history: window.filter(entry => entry.month !== month).map(toView),
      revenue12: money(sum(months.flatMap(m => [m.domestic, m.exports]))),
      cpp12: money(cppOf(months, declared ?? 'III')),
      declaredAnnex: declared,
    }
  }

  async function declare(
    tenantId: string,
    input: z.infer<typeof declareAnnexSchema>,
  ): Promise<PayrollSheetView> {
    const entity = await requireEntity(deps.entities, tenantId, 'PJ')
    if (input.annex === null) {
      await deps.documents.delete(tenantId, ANNEX_COLLECTION, entity.id)
      return sheet(tenantId)
    }
    await deps.documents.put<DeclaredAnnex>(
      tenantId,
      ANNEX_COLLECTION,
      entity.id,
      { annex: input.annex },
    )
    return sheet(tenantId)
  }

  async function save(
    tenantId: string,
    month: string,
    input: z.infer<typeof savePayrollSchema>,
  ): Promise<PayrollSheetView> {
    await requireEntity(deps.entities, tenantId, 'PJ')
    await deps.documents.put<PayrollEntry>(
      tenantId,
      PAYROLL_COLLECTION,
      month,
      {
        month,
        ...input,
      },
    )
    return sheet(tenantId)
  }

  return { sheet, save, declare }
}
