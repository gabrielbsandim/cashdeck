import { SERVICE_CODES } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route('invoices:service-codes', async () =>
  ok(SERVICE_CODES),
)
