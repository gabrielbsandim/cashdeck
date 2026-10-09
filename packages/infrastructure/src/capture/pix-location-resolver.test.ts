import { describe, expect, it } from 'vitest'
import { Money } from '@cashdeck/domain'
import {
  JwsPixLocationResolver,
  locationUrl,
} from '@/capture/pix-location-resolver'
import { ScriptedTransport } from '@/testing/scripted-transport'

const LOCATION = 'pix.example.com/qr/v2/cobv/abc123'
const URL = `https://${LOCATION}`

const segment = (value: unknown) =>
  Buffer.from(JSON.stringify(value)).toString('base64url')

const jws = (payload: unknown) =>
  `${segment({ alg: 'PS256', typ: 'JWT' })}.${segment(payload)}.c2lnbmF0dXJl`

function resolverWith(...replies: Parameters<ScriptedTransport['on']>[2][]) {
  const scripted = new ScriptedTransport().on('GET', URL, ...replies)
  return {
    scripted,
    resolver: new JwsPixLocationResolver({ transport: scripted.transport }),
  }
}

describe('locationUrl', () => {
  it('builds an https URL for a public host', () => {
    expect(locationUrl(LOCATION)).toBe(URL)
  })

  it('refuses hosts the server must not reach', () => {
    for (const location of [
      'localhost/qr',
      '127.0.0.1/qr',
      '[::1]/qr',
      'pix.example.com:8443/qr',
      'user@pix.example.com/qr',
      'pix example.com/qr',
      `pix.example.com/${'a'.repeat(80)}`,
      '%zz',
    ]) {
      expect(locationUrl(location)).toBeNull()
    }
  })
})

describe('JwsPixLocationResolver', () => {
  it('reads a cobv charge with its final amount and due date', async () => {
    const { scripted, resolver } = resolverWith({
      text: jws({
        txid: 'abc123',
        chave: '11222333000181',
        calendario: { dataDeVencimento: '2026-10-25' },
        valor: { original: '123.45', final: '130.00' },
        recebedor: { nome: 'Fornecedor Exemplo Ltda' },
        status: 'ATIVA',
      }),
    })
    expect(await resolver.resolve(LOCATION)).toEqual({
      amount: Money.of(13000),
      dueDate: '2026-10-25',
      key: '11222333000181',
      payee: 'Fornecedor Exemplo Ltda',
      txid: 'abc123',
    })
    expect(scripted.last('GET', URL).headers?.accept).toBe(
      'application/jose, application/json',
    )
  })

  it('reads an immediate charge with only the original amount', async () => {
    const { resolver } = resolverWith({
      text: jws({ valor: { original: '50.00' }, calendario: {} }),
    })
    expect(await resolver.resolve(LOCATION)).toEqual({
      amount: Money.of(5000),
      dueDate: null,
      key: null,
      payee: null,
      txid: null,
    })
  })

  it('ignores amounts and dates it cannot read', async () => {
    const { resolver } = resolverWith({
      text: jws({
        valor: { original: '0.00', final: 'abc' },
        calendario: { dataDeVencimento: '25/10/2026' },
        chave: '  ',
      }),
    })
    expect(await resolver.resolve(LOCATION)).toMatchObject({
      amount: null,
      dueDate: null,
      key: null,
    })
  })

  it('answers null for refused locations, errors and non JWS bodies', async () => {
    const { resolver } = resolverWith(
      { status: 404, text: 'not found' },
      { text: 'plain text' },
      { text: 'a.%%%.c' },
      { text: `a.${Buffer.from('"just a string"').toString('base64url')}.c` },
    )
    expect(await resolver.resolve('localhost/qr')).toBeNull()
    expect(await resolver.resolve(LOCATION)).toBeNull()
    expect(await resolver.resolve(LOCATION)).toBeNull()
    expect(await resolver.resolve(LOCATION)).toBeNull()
    expect(await resolver.resolve(LOCATION)).toBeNull()
  })

  it('gives up on a slow location', async () => {
    const resolver = new JwsPixLocationResolver({
      transport: () => new Promise(() => undefined),
      timeoutMs: 5,
    })
    await expect(resolver.resolve(LOCATION)).rejects.toThrow('timed out')
  })
})
