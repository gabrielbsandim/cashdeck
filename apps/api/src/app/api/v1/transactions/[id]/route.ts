import { updateTransactionSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const PATCH = route<{ id: string }>(
  'transactions:update',
  async ({ request, tenantId, params, container }) => {
    const input = updateTransactionSchema.parse(await readJson(request))
    return ok(await container.updateTransaction(tenantId, params.id, input))
  },
)
