import {
  type Account,
  addDays,
  CASH_ACCOUNT_TYPES,
  contributedTotal,
  createContribution,
  createGoal,
  daysBetween,
  type FinancialEntity,
  type Goal,
  goalProgress,
  goalSource,
  type LocalDate,
  MIN_PACE_DAYS,
  Money,
  monthlyPace,
  PACE_WINDOW_DAYS,
  paceWindowDays,
  ValidationError,
} from '@cashdeck/domain'
import { money } from '@/dtos/common'
import {
  type ContributionInput,
  type CreateGoalInput,
  type GoalDetail,
  type GoalQuery,
  type GoalView,
  toContributionView,
  type UpdateGoalInput,
} from '@/dtos/goals'
import { type AuditEvent } from '@/ports/repositories'
import { type Deps } from '@/use-cases/deps'
import {
  required,
  requireEntity,
  requireEntityById,
  today,
} from '@/use-cases/shared'

export type GoalDeps = Pick<
  Deps,
  | 'entities'
  | 'accounts'
  | 'transactions'
  | 'investments'
  | 'goals'
  | 'audit'
  | 'clock'
  | 'ids'
>

const LINKABLE_TYPES: readonly Account['type'][] = [
  ...CASH_ACCOUNT_TYPES,
  'INVESTMENT',
]

// What a goal holds and how fast it grew lately; a null pace means it is
// too new to tell.
type Measure = { saved: Money; pace: Money | null; linkedName: string | null }

const UNLINKED: Measure = { saved: Money.zero(), pace: null, linkedName: null }

const or = <T>(value: T | undefined, fallback: T): T =>
  value === undefined ? fallback : value

function archivedAt(current: Goal, archived: boolean | undefined, now: Date) {
  if (archived === undefined) {
    return current.archivedAt
  }
  return archived ? (current.archivedAt ?? now) : null
}

const sumOf = (amounts: readonly Money[]) =>
  amounts.reduce((total, amount) => total.add(amount), Money.zero())

