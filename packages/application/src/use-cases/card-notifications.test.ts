import { Money, ValidationError } from '@cashdeck/domain'
import { describe, expect, it } from 'vitest'
import { NotFoundError } from '@/errors/errors'
import { account, fullDeps, transaction } from '@/testing/deps.test-helpers'
import { TENANT } from '@/testing/scenario.test-helpers'
import { alertText } from '@/use-cases/alert-events'
import { makeCardNotifications } from '@/use-cases/card-notifications'

const notification = (id: string, text: string, postedAt: string) => ({
  id,
  app: 'Card App',
  title: 'Compra aprovada',
  text,
  postedAt,
})

const PHONE = 'phone-a1-session'
const OTHER_PHONE = 'phone-b2-session'

async function setup() {
  const deps = fullDeps()
  await deps.accounts.save(
    account({ id: 'card', type: 'CREDIT_CARD', entityId: 'pf' }),
  )
  await deps.accounts.save(account({ id: 'checking' }))
  return { deps, capture: makeCardNotifications(deps) }
}

describe('card notifications', () => {
  it('stores purchases and refunds as previews, once', async () => {
    const { deps, capture } = await setup()
    await deps.transactions.save(
      transaction({
        id: 'seen',
        accountId: 'card',
        externalId: 'notification:phone-a1:seen-0001',
        bookedOn: '2026-10-09',
      }),
    )
    deps.llm.enqueueObject({
      items: [
        {
          ref: 'n1',
          kind: 'PURCHASE',
          amount: 42.5,
          merchant: ' Bakery ',
          installments: 1,
        },
        {
          ref: 'n2',
          kind: 'PURCHASE',
          amount: 300,
          merchant: '',
          installments: 3,
        },
        {
          ref: 'n3',
          kind: 'REFUND',
          amount: 10,
          merchant: '',
          installments: 1,
        },
        { ref: 'n4', kind: 'OTHER', amount: 0, merchant: '', installments: 1 },
        {
          ref: 'n1',
          kind: 'PURCHASE',
          amount: 1,
          merchant: '',
          installments: 1,
        },
        {
          ref: 'n9',
          kind: 'PURCHASE',
          amount: 1,
          merchant: '',
          installments: 1,
        },
      ],
    })
    const input = {
      accountId: 'card',
      notifications: [
        notification('seen-0001', 'R$ 5,00', '2026-10-09T12:00:00Z'),
        notification('first-001', 'R$ 42,50 em Bakery', '2026-10-10T02:30:00Z'),
        notification('second-01', 'R$ 300,00 em 3x', '2026-10-10T15:00:00Z'),
        {
          ...notification('third-001', 'Estorno', '2026-10-10T16:00:00Z'),
          title: '',
        },
        notification('fourth-01', 'Fatura fechada', '2026-10-10T17:00:00Z'),
      ],
    }
    expect(await capture(TENANT, input, PHONE)).toEqual({
      received: 5,
      added: 3,
    })
    expect(deps.llm.calls[0]?.messages[0]?.content).toContain(
      'n1|Compra aprovada|R$ 42,50 em Bakery',
    )
    const stored = await deps.transactions.all(TENANT, { provisional: true })
    expect(
      stored.map(tx => [
        tx.externalId,
        tx.amount.cents,
        tx.bookedOn,
        tx.description,
        tx.installment?.count ?? null,
      ]),
    ).toEqual([
      ['notification:phone-a1:third-001', 1000, '2026-10-10', 'Card App', null],
      [
        'notification:phone-a1:second-01',
        -10000,
        '2026-10-10',
        'Compra aprovada',
        3,
      ],
      ['notification:phone-a1:first-001', -4250, '2026-10-09', 'Bakery', null],
    ])
    expect(stored.at(-1)?.merchant).toBe('Bakery')
    expect(
      deps.alerts.emitted.map(alert => [
        alert.type,
        alert.entityId,
        alert.data,
        alert.dedupeKey,
      ]),
    ).toEqual([
      [
        'CARD_CHARGE_CAPTURED',
        'pf',
        {
          transactionId: stored[2]?.id,
          card: 'Account card',
          kind: 'PURCHASE',
          merchant: 'Bakery',
          amount: 'R$\u00a042,50',
          day: '09/10',
        },
        'CARD_CHARGE_CAPTURED:notification:phone-a1:first-001',
      ],
      [
        'CARD_CHARGE_CAPTURED',
        'pf',
        {
          transactionId: stored[1]?.id,
          card: 'Account card',
          kind: 'PURCHASE',
          merchant: 'Compra aprovada',
          amount: 'R$\u00a0100,00',
          day: '10/10',
          installments: '3',
        },
        'CARD_CHARGE_CAPTURED:notification:phone-a1:second-01',
      ],
      [
        'CARD_CHARGE_CAPTURED',
        'pf',
        {
          transactionId: stored[0]?.id,
          card: 'Account card',
          kind: 'REFUND',
          merchant: 'Card App',
          amount: 'R$\u00a010,00',
          day: '10/10',
        },
        'CARD_CHARGE_CAPTURED:notification:phone-a1:third-001',
      ],
    ])

    expect(await capture(TENANT, input, PHONE)).toEqual({
      received: 5,
      added: 0,
    })
    expect(deps.llm.calls).toHaveLength(2)
    expect(deps.alerts.emitted).toHaveLength(3)
  })

  it('skips the model when every notification is known', async () => {
    const { deps, capture } = await setup()
    await deps.transactions.save(
      transaction({
        id: 'seen',
        accountId: 'card',
        externalId: 'notification:phone-a1:seen-0001',
        amount: Money.of(-500),
        bookedOn: '2026-10-09',
      }),
    )
    const input = {
      accountId: 'card',
      notifications: [
        notification('seen-0001', 'R$ 5,00', '2026-10-09T12:00:00Z'),
      ],
    }
    expect(await capture(TENANT, input, PHONE)).toEqual({
      received: 1,
      added: 0,
    })
    expect(deps.llm.calls).toHaveLength(0)
  })

  it('adds nothing when the reading is unusable', async () => {
    const { deps, capture } = await setup()
    deps.llm.enqueueObject({ items: 'nope' })
    const input = {
      accountId: 'card',
      notifications: [
        notification('first-001', 'R$ 1,00', '2026-10-10T12:00:00Z'),
      ],
    }
    expect(await capture(TENANT, input, PHONE)).toEqual({
      received: 1,
      added: 0,
    })
  })

  it('takes only a known credit card account', async () => {
    const { capture } = await setup()
    const notifications = [
      notification('first-001', 'R$ 1,00', '2026-10-10T12:00:00Z'),
    ]
    await expect(
      capture(TENANT, { accountId: 'checking', notifications }, PHONE),
    ).rejects.toBeInstanceOf(ValidationError)
    await expect(
      capture(TENANT, { accountId: 'gone', notifications }, PHONE),
    ).rejects.toBeInstanceOf(NotFoundError)
  })

  it('tells a purchase from a refund in both languages', () => {
    const charge = {
      card: 'Card',
      merchant: 'Bakery',
      amount: 'R$ 30,00',
      day: '10/10',
    }
    const purchase = { ...charge, kind: 'PURCHASE', installments: '3' }
    const refund = { ...charge, kind: 'REFUND' }
    expect(alertText('CARD_CHARGE_CAPTURED', purchase, 'pt')).toEqual({
      title: 'Compra no cartão registrada',
      body: 'Card: Bakery · R$ 30,00 em 10/10, parcela 1 de 3.',
    })
    expect(alertText('CARD_CHARGE_CAPTURED', refund, 'pt')).toEqual({
      title: 'Estorno no cartão registrado',
      body: 'Card: Bakery · R$ 30,00 em 10/10.',
    })
    expect(alertText('CARD_CHARGE_CAPTURED', purchase, 'en')).toEqual({
      title: 'Card purchase recorded',
      body: 'Card: Bakery · R$ 30,00 on 10/10, installment 1 of 3.',
    })
    expect(alertText('CARD_CHARGE_CAPTURED', refund, 'en')).toEqual({
      title: 'Card refund recorded',
      body: 'Card: Bakery · R$ 30,00 on 10/10.',
    })
  })

  it('drops a charge another phone already notified', async () => {
    const { deps, capture } = await setup()
    await deps.transactions.save(
      transaction({
        id: 'legacy',
        accountId: 'card',
        externalId: 'notification:legacy-0001',
        amount: Money.of(-2100),
        bookedOn: '2026-10-10',
      }),
    )
    const purchase = (amount: number) => ({
      items: [
        {
          ref: 'n1',
          kind: 'PURCHASE',
          amount,
          merchant: 'Bakery',
          installments: 1,
        },
      ],
    })
    const sent = (id: string, postedAt: string) => ({
      accountId: 'card',
      notifications: [notification(id, 'R$ 21,00 em Bakery', postedAt)],
    })
    deps.llm.enqueueObject(purchase(21))
    expect(
      await capture(TENANT, sent('mine-0001', '2026-10-10T12:00:00Z'), PHONE),
    ).toEqual({ received: 1, added: 1 })

    deps.llm.enqueueObject(purchase(21))
    expect(
      await capture(
        TENANT,
        sent('hers-0001', '2026-10-10T12:00:05Z'),
        OTHER_PHONE,
      ),
    ).toEqual({ received: 1, added: 0 })

    deps.llm.enqueueObject(purchase(21))
    expect(
      await capture(TENANT, sent('mine-0002', '2026-10-10T12:03:00Z'), PHONE),
    ).toEqual({ received: 1, added: 1 })

    deps.llm.enqueueObject(purchase(21))
    expect(
      await capture(
        TENANT,
        sent('hers-0002', '2026-10-10T12:30:00Z'),
        OTHER_PHONE,
      ),
    ).toEqual({ received: 1, added: 1 })
    expect(deps.alerts.emitted).toHaveLength(3)
  })
})
