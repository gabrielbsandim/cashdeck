import { updateCategoryRuleSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const PATCH = route<{ id: string }>(
  'categories:rules:update',
  async ({ request, tenantId, params, container }) => {
    const input = updateCategoryRuleSchema.parse(await readJson(request))
    return ok(await container.categoryRules.update(tenantId, params.id, input))
  },
)

export const DELETE = route<{ id: string }>(
  'categories:rules:remove',
  async ({ tenantId, params, container }) =>
    ok(await container.categoryRules.remove(tenantId, params.id)),
)
