import { getContainer } from '@/server/container'
import { runCronJob } from '@/server/api/cron'
import { readEnv } from '@/server/env'

export const dynamic = 'force-dynamic'
export const maxDuration = 300

export function GET(request: Request) {
  return runCronJob(request, 'preview-sync', () =>
    getContainer().previewFeed.sync(readEnv().CASHDECK_TENANT_ID),
  )
}
