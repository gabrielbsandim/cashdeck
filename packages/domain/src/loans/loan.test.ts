import { describe, expect, it } from 'vitest'
import { readBradescoLoanStatement } from '@/loans/bradesco-statement'
import {
  chargesInstallment,
  installmentIn,
  type LoanInstallment,
  loanBalanceOn,
  type LoanStatement,
  loanStanding,
  prepayment,
} from '@/loans/loan'

const HEADER = [
  'CONTRATO 1234567 Data do contrato 10/01/2026 Extrato Financeiro Ativo',
  'DADOS FINANCEIROS 3.000,00 Valor Financiamento TAXAS Efetiva(a.a)',
  'CET(a.a) 12,00% 12,50% SALDO DEVEDOR 1.000,00 Valor Imóvel 9.000,00',
  'Sistema Amortização SAC 1/3 Prazo SFH - 901 Carteira TR Indexador',
  'ENCARGOS Parcela Data Amortização Valor Total Parcela',
  '0 10/01/2026 50,71 0,00 1,000000 31,51 19,20 0,00 0,00 0,00 0,00',
  '1,000000 3.000,00 Paga 15/01/2026 50,71 Valor Juros 0,00',
]

const ROWS = [
  '1 17/02/2026 1.100,00 1.000,00 1,001719 30,00 10,00 25,00 20,00 5,00',
  '0,00 1,001719 2.000,00 Paga 20/02/2026 1.125,00',
  '15,00',
  '2 17/03/2026 1.085,00 1.000,00 1,000000 30,00 10,00 25,00 0,00 0,00',
  '0,00 1,000000 1.000,00 A Vencer - 0,00 20,00',
  '3 17/04/2026 1.075,00 1.000,00 1,000000 30,00 10,00 25,00 0,00 0,00',
  '0,00 1,000000 0,00 A Vencer - 0,00 10,00',
]

const statement = [...HEADER, ...ROWS].join('\n')

const installment = (
  number: number,
  overrides: Partial<LoanInstallment> = {},
): LoanInstallment => ({
  number,
  dueOn: `2026-0${number + 1}-17`,
  total: 1000,
  principal: 1000,
  interest: 100,
  fees: 10,
  lateFees: 0,
  balance: 0,
  paidOn: null,
  paid: null,
  ...overrides,
})

const loan = (installments: LoanInstallment[]): LoanStatement => ({
  lender: 'Bank',
  contract: '1',
  system: 'SAC',
  indexer: 'TR',
  effectiveRate: 12,
  cet: 12.5,
  principal: 3000,
  propertyValue: null,
  signedOn: '2026-01-10',
  termMonths: 3,
  installments,
})

describe('readBradescoLoanStatement', () => {
  it('reads the terms and every installment of the schedule', () => {
    const read = readBradescoLoanStatement(statement)

    expect(read).toMatchObject({
      lender: 'Bradesco',
      contract: '1234567',
      system: 'SAC',
      indexer: 'TR',
      effectiveRate: 12,
      cet: 12.5,
      principal: 300000,
      propertyValue: 900000,
      signedOn: '2026-01-10',
      termMonths: 3,
    })
    expect(read?.installments).toEqual([
      {
        number: 1,
        dueOn: '2026-02-17',
        total: 110000,
        principal: 100000,
        interest: 1500,
        fees: 6500,
        lateFees: 2500,
        balance: 200000,
        paidOn: '2026-02-20',
        paid: 112500,
      },
      expect.objectContaining({ number: 2, paidOn: null, paid: null }),
      expect.objectContaining({ number: 3, balance: 0, interest: 1000 }),
    ])
  })

  it('leaves the property value and the indexer out when not printed', () => {
    const bare = statement
      .replace('Valor Imóvel 9.000,00', '')
      .replace('TR Indexador', '')

    expect(readBradescoLoanStatement(bare)).toMatchObject({
      propertyValue: null,
      indexer: '',
    })
  })

  it('reads nothing from another document', () => {
    expect(readBradescoLoanStatement('Fatura do cartão')).toBeNull()
  })

  it('reads nothing when a term or the schedule is missing', () => {
    const noSystem = statement.replace('Sistema Amortização SAC', '')
    const noRows = [...HEADER].join('\n')

    expect(readBradescoLoanStatement(noSystem)).toBeNull()
    expect(readBradescoLoanStatement(noRows)).toBeNull()
  })
})

