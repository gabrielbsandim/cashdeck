import { monthlyInsightsQuerySchema } from '@cashdeck/application'
import { route, searchParams } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route(
  'insights:months',
  async ({ request, tenantId, container }) => {
    const query = monthlyInsightsQuerySchema.parse(searchParams(request))
    return ok(await container.monthlyInsights(tenantId, query))
  },
)
