import { Money, ValidationError } from '@cashdeck/domain'
import { describe, expect, it } from 'vitest'
import { NotFoundError } from '@/errors/errors'
import { account, fullDeps, transaction } from '@/testing/deps.test-helpers'
import { TENANT } from '@/testing/scenario.test-helpers'
import { makeCardNotifications } from '@/use-cases/card-notifications'

const notification = (id: string, text: string, postedAt: string) => ({
  id,
  app: 'Card App',
  title: 'Compra aprovada',
  text,
  postedAt,
})

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
        externalId: 'notification:seen-0001',
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
    expect(await capture(TENANT, input)).toEqual({ received: 5, added: 3 })
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
      ['notification:second-01', -10000, '2026-10-10', 'Compra aprovada', 3],
      ['notification:third-001', 1000, '2026-10-10', 'Card App', null],
      ['notification:first-001', -4250, '2026-10-09', 'Bakery', null],
    ])
    expect(stored.at(-1)?.merchant).toBe('Bakery')

    expect(await capture(TENANT, input)).toEqual({ received: 5, added: 0 })
    expect(deps.llm.calls).toHaveLength(2)
  })

  it('skips the model when every notification is known', async () => {
    const { deps, capture } = await setup()
    await deps.transactions.save(
      transaction({
        id: 'seen',
        accountId: 'card',
        externalId: 'notification:seen-0001',
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
    expect(await capture(TENANT, input)).toEqual({ received: 1, added: 0 })
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
    expect(await capture(TENANT, input)).toEqual({ received: 1, added: 0 })
  })

  it('takes only a known credit card account', async () => {
    const { capture } = await setup()
    const notifications = [
      notification('first-001', 'R$ 1,00', '2026-10-10T12:00:00Z'),
    ]
    await expect(
      capture(TENANT, { accountId: 'checking', notifications }),
    ).rejects.toBeInstanceOf(ValidationError)
    await expect(
      capture(TENANT, { accountId: 'gone', notifications }),
    ).rejects.toBeInstanceOf(NotFoundError)
  })
})
