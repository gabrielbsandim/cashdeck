import { entityKindSchema, setDdaSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const PUT = route<{ entity: string }>(
  'capture:dda',
  async ({ request, tenantId, params, container }) => {
    const entity = entityKindSchema.parse(params.entity)
    const input = setDdaSchema.parse(await readJson(request))
    return ok(
      await container.captureSources.setDda(tenantId, entity, input.enabled),
    )
  },
)
