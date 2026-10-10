import { statementPostSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'
import { defer } from '@/server/api/webhook'

export const dynamic = 'force-dynamic'

export const POST = route<{ id: string }>(
  'card-statements:post',
  async ({ request, tenantId, params, container }) => {
    const input = statementPostSchema.parse(await readJson(request))
    const posted = await container.cardStatements.post(
      tenantId,
      params.id,
      input,
    )
    if (posted.added > 0) {
      await defer(
        () => container.categorizeTransactions(tenantId),
        'card-statements:categorize',
      )
    }
    return ok(posted)
  },
)
