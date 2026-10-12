import { createAssetSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route('assets:list', async ({ tenantId, container }) =>
  ok(await container.assets.list(tenantId)),
)

export const POST = route(
  'assets:create',
  async ({ request, tenantId, container }) => {
    const input = createAssetSchema.parse(await readJson(request))
    return ok(await container.assets.create(tenantId, input), 201)
  },
)
