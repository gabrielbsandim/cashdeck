import { route } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const DELETE = route<{ id: string }>(
  'home:funding:items:remove',
  async ({ tenantId, params, container }) =>
    ok(await container.fundingItems.remove(tenantId, params.id)),
)
