import { netWorthQuerySchema } from '@cashdeck/application'
import { route, searchParams } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route(
  'net-worth',
  async ({ request, tenantId, container }) => {
    const query = netWorthQuerySchema.parse(searchParams(request))
    return ok(await container.netWorth(tenantId, query))
  },
)
