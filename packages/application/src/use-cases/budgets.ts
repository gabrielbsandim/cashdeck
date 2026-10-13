import {
  type Budget,
  budgetUsage,
  type Category,
  createBudget,
  type EntityKind,
  Money,
  rolloverInto,
  spendingUsage,
  suggestLimit,
} from '@cashdeck/domain'
import {
  type AcceptSuggestionsInput,
  type BudgetItemView,
  type BudgetMonthQuery,
  type BudgetMonthView,
  type BudgetSuggestionsView,
  type CopyBudgetsInput,
  type CreateBudgetInput,
  type UpdateBudgetInput,
} from '@/dtos/budgets'
import { money } from '@/dtos/common'
import { ConflictError } from '@/errors/errors'
import { type AuditEvent } from '@/ports/repositories'
import { type Deps } from '@/use-cases/deps'
import {
  categoryIndex,
  categoryOf,
  flowEntries,
  groupBy,
  insightScope,
  UNCATEGORIZED,
  within,
} from '@/use-cases/insights'
import {
  addMonths,
  firstDay,
  lastDay,
  monthOf,
  required,
  requireEntity,
  today,
} from '@/use-cases/shared'

export type BudgetDeps = Pick<
  Deps,
  | 'documents'
  | 'entities'
  | 'accounts'
  | 'transactions'
  | 'categories'
  | 'budgets'
  | 'audit'
  | 'clock'
  | 'ids'
>

const SUGGESTION_MONTHS = 3

type Spending = Map<string, number>

function categoryFields(id: string, categories: ReadonlyMap<string, Category>) {
  const category = categories.get(id)
  return {
    categoryId: id,
    key: category?.key ?? null,
    name: category?.name ?? id,
    icon: category?.icon ?? null,
  }
}

function usageView(available: Money, spent: Money) {
  const usage = spendingUsage(available, spent)
  return {
    available: money(usage.available),
    spent: money(spent),
    remaining: money(usage.remaining),
    percent: usage.percent,
    level: usage.level,
  }
}

