import { route } from '@/server/api/handler'
import { payBillSchema } from '@/server/api/schemas'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const POST = route<{ id: string }>(
  'bills:pay',
  async ({ request, tenantId, params, container }) => {
    const input = payBillSchema.parse(await readJson(request))
    const run = await container.runPaymentLadder(tenantId, params.id, input)
    return ok({
      ...(await container.getBill(tenantId, params.id)),
      instructions: run.instructions,
    })
  },
)
