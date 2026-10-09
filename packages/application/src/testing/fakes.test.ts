import { describe, expect, it } from 'vitest'
import {
  createAccount,
  createBill,
  createFinancialEntity,
  Money,
} from '@cashdeck/domain'
import { LlmProviderError } from '@/ports/llm-provider'
import {
  FakeBillSource,
  FakeInvoiceIssuer,
  FakeLlmProvider,
  FakeNotifier,
  FakeOpenFinanceProvider,
  FakePaymentRail,
  FakeReserveFunder,
  FakeSecretVault,
  FakeStatementImporter,
} from '@/testing/providers'
import {
  InMemoryAccountRepository,
  InMemoryBillRepository,
  InMemoryEntityRepository,
  InMemoryFundingRepository,
  InMemoryIdempotencyStore,
  InMemorySecretStore,
  InMemoryPaymentRepository,
  StaticPaymentSettings,
} from '@/testing/repositories'
import { FixedClock, SequentialIdGenerator } from '@/testing/system'

const chat = {
  system: 's',
  messages: [],
  tools: [],
  maxInputTokens: 10,
  maxOutputTokens: 10,
}

describe('system fakes', () => {
  it('controls time and ids', () => {
    const clock = new FixedClock(new Date('2026-01-01T00:00:00Z'))
    clock.set(new Date('2026-02-01T00:00:00Z'))
    expect(clock.now().toISOString()).toBe('2026-02-01T00:00:00.000Z')
    const ids = new SequentialIdGenerator()
    expect([ids.next(), ids.next()]).toEqual(['id_1', 'id_2'])
  })
})