export function makeBudgets(deps: BudgetDeps) {
  const currentMonth = () => monthOf(today(deps.clock.now()))

  async function audit(
    budget: Budget,
    event: Pick<AuditEvent, 'action' | 'result' | 'details'>,
  ) {
    await deps.audit.record({
      id: deps.ids.next(),
      tenantId: budget.tenantId,
      actor: 'USER',
      subjectId: budget.id,
      rail: null,
      at: deps.clock.now(),
      ...event,
    })
  }

  // Expenses per category in the months given, counted the way insights
  // count them: no transfers, investments or card bill payments.
  async function spendingByMonth(
    tenantId: string,
    kind: EntityKind,
    months: readonly string[],
    categories: ReadonlyMap<string, Category>,
  ): Promise<Spending[]> {
    const scope = await insightScope(deps, tenantId, kind)
    const range = {
      from: firstDay(months[0] as string),
      to: lastDay(months.at(-1) as string),
    }
    const entries = await flowEntries(
      deps,
      tenantId,
      scope.accounts,
      categories,
      range,
    )
    return months.map(month => {
      const expenses = within(entries, 'EXPENSE', {
        from: firstDay(month),
        to: lastDay(month),
      })
      return new Map(
        [...groupBy(expenses, categoryOf)].map(([id, group]) => [
          id,
          group.total,
        ]),
      )
    })
  }

  function itemView(
    budget: Budget,
    spent: Spending,
    categories: ReadonlyMap<string, Category>,
  ): BudgetItemView {
    const used = Money.of(spent.get(budget.categoryId) ?? 0)
    const usage = budgetUsage(budget, used)
    return {
      id: budget.id,
      ...categoryFields(budget.categoryId, categories),
      limit: money(budget.limit),
      carried: money(budget.carried),
      rollover: budget.rollover,
      available: money(usage.available),
      spent: money(used),
      remaining: money(usage.remaining),
      percent: usage.percent,
      level: usage.level,
    }
  }

  async function monthView(
    tenantId: string,
    kind: EntityKind,
    month: string,
  ): Promise<BudgetMonthView> {
    const entity = await requireEntity(deps.entities, tenantId, kind)
    const categories = await categoryIndex(deps, tenantId)
    const budgets = await deps.budgets.listMonth(tenantId, entity.id, month)
    const [spent] = await spendingByMonth(tenantId, kind, [month], categories)
    const spending = spent as Spending
    const items = budgets
      .map(budget => itemView(budget, spending, categories))
      .sort((a, b) => b.percent - a.percent || a.name.localeCompare(b.name))
    const budgeted = new Set(budgets.map(budget => budget.categoryId))
    const unbudgeted = [...spending]
      .filter(([id]) => id !== UNCATEGORIZED && !budgeted.has(id))
      .sort(([, a], [, b]) => b - a)
      .map(([id, cents]) => ({
        ...categoryFields(id, categories),
        spent: money(Money.of(cents)),
      }))
    const total = (pick: (item: BudgetItemView) => number) =>
      Money.of(items.reduce((sum, item) => sum + pick(item), 0))
    return {
      month,
      entity: kind,
      total: usageView(
        total(item => item.available.cents),
        total(item => item.spent.cents),
      ),
      items,
      unbudgeted,
    }
  }

  async function find(tenantId: string, id: string): Promise<Budget> {
    return required(await deps.budgets.findById(tenantId, id), 'Budget')
  }

  async function kindOf(tenantId: string, budget: Budget): Promise<EntityKind> {
    const entity = await deps.entities.findById(tenantId, budget.entityId)
    return required(entity, 'Entity').kind
  }

  async function month(
    tenantId: string,
    query: BudgetMonthQuery,
  ): Promise<BudgetMonthView> {
    return monthView(tenantId, query.entity, query.month ?? currentMonth())
  }

  async function create(
    tenantId: string,
    input: CreateBudgetInput,
  ): Promise<BudgetMonthView> {
    const entity = await requireEntity(deps.entities, tenantId, input.entity)
    required(
      await deps.categories.findById(tenantId, input.categoryId),
      'Category',
    )
    const target = input.month ?? currentMonth()
    const taken = await deps.budgets.listMonth(tenantId, entity.id, target)
    if (taken.some(budget => budget.categoryId === input.categoryId)) {
      throw new ConflictError('This category already has a budget this month.')
    }
    const budget = createBudget({
      id: deps.ids.next(),
      tenantId,
      entityId: entity.id,
      categoryId: input.categoryId,
      month: target,
      limit: Money.of(input.limitCents),
      rollover: input.rollover,
    })
    await deps.budgets.save(budget)
    await audit(budget, {
      action: 'budget.create',
      result: 'CREATED',
      details: { month: target, limitCents: input.limitCents },
    })
    return monthView(tenantId, input.entity, target)
  }

  async function update(
    tenantId: string,
    id: string,
    input: UpdateBudgetInput,
  ): Promise<BudgetMonthView> {
    const current = await find(tenantId, id)
    const updated = createBudget({
      ...current,
      limit:
        input.limitCents === undefined
          ? current.limit
          : Money.of(input.limitCents),
      rollover: input.rollover ?? current.rollover,
    })
    await deps.budgets.save(updated)
    await audit(updated, {
      action: 'budget.update',
      result: 'UPDATED',
      details: { fields: Object.keys(input) },
    })
    return monthView(tenantId, await kindOf(tenantId, updated), updated.month)
  }

  async function remove(
    tenantId: string,
    id: string,
  ): Promise<BudgetMonthView> {
    const budget = await find(tenantId, id)
    await deps.budgets.delete(tenantId, id)
    await audit(budget, {
      action: 'budget.delete',
      result: 'DELETED',
      details: { month: budget.month },
    })
    return monthView(tenantId, await kindOf(tenantId, budget), budget.month)
  }

  // A category the next month already budgets keeps its own limit.
  async function copyToNext(
    tenantId: string,
    input: CopyBudgetsInput,
  ): Promise<BudgetMonthView> {
    const entity = await requireEntity(deps.entities, tenantId, input.entity)
    const next = addMonths(input.month, 1)
    const budgets = await deps.budgets.listMonth(
      tenantId,
      entity.id,
      input.month,
    )
    const taken = new Set(
      (await deps.budgets.listMonth(tenantId, entity.id, next)).map(
        budget => budget.categoryId,
      ),
    )
    const categories = await categoryIndex(deps, tenantId)
    const [spent] = await spendingByMonth(
      tenantId,
      input.entity,
      [input.month],
      categories,
    )
    for (const budget of budgets.filter(item => !taken.has(item.categoryId))) {
      const copy = rolloverInto(
        budget,
        Money.of((spent as Spending).get(budget.categoryId) ?? 0),
        { id: deps.ids.next(), month: next },
      )
      await deps.budgets.save(copy)
      await audit(copy, {
        action: 'budget.copy',
        result: 'CREATED',
        details: { from: budget.id, carriedCents: copy.carried.cents },
      })
    }
    return monthView(tenantId, input.entity, next)
  }

  async function suggest(
    tenantId: string,
    query: BudgetMonthQuery,
  ): Promise<BudgetSuggestionsView> {
    const entity = await requireEntity(deps.entities, tenantId, query.entity)
    const target = query.month ?? currentMonth()
    const current = currentMonth()
    const basedOn = Array.from({ length: SUGGESTION_MONTHS }, (_, index) =>
      addMonths(current, index - SUGGESTION_MONTHS),
    )
    const categories = await categoryIndex(deps, tenantId)
    const months = await spendingByMonth(
      tenantId,
      query.entity,
      basedOn,
      categories,
    )
    const limits = new Map(
      (await deps.budgets.listMonth(tenantId, entity.id, target)).map(
        budget => [budget.categoryId, budget.limit],
      ),
    )
    const ids = new Set(months.flatMap(spending => [...spending.keys()]))
    ids.delete(UNCATEGORIZED)
    const items = [...ids]
      .map(id => {
        const totals = months.map(spending => spending.get(id) ?? 0)
        const limit = limits.get(id)
        return {
          ...categoryFields(id, categories),
          months: totals.map(cents => money(Money.of(cents))),
          suggested: money(suggestLimit(totals)),
          current: limit ? money(limit) : null,
        }
      })
      .filter(item => item.suggested.cents > 0)
      .sort((a, b) => b.suggested.cents - a.suggested.cents)
    return {
      month: target,
      entity: query.entity,
      basedOn,
      total: money(
        Money.of(items.reduce((sum, item) => sum + item.suggested.cents, 0)),
      ),
      items,
    }
  }

  // One tap sets every limit: a category with a budget gets the new limit,
  // one without gets a budget.
  async function acceptSuggestions(
    tenantId: string,
    input: AcceptSuggestionsInput,
  ): Promise<BudgetMonthView> {
    const entity = await requireEntity(deps.entities, tenantId, input.entity)
    const target = input.month ?? currentMonth()
    const existing = new Map(
      (await deps.budgets.listMonth(tenantId, entity.id, target)).map(
        budget => [budget.categoryId, budget],
      ),
    )
    for (const item of input.items) {
      required(
        await deps.categories.findById(tenantId, item.categoryId),
        'Category',
      )
      const known = existing.get(item.categoryId)
      const budget = createBudget({
        id: known?.id ?? deps.ids.next(),
        tenantId,
        entityId: entity.id,
        categoryId: item.categoryId,
        month: target,
        limit: Money.of(item.limitCents),
        carried: known?.carried,
        rollover: known?.rollover ?? false,
      })
      await deps.budgets.save(budget)
      await audit(budget, {
        action: 'budget.accept-suggestion',
        result: known ? 'UPDATED' : 'CREATED',
        details: { month: target, limitCents: item.limitCents },
      })
    }
    return monthView(tenantId, input.entity, target)
  }

  return {
    month,
    monthView,
    create,
    update,
    remove,
    copyToNext,
    suggest,
    acceptSuggestions,
  }
}
