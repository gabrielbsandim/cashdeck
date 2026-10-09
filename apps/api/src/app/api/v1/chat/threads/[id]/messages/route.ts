import { pageQuerySchema, sendMessageSchema } from '@cashdeck/application'
import { route, searchParams } from '@/server/api/handler'
import { ok, okPage, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'
// A turn runs the model and its tools within CHAT_TURN_BUDGET_MS.
export const maxDuration = 60

export const GET = route<{ id: string }>(
  'chat:messages',
  async ({ request, tenantId, params, container }) => {
    const page = await container.chat.listMessages(
      tenantId,
      params.id,
      pageQuerySchema.parse(searchParams(request)),
    )
    return okPage(page.items, page.nextCursor)
  },
)

export const POST = route<{ id: string }>(
  'chat:send',
  async ({ request, tenantId, params, container }) => {
    const input = sendMessageSchema.parse(await readJson(request))
    return ok(await container.chat.sendMessage(tenantId, params.id, input), 201)
  },
)