describe('repository fakes', () => {
  it('stores entities and accounts per tenant', async () => {
    const entities = new InMemoryEntityRepository()
    const entity = createFinancialEntity({
      id: 'pf',
      tenantId: 't1',
      kind: 'PF',
      name: 'Personal',
      taxId: '52998224725',
    })
    await entities.save(entity)
    expect(await entities.findById('t1', 'pf')).toEqual(entity)
    expect(await entities.findById('t2', 'pf')).toBeNull()

    const accounts = new InMemoryAccountRepository()
    const account = createAccount({
      id: 'a1',
      tenantId: 't1',
      entityId: 'pf',
      institutionId: 'bank',
      name: 'Checking',
      type: 'CHECKING',
      origin: 'MANUAL',
      balance: Money.of(100),
    })
    await accounts.save(account)
    await accounts.save({ ...account, id: 'a2', tenantId: 't2' })
    expect(await accounts.findById('t1', 'a1')).toEqual(account)
    expect(await accounts.findById('t1', 'missing')).toBeNull()
    expect(await accounts.listByEntity('t1', 'pf')).toEqual([account])
  })

  it('keeps idempotent results and sealed secrets per tenant', async () => {
    const store = new InMemoryIdempotencyStore()
    await store.save('t1', 'k', 'payment', { outcome: 'PAID' })
    expect(await store.find('t1', 'k')).toEqual({ outcome: 'PAID' })
    expect(await store.find('t2', 'k')).toBeNull()

    const secrets = new InMemorySecretStore()
    await secrets.put('t1', 'inter', 'sealed')
    expect(await secrets.get('t1', 'inter')).toBe('sealed')
    expect(await secrets.get('t2', 'inter')).toBeNull()
  })

  it('ignores cancelled bills when deduping by code', async () => {
    const repo = new InMemoryBillRepository()
    const bill = createBill({
      id: 'b1',
      tenantId: 't',
      entityId: 'e',
      kind: 'PIX_KEY',
      source: 'MANUAL',
      amount: Money.of(1),
      dueDate: '2026-10-08',
      code: 'k',
      createdAt: new Date(),
    })
    await repo.save({ ...bill, status: 'CANCELLED' })
    expect(await repo.findByCode('t', 'e', 'k')).toBeNull()
    expect(await repo.findById('t', 'missing')).toBeNull()
  })

  it('sums committed attempts per entity, rail and day', async () => {
    const bills = new InMemoryBillRepository()
    const repo = new InMemoryPaymentRepository(bills)
    const attempt = {
      id: 'a',
      billId: 'b',
      stepIndex: 0,
      rail: 'ASAAS' as const,
      mode: 'AUTOMATIC' as const,
      method: 'BOLETO' as const,
      amount: Money.of(500),
      outcome: 'PAID' as const,
      reason: null,
      externalId: null,
      idempotencyKey: 'b:0',
      at: new Date('2026-10-08T12:00:00Z'),
    }
    await bills.save(
      createBill({
        id: 'b',
        tenantId: 't',
        entityId: 'e',
        kind: 'BOLETO',
        source: 'MANUAL',
        amount: Money.of(500),
        dueDate: '2026-10-08',
        code: 'x',
        createdAt: new Date(0),
      }),
    )
    await repo.addAttempt('t', attempt)
    await repo.addAttempt('t', {
      ...attempt,
      id: 'c',
      idempotencyKey: 'b:1',
      outcome: 'FAILED',
    })
    await repo.addAttempt('t', {
      ...attempt,
      id: 'd',
      idempotencyKey: 'b:2',
      rail: 'INTER_EMPRESAS',
    })
    await repo.addAttempt('other', attempt)
    expect(await repo.committedCents('t', 'e', '2026-10-08', 'ASAAS')).toBe(500)
    expect(await repo.committedCents('t', 'e', '2026-10-08')).toBe(1000)
    expect(await repo.committedCents('t', 'e2', '2026-10-08')).toBe(0)
    expect(await repo.committedCents('t', 'e', '2026-10-09', 'ASAAS')).toBe(0)
    const open = new InMemoryPaymentRepository()
    await open.addAttempt('t', attempt)
    expect(await open.committedCents('t', 'any', '2026-10-08')).toBe(500)
    expect(await repo.listAttempts('t', 'b')).toHaveLength(3)
    expect(await repo.findPlan('t', 'b')).toBeNull()
  })

  it('claims an attempt id once per tenant', async () => {
    const repo = new InMemoryPaymentRepository()
    const claim = {
      id: 'k:claim',
      billId: 'b',
      stepIndex: 0,
      rail: 'ASAAS' as const,
      mode: 'AUTOMATIC' as const,
      method: 'PIX' as const,
      amount: Money.of(1),
      outcome: 'IN_FLIGHT' as const,
      reason: null,
      externalId: null,
      idempotencyKey: 'k',
      at: new Date(0),
    }
    expect(await repo.claimAttempt('t', claim)).toBe(true)
    expect(await repo.claimAttempt('t', claim)).toBe(false)
    expect(await repo.claimAttempt('other', claim)).toBe(true)
  })

  it('lists paid bills newest first and keeps funding rounds unique', async () => {
    const bills = new InMemoryBillRepository()
    const base = createBill({
      id: 'p1',
      tenantId: 't',
      entityId: 'e',
      kind: 'BOLETO',
      source: 'MANUAL',
      amount: Money.of(1),
      dueDate: '2026-10-08',
      code: 'x',
      createdAt: new Date(0),
    })
    await bills.save({ ...base, status: 'PAID', paidAt: new Date(1) })
    await bills.save({ ...base, id: 'p2', status: 'PAID', paidAt: new Date(2) })
    await bills.save({ ...base, id: 'p3', status: 'PAID', paidAt: null })
    await bills.save({ ...base, id: 'open' })
    await bills.save({ ...base, id: 'x', entityId: 'e2', status: 'PAID' })
    const paid = await bills.listRecentPaid('t', 'e', 2)
    expect(paid.map(bill => bill.id)).toEqual(['p2', 'p1'])

    const fundings = new InMemoryFundingRepository()
    const round = {
      id: 'r1',
      tenantId: 't',
      entityId: 'e',
      day: '2026-10-08',
      round: 1,
      billIds: ['p1'],
      billsTotal: Money.of(1),
      available: null,
      amount: Money.of(1),
      status: 'IN_FLIGHT' as const,
      reason: null,
      externalId: null,
      idempotencyKey: 'reserve:e:2026-10-08:1',
      at: new Date(0),
    }
    await fundings.create({ ...round, id: 'r2', round: 2 })
    await fundings.create(round)
    await expect(fundings.create({ ...round, id: 'r3' })).rejects.toThrow(
      'exists',
    )
    await fundings.update({ ...round, status: 'PAID' })
    const listed = await fundings.listByDay('t', 'e', '2026-10-08')
    expect(listed.map(row => [row.round, row.status])).toEqual([
      [1, 'PAID'],
      [2, 'IN_FLIGHT'],
    ])
    expect(await fundings.listByDay('t', 'e', '2026-10-09')).toEqual([])
    expect(await fundings.listByDay('t', 'e2', '2026-10-08')).toEqual([])
  })

  it('serves default settings', async () => {
    expect((await new StaticPaymentSettings().get()).killSwitch).toBe(false)
  })
})

