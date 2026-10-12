import { Money } from '@cashdeck/domain'
import { describe, expect, it } from 'vitest'
import { ConflictError, NotFoundError } from '@/errors/errors'
import { account, fullDeps, transaction } from '@/testing/deps.test-helpers'
import { TENANT } from '@/testing/scenario.test-helpers'
import { alertText, formatMoney } from '@/use-cases/alert-events'
import { budgetAlert, makeRunBudgetAlerts } from '@/use-cases/budget-alerts'
import { makeBudgets } from '@/use-cases/budgets'
import { makeRunDailyAlerts } from '@/use-cases/daily-alerts'

const CATEGORIES = [
  { id: 'food', key: 'restaurants', name: 'Restaurants', icon: 'restaurant' },
  { id: 'market', key: 'groceries', name: 'Groceries', icon: null },
  { id: 'fun', key: null, name: 'Hobbies', icon: null },
  { id: 'moves', key: 'transfers', name: 'Transfers', icon: null },
]

type Line = [string, string, number, string | null, string?]

const LINES: Line[] = [
  ['2026-07-03', 'food', -400_00, 'checking'],
  ['2026-07-04', 'market', -300_00, 'card'],
  ['2026-08-03', 'food', -380_00, 'checking'],
  ['2026-08-04', 'market', -310_00, 'card'],
  ['2026-08-05', 'fun', -80_00, 'checking'],
  ['2026-09-03', 'food', -450_00, 'checking'],
  ['2026-09-05', 'fun', -20_00, 'checking'],
  ['2026-09-06', 'moves', -999_00, 'checking'],
  ['2026-09-07', '', -5_00, 'checking'],
  ['2026-10-02', 'food', -420_00, 'checking'],
  ['2026-10-03', 'market', -350_00, 'card'],
  ['2026-10-04', 'fun', -50_00, 'checking'],
  ['2026-10-05', '', -30_00, 'checking'],
  ['2026-10-05', 'ghost', -1_00, 'checking'],
  ['2026-10-06', 'market', -1_000_00, 'checking', 'PAGAMENTO FATURA'],
  ['2026-10-07', 'food', -70_00, 'company'],
]

async function seeded() {
  const deps = fullDeps()
  for (const category of CATEGORIES) {
    await deps.categories.save({
      ...category,
      tenantId: TENANT,
      parentId: null,
    })
  }
  await deps.accounts.save(account({ id: 'checking', entityId: 'pf' }))
  await deps.accounts.save(
    account({ id: 'card', entityId: 'pf', type: 'CREDIT_CARD' }),
  )
  await deps.accounts.save(account({ id: 'company', entityId: 'pj' }))
  for (const [index, [on, categoryId, cents, accountId, description]] of [
    ...LINES.entries(),
  ]) {
    await deps.transactions.save(
      transaction({
        id: `tx-${index}`,
        accountId: accountId as string,
        amount: Money.of(cents),
        bookedOn: on,
        categoryId: categoryId || null,
        description: description ?? `Purchase ${index}`,
      }),
    )
  }
  const budgets = makeBudgets(deps)
  await budgets.create(TENANT, {
    entity: 'PF',
    categoryId: 'food',
    limitCents: 500_00,
    rollover: true,
  })
  await budgets.create(TENANT, {
    entity: 'PF',
    categoryId: 'market',
    month: '2026-10',
    limitCents: 300_00,
    rollover: false,
  })
  return { deps, budgets }
}

describe('budget month', () => {
  it('measures each category against its limit, fullest first', async () => {
    const { budgets } = await seeded()
    const view = await budgets.month(TENANT, { entity: 'PF' })
    expect(view.month).toBe('2026-10')
    expect(view.total).toEqual({
      available: { cents: 800_00, currency: 'BRL' },
      spent: { cents: 770_00, currency: 'BRL' },
      remaining: { cents: 30_00, currency: 'BRL' },
      percent: 96,
      level: 'NEAR',
    })
    expect(
      view.items.map(item => [
        item.categoryId,
        item.key,
        item.spent.cents,
        item.remaining.cents,
        item.percent,
        item.level,
      ]),
    ).toEqual([
      ['market', 'groceries', 350_00, -50_00, 116, 'REACHED'],
      ['food', 'restaurants', 420_00, 80_00, 84, 'NEAR'],
    ])
    expect(view.unbudgeted).toEqual([
      {
        categoryId: 'fun',
        key: null,
        name: 'Hobbies',
        icon: null,
        spent: { cents: 50_00, currency: 'BRL' },
      },
      {
        categoryId: 'ghost',
        key: null,
        name: 'ghost',
        icon: null,
        spent: { cents: 1_00, currency: 'BRL' },
      },
    ])
  })

  it('shows an empty month with nothing used', async () => {
    const { budgets } = await seeded()
    const view = await budgets.month(TENANT, { entity: 'PJ' })
    expect(view.items).toEqual([])
    expect(view.total.percent).toBe(0)
    expect(view.unbudgeted.map(item => item.categoryId)).toEqual(['food'])
  })
})

