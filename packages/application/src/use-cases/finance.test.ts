import { describe, expect, it } from 'vitest'
import { Money, ValidationError } from '@cashdeck/domain'
import { NotFoundError } from '@/errors/errors'
import { account, fullDeps, transaction } from '@/testing/deps.test-helpers'
import { NOW, TENANT } from '@/testing/scenario.test-helpers'
import {
  makeCreateManualAccount,
  makeGetTransfer,
  makeListAccounts,
  makeListEntities,
  makeListTransactions,
  makeListTransfers,
  makeRecordTransfer,
  makeUpdateAccount,
  makeUpdateEntity,
} from '@/use-cases/finance'

async function seeded() {
  const deps = fullDeps()
  await deps.institutions.save({
    id: 'inst',
    tenantId: TENANT,
    name: 'Bank',
    manual: false,
  })
  await deps.accounts.save(account({ id: 'pj-1', name: 'Operating' }))
  await deps.accounts.save(
    account({ id: 'pf-1', entityId: 'pf', name: 'Checking' }),
  )
  return deps
}

describe('entities and accounts', () => {
  it('lists the entities, personal first', async () => {
    const list = await makeListEntities(fullDeps())(TENANT)
    expect(list.map(entity => entity.kind)).toEqual(['PF', 'PJ'])
    expect(list[1]).toMatchObject({
      taxId: '11222333000181',
      taxRegime: 'SIMPLES_NACIONAL',
    })
  })

  it('updates the name, tax id and regime of an entity, audited', async () => {
    const deps = fullDeps()
    const update = makeUpdateEntity(deps)
    const company = await update(TENANT, 'pj', {
      name: 'Studio Exemplo',
      taxId: '11.444.777/0001-61',
      taxRegime: 'LUCRO_PRESUMIDO',
    })
    expect(company).toMatchObject({
      name: 'Studio Exemplo',
      taxId: '11444777000161',
      taxRegime: 'LUCRO_PRESUMIDO',
    })
    const person = await update(TENANT, 'pf', { name: 'Casa' })
    expect(person).toMatchObject({ name: 'Casa', taxRegime: null })
    expect(deps.audit.events.at(-1)).toMatchObject({
      action: 'entity.update',
      subjectId: 'pf',
      details: { fields: ['name'] },
    })
    await expect(
      update(TENANT, 'pf', { taxId: '11444777000161' }),
    ).rejects.toThrow('matching tax id')
    await expect(update(TENANT, 'nope', {})).rejects.toThrow()
  })

  it('lists every account, or one entity, by name', async () => {
    const deps = await seeded()
    const list = makeListAccounts(deps)
    expect((await list(TENANT)).map(a => a.name)).toEqual([
      'Checking',
      'Operating',
    ])
    const company = await list(TENANT, 'PJ')
    expect(company).toEqual([
      expect.objectContaining({
        id: 'pj-1',
        entityKind: 'PJ',
        institution: 'Bank',
      }),
    ])
  })

  it('shows the logo, the card line and the sync of each account', async () => {
    const deps = fullDeps()
    await deps.institutions.save({
      id: 'branded',
      tenantId: TENANT,
      name: 'Banco Exemplo',
      manual: false,
      connectorId: 1,
      imageUrl: 'https://logo.example/1.svg',
      primaryColor: 'FF0000',
    })
    await deps.institutions.save({
      id: 'plain',
      tenantId: TENANT,
      name: 'Banco Sem Cor',
      manual: false,
      imageUrl: 'https://logo.example/2.svg',
    })
    await deps.connections.save({
      id: 'conn',
      tenantId: TENANT,
      entityId: 'pf',
      institutionId: 'branded',
      provider: 'pluggy',
      itemId: 'item',
      status: 'UPDATED',
      lastSyncAt: NOW,
    })
    await deps.connections.save({
      id: 'fresh',
      tenantId: TENANT,
      entityId: 'pf',
      institutionId: 'branded',
      provider: 'pluggy',
      itemId: 'item-2',
      status: 'UPDATING',
      lastSyncAt: null,
    })
    await deps.accounts.save(
      account({
        id: 'card',
        entityId: 'pf',
        name: 'A card',
        type: 'CREDIT_CARD',
        institutionId: 'branded',
        connectionId: 'conn',
        numberSuffix: '4321',
        credit: {
          limit: Money.of(10_000),
          available: Money.of(4_000),
          closesOn: '2026-10-20',
          dueOn: '2026-10-27',
          brand: 'VISA',
        },
      }),
    )
    await deps.accounts.save(
      account({
        id: 'other',
        entityId: 'pf',
        name: 'B other',
        institutionId: 'plain',
        connectionId: 'fresh',
      }),
    )
    const [card, other] = await makeListAccounts(deps)(TENANT)
    expect(card).toMatchObject({
      numberSuffix: '4321',
      logo: { imageUrl: 'https://logo.example/1.svg', color: 'FF0000' },
      credit: { usedPercent: 60, dueOn: '2026-10-27', brand: 'VISA' },
      sync: { status: 'UPDATED', lastSyncAt: NOW.toISOString() },
    })
    expect(other).toMatchObject({
      logo: { color: null },
      credit: null,
      sync: { status: 'UPDATING', lastSyncAt: null },
    })
  })

  it('shows an unknown institution as blank', async () => {
    const deps = fullDeps()
    await deps.accounts.save(account({ id: 'a', institutionId: 'gone' }))
    const [view] = await makeListAccounts(deps)(TENANT)
    expect(view).toMatchObject({ institution: '', logo: null, sync: null })
  })

  it('fails when an account belongs to no known entity', async () => {
    const deps = fullDeps()
    await deps.accounts.save(account({ id: 'a', entityId: 'ghost' }))
    await expect(makeListAccounts(deps)(TENANT)).rejects.toThrow(NotFoundError)
  })

  it('creates a manual account and keeps one reserve per entity', async () => {
    const deps = await seeded()
    await deps.accounts.save(account({ id: 'old', isReserve: true }))
    await deps.accounts.save(account({ id: 'card', type: 'CREDIT_CARD' }))
    const created = await makeCreateManualAccount(deps)(TENANT, {
      entity: 'PJ',
      institution: 'Broker',
      name: 'Reserve',
      type: 'SAVINGS',
      currency: 'BRL',
      isReserve: true,
      balanceCents: 500000,
    })
    expect(created).toMatchObject({
      institution: 'Broker',
      isReserve: true,
      origin: 'MANUAL',
    })
    expect((await deps.accounts.findById(TENANT, 'old'))?.isReserve).toBe(false)
  })

  it('creates a plain account without touching the reserve', async () => {
    const deps = await seeded()
    await deps.accounts.save(account({ id: 'old', isReserve: true }))
    await makeCreateManualAccount(deps)(TENANT, {
      entity: 'PJ',
      institution: 'Bank',
      name: 'Second',
      type: 'CHECKING',
      currency: 'BRL',
      isReserve: false,
      balanceCents: 0,
    })
    expect((await deps.accounts.findById(TENANT, 'old'))?.isReserve).toBe(true)
  })

  it('updates a manual account', async () => {
    const deps = await seeded()
    const update = makeUpdateAccount(deps)
    const updated = await update(TENANT, 'pj-1', {
      name: 'Main',
      isReserve: true,
      cdiPercent: 100,
      balanceCents: 777,
    })
    expect(updated).toMatchObject({
      name: 'Main',
      isReserve: true,
      cdiPercent: 100,
    })
    expect(updated.balance.cents).toBe(777)
    const kept = await update(TENANT, 'pj-1', {})
    expect(kept).toMatchObject({ name: 'Main', cdiPercent: 100 })
    expect(await update(TENANT, 'pf-1', { name: 'Daily' })).toMatchObject({
      name: 'Daily',
      isReserve: false,
    })
  })

  it('refuses a balance on a connected account and an unknown account', async () => {
    const deps = await seeded()
    await deps.accounts.save(account({ id: 'linked', origin: 'CONNECTED' }))
    const update = makeUpdateAccount(deps)
    await expect(update(TENANT, 'linked', { balanceCents: 1 })).rejects.toThrow(
      ValidationError,
    )
    await expect(update(TENANT, 'nope', {})).rejects.toThrow(NotFoundError)
  })
})

