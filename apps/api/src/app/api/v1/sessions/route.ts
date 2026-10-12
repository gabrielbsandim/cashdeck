import { createSessionSchema } from '@cashdeck/application'
import { route, staticTokenRoute } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const POST = staticTokenRoute(
  'sessions:create',
  async ({ request, tenantId, container, actor }) => {
    const input = createSessionSchema.parse(await readJson(request))
    return ok(await container.sessions.create(tenantId, input, actor), 201)
  },
)

export const GET = route(
  'sessions:list',
  async ({ tenantId, container, sessionId }) =>
    ok(await container.sessions.list(tenantId, sessionId)),
)
