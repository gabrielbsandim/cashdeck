import { updateAutomationSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const PATCH = route(
  'automation:update',
  async ({ request, tenantId, container }) => {
    const input = updateAutomationSchema.parse(await readJson(request))
    return ok(await container.automation.update(tenantId, input))
  },
)
