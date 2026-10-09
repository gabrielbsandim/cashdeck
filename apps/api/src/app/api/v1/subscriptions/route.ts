import {
  insightsScopeQuerySchema,
  subscriptionDecisionSchema,
} from '@cashdeck/application'
import { route, searchParams } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route(
  'subscriptions:list',
  async ({ request, tenantId, container }) => {
    const query = insightsScopeQuerySchema.parse(searchParams(request))
    return ok(await container.subscriptions.list(tenantId, query.entity))
  },
)

export const POST = route(
  'subscriptions:confirm',
  async ({ request, tenantId, container }) => {
    const input = subscriptionDecisionSchema.parse(await readJson(request))
    return ok(
      await container.subscriptions.confirm(tenantId, input.transactionId),
      201,
    )
  },
)
