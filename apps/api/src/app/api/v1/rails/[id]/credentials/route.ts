import { saveRailCredentialsSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route<{ id: string }>(
  'rails:credentials',
  async ({ tenantId, params, container }) =>
    ok(await container.rails.credentials(tenantId, params.id)),
)

export const PUT = route<{ id: string }>(
  'rails:save-credentials',
  async ({ request, tenantId, params, container }) => {
    const input = saveRailCredentialsSchema.parse(await readJson(request))
    return ok(await container.rails.saveCredentials(tenantId, params.id, input))
  },
)
