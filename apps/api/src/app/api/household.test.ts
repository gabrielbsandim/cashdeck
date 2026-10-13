import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { signInTestDevice, STATIC_TOKEN } from '@/app/api/sign-in.test-helpers'
import { resetContainer } from '@/server/container'
import { GET, PUT } from '@/app/api/v1/household/route'

let session = ''
const URL = 'http://localhost/api/v1/household'

const json = async (response: Response) => ({
  status: response.status,
  body: await response.json(),
})

const put = (body: unknown) =>
  PUT(
    new Request(URL, {
      method: 'PUT',
      headers: {
        authorization: `Bearer ${session}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify(body),
    }),
  )

beforeEach(async () => {
  vi.stubEnv('CASHDECK_API_TOKEN', STATIC_TOKEN)
  session = await signInTestDevice()
})

afterEach(() => {
  resetContainer()
  vi.unstubAllEnvs()
})

describe('household route', () => {
  it('keeps the members by their CPF and lists them back', async () => {
    const empty = await json(
      await GET(
        new Request(URL, { headers: { authorization: `Bearer ${session}` } }),
      ),
    )
    expect(empty.body.data).toEqual({ members: [] })
    const saved = await json(
      await put({ members: [{ name: 'Ana Lima', taxId: '111.444.777-35' }] }),
    )
    expect(saved.status).toBe(200)
    expect(saved.body.data).toEqual({
      members: [{ name: 'Ana Lima', taxId: '11144477735' }],
    })
  })

  it('refuses a company as a member', async () => {
    const refused = await put({
      members: [{ name: 'Ana Lima ME', taxId: '11.222.333/0001-81' }],
    })
    expect(refused.status).toBe(422)
  })
})