describe('loanStanding', () => {
  const schedule = [
    installment(1, {
      balance: 2000,
      paidOn: '2026-02-20',
      paid: 1150,
      lateFees: 50,
    }),
    installment(2, { balance: 1000 }),
    installment(3, { balance: 0 }),
  ]

  it('splits what was paid from what is still owed', () => {
    const standing = loanStanding(loan(schedule), '2026-03-01')

    expect(standing.balance).toBe(2000)
    expect(standing.paid).toEqual({
      count: 1,
      total: 1150,
      interest: 100,
      principal: 1000,
      fees: 10,
      lateFees: 50,
    })
    expect(standing.remaining).toMatchObject({ count: 2, total: 2000 })
    expect(standing.open.map(open => open.number)).toEqual([2, 3])
    expect(standing.lastDueOn).toBe('2026-04-17')
  })

  it('counts a past due installment the statement left open as debited', () => {
    const standing = loanStanding(loan(schedule), '2026-03-20')

    expect(standing.paid).toMatchObject({ count: 2, total: 2150 })
    expect(standing.balance).toBe(1000)
  })

  it('keeps an installment due on a weekend open until the business day', () => {
    const weekend = [installment(1, { dueOn: '2026-10-10', balance: 0 })]

    expect(loanStanding(loan(weekend), '2026-10-13').open).toHaveLength(1)
    expect(loanStanding(loan(weekend), '2026-10-14').open).toHaveLength(0)
  })

  it('owes nothing once every installment is behind', () => {
    const standing = loanStanding(loan([]), '2026-05-01')

    expect(standing.balance).toBe(0)
    expect(standing.lastDueOn).toBeNull()
  })
})

describe('loanBalanceOn', () => {
  it('drops by each installment once debited, the carnival one a day later, and nothing is owed after the last', () => {
    const unrecorded = loan([
      installment(1, { balance: 2000 }),
      installment(2, { balance: 1000 }),
      installment(3),
    ])
    expect(loanBalanceOn(unrecorded, '2026-02-18')).toBe(3000)
    expect(loanBalanceOn(unrecorded, '2026-02-19')).toBe(2000)
    expect(loanBalanceOn(unrecorded, '2026-05-01')).toBe(0)
  })
})

describe('prepayment', () => {
  const schedule = [
    installment(1, { balance: 2000, interest: 300 }),
    installment(2, { balance: 1000, interest: 200 }),
    installment(3, { balance: 0, interest: 100 }),
  ]

  it('cuts the installments it covers and the interest on what is left', () => {
    expect(prepayment(loan(schedule), '2026-01-20', 1500)).toEqual({
      amount: 1500,
      interestSaved: 150 + 150 + 100,
      feesSaved: 10,
      monthsCut: 1,
      lastDueOn: '2026-03-17',
      balanceAfter: 1500,
    })
  })

  it('pays the loan off when the amount covers the balance', () => {
    expect(prepayment(loan(schedule), '2026-01-20', 5000)).toMatchObject({
      monthsCut: 3,
      lastDueOn: null,
      balanceAfter: 0,
    })
  })

  it('simulates a positive amount only', () => {
    expect(() => prepayment(loan(schedule), '2026-01-20', 0)).toThrow(
      'positive',
    )
  })
})

describe('installments by amount and month', () => {
  const schedule = [
    installment(1, { total: 1100, paid: 1125, paidOn: '2026-02-20' }),
    installment(2, { total: 1085 }),
  ]

  it('knows a debit of a scheduled or a paid amount', () => {
    expect(chargesInstallment(loan(schedule), 1125)).toBe(true)
    expect(chargesInstallment(loan(schedule), 1085)).toBe(true)
    expect(chargesInstallment(loan(schedule), 999)).toBe(false)
  })

  it('finds the installment due in a month', () => {
    expect(installmentIn(loan(schedule), '2026-03')?.number).toBe(2)
    expect(installmentIn(loan(schedule), '2027-01')).toBeNull()
  })
})
