import { createVerify, generateKeyPairSync } from 'node:crypto'
import { describe, expect, it } from 'vitest'
import { FcmNotifier, serviceAccountAssertion } from '@/notify/fcm-notifier'
import { credentials, TENANT } from '@/testing/provider-fixtures'
import { ScriptedTransport } from '@/testing/scripted-transport'

const TOKEN = 'https://oauth2.googleapis.com/token'
const SEND =
  'https://fcm.googleapis.com/v1/projects/cashdeck-test/messages:send'

const { privateKey, publicKey } = generateKeyPairSync('rsa', {
  modulusLength: 2048,
})
const account = {
  project_id: 'cashdeck-test',
  client_email: 'push@cashdeck-test.iam.gserviceaccount.com',
  private_key: privateKey.export({ type: 'pkcs8', format: 'pem' }).toString(),
}

const notification = {
  tenantId: TENANT,
  type: 'BILL_PAID',
  title: 'Conta paga',
  body: 'Energia paga pelo Pix.',
  data: { billId: 'bill-1' },
}

function notifier(
  scripted: ScriptedTransport,
  devices: string[],
  invalid: string[] = [],
) {
  return new FcmNotifier({
    credentials: credentials({
      FCM_SERVICE_ACCOUNT_JSON: JSON.stringify(account),
    }),
    transport: scripted.transport,
    deviceTokens: async () => devices,
    onInvalidToken: async (_tenant, token) => {
      invalid.push(token)
    },
    now: () => 1_791_000_000_000,
  })
}

describe('serviceAccountAssertion', () => {
  it('signs an RS256 JWT for the messaging scope', () => {
    const jwt = serviceAccountAssertion(account, 1000)
    const [header, claims, signature] = jwt.split('.')
    expect(
      JSON.parse(Buffer.from(header ?? '', 'base64url').toString()),
    ).toEqual({
      alg: 'RS256',
      typ: 'JWT',
    })
    expect(
      JSON.parse(Buffer.from(claims ?? '', 'base64url').toString()),
    ).toEqual({
      iss: account.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: TOKEN,
      iat: 1000,
      exp: 4600,
    })
    const valid = createVerify('RSA-SHA256')
      .update(`${header}.${claims}`)
      .verify(publicKey, Buffer.from(signature ?? '', 'base64url'))
    expect(valid).toBe(true)
  })
})

describe('FcmNotifier', () => {
  it('sends one message per device and drops stale tokens', async () => {
    const invalid: string[] = []
    const scripted = new ScriptedTransport()
      .on('POST', TOKEN, {
        json: { access_token: 'fcm-token', expires_in: 3600 },
      })
      .on(
        'POST',
        SEND,
        { json: { name: 'projects/x/messages/1' } },
        { status: 404, json: {} },
        {
          status: 400,
          json: {
            error: {
              status: 'INVALID_ARGUMENT',
              details: [{ errorCode: 'UNREGISTERED' }],
            },
          },
        },
      )
    await notifier(scripted, ['d1', 'd2', 'd3'], invalid).notify(notification)
    expect(invalid).toEqual(['d2', 'd3'])
    expect(scripted.body('POST', SEND)).toEqual({
      message: {
        token: 'd3',
        notification: { title: 'Conta paga', body: 'Energia paga pelo Pix.' },
        data: { type: 'BILL_PAID', billId: 'bill-1' },
      },
    })
    expect(scripted.last('POST', SEND).headers).toMatchObject({
      authorization: 'Bearer fcm-token',
    })
    expect(scripted.last('POST', TOKEN).body).toContain(
      'grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer',
    )
  })

  it('does nothing without devices and fails on real errors', async () => {
    const quiet = new ScriptedTransport()
    await notifier(quiet, []).notify(notification)
    expect(quiet.requests).toEqual([])
    const failing = new ScriptedTransport()
      .on('POST', TOKEN, { json: {} })
      .on(
        'POST',
        SEND,
        { status: 500, text: 'down' },
        { status: 400, text: 'bad' },
      )
    const push = notifier(failing, ['d1'])
    await expect(push.notify(notification)).rejects.toThrow('answered 500')
    await expect(push.notify(notification)).rejects.toThrow('answered 400')
    expect(failing.requests.filter(r => r.url === TOKEN)).toHaveLength(1)
  })

  it('reports a refused token and a missing service account', async () => {
    const refused = new ScriptedTransport().on('POST', TOKEN, { status: 400 })
    await expect(
      notifier(refused, ['d1']).notify(notification),
    ).rejects.toThrow('the token request was refused')
    const unconfigured = new FcmNotifier({
      credentials: credentials({}),
      transport: refused.transport,
      deviceTokens: async () => ['d1'],
    })
    await expect(unconfigured.notify(notification)).rejects.toThrow(
      'Firebase Cloud Messaging is not configured.',
    )
    const defaults = new FcmNotifier({
      credentials: credentials({
        FCM_SERVICE_ACCOUNT_JSON: JSON.stringify(account),
      }),
      transport: new ScriptedTransport()
        .on('POST', TOKEN, { json: { access_token: 't' } })
        .on('POST', SEND, { status: 404 }).transport,
      deviceTokens: async () => ['d1'],
    })
    await expect(defaults.notify(notification)).resolves.toBeUndefined()
  })
})
