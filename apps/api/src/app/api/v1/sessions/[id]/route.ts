import { route } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const DELETE = route<{ id: string }>(
  'sessions:revoke',
  async ({ tenantId, params, container, actor }) =>
    ok(await container.sessions.revoke(tenantId, params.id, actor)),
)
