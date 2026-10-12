import { describe, expect, it } from 'vitest'
import {
  createBudget,
  type CreditLine,
  Money,
  recipientKeys,
  recurrenceKey,
} from '@cashdeck/domain'
import { type SafeToSpendView } from '@/dtos/safe-to-spend'
import { type Recurrence } from '@/ports/records'
import {
  account,
  bill,
  fullDeps,
  transaction,
} from '@/testing/deps.test-helpers'
import { TENANT } from '@/testing/scenario.test-helpers'
import { AUTO_DEBIT_COLLECTION } from '@/use-cases/auto-debit'
import { FUNDING_ITEMS_COLLECTION } from '@/use-cases/funding-plan'
import { makeSafeToSpend } from '@/use-cases/safe-to-spend'
import { makeSetSpendingPlan } from '@/use-cases/spending-plan'

const EMPLOYER = '12345678000195'
const OWN_CPF = '52998224725'

const credit = (
  dueOn: string,
  closesOn: string,
  openBill: number,
): CreditLine => ({
  limit: Money.of(1_000_000),
  available: Money.of(500_000),
  closesOn,
  dueOn,
  brand: null,
  openBill: Money.of(openBill),
})

const recurrence = (
  overrides: Partial<Recurrence> & Pick<Recurrence, 'id' | 'key'>,
): Recurrence => ({
  tenantId: TENANT,
  entityId: 'pf',
  name: 'Streaming Plus',
  amount: Money.of(5590),
  dayOfMonth: 15,
  status: 'CONFIRMED',
  lastSeenOn: null,
  ...overrides,
})

