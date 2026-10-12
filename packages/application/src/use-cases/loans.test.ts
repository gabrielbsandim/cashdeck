import { describe, expect, it } from 'vitest'
import { fullDeps } from '@/testing/deps.test-helpers'
import { TENANT } from '@/testing/scenario.test-helpers'
import { loanStatement as statement } from '@/testing/loans.test-helpers'
import { FakeDocumentTextReader } from '@/testing/services'
import { makeLoans } from '@/use-cases/loans'

const upload = {
  entity: 'PF' as const,
  fileName: 'extrato.pdf',
  mimeType: 'application/pdf',
  base64: 'JVBERi0xLjQ=',
}

const setup = (text: string | null) => {
  const deps = fullDeps({ documentText: new FakeDocumentTextReader(text) })
  return { deps, loans: makeLoans(deps) }
}

describe('loans', () => {
  it('imports a statement and shows what is paid and still owed', async () => {
    const { loans } = setup(statement('1234567', '10/08/2026'))

    const view = await loans.importStatement(TENANT, upload)

    expect(view).toMatchObject({
      id: 'bradesco-1234567',
      entity: 'PF',
      name: 'Bradesco 1234567',
      system: 'SAC',
      effectiveRate: 12,
      principal: { cents: 300000 },
      propertyValue: { cents: 900000 },
      paidCount: 1,
      balance: { cents: 200000 },
      lastDueOn: '2026-11-17',
      next: { number: 2, dueOn: '2026-10-17', total: { cents: 108500 } },
      remaining: {
        count: 2,
        total: { cents: 216000 },
        interest: { cents: 3000 },
        fees: { cents: 13000 },
      },
      paid: { total: { cents: 112500 }, lateFees: { cents: 2500 } },
      importedAt: '2026-10-08T12:00:00.000Z',
    })
    expect(view.upcoming.map(installment => installment.number)).toEqual([2, 3])
  })

  it('lists loans by signing date and replaces a contract imported again', async () => {
    const { deps, loans } = setup(statement('1234567', '10/08/2026'))
    await loans.importStatement(TENANT, upload)
    await loans.importStatement(TENANT, upload)
    const older = makeLoans({
      ...deps,
      documentText: new FakeDocumentTextReader(
        statement('7654321', '01/01/2020'),
      ),
    })
    await older.importStatement(TENANT, upload)

    const { items } = await loans.list(TENANT)

    expect(items.map(item => item.contract)).toEqual(['7654321', '1234567'])
  })

  it('shows no next installment once the schedule is behind', async () => {
    const { deps, loans } = setup(statement('1234567', '10/08/2026'))
    await loans.importStatement(TENANT, upload)
    deps.clock.set(new Date('2026-12-01T12:00:00Z'))

    const [view] = (await loans.list(TENANT)).items

    expect(view).toMatchObject({ next: null, balance: { cents: 0 } })
  })

  it('keeps a statement without the property value', async () => {
    const text = statement('1234567', '10/08/2026').replace(
      'Valor Imóvel 9.000,00',
      '',
    )
    const { loans } = setup(text)

    const view = await loans.importStatement(TENANT, upload)

    expect(view.propertyValue).toBeNull()
  })

  it('refuses a file that is not a loan statement', async () => {
    await expect(
      setup('Fatura do cartão').loans.importStatement(TENANT, upload),
    ).rejects.toThrow('loan statement')
    await expect(
      setup(null).loans.importStatement(TENANT, upload),
    ).rejects.toThrow('loan statement')
  })

  it('simulates a prepayment and removes a loan', async () => {
    const { loans } = setup(statement('1234567', '10/08/2026'))
    const { id } = await loans.importStatement(TENANT, upload)

    expect(await loans.simulatePrepayment(TENANT, id, 150000)).toEqual({
      amount: { cents: 150000, currency: 'BRL' },
      interestSaved: { cents: 2500, currency: 'BRL' },
      feesSaved: { cents: 6500, currency: 'BRL' },
      monthsCut: 1,
      lastDueOn: '2026-10-17',
      balanceAfter: { cents: 50000, currency: 'BRL' },
    })

    expect(await loans.remove(TENANT, id)).toEqual({ id })
    expect((await loans.list(TENANT)).items).toEqual([])
    await expect(loans.remove(TENANT, id)).rejects.toThrow('Loan')
  })

  it('registers a loan from the terms a bank app shows', async () => {
    const { loans } = setup(null)

    const view = await loans.register(TENANT, {
      lender: 'Caixa',
      contract: '42',
      system: 'PRICE',
      indexer: 'TR',
      effectiveRate: (1.01 ** 12 - 1) * 100,
      cet: 12.7,
      principal: 4000,
      propertyValue: null,
      signedOn: '2026-08-10',
      termMonths: 4,
      paid: [{ number: 1, dueOn: '2026-09-10', total: 1100, paid: null }],
      reference: { number: 1, principal: 990, interest: 100, fees: 10 },
      balance: 3000,
    })

    expect(view).toMatchObject({
      id: 'caixa-42',
      entity: 'PF',
      system: 'PRICE',
      paidCount: 1,
      balance: { cents: 3000 },
      next: { number: 2, dueOn: '2026-10-10', total: { cents: 1030 } },
    })
    expect(
      await loans.simulatePrepayment(TENANT, 'caixa-42', 1000),
    ).toMatchObject({ monthsCut: 1, interestSaved: { cents: 30 } })
  })
})
