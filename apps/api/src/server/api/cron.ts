import { timingSafeEqual } from 'node:crypto'
import { NextResponse } from 'next/server'
import { fail, handleError } from '@/server/api/respond'
import { readEnv } from '@/server/env'

function isAuthorized(request: Request, secret: string | undefined): boolean {
  if (!secret) {
    return false
  }
  const given = Buffer.from(request.headers.get('authorization') ?? '')
  const expected = Buffer.from(`Bearer ${secret}`)
  return given.length === expected.length && timingSafeEqual(given, expected)
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
    return handleError(error, `cron:${source}`)
  }
}
