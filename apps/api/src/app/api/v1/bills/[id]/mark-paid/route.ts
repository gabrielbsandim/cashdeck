import { z } from 'zod'
import { getContainer } from '@/server/container'
import { handleError, ok, readJson } from '@/server/api/respond'
import { resolveTenant } from '@/server/api/tenant'

export const dynamic = 'force-dynamic'

const markPaidSchema = z.object({ proof: z.string().max(500).optional() })

type Context = { params: Promise<{ id: string }> }

export async function POST(request: Request, context: Context) {
  try {
    const { id } = await context.params
    const input = markPaidSchema.parse(await readJson(request))
    const tenantId = resolveTenant(request)
    const container = getContainer()
    const bill = await container.markBillPaid(tenantId, id, input.proof ?? null)
    return ok(await container.describeBill(tenantId, bill))
  } catch (error) {
    return handleError(error, 'bills:mark-paid')
  }
}
