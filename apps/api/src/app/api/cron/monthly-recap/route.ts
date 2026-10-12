import { getContainer } from '@/server/container'
import { runCronJob } from '@/server/api/cron'
import { readEnv } from '@/server/env'

export const dynamic = 'force-dynamic'
export const maxDuration = 300

// Day 1: the recap of the month that closed, pushed once per month.
export function GET(request: Request) {
  return runCronJob(request, 'monthly-recap', () =>
    getContainer().monthlyRecap.run(readEnv().CASHDECK_TENANT_ID),
  )
}
