import { route } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const POST = route('invoices:test', async ({ container }) =>
  ok(await container.testIssuer()),
)
