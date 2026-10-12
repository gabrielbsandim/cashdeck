import { type Goal, type GoalContribution } from '@cashdeck/domain'
import { type GoalRepository } from '@/ports/planning'

export class InMemoryGoalRepository implements GoalRepository {
  private readonly goals = new Map<string, Goal>()
  private readonly contributions = new Map<string, GoalContribution>()

  async list(tenantId: string): Promise<Goal[]> {
    return [...this.goals.values()].filter(goal => goal.tenantId === tenantId)
  }

  async findById(tenantId: string, id: string): Promise<Goal | null> {
    const goal = this.goals.get(id)
    return goal?.tenantId === tenantId ? goal : null
  }

  async save(goal: Goal): Promise<void> {
    this.goals.set(goal.id, goal)
  }

  async delete(tenantId: string, id: string): Promise<void> {
    if (this.goals.get(id)?.tenantId !== tenantId) {
      return
    }
    this.goals.delete(id)
    for (const contribution of await this.listContributions(tenantId, id)) {
      this.contributions.delete(contribution.id)
    }
  }

  async listContributions(
    tenantId: string,
    goalId: string,
  ): Promise<GoalContribution[]> {
    return [...this.contributions.values()]
      .filter(item => item.tenantId === tenantId && item.goalId === goalId)
      .sort(
        (a, b) =>
          a.on.localeCompare(b.on) ||
          a.createdAt.getTime() - b.createdAt.getTime(),
      )
  }

  async saveContribution(contribution: GoalContribution): Promise<void> {
    this.contributions.set(contribution.id, contribution)
  }

  async deleteContribution(tenantId: string, id: string): Promise<void> {
    if (this.contributions.get(id)?.tenantId === tenantId) {
      this.contributions.delete(id)
    }
  }
}
