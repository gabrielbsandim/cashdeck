import { SYSTEM_ACTOR } from '@cashdeck/application'
import { getContainer, resetContainer } from '@/server/container'

export const STATIC_TOKEN = 'static-token-0123456789'

// Signs a test device in on the current container and returns its bearer.
export async function signInTestDevice(): Promise<string> {
  const container = getContainer()
  const created = await container.sessions.create(
    container.env.CASHDECK_TENANT_ID,
    { deviceName: 'Test phone', platform: 'ANDROID' },
    SYSTEM_ACTOR,
  )
  return created.token
}

// A test that stubs env or fetch after setup needs a container built after it.
export async function restartTestDevice(): Promise<string> {
  resetContainer()
  return signInTestDevice()
}
