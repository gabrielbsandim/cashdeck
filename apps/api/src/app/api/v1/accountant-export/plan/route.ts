import { exportPeriodQuerySchema } from '@cashdeck/application'
import { route, searchParams } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route(
  'export:plan',
  async ({ request, tenantId, container }) => {
    const query = exportPeriodQuerySchema.parse(searchParams(request))
    return ok(await container.accountantExport.plan(tenantId, query))
  },
)
