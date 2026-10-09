import { listAlertsQuerySchema } from '@cashdeck/application'
import { route, searchParams } from '@/server/api/handler'
import { okPage } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route(
  'alerts:list',
  async ({ request, tenantId, container }) => {
    const query = listAlertsQuerySchema.parse(searchParams(request))
    const page = await container.alerts.list(tenantId, query)
    return okPage(page.items, page.nextCursor)
  },
)
