import { isoMonth, saveRevenueSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const PUT = route<{ month: string }>(
  'revenue:save',
  async ({ request, tenantId, params, container }) => {
    const month = isoMonth.parse(params.month)
    const input = saveRevenueSchema.parse(await readJson(request))
    return ok(await container.revenue.save(tenantId, month, input))
  },
)
