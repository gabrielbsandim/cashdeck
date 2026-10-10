import { Money, type Transaction } from '@cashdeck/domain'
import { describe, expect, it, vi } from 'vitest'
import { ProviderNotConfiguredError } from '@/errors/errors'
import {
  type PreviewAccount,
  type ProviderTransaction,
} from '@/ports/providers'
import { account, fullDeps, transaction } from '@/testing/deps.test-helpers'
import { FakePreviewProvider } from '@/testing/providers'
import { TENANT } from '@/testing/scenario.test-helpers'
import {
  makePreviewFeed,
  pairMovements,
  settlePreviews,
} from '@/use-cases/preview-feed'

const movement = (cents: number, bookedOn: string, description = 'Market') => ({
  amount: Money.of(cents),
  bookedOn,
  description,
})

describe('pairMovements', () => {
  it('pairs by amount on the closest day, then by merchant words', () => {
    const near = movement(-500, '2026-10-06', 'Bakery')
    const far = movement(-500, '2026-10-03', 'Bakery')
    const converted = movement(-1210, '2026-10-05', 'Store Abroad')
    const left = [
      movement(-500, '2026-10-05'),
      movement(-1200, '2026-10-05', 'STORE ABROAD 123'),
    ]
    const pairs = pairMovements(left, [far, near, converted])
    expect(pairs).toEqual([
      [left[0], near],
      [left[1], converted],
    ])
  })

  it('leaves alone what is too far, reversed or has no words', () => {
    const left = [
      movement(-500, '2026-10-01'),
      movement(-700, '2026-10-05', 'Refund Shop'),
      movement(-800, '2026-10-05', 'PIX 123'),
    ]
    const right = [
      movement(-500, '2026-10-04'),
      movement(700, '2026-10-05', 'Refund Shop'),
      movement(-900, '2026-10-05', 'PIX 456'),
    ]
    expect(pairMovements(left, right)).toEqual([])
  })

  it('uses each movement once', () => {
    const twin = movement(-500, '2026-10-05')
    const pairs = pairMovements(
      [twin, { ...twin }],
      [movement(-500, '2026-10-05')],
    )
    expect(pairs).toHaveLength(1)
  })
})

