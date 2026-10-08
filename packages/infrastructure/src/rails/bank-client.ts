import { type ClientCertificate, mtlsTransport } from '@/http/mtls-transport'
import { TokenCache } from '@/http/token-cache'
import {
  type Call,
  type HttpResponse,
  isSuccess,
  ProviderHttpError,
  readJson,
  send,
  type Transport,
} from '@/http/transport'

export type MtlsFactory = (certificate: ClientCertificate) => Transport

export type BankClientConfig = {
  provider: string
  tokenUrl: string
  clientId: string
  clientSecret: string
  scope: string | null
  certificate: ClientCertificate
  headers?: Record<string, string>
}

type TokenAnswer = { access_token?: string; expires_in?: number }

// One mTLS session and one cached OAuth token per client id; the bank APIs
// rate limit token issuance, so a token is reused until close to its expiry.
export class BankClients {
  private readonly clients = new Map<string, BankClient>()

  constructor(
    private readonly mtls: MtlsFactory = mtlsTransport,
    private readonly now: () => number = Date.now,
  ) {}

  for(config: BankClientConfig): BankClient {
    const key = `${config.tokenUrl}|${config.clientId}`
    const existing = this.clients.get(key)
    if (existing) {
      return existing
    }
    const client = new BankClient(
      config,
      this.mtls(config.certificate),
      this.now,
    )
    this.clients.set(key, client)
    return client
  }
}

export class BankClient {
  private readonly tokens: TokenCache

  constructor(
    private readonly config: BankClientConfig,
    private readonly transport: Transport,
    now: () => number,
  ) {
    this.tokens = new TokenCache(() => this.issueToken(), now)
  }

  async call(call: Call): Promise<HttpResponse> {
    const response = await this.authorized(call)
    if (response.status !== 401) {
      return response
    }
    this.tokens.invalidate()
    return this.authorized(call)
  }

  private async authorized(call: Call): Promise<HttpResponse> {
    const token = await this.tokens.get()
    return send(this.transport, {
      ...call,
      headers: {
        ...this.config.headers,
        ...call.headers,
        authorization: `Bearer ${token}`,
      },
    })
  }

  private async issueToken() {
    const form: Record<string, string> = {
      client_id: this.config.clientId,
      client_secret: this.config.clientSecret,
      grant_type: 'client_credentials',
    }
    if (this.config.scope) {
      form.scope = this.config.scope
    }
    const response = await send(this.transport, {
      method: 'POST',
      url: this.config.tokenUrl,
      form,
    })
    if (!isSuccess(response)) {
      throw new ProviderHttpError(
        this.config.provider,
        response.status,
        'the token request was refused',
      )
    }
    const answer = readJson<TokenAnswer>(response)
    if (!answer.access_token) {
      throw new ProviderHttpError(
        this.config.provider,
        response.status,
        'the token answer had no access_token',
      )
    }
    return {
      accessToken: answer.access_token,
      expiresInSeconds: answer.expires_in ?? 3600,
    }
  }
}
