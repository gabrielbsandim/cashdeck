import { NextResponse } from 'next/server'
import { entityKindSchema } from '@cashdeck/application'
import { verifyState } from '@/server/api/auth'
import { reportError } from '@/server/observability'
import { getContainer } from '@/server/container'

export const dynamic = 'force-dynamic'

// The provider redirects the browser here, so there is no bearer token: the
// signed state proves the flow started from an authorized app.
export async function GET(request: Request) {
  const container = getContainer()
  const scheme = container.env.CASHDECK_APP_SCHEME
  const back = (query: string) =>
    NextResponse.redirect(`${scheme}://capture?${query}`, 302)
  const url = new URL(request.url)
  const state = verifyState(
    url.searchParams.get('state') ?? '',
    container.deps.clock.now(),
  )
  const entity = entityKindSchema.safeParse(state?.entity)
  const code = url.searchParams.get('code')
  if (!state || !entity.success || !code) {
    return back('error=INVALID_STATE')
  }
  try {
    await container.captureSources.completeMailbox(
      state.tenantId,
      entity.data,
      code,
    )
    return back('connected=1')
  } catch (error) {
    reportError(error, 'capture:oauth-callback')
    return back('error=AUTHORIZATION_FAILED')
  }
}
