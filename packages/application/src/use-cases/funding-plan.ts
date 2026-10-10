import { addDays, type Bill, type BillStatus, Money } from '@cashdeck/domain'
import { money } from '@/dtos/common'
import { type FundingPlan } from '@/dtos/home'
import { loadAutoDebit } from '@/use-cases/auto-debit'
import { type Deps } from '@/use-cases/deps'
import {
  addMonths,
  allPages,
  monthOf,
  requireEntity,
  today,
} from '@/use-cases/shared'

const HISTORY_MONTHS = 6
const UPCOMING_DAYS = 30
const FUNDED: readonly BillStatus[] = ['OPEN', 'NEEDS_CONFIRMATION']

const sum = (bills: readonly Bill[]) =>
  bills.reduce((total, bill) => total.add(bill.amount), Money.zero())

// How much the Asaas balance pays a month: every personal bill the app knows,
// however it was paid, since that is what it pays once topped up.
export function makeFundingPlan(
  deps: Pick<Deps, 'entities' | 'bills' | 'documents' | 'funder' | 'clock'>,
) {
  async function balanceOf(tenantId: string, entityId: string) {
    try {
      return Money.of(await deps.funder.availableCents({ tenantId, entityId }))
    } catch {
      return null
    }
  }

  return async function fundingPlan(tenantId: string): Promise<FundingPlan> {
    const entity = await requireEntity(deps.entities, tenantId, 'PF')
    const day = today(deps.clock.now())
    const isAutoDebit = await loadAutoDebit(deps, tenantId)
    const bills = (
      await allPages(request =>
        deps.bills.list(tenantId, { entityId: entity.id }, request),
      )
    ).filter(bill => bill.status !== 'CANCELLED' && !isAutoDebit(bill))
    const current = monthOf(day)
    const first = bills
      .map(bill => monthOf(bill.dueDate))
      .reduce(
        (earliest, month) => (month < earliest ? month : earliest),
        current,
      )
    const floor = addMonths(current, 1 - HISTORY_MONTHS)
    const start = first > floor ? first : floor
    const months: FundingPlan['months'] = []
    for (let month = start; month <= current; month = addMonths(month, 1)) {
      const own = bills.filter(bill => monthOf(bill.dueDate) === month)
      months.push({ month, total: money(sum(own)) })
    }
    const total = months.reduce((cents, month) => cents + month.total.cents, 0)
    const end = addDays(day, UPCOMING_DAYS)
    const upcoming = sum(
      bills.filter(
        bill =>
          FUNDED.includes(bill.status) &&
          bill.dueDate >= day &&
          bill.dueDate <= end,
      ),
    )
    const balance = await balanceOf(tenantId, entity.id)
    const shortfall = upcoming.subtract(balance ?? Money.zero())
    return {
      balance: balance && money(balance),
      monthlyAverage: money(Money.of(Math.round(total / months.length))),
      months,
      upcoming: money(upcoming),
      topUp: money(shortfall.isPositive() ? shortfall : Money.zero()),
    }
  }
}
