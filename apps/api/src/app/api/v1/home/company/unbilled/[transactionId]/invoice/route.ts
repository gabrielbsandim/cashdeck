import { route } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const POST = route<{ transactionId: string }>(
  'home:invoice-receipt',
  async ({ tenantId, params, container }) => {
    await container.invoiceReceipt(tenantId, params.transactionId)
    return ok(await container.companySummary(tenantId))
  },
)
