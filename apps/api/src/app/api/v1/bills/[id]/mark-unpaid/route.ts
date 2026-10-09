import { route } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const POST = route<{ id: string }>(
  'bills:mark-unpaid',
  async ({ tenantId, params, container }) => {
    const bill = await container.markBillUnpaid(tenantId, params.id)
    return ok(await container.describeBill(tenantId, bill))
  },
)
