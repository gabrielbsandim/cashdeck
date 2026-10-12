import { describe, expect, it } from 'vitest'
import { Money } from '@/money/money'
import {
  balanceAtEndOf,
  monthEnds,
  netWorthChange,
  netWorthOn,
  positionValueOn,
  type RolledBackAccount,
  type SnapshottedPosition,
} from '@/net-worth/net-worth'

const checking: RolledBackAccount = {
  kind: 'CASH',
  balance: Money.of(300000),
  movements: [
    { on: '2026-09-10', amount: Money.of(-50000) },
    { on: '2026-10-05', amount: Money.of(800000) },
    { on: '2026-10-06', amount: Money.of(-600000) },
  ],
}

const card: RolledBackAccount = {
  kind: 'CARD',
  balance: Money.of(-120000),
  movements: [
    { on: '2026-09-15', amount: Money.of(-40000) },
    { on: '2026-10-02', amount: Money.of(200000) },
  ],
}

const broker: RolledBackAccount = {
  kind: 'INVESTMENT',
  balance: Money.of(100000),
  movements: [],
}

const cdb: SnapshottedPosition = {
  current: Money.of(510000),
  snapshots: [
    { day: '2026-09-30', cents: 505000 },
    { day: '2026-08-31', cents: 500000 },
  ],
}

describe('balanceAtEndOf', () => {
  it('undoes what was booked after the day', () => {
    expect(balanceAtEndOf(checking, '2026-09-30').cents).toBe(100000)
    expect(balanceAtEndOf(checking, '2026-08-31').cents).toBe(150000)
    expect(balanceAtEndOf(checking, '2026-10-08').cents).toBe(300000)
  })
})

describe('positionValueOn', () => {
  it('reads the last snapshot on or before the day, today the balance', () => {
    expect(positionValueOn(cdb, '2026-10-08', '2026-10-08').cents).toBe(510000)
    expect(positionValueOn(cdb, '2026-09-30', '2026-10-08').cents).toBe(505000)
    expect(positionValueOn(cdb, '2026-09-15', '2026-10-08').cents).toBe(500000)
    expect(positionValueOn(cdb, '2026-07-31', '2026-10-08').cents).toBe(0)
  })
})

describe('netWorthOn', () => {
  it('adds cash and investments and takes off what the cards owe', () => {
    const today = netWorthOn(
      '2026-10-08',
      '2026-10-08',
      [checking, card, broker],
      [cdb],
    )
    expect(today).toEqual({
      on: '2026-10-08',
      cash: Money.of(300000),
      investments: Money.of(610000),
      realEstate: Money.zero(),
      vehicles: Money.zero(),
      otherAssets: Money.zero(),
      cardDebt: Money.of(120000),
      loanDebt: Money.zero(),
      assets: Money.of(910000),
      liabilities: Money.of(120000),
      total: Money.of(790000),
    })
    const september = netWorthOn(
      '2026-09-30',
      '2026-10-08',
      [checking, card, broker],
      [cdb],
    )
    expect(september.cash.cents).toBe(100000)
    expect(september.cardDebt.cents).toBe(320000)
    expect(september.total.cents).toBe(100000 + 605000 - 320000)
  })

  it('never counts a card in credit as debt', () => {
    const paidAhead: RolledBackAccount = {
      kind: 'CARD',
      balance: Money.of(5000),
      movements: [],
    }
    expect(
      netWorthOn('2026-10-08', '2026-10-08', [paidAhead], []).cardDebt.cents,
    ).toBe(0)
  })

  it('adds what is owned by kind and takes off what loans still owe', () => {
    const home = {
      kind: 'PROPERTY' as const,
      acquiredOn: '2025-03-10',
      soldOn: null,
      valuations: [{ day: '2026-10-01', cents: 60000000 }],
    }
    const car = {
      kind: 'VEHICLE' as const,
      acquiredOn: '2024-01-15',
      soldOn: null,
      valuations: [
        { day: '2026-09-01', cents: 9000000 },
        { day: '2026-10-01', cents: 8900000 },
      ],
    }
    const bike = { ...car, kind: 'OTHER' as const, valuations: [] }
    const loan = {
      lender: 'Banco Exemplo',
      contract: '1',
      system: 'SAC' as const,
      indexer: 'TR',
      effectiveRate: 10,
      cet: 11,
      principal: 40000000,
      propertyValue: null,
      signedOn: '2025-03-10',
      termMonths: 2,
      installments: [
        {
          number: 1,
          dueOn: '2026-09-10',
          total: 20300000,
          principal: 20000000,
          interest: 300000,
          fees: 0,
          lateFees: 0,
          balance: 20000000,
          paidOn: '2026-09-10',
          paid: 20300000,
        },
        {
          number: 2,
          dueOn: '2026-10-13',
          total: 20150000,
          principal: 20000000,
          interest: 150000,
          fees: 0,
          lateFees: 0,
          balance: 0,
          paidOn: null,
          paid: null,
        },
      ],
    }
    const belongings = { assets: [home, car, bike], loans: [loan] }
    const today = netWorthOn('2026-10-08', '2026-10-08', [], [], belongings)
    expect(today).toMatchObject({
      realEstate: Money.of(60000000),
      vehicles: Money.of(8900000),
      otherAssets: Money.zero(),
      loanDebt: Money.of(20000000),
      assets: Money.of(68900000),
      liabilities: Money.of(20000000),
      total: Money.of(48900000),
    })
    const august = netWorthOn('2026-08-31', '2026-10-08', [], [], belongings)
    expect(august.realEstate.cents).toBe(60000000)
    expect(august.vehicles.cents).toBe(9000000)
    expect(august.loanDebt.cents).toBe(40000000)
    const before = netWorthOn('2025-01-31', '2026-10-08', [], [], belongings)
    expect(before.realEstate.cents).toBe(0)
    expect(before.loanDebt.cents).toBe(0)
  })
})

describe('monthEnds', () => {
  it('lists the month ends before the current month, oldest first', () => {
    expect(monthEnds('2026-10-08', 3)).toEqual([
      '2026-07-31',
      '2026-08-31',
      '2026-09-30',
    ])
    expect(monthEnds('2026-03-01', 2)).toEqual(['2026-01-31', '2026-02-28'])
  })
})

describe('netWorthChange', () => {
  it('gives the change and its share of the previous value', () => {
    expect(netWorthChange(Money.of(110000), Money.of(100000))).toEqual({
      amount: Money.of(10000),
      percent: 10,
    })
    expect(netWorthChange(Money.of(-5000), Money.of(-10000))).toEqual({
      amount: Money.of(5000),
      percent: 50,
    })
    expect(netWorthChange(Money.of(5000), Money.zero())).toEqual({
      amount: Money.of(5000),
      percent: null,
    })
  })
})
