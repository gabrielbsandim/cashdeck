import { type AlertType, crossedThreshold, Money } from '@cashdeck/domain'
import { type BudgetItemView } from '@/dtos/budgets'
import { type AlertInput } from '@/ports/alerts'
import { formatMoney } from '@/use-cases/alert-events'
import { type BudgetDeps, makeBudgets } from '@/use-cases/budgets'
import { type Deps } from '@/use-cases/deps'
import { monthOf, today } from '@/use-cases/shared'

const THRESHOLD_ALERTS: Record<80 | 100, AlertType> = {
  80: 'BUDGET_NEAR_LIMIT',
  100: 'BUDGET_LIMIT_REACHED',
}

export function budgetAlert(
  tenantId: string,
  entityId: string,
  month: string,
  item: BudgetItemView,
): AlertInput | null {
  const threshold = crossedThreshold(item.percent)
  if (threshold === null) {
    return null
  }
  const type = THRESHOLD_ALERTS[threshold]
  return {
    tenantId,
    type,
    entityId,
    data: {
      budgetId: item.id,
      categoryId: item.categoryId,
      categoryKey: item.key ?? '',
      category: item.name,
      spent: formatMoney(Money.of(item.spent.cents, item.spent.currency)),
      limit: formatMoney(
        Money.of(item.available.cents, item.available.currency),
      ),
      percent: String(item.percent),
      month,
    },
    // One per category, month and threshold: the next day only the step
    // still unannounced goes out.
    dedupeKey: `${type}:${entityId}:${item.categoryId}:${month}`,
  }
}

// Warns at 80% and at 100% of every budget of the current month.
export function makeRunBudgetAlerts(deps: BudgetDeps & Pick<Deps, 'alerts'>) {
  const budgets = makeBudgets(deps)
  return async function runBudgetAlerts(tenantId: string): Promise<number> {
    const month = monthOf(today(deps.clock.now()))
    let emitted = 0
    for (const entity of await deps.entities.list(tenantId)) {
      const planned = await deps.budgets.listMonth(tenantId, entity.id, month)
      if (planned.length === 0) {
        continue
      }
      const view = await budgets.monthView(tenantId, entity.kind, month)
      for (const item of view.items) {
        const alert = budgetAlert(tenantId, entity.id, month, item)
        emitted += alert && (await deps.alerts.emit(alert)) ? 1 : 0
      }
    }
    return emitted
  }
}
