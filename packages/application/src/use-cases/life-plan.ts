import {
  assetValueOn,
  lifePlan,
  loanBalanceOn,
  Money,
  type PlanGoal,
  type PlanStart,
} from '@cashdeck/domain'
import { money } from '@/dtos/common'
import {
  planGoalInputSchema,
  type PlanGoalInput,
  type PlanGoalView,
  type PlanOrderInput,
  type PlanSettings,
  type PlanView,
} from '@/dtos/life-plan'
import { type NetWorthView } from '@/dtos/net-worth'
import { loadAssets, type StoredAsset } from '@/use-cases/assets'
import { type Deps } from '@/use-cases/deps'
import { loadLoans, type StoredLoan } from '@/use-cases/loans'
import { makeNetWorthFromBalancesAndSnapshots } from '@/use-cases/net-worth'
import { makeSafeToSpend } from '@/use-cases/safe-to-spend'
import { required, today } from '@/use-cases/shared'

export const PLAN_GOALS_COLLECTION = 'plan-goals'
export const PLAN_SETTINGS_COLLECTION = 'plan-settings'
const SETTINGS_ID = 'family'

export const DEFAULT_PLAN_SETTINGS: PlanSettings = {
  reserveMonths: 6,
  yearlyYield: 6,
  keepInvested: 0,
  monthlySavings: null,
}

export type StoredPlanGoal = PlanGoalInput & {
  id: string
  order: number
  createdAt: string
}

type LifePlanDeps = Parameters<typeof makeSafeToSpend>[0] &
  Parameters<typeof makeNetWorthFromBalancesAndSnapshots>[0] &
  Pick<Deps, 'ids' | 'goals'>

type Belongings = {
  assets: ReadonlyMap<string, StoredAsset>
  loans: ReadonlyMap<string, StoredLoan>
}

const byOrder = (a: StoredPlanGoal, b: StoredPlanGoal) => a.order - b.order

const cents = (value: number) => money(Money.of(Math.round(value)))

// A sold asset or a missing one leaves the trade-in typed by hand.
function liveAsset(goal: StoredPlanGoal, belongings: Belongings) {
  if (goal.kind !== 'PURCHASE' || goal.tradeInAssetId === null) {
    return null
  }
  const asset = belongings.assets.get(goal.tradeInAssetId)
  return asset && asset.soldOn === null ? asset : null
}

function equityOf(
  asset: StoredAsset,
  belongings: Belongings,
  day: string,
): number {
  const loan = belongings.loans.get(asset.loanId ?? '')
  const owed = loan ? loanBalanceOn(loan, day) : 0
  return assetValueOn(asset, day).cents - owed
}

function toDomain(goal: StoredPlanGoal, tradeIn: number): PlanGoal {
  switch (goal.kind) {
    case 'PURCHASE':
      return {
        id: goal.id,
        kind: 'PURCHASE',
        name: goal.name,
        priceCents: goal.price,
        tradeInCents: tradeIn,
        financedCents: goal.financed,
        monthlyCostCents: goal.monthlyCost,
        keepsValue: goal.keepsValue,
        payment: goal.payment,
        installments: goal.installments,
        notBefore: goal.notBefore,
        by: goal.by,
      }
    case 'YEARLY':
      return {
        id: goal.id,
        kind: 'YEARLY',
        name: goal.name,
        yearlyCents: goal.yearly,
      }
    case 'MILESTONE':
      return {
        id: goal.id,
        kind: 'MILESTONE',
        name: goal.name,
        metric: goal.metric,
        targetCents: goal.target,
        by: goal.by,
      }
  }
}

const EMPTY_FIELDS = {
  price: null,
  tradeIn: null,
  tradeInAssetId: null,
  tradeInAssetName: null,
  financed: null,
  monthlyCost: null,
  keepsValue: null,
  payment: null,
  installments: null,
  goalId: null,
  notBefore: null,
  by: null,
  yearly: null,
  metric: null,
  target: null,
  current: null,
}