async function seed() {
  const deps = fullDeps()
  const accounts = [
    account({ id: 'chk', entityId: 'pf', balance: Money.of(500000) }),
    account({
      id: 'res',
      entityId: 'pf',
      type: 'SAVINGS',
      isReserve: true,
      balance: Money.of(15000),
    }),
    account({ id: 'usd', entityId: 'pf', balance: Money.of(9000, 'USD') }),
    account({
      id: 'card',
      entityId: 'pf',
      name: 'Gold card',
      type: 'CREDIT_CARD',
      balance: Money.of(-80000),
      credit: credit('2026-10-17', '2026-10-10', 80000),
    }),
    account({
      id: 'boleto-card',
      entityId: 'pf',
      type: 'CREDIT_CARD',
      credit: credit('2026-10-15', '2026-10-08', 30000),
    }),
    account({
      id: 'early-card',
      entityId: 'pf',
      type: 'CREDIT_CARD',
      credit: credit('2026-10-12', '2026-10-05', 40000),
    }),
    account({
      id: 'empty-card',
      entityId: 'pf',
      type: 'CREDIT_CARD',
      credit: credit('2026-10-20', '2026-10-13', 0),
    }),
    account({
      id: 'late-card',
      entityId: 'pf',
      type: 'CREDIT_CARD',
      credit: credit('2026-11-10', '2026-11-03', 25000),
    }),
  ]
  for (const row of accounts) {
    await deps.accounts.save(row)
  }
  await deps.cardBills.saveAll([
    {
      id: 'old',
      tenantId: TENANT,
      accountId: 'card',
      externalId: null,
      closesOn: '2026-09-10',
      dueOn: '2026-09-17',
      total: Money.of(70000),
      minimum: null,
    },
  ])
  const incomes = [
    { id: 's1', bookedOn: '2026-08-25', amount: 800000 },
    { id: 's2', bookedOn: '2026-09-25', amount: 800000 },
  ]
  for (const row of incomes) {
    await deps.transactions.save(
      transaction({
        ...row,
        accountId: 'chk',
        amount: Money.of(row.amount),
        description: 'Salary',
        counterparty: EMPLOYER,
      }),
    )
  }
  for (const [id, bookedOn] of [
    ['p1', '2026-09-05'],
    ['p2', '2026-10-05'],
  ] as const) {
    await deps.transfers.save({
      id: `tr-${id}`,
      tenantId: TENANT,
      kind: 'PRO_LABORE',
      amount: Money.of(300000),
      at: new Date(`${bookedOn}T12:00:00Z`),
      rail: 'PIX',
      fromAccountId: 'pj-chk',
      toAccountId: 'chk',
      document: null,
    })
    await deps.transactions.save(
      transaction({
        id,
        accountId: 'chk',
        bookedOn,
        amount: Money.of(300000),
        transferGroupId: `tr-${id}`,
      }),
    )
  }
  const others = [
    transaction({
      id: 'own1',
      accountId: 'chk',
      bookedOn: '2026-08-12',
      amount: Money.of(900000),
      counterparty: OWN_CPF,
    }),
    transaction({
      id: 'own2',
      accountId: 'chk',
      bookedOn: '2026-09-12',
      amount: Money.of(900000),
      counterparty: OWN_CPF,
    }),
    transaction({
      id: 'unlinked',
      accountId: 'chk',
      bookedOn: '2026-10-01',
      amount: Money.of(1000),
      transferGroupId: 'missing',
    }),
    transaction({
      id: 'cb1',
      accountId: 'chk',
      bookedOn: '2026-09-02',
      amount: Money.of(500),
      description: 'Cashback',
    }),
    transaction({
      id: 'cb2',
      accountId: 'chk',
      bookedOn: '2026-10-02',
      amount: Money.of(500),
      description: 'Cashback',
    }),
    transaction({
      id: 'ghost',
      accountId: 'chk',
      bookedOn: '2026-10-07',
      amount: Money.of(5_000_000),
      provisional: true,
    }),
    transaction({
      id: 'stream1',
      accountId: 'chk',
      bookedOn: '2026-09-15',
      amount: Money.of(-5590),
      description: 'Streaming Plus',
    }),
    transaction({
      id: 'stream0',
      accountId: 'chk',
      bookedOn: '2026-08-15',
      amount: Money.of(-5590),
      description: 'Streaming Plus',
    }),
    transaction({
      id: 'gym',
      accountId: 'chk',
      bookedOn: '2026-10-03',
      amount: Money.of(-9900),
      description: 'Gym Club',
    }),
    transaction({
      id: 'early',
      accountId: 'chk',
      bookedOn: '2026-10-06',
      amount: Money.of(-40000),
      description: 'Pagamento Boleto Banco Exemplo',
    }),
    transaction({
      id: 'mortgage',
      accountId: 'chk',
      bookedOn: '2026-09-29',
      amount: Money.of(-100000),
      description: 'Mortgage Bank',
    }),
    transaction({
      id: 'dinner',
      accountId: 'card',
      bookedOn: '2026-10-04',
      amount: Money.of(-15000),
      description: 'Restaurante Exemplo',
    }),
    transaction({
      id: 'old-payment',
      accountId: 'chk',
      bookedOn: '2026-07-01',
      amount: Money.of(-80000),
      description: 'Pagamento fatura cartao',
    }),
  ]
  for (const row of others) {
    await deps.transactions.save(row)
  }
  const keyOf = (description: string) =>
    recurrenceKey(transaction({ id: 'key', accountId: 'chk', description }))
  const streaming = keyOf('Streaming Plus')
  await deps.recurrences.save(recurrence({ id: 'r1', key: streaming }))
  await deps.recurrences.save(
    recurrence({
      id: 'r2',
      key: keyOf('Gym Club'),
      name: 'Gym Club',
      dayOfMonth: 20,
    }),
  )
  await deps.recurrences.save(recurrence({ id: 'r3', key: 'card only' }))
  await deps.recurrences.save(
    recurrence({ id: 'r4', key: 'dismissed', status: 'DISMISSED' }),
  )
  await deps.recurrences.save(
    recurrence({ id: 'r5', key: streaming, entityId: 'pj' }),
  )
  await deps.recurrences.save(
    recurrence({
      id: 'r6',
      key: keyOf('Mortgage Bank'),
      name: 'Mortgage Bank',
      amount: Money.of(100000),
      dayOfMonth: 29,
      status: 'DISMISSED',
    }),
  )
  const debit = bill({ id: 'b2', payee: 'Water Co', dueDate: '2026-10-14' })
  const bills = [
    bill({ id: 'b1', payee: 'Power Co', dueDate: '2026-10-12' }),
    { ...debit, amount: Money.of(10000) },
    bill({ id: 'b3', status: 'PAID', dueDate: '2026-10-12' }),
    bill({ id: 'b4', dueDate: '2026-09-01' }),
    bill({ id: 'b5', dueDate: '2026-11-30' }),
    bill({
      id: 'b6',
      payee: 'Card boleto',
      dueDate: '2026-10-16',
      amount: Money.of(30000),
    }),
    bill({
      id: 'b7',
      payee: null,
      dueDate: '2026-10-20',
      amount: Money.of(2000),
    }),
  ]
  for (const row of bills) {
    await deps.bills.save(row)
  }
  for (const key of recipientKeys(debit)) {
    await deps.documents.put(TENANT, AUTO_DEBIT_COLLECTION, `pf|${key}`, {
      entityId: 'pf',
      key,
    })
  }
  await deps.documents.put(TENANT, FUNDING_ITEMS_COLLECTION, 'f1', {
    id: 'f1',
    name: 'Cleaner',
    amount: { cents: 20000, currency: 'BRL' },
    dayOfMonth: 20,
  })
  return deps
}

