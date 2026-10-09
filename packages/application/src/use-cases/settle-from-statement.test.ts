import { Money } from '@cashdeck/domain'
import { describe, expect, it } from 'vitest'
import {
  account,
  alert,
  bill,
  fullDeps,
  transaction,
} from '@/testing/deps.test-helpers'
import { NOW, TENANT } from '@/testing/scenario.test-helpers'
import { makeSetAutoDebit } from '@/use-cases/auto-debit'
import { makeGetBill } from '@/use-cases/bills'
import { makeSettleFromStatement } from '@/use-cases/settle-from-statement'

describe('settleFromStatement', () => {
  it('marks paid the open bills an outgoing transaction paid', async () => {
    const deps = fullDeps()
    await deps.accounts.save(account({ id: 'chk', entityId: 'pf' }))
    await deps.accounts.save(
      account({ id: 'card', entityId: 'pf', type: 'CREDIT_CARD' }),
    )
    const due = { amount: Money.of(38963), dueDate: '2026-10-06' }
    await deps.bills.save(bill({ id: 'amil', ...due }))
    await deps.bills.save(
      bill({
        id: 'desk',
        amount: Money.of(9999),
        dueDate: '2026-10-08',
        status: 'NEEDS_CONFIRMATION',
      }),
    )
    await deps.bills.save(bill({ id: 'card-paid', ...due, status: 'ASSISTED' }))
    await deps.bills.save(bill({ id: 'rail', ...due, status: 'PROCESSING' }))
    await deps.transactions.save(
      transaction({
        id: 't1',
        accountId: 'chk',
        amount: Money.of(-38963),
        bookedOn: '2026-10-06',
      }),
    )
    await deps.transactions.save(
      transaction({
        id: 't2',
        accountId: 'chk',
        amount: Money.of(-9999),
        bookedOn: '2026-10-08',
      }),
    )
    await deps.transactions.save(
      transaction({
        id: 't3',
        accountId: 'card',
        amount: Money.of(-38963),
        bookedOn: '2026-10-06',
      }),
    )

    await deps.alertStore.add(
      alert({ id: 'ask', type: 'PAYMENT_NEEDS_CONFIRMATION', billId: 'desk' }),
    )
    await deps.alertStore.add(
      alert({ id: 'news', type: 'BILL_CAPTURED', billId: 'desk' }),
    )

    const settled = await makeSettleFromStatement(deps)(TENANT, 'pf')

    expect(settled).toBe(2)
    const amil = await deps.bills.findById(TENANT, 'amil')
    expect(amil).toMatchObject({
      status: 'PAID',
      paidBy: 'STATEMENT',
      paidAt: NOW,
    })
    expect((await deps.alertStore.findById(TENANT, 'ask'))?.readAt).toEqual(NOW)
    expect((await deps.alertStore.findById(TENANT, 'news'))?.readAt).toBeNull()
    expect((await deps.bills.findById(TENANT, 'desk'))?.status).toBe('PAID')
    expect((await deps.bills.findById(TENANT, 'card-paid'))?.status).toBe(
      'ASSISTED',
    )
    expect((await deps.bills.findById(TENANT, 'rail'))?.status).toBe(
      'PROCESSING',
    )
    expect(
      deps.audit.events
        .filter(event => event.action === 'bill.settled_from_statement')
        .map(event => [event.subjectId, event.details]),
    ).toEqual([
      ['amil', { transactionId: 't1' }],
      ['desk', { transactionId: 't2' }],
    ])
  })

  it('waits two weeks for a bank debit to post', async () => {
    const deps = fullDeps()
    await deps.accounts.save(account({ id: 'chk', entityId: 'pf' }))
    const due = { amount: Money.of(20880), dueDate: '2026-10-08' }
    await deps.bills.save(bill({ id: 'phone', ...due }))
    await deps.transactions.save(
      transaction({
        id: 'debit',
        accountId: 'chk',
        amount: Money.of(-20880),
        bookedOn: '2026-10-22',
      }),
    )
    const settle = makeSettleFromStatement(deps)
    expect(await settle(TENANT, 'pf')).toBe(0)

    await makeSetAutoDebit(deps, makeGetBill(deps))(TENANT, 'phone', true)

    expect(await settle(TENANT, 'pf')).toBe(1)
  })

  it('does nothing without an unsettled bill', async () => {
    const deps = fullDeps()
    await deps.bills.save(bill({ id: 'paid', status: 'PAID' }))
    expect(await makeSettleFromStatement(deps)(TENANT, 'pf')).toBe(0)
  })
})
