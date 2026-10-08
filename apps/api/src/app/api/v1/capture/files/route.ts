import { captureFileSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const POST = route(
  'capture:file',
  async ({ request, tenantId, container }) => {
    const input = captureFileSchema.parse(await readJson(request))
    const result = await container.captureFile(tenantId, input)
    return ok(
      await container.describeBill(tenantId, result.bill),
      result.duplicate ? 200 : 201,
    )
  },
)
