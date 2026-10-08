import { route } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const DELETE = route<{ id: string }>(
  'capture:disconnect',
  async ({ tenantId, params, container }) =>
    ok(await container.captureSources.disconnect(tenantId, params.id)),
)
