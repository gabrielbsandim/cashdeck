import { categorizeGroupSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const POST = route(
  'categories:review:categorize',
  async ({ request, tenantId, container }) => {
    const input = categorizeGroupSchema.parse(await readJson(request))
    return ok(await container.categoryReview.categorizeGroup(tenantId, input))
  },
)
