import {
  budgetMonthQuerySchema,
  createBudgetSchema,
} from '@cashdeck/application'
import { route, searchParams } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route(
  'budgets:month',
  async ({ request, tenantId, container }) => {
    const query = budgetMonthQuerySchema.parse(searchParams(request))
    return ok(await container.budgets.month(tenantId, query))
  },
)

export const POST = route(
  'budgets:create',
  async ({ request, tenantId, container }) => {
    const input = createBudgetSchema.parse(await readJson(request))
    return ok(await container.budgets.create(tenantId, input), 201)
  },
)
