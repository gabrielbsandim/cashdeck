import { updateGoalSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route<{ id: string }>(
  'goals:get',
  async ({ tenantId, params, container }) =>
    ok(await container.goals.get(tenantId, params.id)),
)

export const PATCH = route<{ id: string }>(
  'goals:update',
  async ({ request, tenantId, params, container }) => {
    const input = updateGoalSchema.parse(await readJson(request))
    return ok(await container.goals.update(tenantId, params.id, input))
  },
)

export const DELETE = route<{ id: string }>(
  'goals:remove',
  async ({ tenantId, params, container }) =>
    ok(await container.goals.remove(tenantId, params.id)),
)
