import { importStatementSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const POST = route(
  'card-statements:read',
  async ({ request, tenantId, container }) => {
    const input = importStatementSchema.parse(await readJson(request))
    return ok(await container.cardStatements.read(tenantId, input), 201)
  },
)
