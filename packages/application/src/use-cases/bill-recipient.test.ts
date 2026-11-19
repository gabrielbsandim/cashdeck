import { describe, expect, it } from 'vitest'
import { NotFoundError } from '@/errors/errors'
import { bill, fullDeps } from '@/testing/deps.test-helpers'
import { FakeRecipientDirectory } from '@/testing/providers'
import {
  BOLETO_LINE,
  PIX_NO_AMOUNT,
  TENANT,
} from '@/testing/scenario.test-helpers'
import { makeBillRecipient } from '@/use-cases/bill-recipient'

const HOLDER = { name: 'Loja Exemplo', taxId: '12.345.678/0001-90', bank: null }

function setup(
  payees: ConstructorParameters<typeof FakeRecipientDirectory>[0],
) {
  const recipientDirectory = new FakeRecipientDirectory(payees)
  const deps = fullDeps({ recipientDirectory })
  return {
    deps,
    recipientDirectory,
    billRecipient: makeBillRecipient(deps),
  }
}

describe('billRecipient', () => {
  it('names the verified receiver of a Pix QR bill', async () => {
    const { deps, recipientDirectory, billRecipient } = setup({
      [PIX_NO_AMOUNT]: HOLDER,
    })
    await deps.bills.save(
      bill({ id: 'qr', kind: 'PIX_QR', code: PIX_NO_AMOUNT, entityId: 'pj' }),
    )

    expect(await billRecipient(TENANT, 'qr')).toEqual({
      ...HOLDER,
      verified: true,
    })
    expect(recipientDirectory.lookups).toEqual([
      { query: PIX_NO_AMOUNT, scope: { tenantId: TENANT, entityId: 'pj' } },
    ])
  })

  it('checks the Pix code of a boleto that carries one', async () => {
    const { deps, recipientDirectory, billRecipient } = setup({
      [PIX_NO_AMOUNT]: HOLDER,
    })
    await deps.bills.save(
      bill({ id: 'bolepix', code: BOLETO_LINE, pixCode: PIX_NO_AMOUNT }),
    )

    expect((await billRecipient(TENANT, 'bolepix'))?.verified).toBe(true)
    expect(recipientDirectory.lookups[0]?.query).toBe(PIX_NO_AMOUNT)
  })

  it('falls back to the payee, unverified, when the lookup fails', async () => {
    const { deps, billRecipient } = setup({
      [PIX_NO_AMOUNT]: new Error('directory down'),
    })
    await deps.bills.save(
      bill({ id: 'qr', kind: 'PIX_QR', code: PIX_NO_AMOUNT, payee: null }),
    )

    expect(await billRecipient(TENANT, 'qr')).toEqual({
      name: 'Unknown',
      taxId: null,
      bank: null,
      verified: false,
    })
  })

  it('has nothing to check on a bill without a Pix code', async () => {
    const { deps, recipientDirectory, billRecipient } = setup({})
    await deps.bills.save(bill({ id: 'boleto', code: BOLETO_LINE }))
    await deps.bills.save(bill({ id: 'key', kind: 'PIX_KEY', code: 'a@b.c' }))

    expect(await billRecipient(TENANT, 'boleto')).toBeNull()
    expect(await billRecipient(TENANT, 'key')).toBeNull()
    expect(recipientDirectory.lookups).toEqual([])
  })

  it('refuses a bill that does not exist', async () => {
    const { billRecipient } = setup({})

    await expect(billRecipient(TENANT, 'missing')).rejects.toBeInstanceOf(
      NotFoundError,
    )
  })
})
