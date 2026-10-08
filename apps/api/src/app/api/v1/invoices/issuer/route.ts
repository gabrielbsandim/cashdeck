import { saveIssuerSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route('invoices:issuer', async ({ tenantId, container }) =>
  ok(await container.issuerSetup.get(tenantId)),
)

export const PUT = route(
  'invoices:save-issuer',
  async ({ request, tenantId, container }) => {
    const input = saveIssuerSchema.parse(await readJson(request))
    return ok(await container.issuerSetup.save(tenantId, input))
  },
)
