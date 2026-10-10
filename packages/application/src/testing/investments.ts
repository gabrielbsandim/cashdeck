import {
  type InvestmentPosition,
  type InvestmentRepository,
} from '@/ports/investments'

const keyOf = (position: InvestmentPosition) =>
  `${position.tenantId}:${position.connectionId}:${position.externalId}`

export class InMemoryInvestmentRepository implements InvestmentRepository {
  private readonly rows = new Map<string, InvestmentPosition>()

  async saveAll(positions: readonly InvestmentPosition[]): Promise<void> {
    for (const position of positions) {
      const known = this.rows.get(keyOf(position))
      this.rows.set(keyOf(position), {
        ...position,
        id: known?.id ?? position.id,
      })
    }
  }

  async list(tenantId: string): Promise<InvestmentPosition[]> {
    return [...this.rows.values()].filter(row => row.tenantId === tenantId)
  }

  async deleteByConnection(
    tenantId: string,
    connectionId: string,
  ): Promise<void> {
    for (const [key, row] of this.rows) {
      if (row.tenantId === tenantId && row.connectionId === connectionId) {
        this.rows.delete(key)
      }
    }
  }
}
