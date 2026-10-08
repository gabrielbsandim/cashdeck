import { Money } from '@cashdeck/domain'
import { type z } from 'zod'
import { money } from '@/dtos/common'
import { type PayrollSheetView, type savePayrollSchema } from '@/dtos/payroll'
import { type Deps } from '@/use-cases/deps'
import { brlOf } from '@/use-cases/invoices'
import {
  addMonths,
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

export async function issuedRevenue(
  deps: Pick<Deps, 'invoices'>,
  tenantId: string,
  entityId: string,
  range: { from: string; to: string },
): Promise<Money> {
  const invoices = await deps.invoices.all(tenantId, {
    entityId,
    status: 'ISSUED',
    competenceFrom: range.from,
    competenceTo: range.to,
  })
  return invoices.reduce(
    (sum, invoice) => sum.add(brlOf(invoice)),
    Money.zero(),
  )
}

export function makePayroll(
  deps: Pick<Deps, 'entities' | 'documents' | 'invoices' | 'clock'>,
) {
  async function sheet(tenantId: string): Promise<PayrollSheetView> {
    const entity = await requireEntity(deps.entities, tenantId, 'PJ')
    const month = monthOf(today(deps.clock.now()))
    const window = await payrollWindow(deps, tenantId, month)
    const current = window.find(entry => entry.month === month) ?? empty(month)
    const revenue12 = await issuedRevenue(deps, tenantId, entity.id, {
      from: addMonths(month, -11),
      to: month,
    })
    return {
      current: toView(current),
      history: window.filter(entry => entry.month !== month).map(toView),
      revenue12: money(revenue12),
    }
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

  return { sheet, save }
}
