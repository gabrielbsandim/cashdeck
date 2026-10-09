import { updateAlertSettingsSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route('alerts:settings', async ({ tenantId, container }) =>
  ok(await container.alerts.settings(tenantId)),
)

export const PATCH = route(
  'alerts:settings:update',
  async ({ request, tenantId, container }) => {
    const input = updateAlertSettingsSchema.parse(await readJson(request))
    return ok(await container.alerts.updateSettings(tenantId, input))
  },
)
