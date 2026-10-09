import { getContainer } from '@/server/container'
import { runCronJob } from '@/server/api/cron'
import { readEnv } from '@/server/env'

export const dynamic = 'force-dynamic'
export const maxDuration = 300

export function GET(request: Request) {
  return runCronJob(request, 'capture', () =>
    getContainer().captureSources.captureAll(readEnv().CASHDECK_TENANT_ID),
  )
}
