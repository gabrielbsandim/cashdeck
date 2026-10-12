import { type LocalDate } from '@cashdeck/domain'
import {
  type IncomeSource,
  type IncomeSourcesView,
  type SpendingPlanInput,
  type SpendingPlanView,
} from '@/dtos/safe-to-spend'
import { type Deps } from '@/use-cases/deps'
import {
  categoryIndex,
  cents,
  type FlowEntry,
  flowEntries,
  insightScope,
  type InsightsDeps,
} from '@/use-cases/insights'
import {
  addMonths,
  firstDay,
  monthOf,
  requireEntity,
  today,
} from '@/use-cases/shared'

export const SPENDING_PLAN_COLLECTION = 'spending-plans'

// Older documents lack the income sources.
type SpendingPlanDocument = {
  savings?: SpendingPlanView['savings']
  incomeSources?: IncomeSource[]
}

type SpendingPlanDeps = InsightsDeps & Pick<Deps, 'documents'>

// Months of credits the payers to choose from are read from.
const SOURCE_MONTHS = 6
const MAX_CANDIDATES = 12

const digits = (value: string | null) => (value ?? '').replace(/\D/g, '')

export async function loadSpendingPlan(
  deps: Pick<Deps, 'documents'>,
  tenantId: string,
  entityId: string,
): Promise<SpendingPlanView> {
  const stored = await deps.documents.get<SpendingPlanDocument>(
    tenantId,
    SPENDING_PLAN_COLLECTION,
    entityId,
  )
  return {
    savings: stored?.savings ?? null,
    incomeSources: stored?.incomeSources ?? [],
  }
}

// Income is what the chosen payers send, matched by their CPF or CNPJ; until
// one is chosen, any credit that is not own money moving.
export function incomeTest(
  sources: readonly IncomeSource[],
  cards: ReadonlySet<string>,
): (entry: FlowEntry) => boolean {
  if (sources.length === 0) {
    return entry => entry.kind === 'INCOME'
  }
  const payers = new Set(sources.map(source => source.taxId))
  return ({ transaction }) =>
    transaction.amount.isPositive() &&
    !cards.has(transaction.accountId) &&
    payers.has(digits(transaction.counterparty))
}

type Candidate = {
  taxId: string
  name: string
  total: number
  months: Set<string>
  lastOn: LocalDate
}

function candidatesOf(
  entries: readonly FlowEntry[],
  chosen: ReadonlySet<string>,
): Candidate[] {
  const byPayer = new Map<string, Candidate>()
  for (const { transaction, cents: amount } of entries) {
    const taxId = digits(transaction.counterparty)
    const known = byPayer.get(taxId) ?? {
      taxId,
      name: '',
      total: 0,
      months: new Set<string>(),
      lastOn: '',
    }
    known.total += amount
    known.months.add(monthOf(transaction.bookedOn))
    if (transaction.bookedOn >= known.lastOn) {
      known.lastOn = transaction.bookedOn
      known.name = transaction.merchant ?? transaction.description
    }
    byPayer.set(taxId, known)
  }
  const ranked = [...byPayer.values()].sort((a, b) => b.total - a.total)
  return ranked.filter(
    (candidate, rank) => rank < MAX_CANDIDATES || chosen.has(candidate.taxId),
  )
}

export function makeIncomeSources(deps: SpendingPlanDeps) {
  // The payers that sent the person money lately, the largest first, with
  // the chosen ones always listed.
  return async function incomeSources(
    tenantId: string,
  ): Promise<IncomeSourcesView> {
    const day = today(deps.clock.now())
    const scope = await insightScope(deps, tenantId, 'PF')
    const entity = scope.entities[0] as (typeof scope.entities)[number]
    const plan = await loadSpendingPlan(deps, tenantId, entity.id)
    const chosen = new Set(plan.incomeSources.map(source => source.taxId))
    const cards = new Set(
      scope.accounts
        .filter(account => account.type === 'CREDIT_CARD')
        .map(account => account.id),
    )
    const entries = await flowEntries(
      deps,
      tenantId,
      scope.accounts,
      await categoryIndex(deps, tenantId),
      {
        from: firstDay(addMonths(monthOf(day), -SOURCE_MONTHS)),
        to: day,
      },
    )
    const credits = entries.filter(
      entry =>
        digits(entry.transaction.counterparty) !== '' &&
        (entry.kind === 'INCOME' ||
          incomeTest(plan.incomeSources, cards)(entry)),
    )
    return {
      items: candidatesOf(credits, chosen).map(candidate => ({
        taxId: candidate.taxId,
        name: candidate.name,
        total: cents(candidate.total),
        months: candidate.months.size,
        lastOn: candidate.lastOn,
        selected: chosen.has(candidate.taxId),
      })),
    }
  }
}

// Changes what the input names and keeps the rest: a null savings target goes
// back to what a typical month leaves over, no sources to every credit.
export function makeSetSpendingPlan(
  deps: Pick<Deps, 'entities' | 'documents'>,
) {
  return async function setSpendingPlan(
    tenantId: string,
    input: SpendingPlanInput,
  ): Promise<SpendingPlanView> {
    const entity = await requireEntity(deps.entities, tenantId, 'PF')
    const stored = await loadSpendingPlan(deps, tenantId, entity.id)
    const plan: SpendingPlanView = {
      savings: input.savings === undefined ? stored.savings : input.savings,
      incomeSources: input.incomeSources ?? stored.incomeSources,
    }
    await deps.documents.put<SpendingPlanDocument>(
      tenantId,
      SPENDING_PLAN_COLLECTION,
      entity.id,
      plan,
    )
    return plan
  }
}
