import { route } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const POST = route<{ id: string }>(
  'bills:reconcile',
  async ({ tenantId, params, container }) => {
    await container.reconcileBill(tenantId, params.id)
    return ok(await container.getBill(tenantId, params.id))
  },
)
