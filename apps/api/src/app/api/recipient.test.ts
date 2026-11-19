import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { signInTestDevice, STATIC_TOKEN } from '@/app/api/sign-in.test-helpers'
import { resetContainer } from '@/server/container'
import { POST as captureBill } from '@/app/api/v1/bills/route'
import { GET as billRecipient } from '@/app/api/v1/bills/[id]/recipient/route'

const BOLETO_LINE = '00190000090280001234256789012178916050000012345'
const PIX_CODE =
  '00020126580014br.gov.bcb.pix0136123e4567-e12b-12d1-a456-4266554400005204000053039865802BR5913Fulano de Tal6008BRASILIA62070503***63041D3D'

let session = ''

const params = (id: string) => ({ params: Promise.resolve({ id }) })

async function capture(code: Record<string, unknown>): Promise<string> {
  const response = await captureBill(
    new Request('http://localhost/api/v1/bills', {
      method: 'POST',
      headers: { authorization: `Bearer ${session}` },
      body: JSON.stringify({
        entityId: 'personal',
        amountCents: 2500,
        dueDate: '2026-10-20',
        ...code,
      }),
    }),
  )
  const body = await response.json()
  return body.data.id
}

async function recipient(id: string) {
  const response = await billRecipient(
    new Request(`http://localhost/api/v1/bills/${id}/recipient`, {
      headers: { authorization: `Bearer ${session}` },
    }),
    params(id),
  )
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

describe('GET /v1/bills/{id}/recipient', () => {
  it('answers the receiver check of a Pix code bill', async () => {
    const id = await capture({ pixCode: PIX_CODE, payee: 'Loja Exemplo' })
    const answer = await recipient(id)
    expect(answer.status).toBe(200)
    expect(answer.body.data).toEqual({
      name: 'Loja Exemplo',
      taxId: null,
      bank: null,
      verified: false,
    })
  })

  it('answers null for a bill that is not a Pix QR', async () => {
    const id = await capture({ paymentCode: BOLETO_LINE })
    const answer = await recipient(id)
    expect(answer.status).toBe(200)
    expect(answer.body.data).toBeNull()
  })

  it('answers 404 for an unknown bill', async () => {
    expect((await recipient('nope')).status).toBe(404)
  })
})