describe('budget changes', () => {
  it('refuses a second budget for a category and an unknown category', async () => {
    const { budgets } = await seeded()
    await expect(
      budgets.create(TENANT, {
        entity: 'PF',
        categoryId: 'food',
        limitCents: 1,
        rollover: false,
      }),
    ).rejects.toBeInstanceOf(ConflictError)
    await expect(
      budgets.create(TENANT, {
        entity: 'PF',
        categoryId: 'gone',
        limitCents: 1,
        rollover: false,
      }),
    ).rejects.toBeInstanceOf(NotFoundError)
  })

  it('edits and deletes a budget, with an audit event each', async () => {
    const { deps, budgets } = await seeded()
    const [market] = (await budgets.month(TENANT, { entity: 'PF' })).items
    const id = market?.id as string
    const raised = await budgets.update(TENANT, id, {
      limitCents: 400_00,
      rollover: true,
    })
    expect(raised.items.find(item => item.id === id)).toMatchObject({
      limit: { cents: 400_00 },
      rollover: true,
      percent: 87,
    })
    const same = await budgets.update(TENANT, id, {})
    expect(same.items.find(item => item.id === id)?.limit.cents).toBe(400_00)
    const after = await budgets.remove(TENANT, id)
    expect(after.items.map(item => item.categoryId)).toEqual(['food'])
    await expect(budgets.remove(TENANT, id)).rejects.toBeInstanceOf(
      NotFoundError,
    )
    expect(deps.audit.events.map(event => event.action)).toEqual([
      'budget.create',
      'budget.create',
      'budget.update',
      'budget.update',
      'budget.delete',
    ])
  })

  it('copies the month ahead, carrying what a rollover left', async () => {
    const { deps, budgets } = await seeded()
    await budgets.create(TENANT, {
      entity: 'PF',
      categoryId: 'market',
      month: '2026-11',
      limitCents: 999_00,
      rollover: false,
    })
    await budgets.create(TENANT, {
      entity: 'PF',
      categoryId: 'moves',
      limitCents: 100_00,
      rollover: true,
    })
    const next = await budgets.copyToNext(TENANT, {
      entity: 'PF',
      month: '2026-10',
    })
    expect(next.month).toBe('2026-11')
    expect(
      next.items.map(item => [
        item.categoryId,
        item.limit.cents,
        item.carried.cents,
        item.available.cents,
        item.rollover,
      ]),
    ).toEqual([
      ['market', 999_00, 0, 999_00, false],
      ['food', 500_00, 80_00, 580_00, true],
      ['moves', 100_00, 100_00, 200_00, true],
    ])
    expect(deps.audit.events.at(-1)).toMatchObject({
      action: 'budget.copy',
      details: { carriedCents: 100_00 },
    })
    const names = await deps.budgets.list(TENANT, 'pf', '2026-11')
    expect(names.find(row => row.categoryId === 'food')?.limit).toEqual(
      Money.of(580_00),
    )
  })
})

