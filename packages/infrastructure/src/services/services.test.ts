import { describe, expect, it } from 'vitest'
import { ProviderNotConfiguredError } from '@cashdeck/application'
import { ValidationError } from '@cashdeck/domain'
import { type HttpRequest, type HttpResponse } from '@/http/transport'
import { X509CertificateInspector } from '@/services/certificate-inspector'
import { GoogleMailboxAuthorizer } from '@/services/google-mailbox-authorizer'
import { crc32, StoredZipWriter } from '@/services/zip-writer'

// A throwaway self-signed certificate for the subject "cashdeck-test".
const PEM = `-----BEGIN CERTIFICATE-----
MIIBhDCCASugAwIBAgIUP+n9+maJySFGBb0ro6bhPPET+JkwCgYIKoZIzj0EAwIw
GDEWMBQGA1UEAwwNY2FzaGRlY2stdGVzdDAeFw0yNjEwMDgyMzI5NDBaFw0zNjEw
MDUyMzI5NDBaMBgxFjAUBgNVBAMMDWNhc2hkZWNrLXRlc3QwWTATBgcqhkjOPQIB
BggqhkjOPQMBBwNCAARTFEVXkvZq4Hj2uvgdM0RkWDMThq9PYFCnGftnZZVfyVrM
oEKzm6wVkzcw6RIH8i/rysTnnVbanQwlXdBGdsODo1MwUTAdBgNVHQ4EFgQUOy8x
7kXfFVKXFNdSFZpfhSCFTNwwHwYDVR0jBBgwFoAUOy8x7kXfFVKXFNdSFZpfhSCF
TNwwDwYDVR0TAQH/BAUwAwEB/zAKBggqhkjOPQQDAgNHADBEAiA6mR97pulAOTpf
RA4n8fPr6BwwTFi8sF7CibhChM/m7gIgZl6R8c9dA9lifknQUyyJUezJ/vGNw4cb
QkLquCZvYL8=
-----END CERTIFICATE-----`

const FINGERPRINT =
  '39a83ee6af90d12be64292cb868b34d5f6715960ad81c0c4c32fce9824f09f9f'
const bytes = (text: string) => new TextEncoder().encode(text)

function derOf(pem: string): Uint8Array {
  const body = pem.replace(/-----[A-Z ]+-----/g, '').replace(/\s+/g, '')
  return Uint8Array.from(Buffer.from(body, 'base64'))
}

describe('X509CertificateInspector', () => {
  const inspector = new X509CertificateInspector()

  it('reads the expiry and fingerprint of PEM and DER files', () => {
    const facts = { fingerprint: FINGERPRINT, validUntil: '2036-10-05' }
    expect(
      inspector.inspect({ fileName: 'company.pem', bytes: bytes(PEM) }),
    ).toEqual(facts)
    expect(
      inspector.inspect({ fileName: 'company.cer', bytes: derOf(PEM) }),
    ).toEqual(facts)
    expect(
      inspector.inspect({ fileName: 'bundle.pfx', bytes: bytes(PEM) }),
    ).toEqual(facts)
  })

  it('cannot see inside a PKCS#12 bundle and refuses garbage', () => {
    const facts = inspector.inspect({
      fileName: 'company.P12',
      bytes: new Uint8Array([1, 2, 3]),
    })
    expect(facts.validUntil).toBeNull()
    expect(facts.fingerprint).toHaveLength(64)
    expect(() =>
      inspector.inspect({ fileName: 'a.crt', bytes: new Uint8Array() }),
    ).toThrow(ValidationError)
    expect(() =>
      inspector.inspect({ fileName: 'a.crt', bytes: bytes('nope') }),
    ).toThrow('could not be read')
  })
})

