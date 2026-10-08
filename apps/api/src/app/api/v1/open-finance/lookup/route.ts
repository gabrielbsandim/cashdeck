import { lookupItemSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const POST = route(
  'open-finance:lookup',
  async ({ request, tenantId, container }) => {
    const input = lookupItemSchema.parse(await readJson(request))
    return ok(await container.openFinance.lookup(tenantId, input.itemId))
  },
)
