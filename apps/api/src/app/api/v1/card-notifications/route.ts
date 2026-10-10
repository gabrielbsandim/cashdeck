import { captureNotificationsSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const POST = route(
  'card-notifications:capture',
  async ({ request, tenantId, container }) => {
    const input = captureNotificationsSchema.parse(await readJson(request))
    return ok(await container.captureNotifications(tenantId, input))
  },
)
