import { monthlyRecapQuerySchema } from '@cashdeck/application'
import { route, searchParams } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'
export const maxDuration = 60

export const GET = route(
  'recaps:latest',
  async ({ request, tenantId, container }) => {
    const query = monthlyRecapQuerySchema.parse(searchParams(request))
    return ok(await container.monthlyRecap.latest(tenantId, query))
  },
)
