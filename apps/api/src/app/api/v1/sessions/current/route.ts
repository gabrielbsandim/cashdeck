import { route } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const DELETE = route(
  'sessions:sign-out',
  async ({ tenantId, container, actor, sessionId }) =>
    ok(await container.sessions.revoke(tenantId, sessionId, actor)),
)
