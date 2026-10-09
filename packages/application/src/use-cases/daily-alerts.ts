import {
  addDays,
  type Bill,
  type BillStatus,
  type LocalDate,
  Money,
  toLocalDate,
} from '@cashdeck/domain'
import { billAlert, formatDay, formatMoney } from '@/use-cases/alert-events'
import { loadAutoDebit } from '@/use-cases/auto-debit'
import { type Deps } from '@/use-cases/deps'
import { allPages } from '@/use-cases/shared'

type DailyAlertDeps = Pick<
  Deps,
  'bills' | 'accounts' | 'clock' | 'alerts' | 'documents'
>

export type DailyAlertsResult = { dueSoon: number; lowBalance: number }

const UNPAID: readonly BillStatus[] = [
  'OPEN',
  'NEEDS_CONFIRMATION',
  'AWAITING_BANK_APPROVAL',
  'ASSISTED',
]

// The ones the reserve funds on the due date; assisted and bank-approved
// bills are paid from elsewhere.
const FUNDED: readonly BillStatus[] = ['OPEN', 'NEEDS_CONFIRMATION']

export function makeRunDailyAlerts(deps: DailyAlertDeps) {
  async function dueOn(tenantId: string, day: LocalDate): Promise<Bill[]> {
    const bills: Bill[] = []
    for (const status of UNPAID) {
      const page = await allPages(request =>
        deps.bills.list(tenantId, { status }, request),
      )
      bills.push(...page.filter(bill => bill.dueDate === day))
    }
    return bills
  }

  async function lowBalance(
    tenantId: string,
    entityId: string,
    bills: Bill[],
    day: LocalDate,
  ): Promise<boolean> {
    const accounts = await deps.accounts.listByEntity(tenantId, entityId)
    const reserve = accounts.find(account => account.isReserve)
    if (!reserve) {
      return false
    }
    const needed = bills.reduce(
      (sum, bill) => sum.add(bill.amount),
      Money.zero(),
    )
    const shortfall = needed.subtract(reserve.balance)
    if (!shortfall.isPositive()) {
      return false
    }
    const emitted = await deps.alerts.emit({
      tenantId,
      type: 'LOW_BALANCE',
      entityId,
      data: {
        shortfall: formatMoney(shortfall),
        balance: formatMoney(reserve.balance),
        needed: formatMoney(needed),
        dueDate: formatDay(day),
      },
      dedupeKey: `LOW_BALANCE:${entityId}:${day}`,
    })
    return emitted !== null
  }

  return async function runDailyAlerts(
    tenantId: string,
  ): Promise<DailyAlertsResult> {
    const tomorrow = addDays(toLocalDate(deps.clock.now()), 1)
    const isAutoDebit = await loadAutoDebit(deps, tenantId)
    // The bank debits these by itself: nothing to pay and nothing to fund.
    const bills = (await dueOn(tenantId, tomorrow)).filter(
      bill => !isAutoDebit(bill),
    )
    const result: DailyAlertsResult = { dueSoon: 0, lowBalance: 0 }
    for (const bill of bills) {
      const alert = billAlert(
        'BILL_DUE_SOON',
        bill,
        {},
        `BILL_DUE_SOON:${bill.id}:${bill.dueDate}`,
      )
      result.dueSoon += (await deps.alerts.emit(alert)) ? 1 : 0
    }
    const funded = bills.filter(bill => FUNDED.includes(bill.status))
    const entities = new Set(funded.map(bill => bill.entityId))
    for (const entityId of entities) {
      const own = funded.filter(bill => bill.entityId === entityId)
      result.lowBalance += (await lowBalance(tenantId, entityId, own, tomorrow))
        ? 1
        : 0
    }
    return result
  }
}
