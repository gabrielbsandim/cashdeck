import { type DeviceSession, isSessionActive } from '@cashdeck/domain'
import {
  type DeviceSessionRepository,
  type SessionTokens,
} from '@/ports/sessions'

export class InMemoryDeviceSessionRepository implements DeviceSessionRepository {
  private readonly rows = new Map<string, DeviceSession>()

  async findByTokenHash(
    tenantId: string,
    tokenHash: string,
  ): Promise<DeviceSession | null> {
    const row = [...this.rows.values()].find(
      session => session.tokenHash === tokenHash,
    )
    return row?.tenantId === tenantId ? row : null
  }

  async findById(tenantId: string, id: string): Promise<DeviceSession | null> {
    const row = this.rows.get(id)
    return row?.tenantId === tenantId ? row : null
  }

  async listActive(tenantId: string, now: Date): Promise<DeviceSession[]> {
    return [...this.rows.values()]
      .filter(row => row.tenantId === tenantId && isSessionActive(row, now))
      .sort((a, b) => b.lastUsedAt.getTime() - a.lastUsedAt.getTime())
  }

  async save(session: DeviceSession): Promise<void> {
    this.rows.set(session.id, session)
  }
}

// Readable tokens and hashes, so a test can tell what was stored.
export class FakeSessionTokens implements SessionTokens {
  private counter = 0

  issue(): string {
    this.counter += 1
    return `session-token-${this.counter}`
  }

  hash(token: string): string {
    return `hash(${token})`
  }
}
