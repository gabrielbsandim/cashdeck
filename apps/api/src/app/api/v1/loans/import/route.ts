import { importLoanSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const POST = route(
  'loans:import',
  async ({ request, tenantId, container }) => {
    const input = importLoanSchema.parse(await readJson(request))
    return ok(await container.loans.importStatement(tenantId, input), 201)
  },
)
