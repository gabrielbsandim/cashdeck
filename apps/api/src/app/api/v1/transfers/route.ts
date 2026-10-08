import {
  listTransfersQuerySchema,
  recordTransferSchema,
} from '@cashdeck/application'
import { route, searchParams } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route(
  'transfers:list',
  async ({ request, tenantId, container }) => {
    const query = listTransfersQuerySchema.parse(searchParams(request))
    return ok(await container.listTransfers(tenantId, query.month))
  },
)

export const POST = route(
  'transfers:record',
  async ({ request, tenantId, container }) => {
    const input = recordTransferSchema.parse(await readJson(request))
    return ok(await container.recordTransfer(tenantId, input), 201)
  },
)