describe('settlePreviews', () => {
  const checking = account({ id: 'a1', connectionId: 'c1' })

  async function seeded() {
    const deps = fullDeps()
    const save = (overrides: Parameters<typeof transaction>[0]) =>
      deps.transactions.save(transaction(overrides))
    await save({
      id: 'p-edited',
      accountId: 'a1',
      externalId: 'pierre:1',
      amount: Money.of(-500),
      bookedOn: '2026-10-05',
      description: 'Market',
      categoryId: 'groceries',
      categorizedBy: 'USER',
      categoryConfidence: 1,
      note: 'weekly',
      provisional: true,
    })
    await save({
      id: 'p-gone',
      accountId: 'a1',
      externalId: 'pierre:2',
      amount: Money.of(-900),
      bookedOn: '2026-10-01',
      provisional: true,
    })
    await save({
      id: 'p-kept',
      accountId: 'a1',
      externalId: 'pierre:3',
      amount: Money.of(-300),
      bookedOn: '2026-10-01',
      note: 'check this',
      provisional: true,
    })
    await save({
      id: 'p-recent',
      accountId: 'a1',
      externalId: 'pierre:4',
      amount: Money.of(-200),
      bookedOn: '2026-10-07',
      provisional: true,
    })
    await save({
      id: 'stored',
      accountId: 'a1',
      externalId: 'tx-stored',
      amount: Money.of(-200),
      bookedOn: '2026-10-07',
    })
    return deps
  }

  const incoming = [
    transaction({
      id: 'new-1',
      accountId: 'a1',
      externalId: 'tx-1',
      amount: Money.of(-500),
      bookedOn: '2026-10-05',
      description: 'MARKET SA',
      merchant: 'Market',
    }),
    transaction({
      id: 'again',
      accountId: 'a1',
      externalId: 'tx-stored',
      amount: Money.of(-200),
      bookedOn: '2026-10-07',
    }),
  ]

  it('confirms a recognised preview with the main facts and the user edits', async () => {
    const deps = await seeded()
    const result = await settlePreviews(deps, checking, incoming, '2026-10-08')
    expect(result).toEqual({ confirmed: 1, dropped: 1 })
    expect(await deps.transactions.findById(TENANT, 'p-edited')).toMatchObject({
      externalId: 'tx-1',
      description: 'MARKET SA',
      merchant: 'Market',
      categoryId: 'groceries',
      categorizedBy: 'USER',
      note: 'weekly',
      provisional: false,
    })
    expect(await deps.transactions.findById(TENANT, 'p-gone')).toBeNull()
    expect(await deps.transactions.findById(TENANT, 'p-kept')).not.toBeNull()
    expect(await deps.transactions.findById(TENANT, 'p-recent')).toMatchObject({
      provisional: true,
    })
  })

  it('drops nothing when the main provider does not say how far it collected', async () => {
    const deps = await seeded()
    expect(await settlePreviews(deps, checking, [], null)).toEqual({
      confirmed: 0,
      dropped: 0,
    })
    expect(await deps.transactions.findById(TENANT, 'p-gone')).not.toBeNull()
  })

  it('keeps a preview another edit already claimed', async () => {
    const deps = await seeded()
    const edit = async (id: string, patch: Partial<Transaction>) => {
      const stored = await deps.transactions.findById(TENANT, id)
      if (!stored) {
        throw new Error(`missing ${id}`)
      }
      await deps.transactions.save({ ...stored, ...patch })
    }
    await edit('p-gone', { categorizedBy: 'USER' })
    await edit('p-recent', { transferGroupId: 'g1', bookedOn: '2026-10-01' })
    await deps.transactions.save(
      transaction({
        id: 'p-invoiced',
        accountId: 'a1',
        externalId: 'pierre:5',
        bookedOn: '2026-10-01',
        invoiceId: 'inv-1',
        provisional: true,
      }),
    )
    const result = await settlePreviews(deps, checking, [], '2026-10-08')
    expect(result).toEqual({ confirmed: 0, dropped: 0 })
  })

  it('does nothing for an account without previews', async () => {
    const deps = fullDeps()
    const all = vi.spyOn(deps.transactions, 'all')
    expect(
      await settlePreviews(deps, checking, incoming, '2026-10-08'),
    ).toEqual({ confirmed: 0, dropped: 0 })
    expect(all).toHaveBeenCalledTimes(1)
  })
})

