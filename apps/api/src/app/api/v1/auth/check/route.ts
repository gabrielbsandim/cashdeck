import { route } from '@/server/api/handler'
import { ok } from '@/server/api/respond'
import { API_VERSION } from '@/server/api/openapi'

export const dynamic = 'force-dynamic'

export const GET = route('auth:check', async ({ tenantId, container }) => {
  const entities = await container.listEntities(tenantId)
  return ok({
    server: {
      name: container.env.CASHDECK_SERVER_NAME,
      version: API_VERSION,
      tenantId,
    },
    entities: entities.map(({ id, kind, name }) => ({ id, kind, name })),
  })
})
