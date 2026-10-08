export type IssuedToken = { accessToken: string; expiresInSeconds: number }

const REFRESH_MARGIN_MS = 60_000

export class TokenCache {
  private token: { value: string; expiresAt: number } | null = null

  constructor(
    private readonly issue: () => Promise<IssuedToken>,
    private readonly now: () => number = Date.now,
  ) {}

  async get(): Promise<string> {
    if (this.token && this.token.expiresAt - REFRESH_MARGIN_MS > this.now()) {
      return this.token.value
    }
    const issued = await this.issue()
    this.token = {
      value: issued.accessToken,
      expiresAt: this.now() + issued.expiresInSeconds * 1000,
    }
    return issued.accessToken
  }

  invalidate(): void {
    this.token = null
  }
}
