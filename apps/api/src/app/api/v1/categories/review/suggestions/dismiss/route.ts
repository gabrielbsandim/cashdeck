import { ruleSuggestionDecisionSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const POST = route(
  'categories:review:dismiss',
  async ({ request, tenantId, container }) => {
    const input = ruleSuggestionDecisionSchema.parse(await readJson(request))
    return ok(
      await container.categoryReview.dismissSuggestion(tenantId, input.id),
    )
  },
)
