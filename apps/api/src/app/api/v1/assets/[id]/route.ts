import { updateAssetSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const PATCH = route<{ id: string }>(
  'assets:update',
  async ({ request, tenantId, params, container }) => {
    const input = updateAssetSchema.parse(await readJson(request))
    return ok(await container.assets.update(tenantId, params.id, input))
  },
)

export const DELETE = route<{ id: string }>(
  'assets:remove',
  async ({ tenantId, params, container }) =>
    ok(await container.assets.remove(tenantId, params.id)),
)
