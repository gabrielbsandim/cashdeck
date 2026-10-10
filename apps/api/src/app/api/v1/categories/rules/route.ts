import { createCategoryRuleSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const POST = route(
  'categories:rules:create',
  async ({ request, tenantId, container }) => {
    const input = createCategoryRuleSchema.parse(await readJson(request))
    const { rule, updated } = await container.createCategoryRule(
      tenantId,
      input,
    )
    return ok(
      { pattern: rule.pattern, categoryId: rule.categoryId, updated },
      201,
    )
  },
)
