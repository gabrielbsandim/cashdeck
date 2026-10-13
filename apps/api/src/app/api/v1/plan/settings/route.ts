import { planSettingsSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const PUT = route(
  'plan:settings',
  async ({ request, tenantId, container }) => {
    const input = planSettingsSchema.parse(await readJson(request))
    return ok(await container.lifePlan.saveSettings(tenantId, input))
  },
)
