import { readEnv } from '@/server/env'

// Self-hosted: one deployment serves one tenant. Auth resolves it per request
// once household members and the hosted mode land.
export function resolveTenant(_request: Request): string {
  return readEnv().CASHDECK_TENANT_ID
}
