import { cancelInvoiceSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const POST = route<{ id: string }>(
  'invoices:cancel',
  async ({ request, tenantId, params, container }) => {
    const { reason } = cancelInvoiceSchema.parse(await readJson(request))
    const invoice = await container.invoiceLifecycle.cancel(
      tenantId,
      params.id,
      reason,
    )
    const [view] = await container.invoiceViews(tenantId, [invoice])
    return ok(view)
  },
)
