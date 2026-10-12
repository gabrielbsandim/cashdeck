import { type Goal, type GoalContribution } from '@cashdeck/domain'

export interface GoalRepository {
  list(tenantId: string): Promise<Goal[]>
  findById(tenantId: string, id: string): Promise<Goal | null>
  save(goal: Goal): Promise<void>
  // Drops its contributions too.
  delete(tenantId: string, id: string): Promise<void>
  // Oldest first.
  listContributions(
    tenantId: string,
    goalId: string,
  ): Promise<GoalContribution[]>
  saveContribution(contribution: GoalContribution): Promise<void>
  deleteContribution(tenantId: string, id: string): Promise<void>
}
