import { spendingPlanInputSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const PUT = route(
  'home:spending-plan',
  async ({ request, tenantId, container }) => {
    const input = spendingPlanInputSchema.parse(await readJson(request))
    return ok(await container.setSpendingPlan(tenantId, input))
  },
)