describe('StoredZipWriter', () => {
  it('computes the standard CRC-32', () => {
    expect(crc32(bytes('123456789'))).toBe(0xcbf43926)
  })

  it('writes stored entries a ZIP reader can walk', () => {
    const zip = new StoredZipWriter().zip([
      { name: 'invoices.csv', content: 'a,b\n' },
      { name: 'tax-guides/das.pdf', content: new Uint8Array([1, 2, 3]) },
    ])
    const view = new DataView(zip.buffer, zip.byteOffset, zip.byteLength)
    expect(view.getUint32(0, true)).toBe(0x04034b50)
    const end = zip.length - 22
    expect(view.getUint32(end, true)).toBe(0x06054b50)
    expect(view.getUint16(end + 10, true)).toBe(2)
    const directory = view.getUint32(end + 16, true)
    expect(view.getUint32(directory, true)).toBe(0x02014b50)
    const nameLength = view.getUint16(26, true)
    const name = new TextDecoder().decode(zip.slice(30, 30 + nameLength))
    expect(name).toBe('invoices.csv')
    const size = view.getUint32(18, true)
    const data = zip.slice(30 + nameLength, 30 + nameLength + size)
    expect(new TextDecoder().decode(data)).toBe('a,b\n')
    expect(view.getUint32(14, true)).toBe(crc32(data))
  })
})

type Reply = { status: number; text: string }

function transport(replies: Reply[]) {
  const requests: HttpRequest[] = []
  return {
    requests,
    send: async (request: HttpRequest): Promise<HttpResponse> => {
      requests.push(request)
      const reply = replies.shift() ?? { status: 500, text: '' }
      return { ...reply, headers: {} }
    },
  }
}

const ENV = {
  GMAIL_CLIENT_ID: 'client-id',
  GMAIL_CLIENT_SECRET: 'client-secret',
  GMAIL_REDIRECT_URI:
    'https://api.example.com/api/v1/capture-sources/mailboxes/oauth/callback',
}

describe('GoogleMailboxAuthorizer', () => {
  it('builds an offline consent URL', () => {
    const url = new URL(
      new GoogleMailboxAuthorizer(ENV, transport([]).send).authorizationUrl(
        's1',
      ),
    )
    expect(url.origin).toBe('https://accounts.google.com')
    expect(Object.fromEntries(url.searchParams)).toMatchObject({
      client_id: 'client-id',
      access_type: 'offline',
      prompt: 'consent',
      state: 's1',
      scope: 'https://www.googleapis.com/auth/gmail.readonly email',
    })
  })

  it('exchanges the code and reads the address', async () => {
    const http = transport([
      {
        status: 200,
        text: JSON.stringify({ access_token: 'at', refresh_token: 'rt' }),
      },
      { status: 200, text: JSON.stringify({ email: 'person@example.com' }) },
    ])
    const mailbox = await new GoogleMailboxAuthorizer(ENV, http.send).exchange(
      'code-1',
    )
    expect(mailbox).toEqual({
      address: 'person@example.com',
      refreshToken: 'rt',
    })
    expect(http.requests[0]?.body).toContain('grant_type=authorization_code')
    expect(http.requests[1]?.headers?.authorization).toBe('Bearer at')
  })

  it('refuses a rejected code, a missing refresh token or address', async () => {
    const run = (replies: Reply[]) =>
      new GoogleMailboxAuthorizer(ENV, transport(replies).send).exchange('c')
    await expect(run([{ status: 400, text: '<html>' }])).rejects.toThrow(
      'was refused',
    )
    await expect(run([{ status: 200, text: '{}' }])).rejects.toThrow(
      'was refused',
    )
    await expect(
      run([
        { status: 200, text: '{"refresh_token":"rt"}' },
        { status: 401, text: 'no' },
      ]),
    ).rejects.toThrow('address')
    await expect(
      run([
        { status: 200, text: '{"refresh_token":"rt"}' },
        { status: 200, text: '{}' },
      ]),
    ).rejects.toThrow(ValidationError)
  })

  it('is not configured without the OAuth client', () => {
    const authorizer = new GoogleMailboxAuthorizer(
      { GMAIL_CLIENT_ID: 'x' },
      transport([]).send,
    )
    expect(() => authorizer.authorizationUrl('s')).toThrow(
      ProviderNotConfiguredError,
    )
  })
})
