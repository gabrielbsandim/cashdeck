import { regenerateSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'
// A turn runs the model and its tools within CHAT_TURN_BUDGET_MS.
export const maxDuration = 60

export const POST = route<{ id: string; messageId: string }>(
  'chat:regenerate',
  async ({ request, tenantId, params, container, actor }) => {
    const input = regenerateSchema.parse(await readJson(request))
    return ok(
      await container.chat.regenerate(
        tenantId,
        params.id,
        params.messageId,
        input,
        actor,
      ),
      201,
    )
  },
)
