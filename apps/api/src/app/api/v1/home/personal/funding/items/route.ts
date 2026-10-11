import { fundingItemInputSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const POST = route(
  'home:funding:items:add',
  async ({ request, tenantId, container }) => {
    const input = fundingItemInputSchema.parse(await readJson(request))
    return ok(await container.fundingItems.add(tenantId, input), 201)
  },
)
