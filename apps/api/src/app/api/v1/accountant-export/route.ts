import { generateExportSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const POST = route(
  'export:generate',
  async ({ request, tenantId, container }) => {
    const input = generateExportSchema.parse(await readJson(request))
    return ok(await container.accountantExport.generate(tenantId, input), 201)
  },
)
