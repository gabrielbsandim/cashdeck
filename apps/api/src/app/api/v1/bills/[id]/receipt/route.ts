import { route } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route<{ id: string }>(
  'bills:receipt',
  async ({ tenantId, params, container }) =>
    ok(await container.receipts.receipt(tenantId, params.id)),
)
