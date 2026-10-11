import { debitAccountInputSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const PUT = route(
  'home:funding:debit-account',
  async ({ request, tenantId, container }) => {
    const { accountId } = debitAccountInputSchema.parse(await readJson(request))
    return ok(await container.setDebitAccount(tenantId, accountId))
  },
)
