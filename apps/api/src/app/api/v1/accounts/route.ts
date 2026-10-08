import {
  createAccountSchema,
  listAccountsQuerySchema,
} from '@cashdeck/application'
import { route, searchParams } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route(
  'accounts:list',
  async ({ request, tenantId, container }) => {
    const query = listAccountsQuerySchema.parse(searchParams(request))
    return ok(await container.listAccounts(tenantId, query.entity))
  },
)

export const POST = route(
  'accounts:create',
  async ({ request, tenantId, container }) => {
    const input = createAccountSchema.parse(await readJson(request))
    return ok(await container.createManualAccount(tenantId, input), 201)
  },
)
