import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { LOANS_COLLECTION, type StoredLoan } from '@cashdeck/application'
import { signInTestDevice, STATIC_TOKEN } from '@/app/api/sign-in.test-helpers'
import { getContainer, resetContainer } from '@/server/container'
import { GET as listLoans } from '@/app/api/v1/loans/route'
import { POST as importLoan } from '@/app/api/v1/loans/import/route'
import { DELETE as removeLoan } from '@/app/api/v1/loans/[id]/route'
import { GET as prepayment } from '@/app/api/v1/loans/[id]/prepayment/route'

let session = ''
const TENANT = 'local'

function request(path: string, method = 'GET', body?: unknown) {
  return new Request(`http://localhost/api/v1/${path}`, {
    method,
    headers: {
      authorization: `Bearer ${session}`,
      'content-type': 'application/json',
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  })
}

const withId = (id: string) => ({ params: Promise.resolve({ id }) })

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

async function storeLoan() {
  const { deps } = getContainer()
  const personal = await deps.entities.findByKind(TENANT, 'PF')
  const loan: StoredLoan = {
    id: 'bank-1',
    entityId: personal?.id ?? '',
    entity: 'PF',
    importedAt: '2026-10-01T12:00:00.000Z',
    lender: 'Bank',
    contract: '1',
    system: 'SAC',
    indexer: 'TR',
    effectiveRate: 12,
    cet: 12.5,
    principal: 200_000,
    propertyValue: null,
    signedOn: '2025-01-10',
    termMonths: 2,
    installments: [
      {
        number: 1,
        dueOn: '2099-01-17',
        total: 102_000,
        principal: 100_000,
        interest: 2_000,
        fees: 0,
        lateFees: 0,
        balance: 100_000,
        paidOn: null,
        paid: null,
      },
    ],
  }
  await deps.documents.put(TENANT, LOANS_COLLECTION, loan.id, loan)
}

describe('loan routes', () => {
  it('lists, simulates and removes a stored loan', async () => {
    await storeLoan()

    const listed = await json(await listLoans(request('loans')))
    expect(listed.status).toBe(200)
    expect(listed.body.data.items).toMatchObject([
      { id: 'bank-1', name: 'Bank 1', balance: { cents: 200_000 } },
    ])

    const simulated = await json(
      await prepayment(
        request('loans/bank-1/prepayment?amount=100000'),
        withId('bank-1'),
      ),
    )
    expect(simulated.status).toBe(200)
    expect(simulated.body.data).toMatchObject({
      interestSaved: { cents: 1_000 },
      balanceAfter: { cents: 100_000 },
    })

    const removed = await json(
      await removeLoan(request('loans/bank-1', 'DELETE'), withId('bank-1')),
    )
    expect(removed).toMatchObject({
      status: 200,
      body: { data: { id: 'bank-1' } },
    })
  })

  it('rejects a bad amount, an unknown loan and an unreadable file', async () => {
    await storeLoan()
    const badAmount = await prepayment(
      request('loans/bank-1/prepayment?amount=0'),
      withId('bank-1'),
    )
    expect(badAmount.status).toBe(422)

    const unknown = await removeLoan(
      request('loans/none', 'DELETE'),
      withId('none'),
    )
    expect(unknown.status).toBe(404)

    const unreadable = await importLoan(
      request('loans/import', 'POST', {
        fileName: 'extrato.pdf',
        mimeType: 'application/pdf',
        base64: 'bm90IGEgcGRm',
      }),
    )
    expect(unreadable.status).toBe(422)
  })
})
