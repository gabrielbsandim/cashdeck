import { createInvoiceTemplateSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route(
  'invoices:templates',
  async ({ tenantId, container }) =>
    ok(await container.invoiceTemplates.list(tenantId)),
)

export const POST = route(
  'invoices:create-template',
  async ({ request, tenantId, container }) => {
    const input = createInvoiceTemplateSchema.parse(await readJson(request))
    return ok(await container.invoiceTemplates.create(tenantId, input), 201)
  },
)
