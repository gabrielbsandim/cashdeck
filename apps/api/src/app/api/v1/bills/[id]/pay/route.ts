import { z } from 'zod'
import { getContainer } from '@/server/container'
import { handleError, ok, readJson } from '@/server/api/respond'
import { resolveTenant } from '@/server/api/tenant'

export const dynamic = 'force-dynamic'

const payBillSchema = z.object({ confirmed: z.boolean().optional() })

type Context = { params: Promise<{ id: string }> }

export async function POST(request: Request, context: Context) {
  try {
    const { id } = await context.params
    const input = payBillSchema.parse(await readJson(request))
    const tenantId = resolveTenant(request)
    const container = getContainer()
    const run = await container.runPaymentLadder(tenantId, id, input)
    return ok({
      ...(await container.getBill(tenantId, id)),
      instructions: run.instructions,
    })
  } catch (error) {
    return handleError(error, 'bills:pay')
  }
}
