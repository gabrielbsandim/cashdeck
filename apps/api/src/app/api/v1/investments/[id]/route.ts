import { investmentDetailQuerySchema } from '@cashdeck/application'
import { route, searchParams } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route<{ id: string }>(
  'investments:get',
  async ({ request, tenantId, params, container }) => {
    const query = investmentDetailQuerySchema.parse(searchParams(request))
    return ok(
      await container.investmentPerformance.detail(
        tenantId,
        params.id,
        query.period,
      ),
    )
  },
)
