import {
  type Goal as GoalRow,
  type GoalContribution as ContributionRow,
  type PrismaClient,
} from '@prisma/client'
import {
  type BudgetLimit,
  type BudgetRepository,
  type GoalRepository,
} from '@cashdeck/application'
import {
  type Budget,
  budgetAvailable,
  type Goal,
  type GoalContribution,
  Money,
} from '@cashdeck/domain'
import { fromDbDate, toDbDate } from '@/repositories/mappers'

type BudgetRow = {
  id: string
  tenantId: string
  entityId: string
  categoryId: string
  month: string
  limitCents: bigint
  carriedCents: bigint
  rollover: boolean
}

export function goalFromRow(row: GoalRow): Goal {
  return {
    id: row.id,
    tenantId: row.tenantId,
    entityId: row.entityId,
    name: row.name,
    target: Money.of(Number(row.targetCents)),
    deadline: row.deadline ? fromDbDate(row.deadline) : null,
    accountId: row.accountId,
    investmentId: row.investmentId,
    icon: row.icon,
    color: row.color,
    createdAt: row.createdAt,
    archivedAt: row.archivedAt,
  }
}

export function goalToRow(goal: Goal): GoalRow {
  return {
    id: goal.id,
    tenantId: goal.tenantId,
    entityId: goal.entityId,
    name: goal.name,
    targetCents: BigInt(goal.target.cents),
    deadline: goal.deadline ? toDbDate(goal.deadline) : null,
    accountId: goal.accountId,
    investmentId: goal.investmentId,
    icon: goal.icon,
    color: goal.color,
    createdAt: goal.createdAt,
    archivedAt: goal.archivedAt,
  }
}

function contributionFromRow(row: ContributionRow): GoalContribution {
  return {
    id: row.id,
    tenantId: row.tenantId,
    goalId: row.goalId,
    amount: Money.of(Number(row.amountCents)),
    on: fromDbDate(row.on),
    note: row.note,
    createdAt: row.createdAt,
  }
}

export class PrismaGoalRepository implements GoalRepository {
  constructor(private readonly db: PrismaClient) {}

  async list(tenantId: string): Promise<Goal[]> {
    const rows = await this.db.goal.findMany({
      where: { tenantId },
      orderBy: [{ createdAt: 'asc' }, { id: 'asc' }],
    })
    return rows.map(goalFromRow)
  }

  async findById(tenantId: string, id: string): Promise<Goal | null> {
    const row = await this.db.goal.findFirst({ where: { tenantId, id } })
    return row ? goalFromRow(row) : null
  }

  async save(goal: Goal): Promise<void> {
    const row = goalToRow(goal)
    await this.db.goal.upsert({
      where: { id: goal.id },
      create: row,
      update: row,
    })
  }

  async delete(tenantId: string, id: string): Promise<void> {
    await this.db.goalContribution.deleteMany({
      where: { tenantId, goalId: id },
    })
    await this.db.goal.deleteMany({ where: { tenantId, id } })
  }

  async listContributions(
    tenantId: string,
    goalId: string,
  ): Promise<GoalContribution[]> {
    const rows = await this.db.goalContribution.findMany({
      where: { tenantId, goalId },
      orderBy: [{ on: 'asc' }, { createdAt: 'asc' }],
    })
    return rows.map(contributionFromRow)
  }

  async saveContribution(contribution: GoalContribution): Promise<void> {
    await this.db.goalContribution.create({
      data: {
        id: contribution.id,
        tenantId: contribution.tenantId,
        goalId: contribution.goalId,
        amountCents: BigInt(contribution.amount.cents),
        on: toDbDate(contribution.on),
        note: contribution.note,
        createdAt: contribution.createdAt,
      },
    })
  }

  async deleteContribution(tenantId: string, id: string): Promise<void> {
    await this.db.goalContribution.deleteMany({ where: { tenantId, id } })
  }
}

function budgetFromRow(row: BudgetRow): Budget {
  return {
    id: row.id,
    tenantId: row.tenantId,
    entityId: row.entityId,
    categoryId: row.categoryId,
    month: row.month,
    limit: Money.of(Number(row.limitCents)),
    carried: Money.of(Number(row.carriedCents)),
    rollover: row.rollover,
  }
}

export class PrismaBudgetRepository implements BudgetRepository {
  constructor(private readonly db: PrismaClient) {}

  async list(
    tenantId: string,
    entityId: string,
    month: string,
  ): Promise<BudgetLimit[]> {
    const budgets = await this.listMonth(tenantId, entityId, month)
    const categories = await this.db.category.findMany({
      where: { tenantId, id: { in: budgets.map(budget => budget.categoryId) } },
    })
    const names = new Map(
      categories.map(category => [category.id, category.name]),
    )
    return budgets.map(budget => ({
      categoryId: budget.categoryId,
      categoryName: names.get(budget.categoryId) ?? budget.categoryId,
      limit: budgetAvailable(budget),
    }))
  }

  async listMonth(
    tenantId: string,
    entityId: string,
    month: string,
  ): Promise<Budget[]> {
    const rows = await this.db.budget.findMany({
      where: { tenantId, entityId, month },
      orderBy: { categoryId: 'asc' },
    })
    return rows.map(budgetFromRow)
  }

  async findById(tenantId: string, id: string): Promise<Budget | null> {
    const row = await this.db.budget.findFirst({ where: { tenantId, id } })
    return row ? budgetFromRow(row) : null
  }

  async save(budget: Budget): Promise<void> {
    const row = {
      id: budget.id,
      tenantId: budget.tenantId,
      entityId: budget.entityId,
      categoryId: budget.categoryId,
      month: budget.month,
      limitCents: BigInt(budget.limit.cents),
      carriedCents: BigInt(budget.carried.cents),
      rollover: budget.rollover,
    }
    await this.db.budget.upsert({
      where: { id: budget.id },
      create: row,
      update: row,
    })
  }

  async delete(tenantId: string, id: string): Promise<void> {
    await this.db.budget.deleteMany({ where: { tenantId, id } })
  }
}

export function createPrismaPlanning(db: PrismaClient) {
  return {
    goals: new PrismaGoalRepository(db),
    budgets: new PrismaBudgetRepository(db),
  }
}
