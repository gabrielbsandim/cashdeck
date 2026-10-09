import { describe, expect, it } from 'vitest'
import { type AccountType } from '@/entities/account'
import { createTransaction } from '@/entities/transaction'
import {
  classifyFlow,
  type FlowLine,
  isCardBillPayment,
  isInvestment,
  namesOwner,
} from '@/insights/money-flow'
import { Money } from '@/money/money'

function line(
  id: string,
  cents: number,
  options: {
    accountId?: string
    accountType?: AccountType
    bookedOn?: string
    description?: string
    categoryKey?: string | null
    transferGroupId?: string | null
  } = {},
): FlowLine {
  return {
    transaction: createTransaction({
      id,
      tenantId: 't1',
      accountId: options.accountId ?? 'checking',
      amount: Money.of(cents),
      bookedOn: options.bookedOn ?? '2026-10-05',
      description: options.description ?? `Line ${id}`,
      transferGroupId: options.transferGroupId ?? null,
    }),
    accountType: options.accountType ?? 'CHECKING',
    categoryKey: options.categoryKey ?? null,
  }
}

describe('money flow', () => {
  it('spots a card bill payment', () => {
    expect(isCardBillPayment('PAGAMENTO FATURA CARTAO')).toBe(true)
    expect(isCardBillPayment('Pgto fatura')).toBe(true)
    expect(isCardBillPayment('Pagamento recebido')).toBe(true)
    expect(isCardBillPayment('PAG CARTAO DE CREDITO')).toBe(true)
    expect(isCardBillPayment('Fatura energia')).toBe(false)
    expect(isCardBillPayment('Pagamento boleto')).toBe(false)
    expect(isCardBillPayment('Cartao presente')).toBe(false)
  })

  it('classifies income, spending and neutral moves', () => {
    const kinds = classifyFlow([
      line('salary', 500_000),
      line('market', -20_000),
      line('card-buy', -5_000, {
        accountId: 'card',
        accountType: 'CREDIT_CARD',
      }),
      line('refund', 1_000, { accountId: 'card', accountType: 'CREDIT_CARD' }),
      line('bill', -30_000, { description: 'Pagamento fatura' }),
      line('pro-labore', 100_000, { transferGroupId: 'g1' }),
      line('broker', -50_000, { categoryKey: 'investments' }),
      line('food', -3_000, { categoryKey: 'restaurants' }),
    ])
    expect(Object.fromEntries(kinds)).toEqual({
      salary: 'INCOME',
      market: 'EXPENSE',
      'card-buy': 'EXPENSE',
      refund: 'NEUTRAL',
      bill: 'NEUTRAL',
      'pro-labore': 'NEUTRAL',
      broker: 'NEUTRAL',
      food: 'EXPENSE',
    })
  })

  it('treats investments and Pix to the own name as moves', () => {
    expect(isInvestment('APLICAÇÃO DE CDB')).toBe(true)
    expect(isInvestment('Resgate Tesouro Selic')).toBe(true)
    expect(isInvestment('Cdbx loja')).toBe(false)
    const owners = ['Maria Exemplo Silva', 'Exemplo']
    expect(namesOwner('Pix enviado para MARIA EXEMPLO SILVA', owners)).toBe(
      true,
    )
    expect(namesOwner('JOANA MARIA EXEMPLO SILVA', owners)).toBe(true)
    expect(namesOwner('Exemplo Comercio', owners)).toBe(false)
    expect(namesOwner('MARIA EXEMPLO SILVANA', owners)).toBe(false)
    const kinds = classifyFlow(
      [
        line('cdb-out', -50_000, { description: 'EMISSAO DE CDB' }),
        line('cdb-in', 20_000, { description: 'RESGATE DE CDB' }),
        line('own-out', -30_000, { description: 'MARIA EXEMPLO SILVA' }),
        line('own-in', 9_000, {
          description: 'Pix recebido de Maria Exemplo Silva',
        }),
        line('other', -4_000, { description: 'JOSE EXEMPLO SILVA' }),
      ],
      { ownNames: owners },
    )
    expect(Object.fromEntries(kinds)).toEqual({
      'cdb-out': 'NEUTRAL',
      'cdb-in': 'NEUTRAL',
      'own-out': 'NEUTRAL',
      'own-in': 'NEUTRAL',
      other: 'EXPENSE',
    })
  })

  it('pairs a card bill paid from checking with the credit on the card', () => {
    const card = { accountId: 'card', accountType: 'CREDIT_CARD' as const }
    const kinds = classifyFlow([
      line('paid', -80_000, { description: 'BANCO EMISSOR' }),
      line('credit', 80_000, { ...card, description: 'Inclusao Ciclo' }),
      line('twice', 80_000, { ...card, description: 'Credito avulso' }),
      line('buy', -80_000, { ...card, description: 'Loja' }),
      line('rent', -70_000, { description: 'Aluguel' }),
    ])
    expect(Object.fromEntries(kinds)).toEqual({
      paid: 'NEUTRAL',
      credit: 'NEUTRAL',
      twice: 'NEUTRAL',
      buy: 'EXPENSE',
      rent: 'EXPENSE',
    })
  })

  it('pairs off the two legs of a move between own accounts', () => {
    const kinds = classifyFlow([
      line('out', -10_000, { accountId: 'a', bookedOn: '2026-10-05' }),
      line('in', 10_000, { accountId: 'b', bookedOn: '2026-10-06' }),
      line('again-out', -10_000, { accountId: 'a', bookedOn: '2026-10-06' }),
      line('late-in', 10_000, { accountId: 'b', bookedOn: '2026-10-20' }),
      line('same-account', 7_000, { accountId: 'a' }),
      line('same-out', -7_000, { accountId: 'a' }),
      line('card-out', -4_000, {
        accountId: 'card',
        accountType: 'CREDIT_CARD',
      }),
      line('cash-in', 4_000, { accountId: 'b' }),
    ])
    expect(Object.fromEntries(kinds)).toEqual({
      out: 'NEUTRAL',
      in: 'NEUTRAL',
      'again-out': 'EXPENSE',
      'late-in': 'INCOME',
      'same-account': 'INCOME',
      'same-out': 'EXPENSE',
      'card-out': 'EXPENSE',
      'cash-in': 'INCOME',
    })
  })
})
