import { describe, expect, it } from 'vitest'
import { Money } from '@cashdeck/domain'
import { account, bill, fullDeps } from '@/testing/deps.test-helpers'
import { FakeReserveFunder } from '@/testing/providers'
import { formatMoney } from '@/use-cases/alert-events'
import { TENANT } from '@/testing/scenario.test-helpers'
import { makeSetAutoDebit } from '@/use-cases/auto-debit'
import { makeGetBill } from '@/use-cases/bills'
import { makeRunDailyAlerts } from '@/use-cases/daily-alerts'

const TOMORROW = '2026-10-09'

describe('daily alerts', () => {
  it('warns about unpaid bills due tomorrow and a short reserve', async () => {
    const deps = fullDeps()
    await deps.accounts.save(
      account({
        id: 'reserve',
        entityId: 'pf',
        isReserve: true,
        balance: Money.of(10000),
      }),
    )
    await deps.accounts.save(
      account({ id: 'company-cash', entityId: 'pj', balance: Money.of(0) }),
    )
    const bills = [
      bill({ id: 'open', dueDate: TOMORROW, amount: Money.of(8000) }),
      bill({
        id: 'confirm',
        dueDate: TOMORROW,
        status: 'NEEDS_CONFIRMATION',
        amount: Money.of(4000),
      }),
      bill({ id: 'assisted', dueDate: TOMORROW, status: 'ASSISTED' }),
      bill({ id: 'company', entityId: 'pj', dueDate: TOMORROW }),
      bill({ id: 'paid', dueDate: TOMORROW, status: 'PAID' }),
      bill({ id: 'later', dueDate: '2026-10-20' }),
    ]
    for (const item of bills) {
      await deps.bills.save(item)
    }
    const run = makeRunDailyAlerts(deps)

    expect(await run(TENANT)).toEqual({ dueSoon: 4, lowBalance: 1 })
    expect(
      deps.alerts.emitted.map(alert => [alert.type, alert.billId ?? null]),
    ).toEqual([
      ['BILL_DUE_SOON', 'company'],
      ['BILL_DUE_SOON', 'open'],
      ['BILL_DUE_SOON', 'confirm'],
      ['BILL_DUE_SOON', 'assisted'],
      ['LOW_BALANCE', null],
    ])
    expect(deps.alerts.emitted.at(-1)?.data).toMatchObject({
      shortfall: 'R$ 20,00',
      dueDate: '09/10',
    })
    expect(await run(TENANT)).toEqual({ dueSoon: 0, lowBalance: 0 })
  })

  it('stays quiet about a bill the bank debits by itself', async () => {
    const deps = fullDeps()
    await deps.bills.save(bill({ id: 'debit', dueDate: TOMORROW }))
    await makeSetAutoDebit(deps, makeGetBill(deps))(TENANT, 'debit', true)

    expect(await makeRunDailyAlerts(deps)(TENANT)).toEqual({
      dueSoon: 0,
      lowBalance: 0,
    })
  })

  it('stays quiet when the reserve covers the day', async () => {
    const deps = fullDeps()
    await deps.accounts.save(
      account({
        id: 'reserve',
        entityId: 'pf',
        isReserve: true,
        balance: Money.of(50000),
      }),
    )
    await deps.bills.save(bill({ id: 'open', dueDate: TOMORROW }))
    expect(await makeRunDailyAlerts(deps)(TENANT)).toEqual({
      dueSoon: 1,
      lowBalance: 0,
    })
  })

  it('checks the Asaas balance when there is no reserve account', async () => {
    const deps = { ...fullDeps(), funder: new FakeReserveFunder(5000) }
    await deps.bills.save(
      bill({ id: 'open', dueDate: TOMORROW, amount: Money.of(8000) }),
    )
    expect(await makeRunDailyAlerts(deps)(TENANT)).toEqual({
      dueSoon: 1,
      lowBalance: 1,
    })
    expect(deps.alerts.emitted.at(-1)?.data).toMatchObject({
      shortfall: formatMoney(Money.of(3000)),
      balance: formatMoney(Money.of(5000)),
    })
  })

  it('warns ahead for the bills the next ladder run pays', async () => {
    const deps = { ...fullDeps(), funder: new FakeReserveFunder(5000) }
    // On Thursday the 8th, Friday's ladder pays through Tuesday, past the
    // weekend and the Monday holiday.
    await deps.bills.save(
      bill({ id: 'tuesday', dueDate: '2026-10-13', amount: Money.of(4000) }),
    )
    await deps.bills.save(
      bill({ id: 'monday', dueDate: '2026-10-12', amount: Money.of(3000) }),
    )
    await deps.bills.save(bill({ id: 'wednesday', dueDate: '2026-10-14' }))
    expect(await makeRunDailyAlerts(deps)(TENANT)).toEqual({
      dueSoon: 0,
      lowBalance: 1,
    })
    expect(deps.alerts.emitted.at(-1)?.data).toMatchObject({
      shortfall: formatMoney(Money.of(2000)),
      dueDate: '13/10',
    })
  })

  it('stays quiet when the Asaas balance cannot be read', async () => {
    const deps = {
      ...fullDeps(),
      funder: new FakeReserveFunder(new Error('Asaas is not configured.')),
    }
    await deps.bills.save(bill({ id: 'open', dueDate: TOMORROW }))
    expect(await makeRunDailyAlerts(deps)(TENANT)).toEqual({
      dueSoon: 1,
      lowBalance: 0,
    })
  })
})
