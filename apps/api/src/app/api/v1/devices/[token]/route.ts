import { route } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

// FCM tokens carry a colon, which clients percent-encode in the path.
export const DELETE = route<{ token: string }>(
  'devices:remove',
  async ({ tenantId, params, container }) =>
    ok(
      await container.alerts.removeDevice(
        tenantId,
        decodeURIComponent(params.token),
      ),
    ),
)
