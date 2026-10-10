import { captureNotificationsSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'
import { defer } from '@/server/api/webhook'

export const dynamic = 'force-dynamic'

// The phone gives up after 30 seconds, so the category is set after the answer.
export const POST = route(
  'card-notifications:capture',
  async ({ request, tenantId, container }) => {
    const input = captureNotificationsSchema.parse(await readJson(request))
    const captured = await container.captureNotifications(tenantId, input)
    if (captured.added > 0) {
      await defer(
        () => container.categorizeTransactions(tenantId),
        'card-notifications:categorize',
      )
    }
    return ok(captured)
  },
)
