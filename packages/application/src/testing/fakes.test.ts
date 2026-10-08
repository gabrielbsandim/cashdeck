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
  FakeSecretVault,
  FakeStatementImporter,
} from '@/testing/providers'
import {
  InMemoryAccountRepository,
  InMemoryBillRepository,
  InMemoryEntityRepository,
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

  it('sums committed attempts per rail and day', async () => {
    const repo = new InMemoryPaymentRepository()
    const attempt = {
      id: 'a',
      billId: 'b',
      stepIndex: 0,
      rail: 'ASAAS' as const,
      mode: 'AUTOMATIC' as const,
      amount: Money.of(500),
      outcome: 'PAID' as const,
      reason: null,
      externalId: null,
      idempotencyKey: 'b:0',
      at: new Date('2026-10-08T12:00:00Z'),
    }
    await repo.addAttempt('t', attempt)
    await repo.addAttempt('t', { ...attempt, id: 'c', outcome: 'FAILED' })
    await repo.addAttempt('t', { ...attempt, id: 'd', rail: 'INTER_EMPRESAS' })
    await repo.addAttempt('other', attempt)
    expect(await repo.committedCents('t', 'ASAAS', '2026-10-08')).toBe(500)
    expect(await repo.committedCents('t', 'ASAAS', '2026-10-09')).toBe(0)
    expect(await repo.listAttempts('t', 'b')).toHaveLength(3)
    expect(await repo.findPlan('t', 'b')).toBeNull()
  })

  it('serves default settings', async () => {
    expect((await new StaticPaymentSettings().get()).killSwitch).toBe(false)
  })
})

describe('provider fakes', () => {
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
