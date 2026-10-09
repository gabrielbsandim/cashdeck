import { route } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const DELETE = route<{ id: string }>(
  'subscriptions:remove',
  async ({ tenantId, params, container }) =>
    ok(await container.subscriptions.remove(tenantId, params.id)),
)
