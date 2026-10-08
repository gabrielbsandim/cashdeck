import { route } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route<{ id: string }>(
  'card-statements:get',
  async ({ tenantId, params, container }) =>
    ok(await container.cardStatements.get(tenantId, params.id)),
)
