import { planAdviceInputSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'
export const maxDuration = 60

export const POST = route(
  'plan:advise',
  async ({ request, tenantId, container }) => {
    const input = planAdviceInputSchema.parse(await readJson(request))
    return ok(await container.planAdvice.advise(tenantId, input))
  },
)
