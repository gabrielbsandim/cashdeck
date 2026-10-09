import { route } from '@/server/api/handler'
import { payBillSchema } from '@/server/api/schemas'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const POST = route<{ id: string }>(
  'bills:pay',
  async ({ request, tenantId, params, container, actor }) => {
    const input = payBillSchema.parse(await readJson(request))
    const run = await container.runPaymentLadder(tenantId, params.id, {
      ...input,
      actor,
    })
    return ok({
      ...(await container.getBill(tenantId, params.id)),
      instructions: run.instructions,
    })
  },
)
