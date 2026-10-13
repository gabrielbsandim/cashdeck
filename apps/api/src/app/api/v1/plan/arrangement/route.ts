import { planArrangementSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const PUT = route(
  'plan:arrange',
  async ({ request, tenantId, container }) => {
    const input = planArrangementSchema.parse(await readJson(request))
    return ok(await container.planAdvice.apply(tenantId, input))
  },
)
