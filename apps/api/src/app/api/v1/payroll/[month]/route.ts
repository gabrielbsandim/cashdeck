import { isoMonth, savePayrollSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const PUT = route<{ month: string }>(
  'payroll:save',
  async ({ request, tenantId, params, container }) => {
    const month = isoMonth.parse(params.month)
    const input = savePayrollSchema.parse(await readJson(request))
    return ok(await container.payroll.save(tenantId, month, input))
  },
)
