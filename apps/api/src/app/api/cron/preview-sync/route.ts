import { getContainer } from '@/server/container'
import { runCronJob } from '@/server/api/cron'
import { readEnv } from '@/server/env'

export const dynamic = 'force-dynamic'
export const maxDuration = 300

// The rail accounts are read live, so they ride the most frequent feed.
export function GET(request: Request) {
  return runCronJob(request, 'preview-sync', async () => {
    const tenantId = readEnv().CASHDECK_TENANT_ID
    const railAccounts = await getContainer().railAccounts.sync(tenantId)
    return {
      ...(await getContainer().previewFeed.sync(tenantId)),
      railAccounts,
    }
  })
}