describe('automatic budget', () => {
  it('suggests the median of the last three complete months', async () => {
    const { budgets } = await seeded()
    const suggestions = await budgets.suggest(TENANT, { entity: 'PF' })
    expect(suggestions.basedOn).toEqual(['2026-07', '2026-08', '2026-09'])
    expect(suggestions.total.cents).toBe(720_00)
    expect(
      suggestions.items.map(item => [
        item.categoryId,
        item.months.map(month => month.cents),
        item.suggested.cents,
        item.current?.cents ?? null,
      ]),
    ).toEqual([
      ['food', [400_00, 380_00, 450_00], 400_00, 500_00],
      ['market', [300_00, 310_00, 0], 300_00, 300_00],
      ['fun', [0, 80_00, 20_00], 20_00, null],
    ])
  })

  it('accepts every limit in one go', async () => {
    const { deps, budgets } = await seeded()
    const view = await budgets.acceptSuggestions(TENANT, {
      entity: 'PF',
      items: [
        { categoryId: 'food', limitCents: 400_00 },
        { categoryId: 'fun', limitCents: 20_00 },
      ],
    })
    expect(
      view.items.map(item => [
        item.categoryId,
        item.limit.cents,
        item.rollover,
      ]),
    ).toEqual([
      ['fun', 20_00, false],
      ['market', 300_00, false],
      ['food', 400_00, true],
    ])
    expect(deps.audit.events.slice(-2).map(event => event.result)).toEqual([
      'UPDATED',
      'CREATED',
    ])
    await expect(
      budgets.acceptSuggestions(TENANT, {
        entity: 'PF',
        month: '2026-12',
        items: [{ categoryId: 'gone', limitCents: 1 }],
      }),
    ).rejects.toBeInstanceOf(NotFoundError)
  })
})

describe('budget alerts', () => {
  it('warns once per category, month and threshold', async () => {
    const { deps } = await seeded()
    const run = makeRunBudgetAlerts(deps)
    expect(await run(TENANT)).toBe(2)
    expect(
      deps.alerts.emitted.map(alert => [alert.type, alert.data.categoryId]),
    ).toEqual([
      ['BUDGET_LIMIT_REACHED', 'market'],
      ['BUDGET_NEAR_LIMIT', 'food'],
    ])
    expect(deps.alerts.emitted[1]).toMatchObject({
      entityId: 'pf',
      dedupeKey: 'BUDGET_NEAR_LIMIT:pf:food:2026-10',
      data: {
        categoryKey: 'restaurants',
        category: 'Restaurants',
        percent: '84',
        month: '2026-10',
      },
    })
    expect(await run(TENANT)).toBe(0)

    await deps.transactions.save(
      transaction({
        id: 'more',
        accountId: 'checking',
        amount: Money.of(-100_00),
        bookedOn: '2026-10-07',
        categoryId: 'food',
      }),
    )
    expect(await makeRunDailyAlerts(deps)(TENANT)).toMatchObject({
      budgets: 1,
    })
    expect(deps.alerts.emitted.at(-1)?.type).toBe('BUDGET_LIMIT_REACHED')
  })

  it('writes the push in both languages', () => {
    const fifty = formatMoney(Money.of(50_00))
    const hundred = formatMoney(Money.of(100_00))
    const item = {
      id: 'b1',
      categoryId: 'fun',
      key: null,
      name: 'Hobbies',
      icon: null,
      limit: { cents: 100_00, currency: 'BRL' },
      carried: { cents: 0, currency: 'BRL' },
      rollover: false,
      available: { cents: 100_00, currency: 'BRL' },
      spent: { cents: 50_00, currency: 'BRL' },
      remaining: { cents: 50_00, currency: 'BRL' },
      percent: 50,
      level: 'OK' as const,
    }
    expect(budgetAlert(TENANT, 'pf', '2026-10', item)).toBeNull()
    const reached = budgetAlert(TENANT, 'pf', '2026-10', {
      ...item,
      percent: 100,
    })
    expect(
      alertText('BUDGET_LIMIT_REACHED', reached?.data ?? {}, 'pt'),
    ).toEqual({
      title: 'Orçamento no limite',
      body: `Hobbies: ${fifty} de ${hundred} neste mês.`,
    })
    const near = budgetAlert(TENANT, 'pf', '2026-10', {
      ...item,
      key: 'groceries',
      name: 'Groceries',
      percent: 80,
    })
    expect(alertText('BUDGET_NEAR_LIMIT', near?.data ?? {}, 'pt').body).toBe(
      `Mercado: ${fifty} de ${hundred} (80%) neste mês.`,
    )
    expect(alertText('BUDGET_NEAR_LIMIT', near?.data ?? {}, 'en').body).toBe(
      `Groceries: ${fifty} of ${hundred} (80%) this month.`,
    )
    expect(
      alertText('BUDGET_LIMIT_REACHED', reached?.data ?? {}, 'en').title,
    ).toBe('Budget limit reached')
  })
})
