import { getContainer } from '@/server/container'
import { runCronJob } from '@/server/api/cron'
import { readEnv } from '@/server/env'

export const dynamic = 'force-dynamic'

export function GET(request: Request) {
  return runCronJob(request, 'reconcile-payments', () =>
    getContainer().reconcilePayments(readEnv().CASHDECK_TENANT_ID),
  )
}
