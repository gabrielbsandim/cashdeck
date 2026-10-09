import { z } from 'zod'
import { ALERT_TYPES, type Alert } from '@cashdeck/domain'
import { pageQuerySchema } from '@/dtos/common'
import { DEVICE_PLATFORMS, type DeviceToken } from '@/ports/alerts'

export const alertTypeSchema = z.enum(ALERT_TYPES)

export const alertViewSchema = z.object({
  id: z.string(),
  type: alertTypeSchema,
  entityId: z.string().nullable(),
  billId: z.string().nullable(),
  invoiceId: z.string().nullable(),
  title: z.string(),
  body: z.string(),
  data: z.record(z.string(), z.string()),
  createdAt: z.string(),
  readAt: z.string().nullable(),
})

export type AlertView = z.infer<typeof alertViewSchema>

export const listAlertsQuerySchema = pageQuerySchema.extend({
  unread: z.enum(['true', 'false']).optional(),
})

export const unreadCountViewSchema = z.object({ unread: z.int() })

export const readAllViewSchema = z.object({ updated: z.int() })

export const alertSettingsViewSchema = z.object({
  types: z.array(z.object({ type: alertTypeSchema, muted: z.boolean() })),
})

export type AlertSettingsView = z.infer<typeof alertSettingsViewSchema>

export const updateAlertSettingsSchema = z.object({
  muted: z.partialRecord(alertTypeSchema, z.boolean()),
})

export const registerDeviceSchema = z.object({
  token: z.string().trim().min(1).max(4096),
  platform: z.enum(DEVICE_PLATFORMS),
})

export const deviceViewSchema = z.object({
  token: z.string(),
  platform: z.enum(DEVICE_PLATFORMS),
  createdAt: z.string(),
  lastSeenAt: z.string(),
})

export type DeviceView = z.infer<typeof deviceViewSchema>

export const removeDeviceViewSchema = z.object({ removed: z.boolean() })

export function toAlertView(alert: Alert): AlertView {
  return {
    id: alert.id,
    type: alert.type,
    entityId: alert.entityId,
    billId: alert.billId,
    invoiceId: alert.invoiceId,
    title: alert.title,
    body: alert.body,
    data: { ...alert.data },
    createdAt: alert.createdAt.toISOString(),
    readAt: alert.readAt?.toISOString() ?? null,
  }
}

export function toDeviceView(device: DeviceToken): DeviceView {
  return {
    token: device.token,
    platform: device.platform,
    createdAt: device.createdAt.toISOString(),
    lastSeenAt: device.lastSeenAt.toISOString(),
  }
}
