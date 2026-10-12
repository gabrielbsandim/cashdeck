import { ruleSuggestionDecisionSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const POST = route(
  'categories:review:accept',
  async ({ request, tenantId, container }) => {
    const input = ruleSuggestionDecisionSchema.parse(await readJson(request))
    return ok(
      await container.categoryReview.acceptSuggestion(tenantId, input.id),
      201,
    )
  },
)
