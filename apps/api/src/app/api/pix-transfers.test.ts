import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { signInTestDevice, STATIC_TOKEN } from '@/app/api/sign-in.test-helpers'
import { resetContainer } from '@/server/container'
import { POST as previewPix } from '@/app/api/v1/pix-transfers/preview/route'
import { POST as sendPix } from '@/app/api/v1/pix-transfers/route'

let session = ''

function post(path: string, body: unknown) {
  return new Request(`http://localhost/api/v1${path}`, {
    method: 'POST',
    headers: { authorization: `Bearer ${session}` },
    body: JSON.stringify(body),
  })
}

async function json(response: Response) {
  return { status: response.status, body: await response.json() }
}

beforeEach(async () => {
  vi.stubEnv('CASHDECK_API_TOKEN', STATIC_TOKEN)
  session = await signInTestDevice()
})

afterEach(() => {
  resetContainer()
  vi.unstubAllEnvs()
})

describe('pix transfer routes', () => {
  it('previews who a key pays, then sends and saves the contact', async () => {
    const recipient = {
      name: 'Ana Exemplo',
      pixKey: 'ana@example.com',
      entity: 'PF',
    }
    const preview = await json(
      await previewPix(post('/pix-transfers/preview', recipient)),
    )
    expect(preview.status).toBe(200)
    expect(preview.body.data.contact).toMatchObject({
      id: null,
      pixKeyType: 'EMAIL',
      isNew: true,
    })
    expect(preview.body.data.recipient.name).toEqual(expect.any(String))

    const sent = await json(
      await sendPix(
        post('/pix-transfers', { ...recipient, amountCents: 2050 }),
      ),
    )
    expect(sent.status).toBe(201)
    expect(sent.body.data).toMatchObject({
      kind: 'PIX_KEY',
      payee: 'Ana Exemplo',
      amount: { cents: 2050 },
    })
    expect(sent.body.data).toHaveProperty('instructions')

    const missing = await previewPix(
      post('/pix-transfers/preview', { name: 'Ana', entity: 'PF' }),
    )
    expect(missing.status).toBe(422)
  })
})
