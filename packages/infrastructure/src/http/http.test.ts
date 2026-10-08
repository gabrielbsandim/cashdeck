import { createServer, request as httpRequest, Agent } from 'node:http'
import { type AddressInfo } from 'node:net'
import { describe, expect, it, vi } from 'vitest'
import { mtlsTransport } from '@/http/mtls-transport'
import { TokenCache } from '@/http/token-cache'
import {
  fetchTransport,
  isAuthError,
  isClientError,
  ProviderHttpError,
  readJson,
  safeJson,
  send,
  toCents,
  toDecimal,
  toDecimalString,
} from '@/http/transport'
import { ScriptedTransport } from '@/testing/scripted-transport'

describe('transport helpers', () => {
  it('adapts fetch and keeps response headers', async () => {
    const fetchImpl = vi.fn(
      async () =>
        new Response('{"ok":true}', {
          status: 201,
          headers: { 'x-request-id': 'r1' },
        }),
    )
    const transport = fetchTransport(fetchImpl as unknown as typeof fetch)
    const response = await transport({ method: 'GET', url: 'https://x.test' })
    expect(response).toEqual({
      status: 201,
      headers: {
        'content-type': 'text/plain;charset=UTF-8',
        'x-request-id': 'r1',
      },
      text: '{"ok":true}',
    })
  })

  it('encodes json and form bodies', async () => {
    const scripted = new ScriptedTransport().on('POST', 'https://x.test', {})
    await send(scripted.transport, {
      method: 'POST',
      url: 'https://x.test/a',
      json: { a: 1 },
    })
    await send(scripted.transport, {
      method: 'POST',
      url: 'https://x.test/b',
      form: { a: '1 2' },
    })
    await send(scripted.transport, { method: 'POST', url: 'https://x.test/c' })
    expect(
      scripted.requests.map(r => [r.headers?.['content-type'], r.body]),
    ).toEqual([
      ['application/json', '{"a":1}'],
      ['application/x-www-form-urlencoded', 'a=1+2'],
      [undefined, undefined],
    ])
    expect(scripted.body('POST', 'https://x.test/a')).toEqual({ a: 1 })
    expect(() => scripted.last('GET', 'https://x.test')).toThrow('No request')
    await expect(
      scripted.transport({ method: 'GET', url: 'https://y.test' }),
    ).rejects.toThrow('No scripted reply')
  })

  it('converts money and classifies answers', () => {
    expect(toCents('123.455')).toBe(12346)
    expect(toCents(null)).toBe(0)
    expect(toCents('')).toBe(0)
    expect(toDecimal(12345)).toBe(123.45)
    expect(toDecimalString(1200)).toBe('12.00')
    expect(readJson({ status: 200, headers: {}, text: ' ' })).toEqual({})
    expect(safeJson('nope')).toBeNull()
    expect(isAuthError({ status: 403, headers: {}, text: '' })).toBe(true)
    expect(isClientError({ status: 500, headers: {}, text: '' })).toBe(false)
    expect(new ProviderHttpError('X', 500, 'down').message).toBe(
      'X answered 500: down',
    )
  })
})

describe('mtlsTransport', () => {
  it('sends the request through node and collects the answer', async () => {
    const server = createServer((req, res) => {
      let body = ''
      req.on('data', chunk => (body += chunk))
      req.on('end', () => {
        res.setHeader('set-cookie', ['a=1', 'b=2'])
        res.end(JSON.stringify({ method: req.method, body }))
      })
    })
    await new Promise<void>(resolve => server.listen(0, resolve))
    const { port } = server.address() as AddressInfo
    const transport = mtlsTransport(
      { cert: 'cert', key: 'key' },
      { request: httpRequest as never, agent: new Agent() },
    )
    const response = await transport({
      method: 'POST',
      url: `http://127.0.0.1:${port}/x`,
      body: 'hello',
    })
    server.close()
    expect(JSON.parse(response.text)).toEqual({ method: 'POST', body: 'hello' })
    expect(response.headers['set-cookie']).toBe('a=1, b=2')
    expect(response.status).toBe(200)
  })

  it('rejects when the connection fails', async () => {
    const transport = mtlsTransport(
      { cert: 'cert', key: 'key' },
      { request: httpRequest as never, agent: new Agent() },
    )
    await expect(
      transport({ method: 'GET', url: 'http://127.0.0.1:1/' }),
    ).rejects.toThrow()
  })

  it('builds an https agent from the certificate by default', () => {
    expect(typeof mtlsTransport({ cert: 'c', key: 'k' })).toBe('function')
  })
})

describe('TokenCache', () => {
  it('reuses a token until close to expiry and refreshes after invalidate', async () => {
    let now = 0
    let issued = 0
    const cache = new TokenCache(
      async () => {
        issued += 1
        return { accessToken: `t${issued}`, expiresInSeconds: 120 }
      },
      () => now,
    )
    expect(await cache.get()).toBe('t1')
    now = 30_000
    expect(await cache.get()).toBe('t1')
    now = 70_000
    expect(await cache.get()).toBe('t2')
    cache.invalidate()
    expect(await cache.get()).toBe('t3')
  })

  it('uses the wall clock by default', async () => {
    const cache = new TokenCache(async () => ({
      accessToken: 'a',
      expiresInSeconds: 3600,
    }))
    expect(await cache.get()).toBe('a')
  })
})
