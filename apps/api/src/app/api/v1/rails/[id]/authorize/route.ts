import { route } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const POST = route<{ id: string }>(
  'rails:authorize',
  async ({ tenantId, params, container }) =>
    ok(await container.rails.authorize(tenantId, params.id)),
)
