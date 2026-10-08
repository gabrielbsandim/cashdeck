import { route } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const POST = route<{ id: string }>(
  'rails:test',
  async ({ tenantId, params, container }) =>
    ok(await container.rails.test(tenantId, params.id)),
)
