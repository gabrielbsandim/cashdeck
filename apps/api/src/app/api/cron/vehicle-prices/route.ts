import { getContainer } from '@/server/container'
import { runCronJob } from '@/server/api/cron'
import { readEnv } from '@/server/env'

export const dynamic = 'force-dynamic'
export const maxDuration = 300

// The FIPE table publishes a month's prices in its first days.
export function GET(request: Request) {
  return runCronJob(request, 'vehicle-prices', () =>
    getContainer().assets.refreshPrices(readEnv().CASHDECK_TENANT_ID),
  )
}
