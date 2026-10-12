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
async function raiseJobAlert(
  source: string,
  report: (tenantId: string) => Promise<void>,
): Promise<void> {
  try {
    await report(readEnv().CASHDECK_TENANT_ID)
  } catch (alertError) {
    reportError(alertError, `cron:${source}:alert`)
  }
}

// Jobs list what they skipped under `failures`, at the top or in a sub-result.
export function failuresIn(result: unknown): number {
  if (typeof result !== 'object' || result === null || Array.isArray(result)) {
    return 0
  }
  return Object.entries(result).reduce(
    (sum, [key, value]) =>
      sum +
      (key === 'failures' && Array.isArray(value)
        ? value.length
        : failuresIn(value)),
    0,
  )
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
    await raiseJobAlert(source, tenantId =>
      getContainer().reportJobPartialFailure(
        tenantId,
        source,
        failuresIn(result),
      ),
    )
    return NextResponse.json({
      data: { source, durationMs: Date.now() - startedAt, ...result },
    })
  } catch (error) {
    await raiseJobAlert(source, tenantId =>
      getContainer().reportJobFailure(tenantId, source, error),
    )
    return handleError(error, `cron:${source}`)
  }
}
