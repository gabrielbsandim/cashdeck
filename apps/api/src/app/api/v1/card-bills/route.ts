import { insightsScopeQuerySchema } from '@cashdeck/application'
import { route, searchParams } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route(
  'card-bills:list',
  async ({ request, tenantId, container }) => {
    const query = insightsScopeQuerySchema.parse(searchParams(request))
    return ok(await container.listCardBills(tenantId, query.entity))
  },
)
