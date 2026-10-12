import { describe, expect, it } from 'vitest'
import { type LoanTerms, loanFromTerms } from '@/loans/loan-terms'
import { monthlyRate, prepayment } from '@/loans/loan'

// A 1% monthly rate, as a yearly effective one.
const EFFECTIVE = (1.01 ** 12 - 1) * 100

const terms: LoanTerms = {
  lender: 'Bank',
  contract: '7',
  system: 'PRICE',
  indexer: 'TR',
  effectiveRate: EFFECTIVE,
  cet: EFFECTIVE,
  principal: 4000,
  propertyValue: null,
  signedOn: '2025-12-10',
  termMonths: 5,
  paid: [
    { number: 2, dueOn: '2026-02-10', total: 1100, paid: 1101 },
    { number: 1, dueOn: '2026-01-10', total: 1090, paid: null },
  ],
  reference: { number: 2, principal: 990, interest: 100, fees: 10 },
  balance: 3000,
}

describe('loanFromTerms', () => {
  it('splits the paid installments and projects a Price schedule', () => {
    const loan = loanFromTerms(terms)

    expect(monthlyRate(EFFECTIVE)).toBeCloseTo(0.01, 10)
    expect(loan).toMatchObject({ lender: 'Bank', contract: '7', termMonths: 5 })
    expect(loan.installments).toEqual([
      {
        number: 1,
        dueOn: '2026-01-10',
        total: 1090,
        principal: 981,
        interest: 99,
        fees: 10,
        lateFees: 0,
        balance: 3990,
        paidOn: '2026-01-10',
        paid: 1090,
      },
      {
        number: 2,
        dueOn: '2026-02-10',
        total: 1100,
        principal: 990,
        interest: 100,
        fees: 10,
        lateFees: 0,
        balance: 3000,
        paidOn: '2026-02-10',
        paid: 1101,
      },
      expect.objectContaining({
        number: 3,
        dueOn: '2026-03-10',
        total: 1030,
        principal: 990,
        interest: 30,
        balance: 2010,
        paidOn: null,
      }),
      expect.objectContaining({
        number: 4,
        dueOn: '2026-04-10',
        principal: 1000,
        interest: 20,
        balance: 1010,
      }),
      expect.objectContaining({
        number: 5,
        dueOn: '2026-05-10',
        principal: 1010,
        interest: 10,
        balance: 0,
      }),
    ])
  })

  it('projects a SAC schedule with a fixed amortization', () => {
    const loan = loanFromTerms({ ...terms, system: 'SAC' })

    expect(
      loan.installments
        .slice(2)
        .map(({ principal, interest }) => [principal, interest]),
    ).toEqual([
      [1000, 30],
      [1000, 20],
      [1000, 10],
    ])
  })

  it('needs a paid installment that is also the reference', () => {
    expect(() => loanFromTerms({ ...terms, paid: [] })).toThrow('paid')
    expect(() =>
      loanFromTerms({ ...terms, reference: { ...terms.reference, number: 9 } }),
    ).toThrow('reference')
  })
})

describe('Price prepayment', () => {
  const loan = loanFromTerms(terms)

  it('keeps the installment and pays the smaller balance off sooner', () => {
    expect(prepayment(loan, '2026-02-20', 1000)).toEqual({
      amount: 1000,
      interestSaved: 30,
      feesSaved: 10,
      monthsCut: 1,
      lastDueOn: '2026-04-10',
      balanceAfter: 2000,
    })
  })

  it('pays the loan off when the amount covers the balance', () => {
    expect(prepayment(loan, '2026-02-20', 5000)).toMatchObject({
      interestSaved: 60,
      monthsCut: 3,
      lastDueOn: null,
      balanceAfter: 0,
    })
    expect(prepayment(loan, '2027-01-01', 100)).toMatchObject({
      interestSaved: 0,
      monthsCut: 0,
    })
  })
})
