import { listRailsQuerySchema } from '@cashdeck/application'
import { route, searchParams } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route(
  'rails:list',
  async ({ request, tenantId, container }) => {
    const query = listRailsQuerySchema.parse(searchParams(request))
    return ok(await container.rails.list(tenantId, query.entity))
  },
)