const rows = (view: { lines: readonly SafeToSpendView['lines'][number][] }) =>
  view.lines.map(line => [line.kind, line.label, line.amount.cents, line.on])

describe('safe to spend', () => {
  it('plans the month of a person from the typical income and the target', async () => {
    const deps = await seed()
    const target = { savings: { cents: 300000, currency: 'BRL' as const } }
    expect(await makeSetSpendingPlan(deps)(TENANT, target)).toEqual({
      ...target,
      incomeSources: [],
    })
    const view = await makeSafeToSpend(deps)(TENANT)
    expect(view).toMatchObject({
      asOf: '2026-10-08',
      basis: 'MONTH',
      cash: { cents: 500000 },
      until: '2026-10-31',
      days: 24,
      income: null,
      plan: {
        income: { cents: 800000 },
        typical: { cents: 800000 },
        received: { cents: 500 },
        savings: { cents: 300000 },
        savingsSet: true,
        months: 3,
        sources: 0,
      },
      total: { cents: 325165 },
      daily: { cents: 13548 },
      shortBy: { cents: 0 },
      cashShortBy: { cents: 0 },
    })
    expect(rows(view)).toEqual([
      ['INCOME', '', 800000, null],
      ['SAVINGS', '', -300000, null],
      ['SPENT_CARD', '', -15000, null],
      ['SPENT_ACCOUNT', '', -9900, null],
      ['BILL', 'Power Co', -12345, '2026-10-12'],
      ['BILL', 'Water Co', -10000, '2026-10-14'],
      ['SUBSCRIPTION', 'Streaming Plus', -5590, '2026-10-15'],
      ['BILL', '', -2000, '2026-10-20'],
      ['FIXED', 'Cleaner', -20000, '2026-10-20'],
      ['FIXED', 'Mortgage Bank', -100000, '2026-10-29'],
    ])
  })

  it('saves what a typical month leaves and warns when checking falls short', async () => {
    const deps = await seed()
    const setPlan = makeSetSpendingPlan(deps)
    await setPlan(TENANT, { savings: { cents: 1, currency: 'BRL' } })
    await setPlan(TENANT, { savings: null })
    await deps.accounts.save(
      account({ id: 'chk', entityId: 'pf', balance: Money.of(100000) }),
    )
    const view = await makeSafeToSpend(deps)(TENANT)
    expect(view).toMatchObject({
      plan: { savings: { cents: 694910 }, savingsSet: false },
      total: { cents: -69745 },
      daily: { cents: 0 },
      shortBy: { cents: 69745 },
      cashShortBy: { cents: 144935 },
    })
  })

  it('counts only the chosen payers and what they already sent this month', async () => {
    const deps = await seed()
    const payments = [
      {
        id: 'pay-now',
        accountId: 'chk',
        cents: 900000,
        by: '12.345.678/0001-95',
      },
      { id: 'pay-card', accountId: 'card', cents: 70000, by: EMPLOYER },
      { id: 'pay-other', accountId: 'chk', cents: 40000, by: '11222333000181' },
    ]
    for (const row of payments) {
      await deps.transactions.save(
        transaction({
          id: row.id,
          accountId: row.accountId,
          bookedOn: '2026-10-06',
          amount: Money.of(row.cents),
          counterparty: row.by,
        }),
      )
    }
    await makeSetSpendingPlan(deps)(TENANT, {
      incomeSources: [{ taxId: EMPLOYER, name: 'Employer' }],
    })
    const view = await makeSafeToSpend(deps)(TENANT)
    expect(view.plan).toMatchObject({
      income: { cents: 900000 },
      typical: { cents: 800000 },
      received: { cents: 900000 },
      sources: 1,
    })
    expect(view.lines[0]).toMatchObject({
      kind: 'INCOME',
      amount: { cents: 900000 },
    })
  })

  it('drops a subscription whose charge was captured as a bill that month', async () => {
    const deps = await seed()
    await deps.bills.save(
      bill({
        id: 'b8',
        payee: 'Fatura Streaming Plus',
        dueDate: '2026-10-09',
        amount: Money.of(5790),
      }),
    )
    const view = await makeSafeToSpend(deps)(TENANT)
    const labels = view.lines.map(line => [line.kind, line.label])
    expect(labels).toContainEqual(['BILL', 'Fatura Streaming Plus'])
    expect(labels).not.toContainEqual(['SUBSCRIPTION', 'Streaming Plus'])
  })

  it('runs a person without a closed month on cash until the month end', async () => {
    const deps = fullDeps()
    await deps.accounts.save(
      account({ id: 'chk', entityId: 'pf', balance: Money.of(1000) }),
    )
    await deps.bills.save(
      bill({ id: 'b1', dueDate: '2026-10-20', amount: Money.of(5000) }),
    )
    const view = await makeSafeToSpend(deps)(TENANT)
    expect(view).toMatchObject({
      basis: 'CASH',
      until: '2026-10-31',
      days: 24,
      income: null,
      plan: null,
      total: { cents: -4000 },
      daily: { cents: 0 },
      shortBy: { cents: 4000 },
      cashShortBy: { cents: 4000 },
    })
    expect(view.lines.map(line => line.kind)).toEqual(['BILL'])
  })

  it('runs the company on cash until its next income and keeps its budgets', async () => {
    const deps = await seed()
    await deps.accounts.save(
      account({ id: 'pj-chk', entityId: 'pj', balance: Money.of(300000) }),
    )
    await deps.categories.save({
      id: 'office',
      tenantId: TENANT,
      key: null,
      name: 'Office',
      icon: null,
      parentId: null,
    })
    await deps.budgets.save(
      createBudget({
        id: 'office-budget',
        tenantId: TENANT,
        entityId: 'pj',
        categoryId: 'office',
        month: '2026-10',
        limit: Money.of(48000),
        rollover: false,
      }),
    )
    const credits = [
      {
        id: 'c1',
        bookedOn: '2026-08-20',
        cents: 200000,
        counterparty: EMPLOYER,
      },
      {
        id: 'c2',
        bookedOn: '2026-09-20',
        cents: 200000,
        counterparty: EMPLOYER,
      },
      {
        id: 't1',
        bookedOn: '2026-09-03',
        cents: 1000,
        transferGroupId: 'gone',
      },
      {
        id: 't2',
        bookedOn: '2026-09-04',
        cents: 1000,
        transferGroupId: 'tr-p1',
      },
      { id: 'c3', bookedOn: '2026-09-06', cents: 500 },
    ]
    for (const { cents: amount, ...row } of credits) {
      await deps.transactions.save(
        transaction({ ...row, accountId: 'pj-chk', amount: Money.of(amount) }),
      )
    }
    await deps.transactions.save(
      transaction({
        id: 'paper',
        accountId: 'pj-chk',
        bookedOn: '2026-10-02',
        amount: Money.of(-24000),
        categoryId: 'office',
      }),
    )
    const view = await makeSafeToSpend(deps)(TENANT, 'PJ')
    expect(view).toMatchObject({
      entity: 'PJ',
      basis: 'CASH',
      cash: { cents: 300000 },
      until: '2026-10-20',
      days: 12,
      income: { on: '2026-10-20', amount: { cents: 200000 } },
      plan: null,
      total: { cents: 288000 },
    })
    expect(rows(view)).toEqual([['BUDGET', 'Office', -12000, null]])
  })
})
