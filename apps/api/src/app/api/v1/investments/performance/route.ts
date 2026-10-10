import { investmentPerformanceQuerySchema } from '@cashdeck/application'
import { route, searchParams } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route(
  'investments:performance',
  async ({ request, tenantId, container }) => {
    const query = investmentPerformanceQuerySchema.parse(searchParams(request))
    return ok(
      await container.investmentPerformance.performance(tenantId, query),
    )
  },
)
