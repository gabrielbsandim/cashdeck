import {
  createPixContactSchema,
  pixContactQuerySchema,
} from '@cashdeck/application'
import { route, searchParams } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route(
  'pix-contacts:list',
  async ({ request, tenantId, container }) => {
    const query = pixContactQuerySchema.parse(searchParams(request))
    return ok(await container.pixContacts.list(tenantId, query.search))
  },
)

export const POST = route(
  'pix-contacts:create',
  async ({ request, tenantId, container }) => {
    const input = createPixContactSchema.parse(await readJson(request))
    return ok(await container.pixContacts.create(tenantId, input), 201)
  },
)
