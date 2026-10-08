import { route } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route<{ id: string }>(
  'bills:get',
  async ({ tenantId, params, container }) =>
    ok(await container.getBill(tenantId, params.id)),
)
