import { route } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const DELETE = route<{ id: string; contributionId: string }>(
  'goals:remove-contribution',
  async ({ tenantId, params, container }) =>
    ok(
      await container.goals.removeContribution(
        tenantId,
        params.id,
        params.contributionId,
      ),
    ),
)
