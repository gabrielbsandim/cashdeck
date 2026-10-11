import { updatePixContactSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const PATCH = route<{ id: string }>(
  'pix-contacts:update',
  async ({ request, tenantId, params, container }) => {
    const input = updatePixContactSchema.parse(await readJson(request))
    return ok(await container.pixContacts.update(tenantId, params.id, input))
  },
)

export const DELETE = route<{ id: string }>(
  'pix-contacts:remove',
  async ({ tenantId, params, container }) =>
    ok(await container.pixContacts.remove(tenantId, params.id)),
)
