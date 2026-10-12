import { reviewQueueQuerySchema } from '@cashdeck/application'
import { route, searchParams } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route(
  'categories:review',
  async ({ request, tenantId, container }) => {
    const query = reviewQueueQuerySchema.parse(searchParams(request))
    return ok(await container.categoryReview.queue(tenantId, query.entity))
  },
)
