import { route } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const POST = route<{ invoiceId: string }>(
  'home:approve-draft',
  async ({ tenantId, params, container }) => {
    await container.issueInvoice(tenantId, params.invoiceId)
    return ok(await container.companySummary(tenantId))
  },
)
