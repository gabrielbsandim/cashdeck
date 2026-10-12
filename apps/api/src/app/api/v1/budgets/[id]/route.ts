import { updateBudgetSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const PATCH = route<{ id: string }>(
  'budgets:update',
  async ({ request, tenantId, params, container }) => {
    const input = updateBudgetSchema.parse(await readJson(request))
    return ok(await container.budgets.update(tenantId, params.id, input))
  },
)

export const DELETE = route<{ id: string }>(
  'budgets:remove',
  async ({ tenantId, params, container }) =>
    ok(await container.budgets.remove(tenantId, params.id)),
)
