import { copyBudgetsSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const POST = route(
  'budgets:copy',
  async ({ request, tenantId, container }) => {
    const input = copyBudgetsSchema.parse(await readJson(request))
    return ok(await container.budgets.copyToNext(tenantId, input))
  },
)
