import { route } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const POST = route<{ id: string }>(
  'chat:cancel',
  async ({ tenantId, params, container, actor }) =>
    ok(await container.chat.cancelAction(tenantId, params.id, actor)),
)
