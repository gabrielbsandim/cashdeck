import { describe, expect, it } from 'vitest'
import { createFinancialEntity } from '@/entities/financial-entity'
import { availableToPay, createAccount } from '@/entities/account'
import { createTransaction, transactionKind } from '@/entities/transaction'
import { Money } from '@/money/money'

const base = { id: 'e1', tenantId: 't1' }

describe('createFinancialEntity', () => {
  it('creates a personal and a company entity', () => {
    const pf = createFinancialEntity({
      ...base,
      kind: 'PF',
      name: ' Personal ',
      taxId: '52998224725',
    })
    expect(pf.name).toBe('Personal')
    expect(pf.taxRegime).toBeNull()

    const pj = createFinancialEntity({
      ...base,
      kind: 'PJ',
      name: 'Company',
      taxId: '11222333000181',
      taxRegime: 'SIMPLES_NACIONAL',
    })
    expect(pj.taxId.kind).toBe('CNPJ')
  })

  it('rejects mismatched tax ids and regimes', () => {
    expect(() =>
      createFinancialEntity({
        ...base,
        kind: 'PJ',
        name: 'x',
        taxId: '52998224725',
      }),
    ).toThrow('A PJ entity needs a matching tax id.')
    expect(() =>
      createFinancialEntity({
        ...base,
        kind: 'PF',
        name: 'x',
        taxId: '52998224725',
        taxRegime: 'MEI',
      }),
    ).toThrow('no company tax regime')
    expect(() =>
      createFinancialEntity({
        ...base,
        kind: 'PJ',
        name: 'x',
        taxId: '11222333000181',
      }),
    ).toThrow('needs a tax regime')
  })
})

const accountInput = {
  id: 'a1',
  tenantId: 't1',
  entityId: 'e1',
  institutionId: 'i1',
  name: 'Main',
  type: 'CHECKING' as const,
  origin: 'CONNECTED' as const,
  balance: Money.of(10_000),
}

describe('createAccount', () => {
  it('defaults isReserve to false and allows a cash reserve', () => {
    expect(createAccount(accountInput).isReserve).toBe(false)
    expect(createAccount({ ...accountInput, isReserve: true }).isReserve).toBe(
      true,
    )
  })

  it('rejects a credit card as the reserve', () => {
    expect(() =>
      createAccount({ ...accountInput, type: 'CREDIT_CARD', isReserve: true }),
    ).toThrow('Only a cash account can be the reserve.')
  })

  it('computes the amount available to pay bills', () => {
    expect(availableToPay(createAccount(accountInput)).cents).toBe(10_000)
    expect(
      availableToPay(createAccount({ ...accountInput, type: 'CREDIT_CARD' }))
        .cents,
    ).toBe(0)
    expect(
      availableToPay(createAccount({ ...accountInput, balance: Money.of(-5) }))
        .cents,
    ).toBe(0)
  })
})

const txInput = {
  id: 'tx1',
  tenantId: 't1',
  accountId: 'a1',
  amount: Money.of(-1500),
  bookedOn: '2026-10-08',
  description: 'Market',
}

describe('createTransaction', () => {
  it('classifies income, expense and transfer', () => {
    expect(transactionKind(createTransaction(txInput))).toBe('EXPENSE')
    expect(
      transactionKind(createTransaction({ ...txInput, amount: Money.of(100) })),
    ).toBe('INCOME')
    const transfer = createTransaction({ ...txInput, transferGroupId: 'g1' })
    expect(transactionKind(transfer)).toBe('TRANSFER')
    expect(transfer.categoryId).toBeNull()
  })

  it('rejects zero amounts and bad dates', () => {
    expect(() =>
      createTransaction({ ...txInput, amount: Money.zero() }),
    ).toThrow('must move money')
    expect(() =>
      createTransaction({ ...txInput, bookedOn: '08/10/2026' }),
    ).toThrow('ISO date')
  })
})
