import { sendPixSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const POST = route(
  'pix-transfers:send',
  async ({ request, tenantId, container, actor }) => {
    const input = sendPixSchema.parse(await readJson(request))
    const { run } = await container.pixTransfers.send(tenantId, input, actor)
    return ok(
      {
        ...(await container.getBill(tenantId, run.bill.id)),
        instructions: run.instructions,
      },
      201,
    )
  },
)
