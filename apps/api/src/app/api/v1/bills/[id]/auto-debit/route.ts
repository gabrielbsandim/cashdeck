import { route } from '@/server/api/handler'
import { autoDebitSchema } from '@/server/api/schemas'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const PUT = route<{ id: string }>(
  'bills:auto-debit',
  async ({ request, tenantId, params, container }) => {
    const input = autoDebitSchema.parse(await readJson(request))
    return ok(await container.setAutoDebit(tenantId, params.id, input.enabled))
  },
)