export function makeGoals(deps: GoalDeps) {
  const day = () => today(deps.clock.now())

  async function audit(
    goal: Goal,
    event: Pick<AuditEvent, 'action' | 'result' | 'details'>,
  ) {
    await deps.audit.record({
      id: deps.ids.next(),
      tenantId: goal.tenantId,
      actor: 'USER',
      subjectId: goal.id,
      rail: null,
      at: deps.clock.now(),
      ...event,
    })
  }

  async function find(tenantId: string, id: string): Promise<Goal> {
    return required(await deps.goals.findById(tenantId, id), 'Goal')
  }

  // What was put in on the day the goal started was already saved, so it
  // sets the start and not the pace.
  async function manual(goal: Goal, on: LocalDate): Promise<Measure> {
    const contributions = await deps.goals.listContributions(
      goal.tenantId,
      goal.id,
    )
    const createdOn = today(goal.createdAt)
    const window = paceWindowDays(createdOn, on)
    const start = addDays(on, -window)
    const recent = contributions.filter(
      item => item.on > start && item.on > createdOn,
    )
    const pace = monthlyPace(contributedTotal(recent), window)
    const young = daysBetween(createdOn, on) < MIN_PACE_DAYS
    return {
      saved: contributedTotal(contributions),
      pace: young && !pace.isPositive() ? null : pace,
      linkedName: null,
    }
  }

  async function account(goal: Goal, on: LocalDate): Promise<Measure> {
    const id = goal.accountId as string
    const linked = await deps.accounts.findById(goal.tenantId, id)
    if (!linked) {
      return UNLINKED
    }
    const moved = await deps.transactions.all(goal.tenantId, {
      accountIds: [id],
      from: addDays(on, 1 - PACE_WINDOW_DAYS),
      to: on,
    })
    return {
      saved: linked.balance,
      pace: monthlyPace(sumOf(moved.map(tx => tx.amount)), PACE_WINDOW_DAYS),
      linkedName: linked.name,
    }
  }

  async function investment(goal: Goal, on: LocalDate): Promise<Measure> {
    const id = goal.investmentId as string
    const positions = await deps.investments.list(goal.tenantId)
    const position = positions.find(item => item.id === id)
    if (!position) {
      return UNLINKED
    }
    const snapshots = await deps.investments.listSnapshots(
      goal.tenantId,
      { from: addDays(on, -PACE_WINDOW_DAYS), to: on },
      id,
    )
    const first = [...snapshots].sort((a, b) => a.day.localeCompare(b.day))[0]
    const window = first
      ? Math.max(MIN_PACE_DAYS, daysBetween(first.day, on))
      : 0
    return {
      saved: position.balance,
      pace: first
        ? monthlyPace(
            Money.of(position.balance.cents - first.balanceCents),
            window,
          )
        : null,
      linkedName: position.name,
    }
  }

  function measure(goal: Goal, on: LocalDate): Promise<Measure> {
    switch (goalSource(goal)) {
      case 'ACCOUNT':
        return account(goal, on)
      case 'INVESTMENT':
        return investment(goal, on)
      case 'MANUAL':
        return manual(goal, on)
    }
  }

  async function view(goal: Goal, entity: FinancialEntity): Promise<GoalView> {
    const on = day()
    const { saved, pace, linkedName } = await measure(goal, on)
    const progress = goalProgress({
      target: goal.target,
      saved,
      deadline: goal.deadline,
      today: on,
      pace,
    })
    return {
      id: goal.id,
      entity: entity.kind,
      name: goal.name,
      icon: goal.icon,
      color: goal.color,
      target: money(goal.target),
      saved: money(saved),
      remaining: money(progress.remaining),
      percent: progress.percent,
      status: progress.status,
      deadline: goal.deadline,
      requiredMonthly:
        progress.requiredMonthly && money(progress.requiredMonthly),
      monthlyPace: progress.monthlyPace && money(progress.monthlyPace),
      projectedOn: progress.projectedOn,
      source: goalSource(goal),
      accountId: goal.accountId,
      investmentId: goal.investmentId,
      linkedName,
      createdAt: goal.createdAt.toISOString(),
      archivedAt: goal.archivedAt?.toISOString() ?? null,
    }
  }

  async function detail(goal: Goal): Promise<GoalDetail> {
    const entity = await requireEntityById(
      deps.entities,
      goal.tenantId,
      goal.entityId,
    )
    const contributions =
      goalSource(goal) === 'MANUAL'
        ? await deps.goals.listContributions(goal.tenantId, goal.id)
        : []
    return {
      ...(await view(goal, entity)),
      contributions: [...contributions].reverse().map(toContributionView),
    }
  }

  async function assertAccount(goal: Goal, id: string): Promise<void> {
    const linked = required(
      await deps.accounts.findById(goal.tenantId, id),
      'Account',
    )
    const fits =
      linked.entityId === goal.entityId &&
      LINKABLE_TYPES.includes(linked.type) &&
      linked.balance.currency === goal.target.currency
    if (!fits) {
      throw new ValidationError('This account cannot hold the goal.')
    }
  }

  async function assertInvestment(goal: Goal, id: string): Promise<void> {
    const positions = await deps.investments.list(goal.tenantId)
    const position = required(
      positions.find(item => item.id === id) ?? null,
      'Investment',
    )
    if (position.entityId !== goal.entityId) {
      throw new ValidationError('This investment cannot hold the goal.')
    }
  }

  // A goal follows an account or investment of its own entity, in reais.
  async function assertLinks(goal: Goal): Promise<void> {
    switch (goalSource(goal)) {
      case 'ACCOUNT':
        return assertAccount(goal, goal.accountId as string)
      case 'INVESTMENT':
        return assertInvestment(goal, goal.investmentId as string)
      case 'MANUAL':
        return
    }
  }

  async function list(tenantId: string, query: GoalQuery): Promise<GoalView[]> {
    const entities = (await deps.entities.list(tenantId)).filter(
      entity => !query.entity || entity.kind === query.entity,
    )
    const archived = query.archived === 'true'
    const goals = (await deps.goals.list(tenantId))
      .filter(goal => (goal.archivedAt !== null) === archived)
      .sort((a, b) => a.createdAt.getTime() - b.createdAt.getTime())
    const views: GoalView[] = []
    for (const goal of goals) {
      const entity = entities.find(item => item.id === goal.entityId)
      if (!entity) {
        continue
      }
      views.push(await view(goal, entity))
    }
    return views
  }

  async function get(tenantId: string, id: string): Promise<GoalDetail> {
    return detail(await find(tenantId, id))
  }

  async function create(
    tenantId: string,
    input: CreateGoalInput,
  ): Promise<GoalDetail> {
    const entity = await requireEntity(deps.entities, tenantId, input.entity)
    const goal = createGoal({
      id: deps.ids.next(),
      tenantId,
      entityId: entity.id,
      name: input.name,
      target: Money.of(input.targetCents),
      deadline: input.deadline,
      accountId: input.accountId,
      investmentId: input.investmentId,
      icon: input.icon,
      color: input.color,
      createdAt: deps.clock.now(),
    })
    await assertLinks(goal)
    if (input.initialCents && goalSource(goal) !== 'MANUAL') {
      throw new ValidationError('A linked goal reads its balance instead.')
    }
    await deps.goals.save(goal)
    if (input.initialCents) {
      await deps.goals.saveContribution(
        createContribution({
          id: deps.ids.next(),
          tenantId,
          goalId: goal.id,
          amount: Money.of(input.initialCents),
          on: today(goal.createdAt),
          createdAt: goal.createdAt,
        }),
      )
    }
    await audit(goal, {
      action: 'goal.create',
      result: 'CREATED',
      details: { source: goalSource(goal), targetCents: input.targetCents },
    })
    return detail(goal)
  }

  async function update(
    tenantId: string,
    id: string,
    input: UpdateGoalInput,
  ): Promise<GoalDetail> {
    const current = await find(tenantId, id)
    const updated = createGoal({
      ...current,
      name: or(input.name, current.name),
      target:
        input.targetCents === undefined
          ? current.target
          : Money.of(input.targetCents),
      deadline: or(input.deadline, current.deadline),
      accountId: or(input.accountId, current.accountId),
      investmentId: or(input.investmentId, current.investmentId),
      icon: or(input.icon, current.icon),
      color: or(input.color, current.color),
      archivedAt: archivedAt(current, input.archived, deps.clock.now()),
    })
    await assertLinks(updated)
    await deps.goals.save(updated)
    await audit(updated, {
      action: 'goal.update',
      result: 'UPDATED',
      details: { fields: Object.keys(input) },
    })
    return detail(updated)
  }

  async function remove(tenantId: string, id: string): Promise<{ id: string }> {
    const goal = await find(tenantId, id)
    await deps.goals.delete(tenantId, id)
    await audit(goal, {
      action: 'goal.delete',
      result: 'DELETED',
      details: { name: goal.name },
    })
    return { id }
  }

  async function contribute(
    tenantId: string,
    id: string,
    input: ContributionInput,
  ): Promise<GoalDetail> {
    const goal = await find(tenantId, id)
    if (goalSource(goal) !== 'MANUAL') {
      throw new ValidationError(
        'This goal follows a balance; move the money there instead.',
      )
    }
    const contribution = createContribution({
      id: deps.ids.next(),
      tenantId,
      goalId: goal.id,
      amount: Money.of(input.amountCents),
      on: input.on ?? day(),
      note: input.note,
      createdAt: deps.clock.now(),
    })
    await deps.goals.saveContribution(contribution)
    await audit(goal, {
      action: 'goal.contribute',
      result: 'CREATED',
      details: {
        contributionId: contribution.id,
        amountCents: input.amountCents,
      },
    })
    return detail(goal)
  }

  async function removeContribution(
    tenantId: string,
    id: string,
    contributionId: string,
  ): Promise<GoalDetail> {
    const goal = await find(tenantId, id)
    const contributions = await deps.goals.listContributions(tenantId, id)
    required(
      contributions.find(item => item.id === contributionId) ?? null,
      'Contribution',
    )
    await deps.goals.deleteContribution(tenantId, contributionId)
    await audit(goal, {
      action: 'goal.contribution.delete',
      result: 'DELETED',
      details: { contributionId },
    })
    return detail(goal)
  }

  return {
    list,
    get,
    create,
    update,
    remove,
    contribute,
    removeContribution,
  }
}
