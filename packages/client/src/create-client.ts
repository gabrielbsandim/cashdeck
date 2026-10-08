import { ApiError } from './api-error'
import { type paths } from './generated/schema'

export type ApiPaths = paths

export type ApiClientConfig = {
  baseUrl: string
  getToken?: () =>
    | string
    | null
    | undefined
    | Promise<string | null | undefined>
  getLocale?: () => string | undefined
  fetch?: typeof fetch
}

type Envelope<T> = { data: T; nextCursor?: string | null }
type Failure = {
  error?: { code?: string; message?: string; details?: unknown }
}

export type ApiClient = {
  request<T>(path: string, init?: RequestInit): Promise<Envelope<T>>
}

export function createApiClient(config: ApiClientConfig): ApiClient {
  const doFetch = config.fetch ?? fetch
  return {
    async request<T>(
      path: string,
      init: RequestInit = {},
    ): Promise<Envelope<T>> {
      const token = await config.getToken?.()
      const locale = config.getLocale?.()
      const response = await doFetch(`${config.baseUrl}${path}`, {
        ...init,
        headers: {
          'content-type': 'application/json',
          ...(token ? { authorization: `Bearer ${token}` } : {}),
          ...(locale ? { 'accept-language': locale } : {}),
          ...init.headers,
        },
      })
      const body = (await response.json().catch(() => ({}))) as Envelope<T> &
        Failure
      if (!response.ok) {
        throw new ApiError(
          response.status,
          body.error?.code ?? 'HTTP_ERROR',
          body.error?.message ?? `Request failed with ${response.status}.`,
          body.error?.details,
        )
      }
      return body
    },
  }
}
