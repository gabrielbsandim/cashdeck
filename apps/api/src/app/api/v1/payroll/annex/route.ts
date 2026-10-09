import { declareAnnexSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const PUT = route(
  'payroll:annex',
  async ({ request, tenantId, container }) => {
    const input = declareAnnexSchema.parse(await readJson(request))
    return ok(await container.payroll.declare(tenantId, input))
  },
)
