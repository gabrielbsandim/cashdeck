import { syncQuerySchema } from '@cashdeck/application'
import { route, searchParams } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const POST = route<{ id: string }>(
  'open-finance:sync',
  async ({ request, tenantId, params, container }) => {
    const query = syncQuerySchema.parse(searchParams(request))
    return ok(await container.openFinance.sync(tenantId, params.id, query))
  },
)
