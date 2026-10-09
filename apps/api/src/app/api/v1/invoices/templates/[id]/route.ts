import { updateInvoiceTemplateSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route<{ id: string }>(
  'invoices:template',
  async ({ tenantId, params, container }) =>
    ok(await container.invoiceTemplates.get(tenantId, params.id)),
)

export const PATCH = route<{ id: string }>(
  'invoices:update-template',
  async ({ request, tenantId, params, container }) => {
    const patch = updateInvoiceTemplateSchema.parse(await readJson(request))
    return ok(
      await container.invoiceTemplates.update(tenantId, params.id, patch),
    )
  },
)

export const DELETE = route<{ id: string }>(
  'invoices:delete-template',
  async ({ tenantId, params, container }) =>
    ok(await container.invoiceTemplates.remove(tenantId, params.id)),
)
