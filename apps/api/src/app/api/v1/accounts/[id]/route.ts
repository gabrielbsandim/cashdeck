import { updateAccountSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const PATCH = route<{ id: string }>(
  'accounts:update',
  async ({ request, tenantId, params, container }) => {
    const input = updateAccountSchema.parse(await readJson(request))
    return ok(await container.updateAccount(tenantId, params.id, input))
  },
)
