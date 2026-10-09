import { describe, expect, it } from 'vitest'
import { createFinancialEntity } from '@/entities/financial-entity'
import {
  availableToPay,
  createAccount,
  creditUsedPercent,
  openBillOf,
} from '@/entities/account'
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

  it('keeps a credit line only on a card and reads the share in use', () => {
    const credit = {
      limit: Money.of(10_000),
      available: Money.of(2_500),
      closesOn: '2026-10-20',
      dueOn: '2026-10-27',
      brand: 'VISA',
      openBill: null,
    }
    const card = createAccount({
      ...accountInput,
      type: 'CREDIT_CARD',
      credit,
      numberSuffix: '1234',
    })
    expect(card).toMatchObject({ credit, numberSuffix: '1234' })
    expect(createAccount(accountInput)).toMatchObject({
      credit: null,
      numberSuffix: null,
    })
    expect(() => createAccount({ ...accountInput, credit })).toThrow(
      'Only a credit card has a credit line.',
    )
    expect(creditUsedPercent(credit)).toBe(75)
    expect(creditUsedPercent({ ...credit, available: Money.of(-50) })).toBe(100)
    expect(creditUsedPercent({ ...credit, available: Money.of(20_000) })).toBe(
      0,
    )
    expect(creditUsedPercent({ ...credit, limit: Money.zero() })).toBeNull()
  })

  it('reads the open bill, else everything the card owes', () => {
    const owing = createAccount({
      ...accountInput,
      type: 'CREDIT_CARD',
      balance: Money.of(-9_000),
    })
    expect(openBillOf(owing).cents).toBe(9_000)
    expect(openBillOf({ ...owing, balance: Money.of(300) }).cents).toBe(0)
    const credit = {
      limit: Money.of(10_000),
      available: Money.of(1_000),
      closesOn: null,
      dueOn: null,
      brand: null,
      openBill: Money.of(4_000),
    }
    expect(openBillOf({ ...owing, credit }).cents).toBe(4_000)
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

  it('keeps the merchant and a valid installment', () => {
    const plain = createTransaction(txInput)
    expect(plain).toMatchObject({ merchant: null, installment: null })
    const installment = { number: 3, count: 10, purchaseOn: '2026-08-01' }
    expect(
      createTransaction({ ...txInput, merchant: '  Loja  ', installment }),
    ).toMatchObject({ merchant: 'Loja', installment })
    expect(createTransaction({ ...txInput, merchant: ' ' }).merchant).toBeNull()
    for (const bad of [
      { number: 0, count: 3 },
      { number: 4, count: 3 },
      { number: 1, count: 1 },
      { number: 1.5, count: 3 },
    ]) {
      expect(() =>
        createTransaction({
          ...txInput,
          installment: { ...bad, purchaseOn: null },
        }),
      ).toThrow('An installment is 1 to N of N')
    }
  })
})
