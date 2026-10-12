import { createGoalSchema, goalQuerySchema } from '@cashdeck/application'
import { route, searchParams } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route(
  'goals:list',
  async ({ request, tenantId, container }) => {
    const query = goalQuerySchema.parse(searchParams(request))
    return ok(await container.goals.list(tenantId, query))
  },
)

export const POST = route(
  'goals:create',
  async ({ request, tenantId, container }) => {
    const input = createGoalSchema.parse(await readJson(request))
    return ok(await container.goals.create(tenantId, input), 201)
  },
)
