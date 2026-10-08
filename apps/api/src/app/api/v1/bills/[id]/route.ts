import { getContainer } from '@/server/container'
import { handleError, ok } from '@/server/api/respond'
import { resolveTenant } from '@/server/api/tenant'

export const dynamic = 'force-dynamic'

type Context = { params: Promise<{ id: string }> }

export async function GET(request: Request, context: Context) {
  try {
    const { id } = await context.params
    return ok(await getContainer().getBill(resolveTenant(request), id))
  } catch (error) {
    return handleError(error, 'bills:get')
  }
}
