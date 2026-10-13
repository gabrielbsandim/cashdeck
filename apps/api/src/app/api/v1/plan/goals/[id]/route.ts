import { planGoalInputSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const PUT = route<{ id: string }>(
  'plan:update',
  async ({ request, tenantId, params, container }) => {
    const input = planGoalInputSchema.parse(await readJson(request))
    return ok(await container.lifePlan.update(tenantId, params.id, input))
  },
)

export const DELETE = route<{ id: string }>(
  'plan:remove',
  async ({ tenantId, params, container }) =>
    ok(await container.lifePlan.remove(tenantId, params.id)),
)
