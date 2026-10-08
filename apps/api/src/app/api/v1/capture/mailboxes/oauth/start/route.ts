import { startMailboxSchema } from '@cashdeck/application'
import { signState } from '@/server/api/auth'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const POST = route(
  'capture:oauth-start',
  async ({ request, tenantId, container }) => {
    const input = startMailboxSchema.parse(await readJson(request))
    const state = signState(
      { tenantId, entity: input.entity },
      container.deps.clock.now(),
    )
    return ok(
      await container.captureSources.startMailbox(
        tenantId,
        input.entity,
        state,
      ),
    )
  },
)
