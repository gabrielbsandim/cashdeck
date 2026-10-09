import { type Alert, type AlertType, markAlertRead } from '@cashdeck/domain'
import {
  type AlertEmitter,
  type AlertFilter,
  type AlertInput,
  type AlertRepository,
  type DeviceToken,
  type DeviceTokenRepository,
} from '@/ports/alerts'
import { type Page, type PageRequest } from '@/ports/repositories'

export class InMemoryAlertRepository implements AlertRepository {
  private readonly rows: Alert[] = []

  async add(alert: Alert): Promise<boolean> {
    const duplicate = this.rows.some(
      row =>
        row.tenantId === alert.tenantId &&
        alert.dedupeKey !== null &&
        row.dedupeKey === alert.dedupeKey,
    )
    if (duplicate) {
      return false
    }
    this.rows.push(alert)
    return true
  }

  async findById(tenantId: string, id: string): Promise<Alert | null> {
    return this.of(tenantId).find(row => row.id === id) ?? null
  }

  async list(
    tenantId: string,
    filter: AlertFilter,
    page: PageRequest,
  ): Promise<Page<Alert>> {
    const matching = this.of(tenantId)
      .filter(row => !filter.unreadOnly || row.readAt === null)
      .sort(
        (a, b) =>
          b.createdAt.getTime() - a.createdAt.getTime() ||
          a.id.localeCompare(b.id),
      )
    const start = Number(page.cursor ?? 0)
    const items = matching.slice(start, start + page.limit)
    const end = start + items.length
    return { items, nextCursor: end < matching.length ? String(end) : null }
  }

  async markRead(tenantId: string, id: string, at: Date): Promise<void> {
    this.update(tenantId, row => row.id === id, at)
  }

  async markAllRead(tenantId: string, at: Date): Promise<number> {
    return this.update(tenantId, row => row.readAt === null, at)
  }

  async markBillRead(
    tenantId: string,
    billId: string,
    types: readonly AlertType[],
    at: Date,
  ): Promise<number> {
    return this.update(
      tenantId,
      row =>
        row.readAt === null &&
        row.billId === billId &&
        types.includes(row.type),
      at,
    )
  }

  async unreadCount(tenantId: string): Promise<number> {
    return this.of(tenantId).filter(row => row.readAt === null).length
  }

  private of(tenantId: string): Alert[] {
    return this.rows.filter(row => row.tenantId === tenantId)
  }

  private update(
    tenantId: string,
    matches: (row: Alert) => boolean,
    at: Date,
  ): number {
    let count = 0
    this.rows.forEach((row, index) => {
      if (row.tenantId !== tenantId || !matches(row)) {
        return
      }
      this.rows[index] = markAlertRead(row, at)
      count += 1
    })
    return count
  }
}

export class InMemoryDeviceTokenRepository implements DeviceTokenRepository {
  private readonly rows = new Map<string, DeviceToken>()

  async register(device: DeviceToken): Promise<void> {
    this.rows.set(device.token, device)
  }

  async remove(tenantId: string, token: string): Promise<boolean> {
    if (this.rows.get(token)?.tenantId !== tenantId) {
      return false
    }
    return this.rows.delete(token)
  }

  async list(tenantId: string): Promise<DeviceToken[]> {
    return [...this.rows.values()].filter(row => row.tenantId === tenantId)
  }
}

// Keeps what use cases emit, for assertions; answers like a fresh inbox.
export class RecordingAlertEmitter implements AlertEmitter {
  readonly emitted: AlertInput[] = []

  async emit(input: AlertInput): Promise<Alert | null> {
    const key = input.dedupeKey ?? null
    if (key !== null && this.emitted.some(row => row.dedupeKey === key)) {
      return null
    }
    this.emitted.push(input)
    return {
      id: `alert-${this.emitted.length}`,
      tenantId: input.tenantId,
      type: input.type,
      entityId: input.entityId ?? null,
      billId: input.billId ?? null,
      invoiceId: input.invoiceId ?? null,
      title: input.type,
      body: '',
      data: input.data,
      dedupeKey: input.dedupeKey ?? null,
      createdAt: new Date(0),
      readAt: null,
    }
  }

  types(): string[] {
    return this.emitted.map(input => input.type)
  }
}
