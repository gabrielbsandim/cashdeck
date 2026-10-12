import { type Actor } from '@cashdeck/application'
import {
  apiToken,
  authorizeStatic,
  bearerToken,
  notConfigured,
  sessionActor,
  staticTokenActor,
} from '@/server/api/auth'
import { handleError } from '@/server/api/respond'
import { resolveTenant } from '@/server/api/tenant'
import { type Container, getContainer } from '@/server/container'

export type RouteContext<P> = {
  request: Request
  tenantId: string
  params: P
  container: Container
  actor: Actor
  sessionId: string
}

type Params = Record<string, string>

// Every guarded route goes through here: the device session, the tenant, the
// container and the error envelope.
export function route<P extends Params = Params>(
  scope: string,
  handler: (context: RouteContext<P>) => Promise<Response>,
) {
  return async (
    request: Request,
    context?: { params: Promise<P> },
  ): Promise<Response> => {
    if (!apiToken()) {
      return notConfigured()
    }
    try {
      const container = getContainer()
      const tenantId = resolveTenant(request)
      const session = await container.sessions.authenticate(
        tenantId,
        bearerToken(request),
      )
      return await handler({
        request,
        tenantId,
        params: context ? await context.params : ({} as P),
        container,
        actor: sessionActor(request, session.id),
        sessionId: session.id,
      })
    } catch (error) {
      return handleError(error, scope)
    }
  }
}

export type StaticTokenContext = Omit<
  RouteContext<Params>,
  'params' | 'sessionId'
>

// Only signing a device in takes the static token itself.
export function staticTokenRoute(
  scope: string,
  handler: (context: StaticTokenContext) => Promise<Response>,
) {
  return async (request: Request): Promise<Response> => {
    const denied = authorizeStatic(request)
    if (denied) {
      return denied
    }
    try {
      return await handler({
        request,
        tenantId: resolveTenant(request),
        container: getContainer(),
        actor: staticTokenActor(request),
      })
    } catch (error) {
      return handleError(error, scope)
    }
  }
}

export function searchParams(request: Request): Record<string, string> {
  return Object.fromEntries(new URL(request.url).searchParams)
}
