import { createSign } from 'node:crypto'
import {
  type DeviceLocale,
  type Notification,
  type Notifier,
} from '@cashdeck/application'
import {
  type Credentials,
  requireCredentials,
} from '@/credentials/credential-resolver'
import { TokenCache } from '@/http/token-cache'
import {
  isSuccess,
  ProviderHttpError,
  readJson,
  safeJson,
  send,
  type Transport,
} from '@/http/transport'

const PROVIDER = 'Firebase Cloud Messaging'
const TOKEN_URL = 'https://oauth2.googleapis.com/token'
const SCOPE = 'https://www.googleapis.com/auth/firebase.messaging'

type ServiceAccount = {
  project_id: string
  client_email: string
  private_key: string
}

export type PushDevice = { token: string; locale: DeviceLocale }

export type DeviceTokens = (tenantId: string) => Promise<PushDevice[]>

export type FcmNotifierDeps = {
  credentials: Credentials
  transport: Transport
  deviceTokens: DeviceTokens
  onInvalidToken?: (tenantId: string, token: string) => Promise<void>
  now?: () => number
}

function base64url(value: string): string {
  return Buffer.from(value).toString('base64url')
}

export function serviceAccountAssertion(
  account: ServiceAccount,
  nowSeconds: number,
): string {
  const header = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))
  const claims = base64url(
    JSON.stringify({
      iss: account.client_email,
      scope: SCOPE,
      aud: TOKEN_URL,
      iat: nowSeconds,
      exp: nowSeconds + 3600,
    }),
  )
  const signature = createSign('RSA-SHA256')
    .update(`${header}.${claims}`)
    .sign(account.private_key, 'base64url')
  return `${header}.${claims}.${signature}`
}

type FcmError = {
  error?: { status?: string; details?: Array<{ errorCode?: string }> }
}

// A token the app uninstalled or rotated answers 404 or UNREGISTERED; it is
// reported for removal instead of failing the whole notification.
function isStaleToken(status: number, text: string): boolean {
  if (status === 404) {
    return true
  }
  const body = safeJson(text) as FcmError | null
  const codes = [
    body?.error?.status,
    ...(body?.error?.details ?? []).map(d => d.errorCode),
  ]
  return codes.includes('UNREGISTERED')
}

export class FcmNotifier implements Notifier {
  private readonly tokens: TokenCache
  private account: ServiceAccount | null = null

  constructor(private readonly deps: FcmNotifierDeps) {
    this.tokens = new TokenCache(() => this.issueToken(), deps.now)
  }

  async notify(notification: Notification): Promise<void> {
    const devices = await this.deps.deviceTokens(notification.tenantId)
    if (devices.length === 0) {
      return
    }
    const account = await this.serviceAccount()
    const accessToken = await this.tokens.get()
    for (const device of devices) {
      const response = await send(this.deps.transport, {
        method: 'POST',
        url: `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`,
        headers: { authorization: `Bearer ${accessToken}` },
        json: {
          message: {
            token: device.token,
            notification: notification.localized[device.locale] ?? {
              title: notification.title,
              body: notification.body,
            },
            data: { type: notification.type, ...notification.data },
          },
        },
      })
      if (isSuccess(response)) {
        continue
      }
      if (!isStaleToken(response.status, response.text)) {
        throw new ProviderHttpError(PROVIDER, response.status, response.text)
      }
      await this.deps.onInvalidToken?.(notification.tenantId, device.token)
    }
  }

  private async serviceAccount(): Promise<ServiceAccount> {
    if (this.account) {
      return this.account
    }
    const { FCM_SERVICE_ACCOUNT_JSON } = await requireCredentials(
      this.deps.credentials,
      PROVIDER,
      ['FCM_SERVICE_ACCOUNT_JSON'],
    )
    this.account = JSON.parse(FCM_SERVICE_ACCOUNT_JSON) as ServiceAccount
    return this.account
  }

  private async issueToken() {
    const account = await this.serviceAccount()
    const nowSeconds = Math.floor((this.deps.now ?? Date.now)() / 1000)
    const response = await send(this.deps.transport, {
      method: 'POST',
      url: TOKEN_URL,
      form: {
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion: serviceAccountAssertion(account, nowSeconds),
      },
    })
    if (!isSuccess(response)) {
      throw new ProviderHttpError(
        PROVIDER,
        response.status,
        'the token request was refused',
      )
    }
    const answer = readJson<{ access_token?: string; expires_in?: number }>(
      response,
    )
    return {
      accessToken: answer.access_token ?? '',
      expiresInSeconds: answer.expires_in ?? 3600,
    }
  }
}
