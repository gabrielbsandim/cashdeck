import { route } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const POST = route(
  'automation:resume',
  async ({ tenantId, container, actor }) =>
    ok(await container.automation.resume(tenantId, actor)),
)
