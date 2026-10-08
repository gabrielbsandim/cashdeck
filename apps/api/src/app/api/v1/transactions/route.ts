import { listTransactionsQuerySchema } from '@cashdeck/application'
import { route, searchParams } from '@/server/api/handler'
import { okPage } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route(
  'transactions:list',
  async ({ request, tenantId, container }) => {
    const query = listTransactionsQuerySchema.parse(searchParams(request))
    const page = await container.listTransactions(tenantId, query)
    return okPage(page.items, page.nextCursor)
  },
)
