import { type Prisma, type PrismaClient } from '@prisma/client'
import {
  type AlertFilter,
  type AlertRepository,
  type DevicePlatform,
  type DeviceToken,
  type DeviceTokenRepository,
  type Page,
  type PageRequest,
} from '@cashdeck/application'
import { type Alert, type AlertType } from '@cashdeck/domain'

type AlertRow = Omit<Alert, 'type' | 'data'> & {
  type: string
  data: Prisma.JsonValue
}

export function alertFromRow(row: AlertRow): Alert {
  return {
    ...row,
    type: row.type as AlertType,
    data: row.data as Record<string, string>,
  }
}

const NEWEST_FIRST = [{ createdAt: 'desc' as const }, { id: 'asc' as const }]

export class PrismaAlertRepository implements AlertRepository {
  constructor(private readonly db: PrismaClient) {}

  // The unique (tenant, dedupe key) index turns a repeat into a skipped row.
  async add(alert: Alert): Promise<boolean> {
    const result = await this.db.alert.createMany({
      data: [{ ...alert, data: alert.data as Prisma.InputJsonValue }],
      skipDuplicates: true,
    })
    return result.count === 1
  }

  async findById(tenantId: string, id: string): Promise<Alert | null> {
    const row = await this.db.alert.findFirst({ where: { tenantId, id } })
    return row && alertFromRow(row)
  }

  async list(
    tenantId: string,
    filter: AlertFilter,
    page: PageRequest,
  ): Promise<Page<Alert>> {
    const skip = Number(page.cursor ?? 0)
    const rows = await this.db.alert.findMany({
      where: { tenantId, readAt: filter.unreadOnly ? null : undefined },
      orderBy: NEWEST_FIRST,
      skip,
      take: page.limit + 1,
    })
    const items = rows.slice(0, page.limit).map(alertFromRow)
    const hasMore = rows.length > page.limit
    return { items, nextCursor: hasMore ? String(skip + items.length) : null }
  }

  async markRead(tenantId: string, id: string, at: Date): Promise<void> {
    await this.db.alert.updateMany({
      where: { tenantId, id, readAt: null },
      data: { readAt: at },
    })
  }

  async markAllRead(tenantId: string, at: Date): Promise<number> {
    const result = await this.db.alert.updateMany({
      where: { tenantId, readAt: null },
      data: { readAt: at },
    })
    return result.count
  }

  async unreadCount(tenantId: string): Promise<number> {
    return this.db.alert.count({ where: { tenantId, readAt: null } })
  }
}

type DeviceRow = Omit<DeviceToken, 'platform'> & { platform: string }

const deviceFromRow = (row: DeviceRow): DeviceToken => ({
  ...row,
  platform: row.platform as DevicePlatform,
})

export class PrismaDeviceTokenRepository implements DeviceTokenRepository {
  constructor(private readonly db: PrismaClient) {}

  async register(device: DeviceToken): Promise<void> {
    await this.db.deviceToken.upsert({
      where: { token: device.token },
      create: device,
      update: device,
    })
  }

  async remove(tenantId: string, token: string): Promise<boolean> {
    const result = await this.db.deviceToken.deleteMany({
      where: { tenantId, token },
    })
    return result.count > 0
  }

  async list(tenantId: string): Promise<DeviceToken[]> {
    const rows = await this.db.deviceToken.findMany({
      where: { tenantId },
      orderBy: { lastSeenAt: 'desc' },
    })
    return rows.map(deviceFromRow)
  }
}

export function createPrismaAlertStores(db: PrismaClient) {
  return {
    alertStore: new PrismaAlertRepository(db),
    devices: new PrismaDeviceTokenRepository(db),
  }
}
