import { updateEntitySchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const PATCH = route<{ id: string }>(
  'entities:update',
  async ({ request, tenantId, params, container }) => {
    const input = updateEntitySchema.parse(await readJson(request))
    return ok(await container.updateEntity(tenantId, params.id, input))
  },
)
