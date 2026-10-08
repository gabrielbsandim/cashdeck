import { route } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route(
  'card-statements:latest',
  async ({ tenantId, container }) =>
    ok(await container.cardStatements.latest(tenantId)),
)