describe('provider fakes', () => {
  it('scripts a reserve funder', async () => {
    const funder = new FakeReserveFunder(500).willReturn(new Error('down'))
    const scope = { tenantId: 't', entityId: 'e' }
    expect(await funder.availableCents(scope)).toBe(500)
    const request = {
      tenantId: 't',
      entityId: 'e',
      amountCents: 1,
      idempotencyKey: 'k',
      description: 'd',
    }
    await expect(funder.fund(request)).rejects.toThrow('down')
    expect((await funder.fund(request)).outcome).toBe('PAID')
    funder.available = new Error('no balance')
    await expect(funder.availableCents(scope)).rejects.toThrow('no balance')
  })

  it('scripts a payment rail', async () => {
    const rail = new FakePaymentRail('ASAAS', ['BOLETO'])
    expect(rail.supports('BOLETO')).toBe(true)
    expect(rail.supports('PIX_KEY')).toBe(false)
    expect(new FakePaymentRail('ASAAS').supports('PIX_KEY')).toBe(true)
    expect(await rail.check()).toEqual({ ok: true, message: null })
  })

  it('filters open finance transactions by account and range', async () => {
    const tx = {
      externalId: 'x',
      accountExternalId: 'acc',
      amountCents: -100,
      currency: 'BRL',
      bookedOn: '2026-10-05',
      description: 'Coffee',
    }
    const provider = new FakeOpenFinanceProvider([], [tx])
    const connection = { provider: 'fake', itemId: 'i' }
    expect(await provider.listAccounts()).toEqual([])
    expect(
      await provider.listTransactions(connection, 'acc', {
        from: '2026-10-01',
        to: '2026-10-31',
      }),
    ).toEqual([tx])
    expect(
      await provider.listTransactions(connection, 'acc', {
        from: '2026-10-06',
        to: '2026-10-31',
      }),
    ).toEqual([])
    expect(
      await provider.listTransactions(connection, 'acc', {
        from: '2026-09-01',
        to: '2026-10-04',
      }),
    ).toEqual([])
    expect(
      await provider.listTransactions(connection, 'other', {
        from: '2026-10-01',
        to: '2026-10-31',
      }),
    ).toEqual([])
    expect(await new FakeOpenFinanceProvider().listAccounts()).toEqual([])
    const item = {
      itemId: 'item-1',
      institutionName: 'Bank',
      status: 'UPDATED' as const,
      lastUpdatedAt: null,
    }
    const withItems = new FakeOpenFinanceProvider([], [], [item])
    expect(await withItems.getItem('item-1')).toBe(item)
    expect(await withItems.listBills(connection, 'card')).toEqual([])
    expect(await withItems.listConnectors()).toEqual([])
    await expect(withItems.getItem('nope')).rejects.toThrow('was not found')
  })

  it('reads statements and fetches bills', async () => {
    const draft = { format: 'fake', lines: [], closingDate: null }
    const importer = new FakeStatementImporter(draft)
    const file = {
      name: 'bill.fake',
      mimeType: 'text/plain',
      bytes: new Uint8Array(),
    }
    expect(importer.canRead(file)).toBe(true)
    expect(importer.canRead({ ...file, name: 'bill.pdf' })).toBe(false)
    expect(await importer.read()).toBe(draft)
    expect(await new FakeBillSource().fetch()).toEqual([])
  })

  it('issues invoices idempotently and cancels them', async () => {
    const issuer = new FakeInvoiceIssuer()
    const draft = {
      tenantId: 't',
      entityId: 'e',
      clientName: 'Client',
      clientTaxId: null,
      serviceCode: '01.01',
      description: 'Development',
      amountCents: 100,
      currency: 'BRL',
      export: false,
    }
    const issued = await issuer.issue(draft, 'k1')
    expect(await issuer.issue(draft, 'k1')).toBe(issued)
    expect((await issuer.cancel('k1', 'mistake')).status).toBe('CANCELLED')
    await expect(issuer.get('nope')).rejects.toThrow('was not issued')
    expect(await issuer.check()).toEqual({ ok: true, message: null })
  })

  it('notifies and seals secrets per context', async () => {
    const notifier = new FakeNotifier()
    await notifier.notify({
      tenantId: 't',
      type: 'x',
      title: 'a',
      body: 'b',
      localized: {
        pt: { title: 'a', body: 'b' },
        en: { title: 'A', body: 'B' },
      },
      data: {},
    })
    expect(notifier.sent).toHaveLength(1)
    const vault = new FakeSecretVault()
    const sealed = await vault.seal('secret', 'ctx')
    expect(await vault.open(sealed, 'ctx')).toBe('secret')
    await expect(vault.open(sealed, 'other')).rejects.toThrow('another context')
  })

  it('answers chats from a queue and refuses schema with tools', async () => {
    const llm = new FakeLlmProvider().enqueueObject({ ok: true })
    expect((await llm.chat(chat)).object).toEqual({ ok: true })
    expect((await llm.chat(chat)).text).toBe('fake response')
    expect(llm.calls).toHaveLength(2)
    await expect(
      llm.chat({
        ...chat,
        responseSchema: { type: 'object' },
        tools: [
          { name: 't', description: 'd', parameters: { type: 'object' } },
        ],
      }),
    ).rejects.toThrow(LlmProviderError)
  })
})
