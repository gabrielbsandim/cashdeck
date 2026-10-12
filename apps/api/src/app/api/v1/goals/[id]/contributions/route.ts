import { contributionInputSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const POST = route<{ id: string }>(
  'goals:contribute',
  async ({ request, tenantId, params, container }) => {
    const input = contributionInputSchema.parse(await readJson(request))
    return ok(await container.goals.contribute(tenantId, params.id, input), 201)
  },
)
