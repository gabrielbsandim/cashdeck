import { type Actor } from '@cashdeck/application'
import { authorize, requestActor } from '@/server/api/auth'
import { handleError } from '@/server/api/respond'
import { resolveTenant } from '@/server/api/tenant'
import { type Container, getContainer } from '@/server/container'

export type RouteContext<P> = {
  request: Request
  tenantId: string
  params: P
  container: Container
  actor: Actor
}

type Params = Record<string, string>

// Every guarded route goes through here: the token check, the tenant, the
// container and the error envelope.
export function route<P extends Params = Params>(
  scope: string,
  handler: (context: RouteContext<P>) => Promise<Response>,
) {
  return async (
    request: Request,
    context?: { params: Promise<P> },
  ): Promise<Response> => {
    const denied = authorize(request)
    if (denied) {
      return denied
    }
    try {
      return await handler({
        request,
        tenantId: resolveTenant(request),
        params: context ? await context.params : ({} as P),
        container: getContainer(),
        actor: requestActor(request),
      })
    } catch (error) {
      return handleError(error, scope)
    }
  }
}

export function searchParams(request: Request): Record<string, string> {
  return Object.fromEntries(new URL(request.url).searchParams)
}
