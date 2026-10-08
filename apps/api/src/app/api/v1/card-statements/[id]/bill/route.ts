import { statementBillSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const POST = route<{ id: string }>(
  'card-statements:bill',
  async ({ request, tenantId, params, container }) => {
    const input = statementBillSchema.parse(await readJson(request))
    return ok(
      await container.cardStatements.createBill(tenantId, params.id, input),
      201,
    )
  },
)
