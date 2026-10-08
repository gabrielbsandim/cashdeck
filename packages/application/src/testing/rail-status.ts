import { type RailId } from '@cashdeck/domain'
import {
  type RailStatus,
  type RailStatusReader,
  type RailStatusScope,
} from '@/ports/rail-status'

export class FakeRailStatusReader implements RailStatusReader {
  readonly asked: string[] = []
  private readonly statuses = new Map<string, RailStatus>()

  constructor(readonly id: RailId) {}

  willReport(externalId: string, status: RailStatus): this {
    this.statuses.set(externalId, status)
    return this
  }

  async status(
    externalId: string,
    _scope: RailStatusScope,
  ): Promise<RailStatus> {
    this.asked.push(externalId)
    return (
      this.statuses.get(externalId) ?? {
        outcome: 'SUBMITTED',
        externalId,
        endToEndId: null,
        settledAt: null,
      }
    )
  }
}
