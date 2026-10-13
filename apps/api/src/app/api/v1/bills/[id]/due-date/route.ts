import { route } from '@/server/api/handler'
import { dueDateSchema } from '@/server/api/schemas'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const PUT = route<{ id: string }>(
  'bills:due-date',
  async ({ request, tenantId, params, container }) => {
    const input = dueDateSchema.parse(await readJson(request))
    const bill = await container.rescheduleBill(
      tenantId,
      params.id,
      input.dueDate,
    )
    return ok(await container.describeBill(tenantId, bill))
  },
)
