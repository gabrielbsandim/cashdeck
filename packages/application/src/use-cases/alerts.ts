import { type Alert, ALERT_TYPES, type AlertType } from '@cashdeck/domain'
import { type z } from 'zod'
import {
  type AlertSettingsView,
  type AlertView,
  type DeviceView,
  type listAlertsQuerySchema,
  type registerDeviceSchema,
  toAlertView,
  toDeviceView,
  type updateAlertSettingsSchema,
} from '@/dtos/alerts'
import { type AlertEmitter, type AlertInput } from '@/ports/alerts'
import { type DocumentStore } from '@/ports/records'
import { type Page } from '@/ports/repositories'
import { ALERT_TEXTS } from '@/use-cases/alert-events'
import { type Deps } from '@/use-cases/deps'
import { required } from '@/use-cases/shared'

export const ALERT_SETTINGS_COLLECTION = 'alert-settings'
const SETTINGS_ID = 'default'

type StoredAlertSettings = { muted: AlertType[] }

export async function mutedAlertTypes(
  documents: DocumentStore,
  tenantId: string,
): Promise<AlertType[]> {
  const stored = await documents.get<StoredAlertSettings>(
    tenantId,
    ALERT_SETTINGS_COLLECTION,
    SETTINGS_ID,
  )
  return stored?.muted ?? []
}

function pushData(alert: Alert): Record<string, string> {
  const refs = {
    alertId: alert.id,
    entityId: alert.entityId,
    billId: alert.billId,
    invoiceId: alert.invoiceId,
  }
  const present = Object.entries(refs).filter(
    (entry): entry is [string, string] => entry[1] !== null,
  )
  return { ...alert.data, ...Object.fromEntries(present) }
}

export type AlertEmitterDeps = Pick<
  Deps,
  'alertStore' | 'documents' | 'notifier' | 'audit' | 'clock' | 'ids'
>

// Every alert lands in the inbox; a muted type only skips the push.
export function makeAlertEmitter(deps: AlertEmitterDeps): AlertEmitter {
  function build(input: AlertInput): Alert {
    const text = ALERT_TEXTS[input.type](input.data)
    return {
      id: deps.ids.next(),
      tenantId: input.tenantId,
      type: input.type,
      entityId: input.entityId ?? null,
      billId: input.billId ?? null,
      invoiceId: input.invoiceId ?? null,
      title: text.title,
      body: text.body,
      data: input.data,
      dedupeKey: input.dedupeKey ?? null,
      createdAt: deps.clock.now(),
      readAt: null,
    }
  }

  async function push(alert: Alert): Promise<void> {
    const muted = await mutedAlertTypes(deps.documents, alert.tenantId)
    if (muted.includes(alert.type)) {
      return
    }
    const failure = await deps.notifier
      .notify({
        tenantId: alert.tenantId,
        type: alert.type,
        title: alert.title,
        body: alert.body,
        data: pushData(alert),
      })
      .then(
        () => null,
        (error: unknown) => String(error),
      )
    await deps.audit.record({
      id: deps.ids.next(),
      tenantId: alert.tenantId,
      actor: 'SYSTEM',
      action: 'alert.push',
      subjectId: alert.id,
      rail: null,
      result: failure === null ? 'SENT' : 'FAILED',
      details: { type: alert.type, reason: failure },
      at: deps.clock.now(),
    })
  }

  return {
    async emit(input: AlertInput): Promise<Alert | null> {
      try {
        const alert = build(input)
        if (!(await deps.alertStore.add(alert))) {
          return null
        }
        await push(alert)
        return alert
      } catch {
        // The payment or capture that raised the alert already happened.
        return null
      }
    },
  }
}

export function makeAlerts(
  deps: Pick<Deps, 'alertStore' | 'devices' | 'documents' | 'clock'>,
) {
  async function settings(tenantId: string): Promise<AlertSettingsView> {
    const muted = await mutedAlertTypes(deps.documents, tenantId)
    return {
      types: ALERT_TYPES.map(type => ({ type, muted: muted.includes(type) })),
    }
  }

  return {
    async list(
      tenantId: string,
      query: z.infer<typeof listAlertsQuerySchema>,
    ): Promise<Page<AlertView>> {
      const page = await deps.alertStore.list(
        tenantId,
        { unreadOnly: query.unread === 'true' },
        { cursor: query.cursor, limit: query.limit },
      )
      return { items: page.items.map(toAlertView), nextCursor: page.nextCursor }
    },

    async unreadCount(tenantId: string): Promise<{ unread: number }> {
      return { unread: await deps.alertStore.unreadCount(tenantId) }
    },

    async markRead(tenantId: string, id: string): Promise<AlertView> {
      const alert = required(
        await deps.alertStore.findById(tenantId, id),
        'Alert',
      )
      const at = alert.readAt ?? deps.clock.now()
      await deps.alertStore.markRead(tenantId, id, at)
      return toAlertView({ ...alert, readAt: at })
    },

    async markAllRead(tenantId: string): Promise<{ updated: number }> {
      return {
        updated: await deps.alertStore.markAllRead(tenantId, deps.clock.now()),
      }
    },

    settings,

    async updateSettings(
      tenantId: string,
      input: z.infer<typeof updateAlertSettingsSchema>,
    ): Promise<AlertSettingsView> {
      const current = new Set(await mutedAlertTypes(deps.documents, tenantId))
      const changes = Object.entries(input.muted) as Array<[AlertType, boolean]>
      for (const [type, muted] of changes) {
        if (muted) {
          current.add(type)
          continue
        }
        current.delete(type)
      }
      await deps.documents.put<StoredAlertSettings>(
        tenantId,
        ALERT_SETTINGS_COLLECTION,
        SETTINGS_ID,
        { muted: ALERT_TYPES.filter(type => current.has(type)) },
      )
      return settings(tenantId)
    },

    async registerDevice(
      tenantId: string,
      input: z.infer<typeof registerDeviceSchema>,
    ): Promise<DeviceView> {
      const now = deps.clock.now()
      const known = (await deps.devices.list(tenantId)).find(
        device => device.token === input.token,
      )
      const device = {
        tenantId,
        token: input.token,
        platform: input.platform,
        createdAt: known?.createdAt ?? now,
        lastSeenAt: now,
      }
      await deps.devices.register(device)
      return toDeviceView(device)
    },

    async removeDevice(
      tenantId: string,
      token: string,
    ): Promise<{ removed: boolean }> {
      return { removed: await deps.devices.remove(tenantId, token) }
    },
  }
}
