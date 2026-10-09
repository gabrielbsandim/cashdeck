import { type Alert, type AlertType } from '@cashdeck/domain'
import { type Page, type PageRequest } from '@/ports/repositories'

export type AlertFilter = { unreadOnly?: boolean }

export interface AlertRepository {
  // False when an alert with the same dedupe key is already stored.
  add(alert: Alert): Promise<boolean>
  findById(tenantId: string, id: string): Promise<Alert | null>
  // Newest first.
  list(
    tenantId: string,
    filter: AlertFilter,
    page: PageRequest,
  ): Promise<Page<Alert>>
  markRead(tenantId: string, id: string, at: Date): Promise<void>
  markAllRead(tenantId: string, at: Date): Promise<number>
  unreadCount(tenantId: string): Promise<number>
  // Marks read the unread alerts of one bill with these types.
  markBillRead(
    tenantId: string,
    billId: string,
    types: readonly AlertType[],
    at: Date,
  ): Promise<number>
}

export const DEVICE_PLATFORMS = ['ANDROID', 'IOS', 'WEB'] as const
export type DevicePlatform = (typeof DEVICE_PLATFORMS)[number]

export type DeviceToken = {
  tenantId: string
  token: string
  platform: DevicePlatform
  createdAt: Date
  lastSeenAt: Date
}

export interface DeviceTokenRepository {
  // Registering a known token refreshes it; a token belongs to one tenant.
  register(device: DeviceToken): Promise<void>
  remove(tenantId: string, token: string): Promise<boolean>
  list(tenantId: string): Promise<DeviceToken[]>
}

export type AlertInput = {
  tenantId: string
  type: AlertType
  entityId?: string | null
  billId?: string | null
  invoiceId?: string | null
  data: Record<string, string>
  dedupeKey?: string | null
}

// Never throws: an alert is a side note to the work that raised it.
export interface AlertEmitter {
  emit(input: AlertInput): Promise<Alert | null>
}
