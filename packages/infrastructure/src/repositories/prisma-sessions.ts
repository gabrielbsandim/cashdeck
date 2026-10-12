import { type PrismaClient } from '@prisma/client'
import { type DeviceSessionRepository } from '@cashdeck/application'
import { type DeviceSession, type SessionPlatform } from '@cashdeck/domain'

type SessionRow = Omit<DeviceSession, 'platform'> & { platform: string }

const sessionFromRow = (row: SessionRow): DeviceSession => ({
  ...row,
  platform: row.platform as SessionPlatform,
})

export class PrismaDeviceSessionRepository implements DeviceSessionRepository {
  constructor(private readonly db: PrismaClient) {}

  async findByTokenHash(
    tenantId: string,
    tokenHash: string,
  ): Promise<DeviceSession | null> {
    const row = await this.db.deviceSession.findFirst({
      where: { tenantId, tokenHash },
    })
    return row && sessionFromRow(row)
  }

  async findById(tenantId: string, id: string): Promise<DeviceSession | null> {
    const row = await this.db.deviceSession.findFirst({
      where: { tenantId, id },
    })
    return row && sessionFromRow(row)
  }

  async listActive(tenantId: string, now: Date): Promise<DeviceSession[]> {
    const rows = await this.db.deviceSession.findMany({
      where: { tenantId, revokedAt: null, expiresAt: { gt: now } },
      orderBy: { lastUsedAt: 'desc' },
    })
    return rows.map(sessionFromRow)
  }

  async save(session: DeviceSession): Promise<void> {
    await this.db.deviceSession.upsert({
      where: { id: session.id },
      create: session,
      update: session,
    })
  }
}
