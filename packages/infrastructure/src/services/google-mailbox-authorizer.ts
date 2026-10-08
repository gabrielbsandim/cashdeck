import {
  type AuthorizedMailbox,
  type MailboxAuthorizer,
  ProviderNotConfiguredError,
} from '@cashdeck/application'
import { ValidationError } from '@cashdeck/domain'
import { isSuccess, readJson, send, type Transport } from '@/http/transport'

const PROVIDER = 'Gmail'
const AUTH_URL = 'https://accounts.google.com/o/oauth2/v2/auth'
const TOKEN_URL = 'https://oauth2.googleapis.com/token'
const USERINFO_URL = 'https://openidconnect.googleapis.com/v1/userinfo'
const SCOPES = ['https://www.googleapis.com/auth/gmail.readonly', 'email']

type Config = { clientId: string; clientSecret: string; redirectUri: string }

export class GoogleMailboxAuthorizer implements MailboxAuthorizer {
  readonly provider = 'GMAIL'

  constructor(
    private readonly env: Record<string, string | undefined>,
    private readonly transport: Transport,
  ) {}

  authorizationUrl(state: string): string {
    const config = this.config()
    const query = new URLSearchParams({
      client_id: config.clientId,
      redirect_uri: config.redirectUri,
      response_type: 'code',
      scope: SCOPES.join(' '),
      access_type: 'offline',
      prompt: 'consent',
      state,
    })
    return `${AUTH_URL}?${query.toString()}`
  }

  async exchange(code: string): Promise<AuthorizedMailbox> {
    const config = this.config()
    const response = await send(this.transport, {
      method: 'POST',
      url: TOKEN_URL,
      form: {
        code,
        client_id: config.clientId,
        client_secret: config.clientSecret,
        redirect_uri: config.redirectUri,
        grant_type: 'authorization_code',
      },
    })
    const tokens = isSuccess(response)
      ? readJson<{ access_token?: string; refresh_token?: string }>(response)
      : {}
    if (!tokens.refresh_token) {
      throw new ValidationError('The authorization code was refused.')
    }
    const info = await send(this.transport, {
      method: 'GET',
      url: USERINFO_URL,
      headers: { authorization: `Bearer ${tokens.access_token ?? ''}` },
    })
    const address = isSuccess(info)
      ? readJson<{ email?: string }>(info).email
      : null
    if (!address) {
      throw new ValidationError('The mailbox address could not be read.')
    }
    return { address, refreshToken: tokens.refresh_token }
  }

  private config(): Config {
    const clientId = this.env.GMAIL_CLIENT_ID?.trim()
    const clientSecret = this.env.GMAIL_CLIENT_SECRET?.trim()
    const redirectUri = this.env.GMAIL_REDIRECT_URI?.trim()
    if (!clientId || !clientSecret || !redirectUri) {
      throw new ProviderNotConfiguredError(PROVIDER)
    }
    return { clientId, clientSecret, redirectUri }
  }
}
