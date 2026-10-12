import {
  monthlyRecapQuerySchema,
  recapMonthSchema,
} from '@cashdeck/application'
import { route, searchParams } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'
// The first read of a month asks the model for its story.
export const maxDuration = 60

export const GET = route<{ month: string }>(
  'recaps:get',
  async ({ request, tenantId, params, container }) => {
    const month = recapMonthSchema.parse(params.month)
    const query = monthlyRecapQuerySchema.parse(searchParams(request))
    return ok(await container.monthlyRecap.get(tenantId, month, query))
  },
)
