import { route } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const POST = route('alerts:read-all', async ({ tenantId, container }) =>
  ok(await container.alerts.markAllRead(tenantId)),
)
