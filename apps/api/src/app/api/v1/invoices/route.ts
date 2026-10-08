import { listInvoicesQuerySchema } from '@cashdeck/application'
import { route, searchParams } from '@/server/api/handler'
import { okPage } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route(
  'invoices:list',
  async ({ request, tenantId, container }) => {
    const query = listInvoicesQuerySchema.parse(searchParams(request))
    const page = await container.listInvoices(tenantId, query)
    return okPage(page.items, page.nextCursor)
  },
)
