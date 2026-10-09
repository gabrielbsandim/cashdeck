import { route } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route(
  'alerts:unread-count',
  async ({ tenantId, container }) =>
    ok(await container.alerts.unreadCount(tenantId)),
)
