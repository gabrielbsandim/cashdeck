import { getContainer } from '@/server/container'
import { runCronJob } from '@/server/api/cron'
import { readEnv } from '@/server/env'

export const dynamic = 'force-dynamic'
export const maxDuration = 300

// Drafts the recurring invoices that are due, then polls the ones still
// processing at the issuer.
export function GET(request: Request) {
  return runCronJob(request, 'invoices', async () => {
    const container = getContainer()
    const tenantId = readEnv().CASHDECK_TENANT_ID
    return {
      drafts: await container.recurringInvoices(tenantId),
      poll: await container.invoiceLifecycle.poll(tenantId),
    }
  })
}