function fieldsOf(
  goal: StoredPlanGoal,
  tradeIn: number,
  asset: StoredAsset | null,
  worth: NetWorthView['current'],
  saving: ReadonlySet<string>,
) {
  switch (goal.kind) {
    case 'PURCHASE':
      return {
        ...EMPTY_FIELDS,
        price: cents(goal.price),
        tradeIn: cents(tradeIn),
        tradeInAssetId: asset?.id ?? null,
        tradeInAssetName: asset?.name ?? null,
        financed: cents(goal.financed),
        monthlyCost: cents(goal.monthlyCost),
        keepsValue: goal.keepsValue,
        payment: goal.payment,
        installments: goal.installments,
        goalId: saving.has(goal.goalId ?? '') ? goal.goalId : null,
        notBefore: goal.notBefore,
        by: goal.by,
      }
    case 'YEARLY':
      return { ...EMPTY_FIELDS, yearly: cents(goal.yearly) }
    case 'MILESTONE':
      return {
        ...EMPTY_FIELDS,
        metric: goal.metric,
        target: cents(goal.target),
        by: goal.by,
        current: goal.metric === 'NET_WORTH' ? worth.total : worth.investments,
      }
  }
}

export function makeLifePlan(deps: LifePlanDeps) {
  const netWorth = makeNetWorthFromBalancesAndSnapshots(deps)
  const safeToSpend = makeSafeToSpend(deps)

  // Goals stored before a field existed take its default.
  const loadGoals = async (tenantId: string) =>
    (await deps.documents.list<StoredPlanGoal>(tenantId, PLAN_GOALS_COLLECTION))
      .map(goal => ({ ...goal, ...planGoalInputSchema.parse(goal) }))
      .sort(byOrder)

  async function savingGoals(tenantId: string): Promise<Set<string>> {
    const goals = await deps.goals.list(tenantId)
    return new Set(
      goals.filter(goal => goal.archivedAt === null).map(goal => goal.id),
    )
  }

  async function settings(tenantId: string): Promise<PlanSettings> {
    const stored = await deps.documents.get<PlanSettings>(
      tenantId,
      PLAN_SETTINGS_COLLECTION,
      SETTINGS_ID,
    )
    return { ...DEFAULT_PLAN_SETTINGS, ...stored }
  }

  async function belongingsOf(tenantId: string): Promise<Belongings> {
    const [assets, loans] = await Promise.all([
      loadAssets(deps, tenantId),
      loadLoans(deps, tenantId),
    ])
    return {
      assets: new Map(assets.map(asset => [asset.id, asset])),
      loans: new Map(loans.map(loan => [loan.id, loan])),
    }
  }

  // Spending is what the monthly plan leaves once its savings target is set
  // aside; the reserve covers months of it.
  async function startOf(tenantId: string) {
    const [chosen, worth, safe] = await Promise.all([
      settings(tenantId),
      netWorth(tenantId, { entity: 'PF', months: 1 }),
      safeToSpend(tenantId, 'PF'),
    ])
    const plan = safe.plan
    const budgeted = plan?.savings.cents ?? 0
    const savings = chosen.monthlySavings ?? budgeted
    const start: PlanStart = {
      month: worth.asOf.slice(0, 7),
      cashCents: worth.current.cash.cents,
      investedCents: worth.current.investments.cents,
      netWorthCents: worth.current.total.cents,
      monthlySavingsCents: savings,
      monthlySpendingCents: Math.max(0, (plan?.income.cents ?? 0) - budgeted),
      reserveMonths: chosen.reserveMonths,
      keepShare: chosen.keepInvested / 100,
      monthlyYield: (1 + chosen.yearlyYield / 100) ** (1 / 12) - 1,
    }
    return { chosen, start, worth: worth.current }
  }

  async function view(tenantId: string): Promise<PlanView> {
    const [{ chosen, start, worth }, belongings, stored, saving] =
      await Promise.all([
        startOf(tenantId),
        belongingsOf(tenantId),
        loadGoals(tenantId),
        savingGoals(tenantId),
      ])
    const day = today(deps.clock.now())
    const assets = stored.map(goal => liveAsset(goal, belongings))
    const tradeIns = stored.map((goal, index) => {
      const asset = assets[index]
      if (asset) {
        return equityOf(asset, belongings, day)
      }
      return goal.kind === 'PURCHASE' ? goal.tradeIn : 0
    })
    const goals = stored.map((goal, index) =>
      toDomain(goal, tradeIns[index] as number),
    )
    const plan = lifePlan(start, goals)
    const names = new Map(stored.map(goal => [goal.id, goal.name]))
    const views = plan.goals.map((planned, index): PlanGoalView => {
      const goal = stored[index] as StoredPlanGoal
      return {
        id: goal.id,
        kind: goal.kind,
        name: goal.name,
        icon: goal.icon,
        status: planned.status,
        month: planned.month,
        cash: cents(planned.cashCents),
        delays: planned.delays.map(delay => ({
          ...delay,
          name: names.get(delay.milestoneId) as string,
        })),
        ...fieldsOf(
          goal,
          tradeIns[index] as number,
          assets[index] ?? null,
          worth,
          saving,
        ),
      }
    })
    return {
      asOf: start.month,
      monthlySavings: cents(start.monthlySavingsCents),
      savingsFromBudget: chosen.monthlySavings === null,
      monthlySpending: cents(start.monthlySpendingCents),
      reserveMonths: chosen.reserveMonths,
      reserve: cents(plan.reserveCents),
      yearlyYield: chosen.yearlyYield,
      keepInvested: chosen.keepInvested,
      netWorth: worth.total,
      invested: worth.investments,
      yearlyProvision: cents(plan.yearlyProvisionCents),
      free: cents(start.monthlySavingsCents - plan.yearlyProvisionCents),
      goals: views,
      timeline: plan.timeline.map(point => ({
        month: point.month,
        netWorth: cents(point.netWorthCents),
        invested: cents(point.investedCents),
      })),
    }
  }

  async function assertAsset(tenantId: string, input: PlanGoalInput) {
    if (input.kind !== 'PURCHASE' || input.tradeInAssetId === null) {
      return
    }
    const assets = await loadAssets(deps, tenantId)
    required(
      assets.find(asset => asset.id === input.tradeInAssetId) ?? null,
      'Asset',
    )
  }

  async function assertGoal(tenantId: string, input: PlanGoalInput) {
    if (input.kind !== 'PURCHASE' || input.goalId === null) {
      return
    }
    required(await deps.goals.findById(tenantId, input.goalId), 'Goal')
  }

  async function find(tenantId: string, id: string) {
    return required(
      await deps.documents.get<StoredPlanGoal>(
        tenantId,
        PLAN_GOALS_COLLECTION,
        id,
      ),
      'Plan goal',
    )
  }

  async function create(tenantId: string, input: PlanGoalInput) {
    await assertAsset(tenantId, input)
    await assertGoal(tenantId, input)
    const goals = await loadGoals(tenantId)
    const id = deps.ids.next()
    const goal: StoredPlanGoal = {
      ...input,
      id,
      order: Math.max(-1, ...goals.map(item => item.order)) + 1,
      createdAt: deps.clock.now().toISOString(),
    }
    await deps.documents.put(tenantId, PLAN_GOALS_COLLECTION, id, goal)
    return view(tenantId)
  }

  async function update(tenantId: string, id: string, input: PlanGoalInput) {
    const current = await find(tenantId, id)
    await assertAsset(tenantId, input)
    await assertGoal(tenantId, input)
    const goal: StoredPlanGoal = {
      ...input,
      id,
      order: current.order,
      createdAt: current.createdAt,
    }
    await deps.documents.put(tenantId, PLAN_GOALS_COLLECTION, id, goal)
    return view(tenantId)
  }

  async function remove(tenantId: string, id: string) {
    await find(tenantId, id)
    await deps.documents.delete(tenantId, PLAN_GOALS_COLLECTION, id)
    return view(tenantId)
  }

  // Goals left out of the list keep their turn after the listed ones.
  async function reorder(tenantId: string, input: PlanOrderInput) {
    const goals = await loadGoals(tenantId)
    const rank = (goal: StoredPlanGoal) => {
      const index = input.ids.indexOf(goal.id)
      return index < 0 ? input.ids.length + goal.order : index
    }
    const ranked = [...goals].sort((a, b) => rank(a) - rank(b))
    for (const [order, goal] of ranked.entries()) {
      await deps.documents.put(tenantId, PLAN_GOALS_COLLECTION, goal.id, {
        ...goal,
        order,
      })
    }
    return view(tenantId)
  }

  async function saveSettings(tenantId: string, input: PlanSettings) {
    await deps.documents.put(
      tenantId,
      PLAN_SETTINGS_COLLECTION,
      SETTINGS_ID,
      input,
    )
    return view(tenantId)
  }

  return { view, create, update, remove, reorder, saveSettings }
}