describe('transactions', () => {
  it('lists transactions by entity and account', async () => {
    const deps = await seeded()
    await deps.transactions.save(transaction({ id: 't1', accountId: 'pj-1' }))
    await deps.transactions.save(transaction({ id: 't2', accountId: 'pf-1' }))
    const list = makeListTransactions(deps)
    const all = await list(TENANT, { limit: 50 })
    expect(all.items.map(t => t.id).sort()).toEqual(['t1', 't2'])
    const one = await list(TENANT, {
      limit: 50,
      entity: 'PJ',
      accountId: 'pj-1',
    })
    expect(one.items).toEqual([
      expect.objectContaining({ id: 't1', entityKind: 'PJ', kind: 'EXPENSE' }),
    ])
    expect(one.nextCursor).toBeNull()
  })
})

describe('internal transfers', () => {
  it('records a transfer and links both bank lines', async () => {
    const deps = await seeded()
    await deps.transactions.save(
      transaction({
        id: 'out',
        accountId: 'pj-1',
        amount: Money.of(-30000),
        bookedOn: '2026-10-07',
      }),
    )
    await deps.transactions.save(
      transaction({
        id: 'in',
        accountId: 'pf-1',
        amount: Money.of(30000),
        bookedOn: '2026-10-09',
      }),
    )
    const view = await makeRecordTransfer(deps)(TENANT, {
      kind: 'PROFIT_DISTRIBUTION',
      amountCents: 30000,
      fromAccountId: 'pj-1',
      toAccountId: 'pf-1',
      rail: 'PIX',
    })
    expect(view).toMatchObject({
      neutral: true,
      at: NOW.toISOString(),
      document: null,
      from: { owner: 'PJ', holder: 'Company', account: 'Operating' },
      to: { owner: 'PF', accountId: 'pf-1' },
    })
    expect(
      (await deps.transactions.findById(TENANT, 'out'))?.transferGroupId,
    ).toBe(view.id)
    expect(
      (await deps.transactions.findById(TENANT, 'in'))?.transferGroupId,
    ).toBe(view.id)
    expect(await makeGetTransfer(deps)(TENANT, view.id)).toEqual(view)
  })

  it('keeps a transfer without matching lines, at the given time', async () => {
    const deps = await seeded()
    const view = await makeRecordTransfer(deps)(TENANT, {
      kind: 'PRO_LABORE',
      amountCents: 100,
      fromAccountId: 'pj-1',
      toAccountId: 'pf-1',
      at: '2026-09-15T12:00:00Z',
      rail: 'TED',
      document: 'receipt-1',
    })
    expect(view).toMatchObject({ neutral: false, document: 'receipt-1' })
    expect(await makeListTransfers(deps)(TENANT, '2026-09')).toHaveLength(1)
    expect(await makeListTransfers(deps)(TENANT)).toEqual([])
  })

  it('refuses a transfer inside one entity or to an unknown account', async () => {
    const deps = await seeded()
    await deps.accounts.save(account({ id: 'pj-2' }))
    const record = makeRecordTransfer(deps)
    const base = { kind: 'PRO_LABORE' as const, amountCents: 1, rail: 'PIX' }
    await expect(
      record(TENANT, { ...base, fromAccountId: 'pj-1', toAccountId: 'pj-2' }),
    ).rejects.toThrow(ValidationError)
    await expect(
      record(TENANT, { ...base, fromAccountId: 'pj-1', toAccountId: 'nope' }),
    ).rejects.toThrow(NotFoundError)
    await expect(makeGetTransfer(deps)(TENANT, 'nope')).rejects.toThrow(
      NotFoundError,
    )
  })

  it('fails when a transfer account belongs to no known entity', async () => {
    const deps = await seeded()
    await deps.accounts.save(account({ id: 'ghost', entityId: 'ghost' }))
    await deps.transfers.save({
      id: 'x',
      tenantId: TENANT,
      kind: 'PRO_LABORE',
      amount: Money.of(1),
      at: NOW,
      rail: 'PIX',
      fromAccountId: 'pj-1',
      toAccountId: 'ghost',
      document: null,
    })
    await expect(makeGetTransfer(deps)(TENANT, 'x')).rejects.toThrow(
      NotFoundError,
    )
  })
})
