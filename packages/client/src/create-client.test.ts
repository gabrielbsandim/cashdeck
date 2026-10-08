import { describe, expect, it, vi } from 'vitest'
import { ApiError } from './api-error'
import { createApiClient } from './create-client'

function respond(status: number, body: unknown) {
  return vi.fn(async () => new Response(JSON.stringify(body), { status }))
}

describe('createApiClient', () => {
  it('sends the token and locale and unwraps the envelope', async () => {
    const fetch = respond(200, { data: { ok: true } })
    const client = createApiClient({
      baseUrl: 'http://api/api/v1',
      fetch,
      getToken: () => 'tok',
      getLocale: () => 'en',
    })
    expect(await client.request('/health')).toEqual({ data: { ok: true } })
    const [url, init] = fetch.mock.calls[0] as unknown as [string, RequestInit]
    expect(url).toBe('http://api/api/v1/health')
    expect(init.headers).toMatchObject({
      authorization: 'Bearer tok',
      'accept-language': 'en',
    })
  })

  it('raises ApiError with the server code', async () => {
    const client = createApiClient({
      baseUrl: '',
      fetch: respond(422, {
        error: { code: 'VALIDATION_ERROR', message: 'bad', details: 1 },
      }),
    })
    await expect(client.request('/bills')).rejects.toMatchObject({
      status: 422,
      code: 'VALIDATION_ERROR',
      message: 'bad',
      details: 1,
    })
  })

  it('uses the global fetch by default', async () => {
    vi.stubGlobal('fetch', respond(200, { data: 1 }))
    expect(await createApiClient({ baseUrl: '' }).request('/x')).toEqual({
      data: 1,
    })
    vi.unstubAllGlobals()
  })

  it('falls back when the error body is not JSON', async () => {
    const fetch = vi.fn(async () => new Response('oops', { status: 502 }))
    const client = createApiClient({ baseUrl: '', fetch })
    const error = await client.request('/x').catch(e => e)
    expect(error).toBeInstanceOf(ApiError)
    expect(error).toMatchObject({
      code: 'HTTP_ERROR',
      message: 'Request failed with 502.',
    })
  })
})
