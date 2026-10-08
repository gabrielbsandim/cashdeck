import { route } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route('home:company', async ({ tenantId, container }) =>
  ok(await container.companySummary(tenantId)),
)
