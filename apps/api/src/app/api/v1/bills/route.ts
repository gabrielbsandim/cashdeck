import { captureBillSchema, listBillsQuerySchema } from '@cashdeck/application'
import { route, searchParams } from '@/server/api/handler'
import { ok, okPage, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route(
  'bills:list',
  async ({ request, tenantId, container }) => {
    const query = listBillsQuerySchema.parse(searchParams(request))
    const page = await container.listBills(
      tenantId,
      { entityId: query.entityId, status: query.status },
      { cursor: query.cursor, limit: query.limit },
    )
    return okPage(page.items, page.nextCursor)
  },
)

export const POST = route(
  'bills:capture',
  async ({ request, tenantId, container }) => {
    const input = captureBillSchema.parse(await readJson(request))
    const result = await container.captureBill(tenantId, input)
    return ok(
      await container.describeBill(tenantId, result.bill),
      result.duplicate ? 200 : 201,
    )
  },
)
