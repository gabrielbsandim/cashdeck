import { planGoalInputSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const POST = route(
  'plan:create',
  async ({ request, tenantId, container }) => {
    const input = planGoalInputSchema.parse(await readJson(request))
    return ok(await container.lifePlan.create(tenantId, input), 201)
  },
)
