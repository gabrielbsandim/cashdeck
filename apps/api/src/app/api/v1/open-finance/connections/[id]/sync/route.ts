import { route } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const POST = route<{ id: string }>(
  'open-finance:sync',
  async ({ tenantId, params, container }) =>
    ok(await container.openFinance.sync(tenantId, params.id)),
)
