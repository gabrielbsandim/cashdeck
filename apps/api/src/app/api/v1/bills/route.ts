import { captureBillSchema, listBillsQuerySchema } from '@cashdeck/application'
import { getContainer } from '@/server/container'
import { handleError, ok, okPage, readJson } from '@/server/api/respond'
import { resolveTenant } from '@/server/api/tenant'

export const dynamic = 'force-dynamic'

export async function GET(request: Request) {
  try {
    const params = Object.fromEntries(new URL(request.url).searchParams)
    const query = listBillsQuerySchema.parse(params)
    const page = await getContainer().listBills(
      resolveTenant(request),
      { entityId: query.entityId, status: query.status },
      { cursor: query.cursor, limit: query.limit },
    )
    return okPage(page.items, page.nextCursor)
  } catch (error) {
    return handleError(error, 'bills:list')
  }
}

export async function POST(request: Request) {
  try {
    const input = captureBillSchema.parse(await readJson(request))
    const tenantId = resolveTenant(request)
    const container = getContainer()
    const result = await container.captureBill(tenantId, input)
    return ok(
      await container.describeBill(tenantId, result.bill),
      result.duplicate ? 200 : 201,
    )
  } catch (error) {
    return handleError(error, 'bills:capture')
  }
}
