import { planOrderSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const PUT = route(
  'plan:reorder',
  async ({ request, tenantId, container }) => {
    const input = planOrderSchema.parse(await readJson(request))
    return ok(await container.lifePlan.reorder(tenantId, input))
  },
)
