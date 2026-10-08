import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export function GET() {
  return ok({ status: 'ok' as const })
}
