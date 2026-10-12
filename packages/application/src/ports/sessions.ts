import { type DeviceSession } from '@cashdeck/domain'

export interface DeviceSessionRepository {
  findByTokenHash(
    tenantId: string,
    tokenHash: string,
  ): Promise<DeviceSession | null>
  findById(tenantId: string, id: string): Promise<DeviceSession | null>
  // Not revoked and not expired at `now`, most recently used first.
  listActive(tenantId: string, now: Date): Promise<DeviceSession[]>
  save(session: DeviceSession): Promise<void>
}

// Bearer secrets for device sessions: random when issued, kept only hashed.
export interface SessionTokens {
  issue(): string
  hash(token: string): string
}
