import { updateInvoiceDraftSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route<{ id: string }>(
  'invoices:get',
  async ({ tenantId, params, container }) =>
    ok(await container.invoiceDrafts.get(tenantId, params.id)),
)

export const PATCH = route<{ id: string }>(
  'invoices:update',
  async ({ request, tenantId, params, container }) => {
    const patch = updateInvoiceDraftSchema.parse(await readJson(request))
    return ok(await container.invoiceDrafts.update(tenantId, params.id, patch))
  },
)
