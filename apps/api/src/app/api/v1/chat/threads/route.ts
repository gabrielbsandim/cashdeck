import { createThreadSchema, pageQuerySchema } from '@cashdeck/application'
import { route, searchParams } from '@/server/api/handler'
import { ok, okPage, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route(
  'chat:threads',
  async ({ request, tenantId, container }) => {
    const page = await container.chat.listThreads(
      tenantId,
      pageQuerySchema.parse(searchParams(request)),
    )
    return okPage(page.items, page.nextCursor)
  },
)

export const POST = route(
  'chat:create-thread',
  async ({ request, tenantId, container }) => {
    const input = createThreadSchema.parse(await readJson(request))
    return ok(await container.chat.createThread(tenantId, input), 201)
  },
)
