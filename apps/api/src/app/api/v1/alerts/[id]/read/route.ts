import { route } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const POST = route<{ id: string }>(
  'alerts:read',
  async ({ tenantId, params, container }) =>
    ok(await container.alerts.markRead(tenantId, params.id)),
)
