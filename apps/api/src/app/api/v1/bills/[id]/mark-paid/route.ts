import { route } from '@/server/api/handler'
import { markPaidSchema } from '@/server/api/schemas'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const POST = route<{ id: string }>(
  'bills:mark-paid',
  async ({ request, tenantId, params, container }) => {
    const input = markPaidSchema.parse(await readJson(request))
    const proof = input.attachmentId ?? input.proof ?? null
    const bill = await container.markBillPaid(tenantId, params.id, proof)
    return ok(await container.describeBill(tenantId, bill))
  },
)