describe('makePreviewFeed', () => {
  const offer = (overrides: Partial<PreviewAccount> = {}): PreviewAccount => ({
    externalId: 'pa-1',
    institutionName: 'Test Bank',
    name: 'Checking',
    type: 'CHECKING',
    balanceCents: 10000,
    ...overrides,
  })

  const feedTx = (
    overrides: Partial<ProviderTransaction> & { externalId: string },
  ): ProviderTransaction => ({
    accountExternalId: 'pa-1',
    amountCents: -500,
    currency: 'BRL',
    bookedOn: '2026-10-07',
    description: 'Market',
    ...overrides,
  })

  async function setup(
    offers: PreviewAccount[],
    feed: ProviderTransaction[],
    accounts = [account({ id: 'a1', name: 'Checking ', connectionId: 'c1' })],
  ) {
    const preview = new FakePreviewProvider(offers, feed)
    const deps = fullDeps({ preview })
    await deps.institutions.ensure({
      id: 'inst',
      tenantId: TENANT,
      name: 'Test Bank',
      manual: false,
    })
    for (const stored of accounts) {
      await deps.accounts.save(stored)
    }
    return { deps, preview, feed: makePreviewFeed(deps) }
  }

  it('stores what the main feed lacks as provisional, once', async () => {
    const { deps, preview, feed } = await setup(
      [offer(), offer({ externalId: 'pa-2', name: 'Savings' })],
      [
        feedTx({
          externalId: 'pierre:1',
          merchant: 'Market',
          counterparty: '11.444.777/0001-61',
          installment: { number: 1, count: 3, purchaseOn: null },
        }),
        feedTx({ externalId: 'pierre:2', amountCents: -800 }),
        feedTx({ externalId: 'pierre:old', bookedOn: '2026-09-01' }),
      ],
      [
        account({ id: 'a1', name: 'Checking ', connectionId: 'c1' }),
        account({ id: 'manual', name: 'Checking' }),
      ],
    )
    await deps.transactions.save(
      transaction({
        id: 'stored',
        accountId: 'a1',
        externalId: 'tx-9',
        amount: Money.of(-800),
        bookedOn: '2026-10-06',
      }),
    )
    expect(await feed.sync(TENANT)).toEqual({ accounts: 1, previews: 1 })
    const [added] = await deps.transactions.all(TENANT, { provisional: true })
    expect(added).toMatchObject({
      accountId: 'a1',
      externalId: 'pierre:1',
      merchant: 'Market',
      counterparty: '11444777000161',
      installment: { number: 1, count: 3 },
    })
    expect(await feed.sync(TENANT)).toEqual({ accounts: 1, previews: 0 })
    expect(preview.refreshes).toBe(2)
  })

  it('tells same-named accounts apart by what they hold, then by balance', async () => {
    const twins = [
      account({ id: 'a1', name: 'Checking', connectionId: 'c1' }),
      account({
        id: 'a2',
        name: 'Checking',
        connectionId: 'c1',
        balance: Money.of(0),
      }),
    ]
    const known = await setup(
      [offer()],
      [
        feedTx({ externalId: 'pierre:1' }),
        feedTx({ externalId: 'pierre:2', amountCents: -100 }),
      ],
      twins,
    )
    await known.deps.transactions.save(
      transaction({
        id: 'stored',
        accountId: 'a2',
        amount: Money.of(-500),
        bookedOn: '2026-10-07',
      }),
    )
    await known.feed.sync(TENANT)
    expect(
      await known.deps.transactions.all(TENANT, { provisional: true }),
    ).toEqual([
      expect.objectContaining({ accountId: 'a2', amount: Money.of(-100) }),
    ])

    const fresh = await setup(
      [offer({ balanceCents: 0 })],
      [feedTx({ externalId: 'pierre:1' })],
      twins,
    )
    await fresh.feed.sync(TENANT)
    expect(
      await fresh.deps.transactions.all(TENANT, { provisional: true }),
    ).toEqual([expect.objectContaining({ accountId: 'a2' })])

    const unknown = await setup(
      [offer({ balanceCents: 7 })],
      [feedTx({ externalId: 'pierre:1' })],
      twins,
    )
    expect(await unknown.feed.sync(TENANT)).toEqual({
      accounts: 0,
      previews: 0,
    })
  })

  it('stays off without credentials and passes other failures through', async () => {
    const { preview, feed } = await setup([offer()], [])
    const listAccounts = vi.spyOn(preview, 'listAccounts')
    listAccounts.mockRejectedValueOnce(new ProviderNotConfiguredError('Feed'))
    expect(await feed.sync(TENANT)).toEqual({ accounts: 0, previews: 0 })
    expect(preview.refreshes).toBe(0)
    listAccounts.mockRejectedValueOnce(new Error('down'))
    await expect(feed.sync(TENANT)).rejects.toThrow('down')
  })

  it('skips an account it cannot place and survives a failed refresh', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => undefined)
    const { preview, feed } = await setup(
      [offer({ institutionName: 'Other Bank' })],
      [feedTx({ externalId: 'pierre:1' })],
      [
        account({
          id: 'a1',
          name: 'Checking',
          connectionId: 'c1',
          institutionId: 'gone',
        }),
      ],
    )
    preview.refreshError = new Error('busy')
    expect(await feed.sync(TENANT)).toEqual({ accounts: 0, previews: 0 })
    expect(warn).toHaveBeenCalledWith(expect.stringContaining('busy'))
    warn.mockRestore()
  })
})
