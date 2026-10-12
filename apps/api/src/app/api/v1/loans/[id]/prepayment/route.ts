import { prepaymentQuerySchema } from '@cashdeck/application'
import { route, searchParams } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route<{ id: string }>(
  'loans:prepayment',
  async ({ request, tenantId, params, container }) => {
    const { amount } = prepaymentQuerySchema.parse(searchParams(request))
    return ok(
      await container.loans.simulatePrepayment(tenantId, params.id, amount),
    )
  },
)
