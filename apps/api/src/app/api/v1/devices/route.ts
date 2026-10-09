import { registerDeviceSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const POST = route(
  'devices:register',
  async ({ request, tenantId, container }) => {
    const input = registerDeviceSchema.parse(await readJson(request))
    return ok(await container.alerts.registerDevice(tenantId, input), 201)
  },
)
