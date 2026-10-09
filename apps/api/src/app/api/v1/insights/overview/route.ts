import { insightsOverviewQuerySchema } from '@cashdeck/application'
import { route, searchParams } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route(
  'insights:overview',
  async ({ request, tenantId, container }) => {
    const query = insightsOverviewQuerySchema.parse(searchParams(request))
    return ok(await container.insightsOverview(tenantId, query))
  },
)
