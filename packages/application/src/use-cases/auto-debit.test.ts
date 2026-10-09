import { describe, expect, it } from 'vitest'
import { createBill, Money } from '@cashdeck/domain'
import { NotFoundError } from '@/errors/errors'
import { FakePaymentRail, FakeReserveFunder } from '@/testing/providers'
import { NOW, scenario, TENANT } from '@/testing/scenario.test-helpers'
import { makeSetAutoDebit } from '@/use-cases/auto-debit'
import { makeDescribeBill, makeGetBill, makeListBills } from '@/use-cases/bills'
import {
  makePrepareFunding,
  makeRunPaymentLadder,
} from '@/use-cases/run-payment-ladder'

function phoneBill(id: string, dueDate: string) {
  return createBill({
    id,
    tenantId: TENANT,
    entityId: 'pf',
    kind: 'PIX_KEY',
    source: 'GMAIL',
    payee: 'Phone company',
    amount: Money.of(20880),
    dueDate,
    code: 'billing@phone.example',
    createdAt: NOW,
  })
}

function setup() {
  const deps = scenario([new FakePaymentRail('ASAAS')])
  const setAutoDebit = makeSetAutoDebit(deps, makeGetBill(deps))
  return { deps, setAutoDebit }
}

describe('auto debit', () => {
  it('flags the payee, so this and next month bills are left to the bank', async () => {
    const { deps, setAutoDebit } = setup()
    await deps.bills.save({
      ...phoneBill('oct', '2026-10-08'),
      status: 'NEEDS_CONFIRMATION',
    })

    const detail = await setAutoDebit(TENANT, 'oct', true)

    expect(detail).toMatchObject({
      status: 'OPEN',
      autoDebit: true,
      confirmationReason: null,
    })
    const next = phoneBill('nov', '2026-11-08')
    await deps.bills.save(next)
    expect((await makeDescribeBill(deps)(TENANT, next)).autoDebit).toBe(true)
    const page = await makeListBills(deps)(TENANT, {}, { limit: 10 })
    expect(page.items.map(item => item.autoDebit)).toEqual([true, true])
    expect(deps.audit.events.at(-1)).toMatchObject({
      action: 'bill.auto_debit_set',
      result: 'ENABLED',
      actor: 'USER',
    })
  })

  it('turns the flag off without touching the bill status', async () => {
    const { deps, setAutoDebit } = setup()
    await deps.bills.save(phoneBill('oct', '2026-10-08'))
    await setAutoDebit(TENANT, 'oct', true)

    const detail = await setAutoDebit(TENANT, 'oct', false)

    expect(detail).toMatchObject({ status: 'OPEN', autoDebit: false })
    expect(deps.audit.events.at(-1)?.result).toBe('DISABLED')
    await expect(setAutoDebit(TENANT, 'nope', true)).rejects.toThrow(
      NotFoundError,
    )
  })

  it('never pays nor asks to confirm an auto debit bill', async () => {
    const { deps, setAutoDebit } = setup()
    await deps.bills.save(phoneBill('oct', '2026-10-08'))
    await setAutoDebit(TENANT, 'oct', true)
    await deps.bills.save({
      ...phoneBill('stale', '2026-10-08'),
      status: 'NEEDS_CONFIRMATION',
    })
    const run = makeRunPaymentLadder(deps)

    const open = await run(TENANT, 'oct', { confirmed: true })
    const stale = await run(TENANT, 'stale')

    expect([open.bill.status, stale.bill.status]).toEqual(['OPEN', 'OPEN'])
    expect([open.attempts, stale.attempts]).toEqual([[], []])
    expect((await deps.bills.findById(TENANT, 'stale'))?.status).toBe('OPEN')
    expect(
      deps.audit.events
        .filter(event => event.action === 'payment.left_to_auto_debit')
        .map(event => event.subjectId),
    ).toEqual(['oct', 'stale'])
  })

  it('leaves auto debit bills out of the reserve funding', async () => {
    const { deps, setAutoDebit } = setup()
    deps.funder = new FakeReserveFunder(0)
    const target = phoneBill('oct', '2026-10-08')
    await deps.bills.save(target)
    await setAutoDebit(TENANT, 'oct', true)

    expect(await makePrepareFunding(deps)(TENANT, [target])).toEqual({
      rounds: 0,
      fundedCents: 0,
    })
  })
})
