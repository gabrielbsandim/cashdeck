import {
  type Account,
  addDays,
  committedByMonth,
  type EntityKind,
  finalMonth,
  groupInstallments,
  type InstallmentPlan,
  Money,
  remainingInstallments,
} from '@cashdeck/domain'
import { money } from '@/dtos/common'
import { type InstallmentsView } from '@/dtos/insights'
import { type Deps } from '@/use-cases/deps'
import { insightScope } from '@/use-cases/insights'
import { addMonths, monthOf, today } from '@/use-cases/shared'

type InstallmentDeps = Pick<
  Deps,
  'entities' | 'accounts' | 'transactions' | 'clock'
>

// Long enough to hold the latest charge of any plan still running.
const HISTORY_DAYS = 400
const MONTHS_AHEAD = 12

export async function activePlans(
  deps: InstallmentDeps,
  tenantId: string,
  kind: EntityKind | undefined,
) {
  const day = today(deps.clock.now())
  const scope = await insightScope(deps, tenantId, kind)
  if (scope.accounts.length === 0) {
    return { day, scope, plans: [] }
  }
  const transactions = await deps.transactions.all(tenantId, {
    accountIds: scope.accounts.map(account => account.id),
    from: addDays(day, -HISTORY_DAYS),
    to: day,
  })
  const month = monthOf(day)
  const plans = groupInstallments(transactions).filter(
    plan =>
      remainingInstallments(plan) > 0 || monthOf(plan.lastBilledOn) === month,
  )
  return { day, scope, plans }
}

const times = (plan: InstallmentPlan, count: number) =>
  money(Money.of(plan.amount.cents * count, plan.amount.currency))

export function makeListInstallments(deps: InstallmentDeps) {
  return async function listInstallments(
    tenantId: string,
    kind?: EntityKind,
  ): Promise<InstallmentsView> {
    const { day, scope, plans } = await activePlans(deps, tenantId, kind)
    const accounts = new Map(
      scope.accounts.map(account => [account.id, account]),
    )
    const kinds = new Map(
      scope.entities.map(entity => [entity.id, entity.kind]),
    )
    const views = plans
      .map(plan => {
        const account = accounts.get(plan.accountId) as Account
        return {
          key: plan.key,
          accountId: plan.accountId,
          card: account.name,
          cardSuffix: account.numberSuffix,
          entityKind: kinds.get(account.entityId) as EntityKind,
          name: plan.name,
          categoryId: plan.categoryId,
          number: plan.number,
          count: plan.count,
          amount: money(plan.amount),
          paid: times(plan, plan.number),
          remaining: times(plan, remainingInstallments(plan)),
          total: times(plan, plan.count),
          purchaseOn: plan.purchaseOn,
          lastBilledOn: plan.lastBilledOn,
          finalMonth: finalMonth(plan),
          transactionIds: [...plan.transactionIds],
        }
      })
      .sort(
        (a, b) =>
          a.finalMonth.localeCompare(b.finalMonth) ||
          a.name.localeCompare(b.name),
      )
    return {
      months: committedByMonth(
        plans,
        addMonths(monthOf(day), 1),
        MONTHS_AHEAD,
      ).map(({ month, amount }) => ({ month, total: money(amount) })),
      plans: views,
    }
  }
}
