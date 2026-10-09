import { confirmActionSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'
export const maxDuration = 60

export const POST = route<{ id: string }>(
  'chat:confirm',
  async ({ request, tenantId, params, container, actor }) => {
    const input = confirmActionSchema.parse(await readJson(request))
    return ok(
      await container.chat.confirmAction(tenantId, params.id, input, actor),
    )
  },
)
