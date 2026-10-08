import { uploadSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const POST = route<{ id: string }>(
  'bills:attach',
  async ({ request, tenantId, params, container }) => {
    const input = uploadSchema.parse(await readJson(request))
    return ok(
      await container.receipts.addAttachment(tenantId, params.id, input),
      201,
    )
  },
)
