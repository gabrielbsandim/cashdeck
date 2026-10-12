import { timingSafeEqual } from 'node:crypto'
import { NextResponse } from 'next/server'
import { fail, handleError } from '@/server/api/respond'
import { getContainer } from '@/server/container'
import { readEnv } from '@/server/env'
import { reportError } from '@/server/observability'

function isAuthorized(request: Request, secret: string | undefined): boolean {
  if (!secret) {
    return false
  }
  const given = Buffer.from(request.headers.get('authorization') ?? '')
  const expected = Buffer.from(`Bearer ${secret}`)
  return given.length === expected.length && timingSafeEqual(given, expected)
}

// A failed run also lands in the app inbox, so it is seen without reading logs.
async function raiseJobAlert(source: string, error: unknown): Promise<void> {
  try {
    await getContainer().reportJobFailure(
      readEnv().CASHDECK_TENANT_ID,
      source,
      error,
    )
  } catch (alertError) {
    reportError(alertError, `cron:${source}:alert`)
  }
}

// Vercel Cron sends `Authorization: Bearer $CRON_SECRET`; without a secret
// configured every cron call is refused rather than left open.
export async function runCronJob(
  request: Request,
  source: string,
  job: () => Promise<object>,
): Promise<NextResponse> {
  if (!isAuthorized(request, readEnv().CRON_SECRET)) {
    return fail('UNAUTHORIZED', 'Invalid cron secret.', 401)
  }
  const startedAt = Date.now()
  try {
    const result = await job()
    return NextResponse.json({
      data: { source, durationMs: Date.now() - startedAt, ...result },
    })
  } catch (error) {
    await raiseJobAlert(source, error)
    return handleError(error, `cron:${source}`)
  }
}
