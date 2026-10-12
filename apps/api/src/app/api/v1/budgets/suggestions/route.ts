import {
  acceptSuggestionsSchema,
  budgetMonthQuerySchema,
} from '@cashdeck/application'
import { route, searchParams } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route(
  'budgets:suggest',
  async ({ request, tenantId, container }) => {
    const query = budgetMonthQuerySchema.parse(searchParams(request))
    return ok(await container.budgets.suggest(tenantId, query))
  },
)

export const POST = route(
  'budgets:accept-suggestions',
  async ({ request, tenantId, container }) => {
    const input = acceptSuggestionsSchema.parse(await readJson(request))
    return ok(await container.budgets.acceptSuggestions(tenantId, input))
  },
)
