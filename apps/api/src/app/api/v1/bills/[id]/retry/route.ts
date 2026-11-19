import { route } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const POST = route<{ id: string }>(
  'bills:pay',
  async ({ tenantId, params, container, actor }) => {
    const run = await container.retryPayment(tenantId, params.id, { actor })
    return ok({
      ...(await container.getBill(tenantId, params.id)),
      instructions: run.instructions,
    })
  },
)
