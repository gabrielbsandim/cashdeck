import { connectItemSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route('open-finance:list', async ({ tenantId, container }) =>
  ok(await container.openFinance.list(tenantId)),
)

export const POST = route(
  'open-finance:connect',
  async ({ request, tenantId, container }) => {
    const input = connectItemSchema.parse(await readJson(request))
    return ok(await container.openFinance.connect(tenantId, input), 201)
  },
)
