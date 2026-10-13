import { householdSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route('household:get', async ({ tenantId, container }) =>
  ok(await container.household.get(tenantId)),
)

export const PUT = route(
  'household:set',
  async ({ request, tenantId, container }) => {
    const input = householdSchema.parse(await readJson(request))
    return ok(await container.household.set(tenantId, input))
  },
)
