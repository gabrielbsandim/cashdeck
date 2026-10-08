import { issuerCertificateSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const PUT = route(
  'invoices:certificate',
  async ({ request, tenantId, container }) => {
    const input = issuerCertificateSchema.parse(await readJson(request))
    return ok(await container.uploadIssuerCertificate(tenantId, input))
  },
)
