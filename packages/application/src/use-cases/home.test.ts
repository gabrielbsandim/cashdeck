import { describe, expect, it } from 'vitest'
import { Money } from '@cashdeck/domain'
import { InMemoryBudgetRepository } from '@/testing/records'
import {
  account,
  bill,
  fullDeps,
  invoice,
  transaction,
} from '@/testing/deps.test-helpers'
import { NOW, TENANT } from '@/testing/scenario.test-helpers'
import {
  makeCompanySummary,
  makeConsolidatedSummary,
  makePersonalSummary,
} from '@/use-cases/home'
import { PAYROLL_COLLECTION } from '@/use-cases/payroll'

const budgets = new InMemoryBudgetRepository([
  {
    tenantId: TENANT,
    entityId: 'pf',
    month: '2026-10',
    categoryId: 'food',
    categoryName: 'Food',
    limit: Money.of(10000),
  },
  {
    tenantId: TENANT,
    entityId: 'pf',
    month: '2026-10',
    categoryId: 'fun',
    categoryName: 'Fun',
    limit: Money.of(10000),
  },
])

describe('personal summary', () => {
  it('adds balances, reserve, forecast, budgets and alerts', async () => {
    const deps = fullDeps({ budgets })
    await deps.institutions.save({
      id: 'inst',
      tenantId: TENANT,
      name: 'Bank',
      manual: false,
    })
    await deps.accounts.save(
      account({
        id: 'chk',
        entityId: 'pf',
        balance: Money.of(200000),
        connectionId: 'c1',
      }),
    )
    await deps.accounts.save(
      account({
        id: 'res',
        entityId: 'pf',
        type: 'SAVINGS',
        isReserve: true,
        balance: Money.of(100000),
        cdiPercent: 102,
      }),
    )
    await deps.accounts.save(
      account({ id: 'card', entityId: 'pf', type: 'CREDIT_CARD' }),
    )
    await deps.connections.save({
      id: 'c1',
      tenantId: TENANT,
      entityId: 'pf',
      institutionId: 'inst',
      provider: 'pluggy',
      itemId: 'i1',
      status: 'UPDATED',
      lastSyncAt: NOW,
    })
    await deps.connections.save({
      id: 'c2',
      tenantId: TENANT,
      entityId: 'pf',
      institutionId: 'inst',
      provider: 'pluggy',
      itemId: 'i2',
      status: 'UPDATED',
      lastSyncAt: null,
    })
    await deps.transactions.save(
      transaction({
        id: 't1',
        accountId: 'chk',
        amount: Money.of(-15000),
        categoryId: 'food',
      }),
    )
    await deps.transactions.save(
      transaction({
        id: 't2',
        accountId: 'chk',
        amount: Money.of(-3000),
        transferGroupId: 'x',
      }),
    )
    await deps.transactions.save(
      transaction({ id: 'pay', accountId: 'chk', amount: Money.of(45000) }),
    )
    await deps.transactions.save(
      transaction({
        id: 'y',
        accountId: 'res',
        amount: Money.of(800),
        bookedOn: '2026-10-02',
      }),
    )
    await deps.bills.save(bill({ id: 'b1', dueDate: '2026-10-10' }))
    await deps.bills.save(bill({ id: 'late', dueDate: '2026-10-01' }))
    await deps.bills.save(bill({ id: 'paid', status: 'PAID' }))
    await deps.bills.save(bill({ id: 'a1', status: 'ASSISTED', payee: null }))
    await deps.bills.save(bill({ id: 'a2', status: 'ASSISTED' }))
    await deps.payments.addAttempt(TENANT, {
      id: 'at1',
      billId: 'a2',
      stepIndex: 0,
      rail: 'ASAAS',
      mode: 'AUTOMATIC',
      method: 'BOLETO',
      amount: Money.of(1),
      outcome: 'FAILED',
      reason: 'DAILY_CAP_EXCEEDED',
      externalId: null,
      idempotencyKey: 'k',
      at: NOW,
    })
    const summary = await makePersonalSummary(deps)(TENANT)
    expect(summary.balance.cents).toBe(200000)
    expect(summary.sync).toEqual({
      accountCount: 1,
      syncedAt: NOW.toISOString(),
    })
    expect(summary.reserve).toMatchObject({
      institution: 'Bank',
      monthYield: { cents: 800 },
      cdiPercent: 102,
    })
    expect(summary.forecast.from).toBe('2026-10-08')
    expect(summary.forecast.balances[0]?.cents).toBe(300000)
    expect(summary.forecast.balances[1]?.cents).toBe(301000)
    expect(summary.budgets.map(b => [b.category, b.spent.cents])).toEqual([
      ['food', 15000],
      ['fun', 0],
    ])
    expect(summary.alerts.map(alert => alert.type)).toEqual([
      'ASSISTED_PAYMENT',
      'ASSISTED_PAYMENT',
      'BUDGET_EXCEEDED',
    ])
    expect(summary.alerts[0]).toMatchObject({
      payee: '',
      reason: 'NOT_CONFIGURED',
    })
    expect(summary.alerts[1]).toMatchObject({ reason: 'DAILY_CAP_EXCEEDED' })
  })

  it('has no reserve, sync or institution when nothing is set up', async () => {
    const deps = fullDeps()
    await deps.accounts.save(
      account({
        id: 'res',
        entityId: 'pf',
        isReserve: true,
        institutionId: 'gone',
      }),
    )
    const summary = await makePersonalSummary(deps)(TENANT)
    expect(summary.sync).toEqual({ accountCount: 0, syncedAt: null })
    expect(summary.reserve?.institution).toBe('')
    const empty = await makePersonalSummary(fullDeps())(TENANT)
    expect(empty.reserve).toBeNull()
  })
})

describe('company summary', () => {
  it('estimates the DAS and lists drafts and unbilled receipts', async () => {
    const deps = fullDeps()
    await deps.accounts.save(account({ id: 'op', balance: Money.of(900000) }))
    await deps.invoices.save(
      invoice({ id: 'i1', competence: '2026-10', issueOn: '2026-10-02' }),
    )
    await deps.invoices.save(
      invoice({
        id: 'i2',
        competence: '2026-10',
        isExport: true,
        amount: Money.of(1000, 'USD'),
        fxRate: 5.4,
      }),
    )
    await deps.invoices.save(invoice({ id: 'old', competence: '2026-03' }))
    await deps.invoices.save(
      invoice({ id: 'd1', status: 'DRAFT', templateId: 'tpl' }),
    )
    await deps.invoices.save(
      invoice({ id: 'd2', status: 'DRAFT', clientId: 'gone' }),
    )
    await deps.invoices.saveClient({
      id: 'client',
      tenantId: TENANT,
      entityId: 'pj',
      name: 'Client Inc',
      taxId: null,
      country: 'US',
    })
    await deps.documents.put(TENANT, PAYROLL_COLLECTION, '2026-09', {
      month: '2026-09',
      proLaboreCents: 50000,
      salariesCents: 0,
      fgtsCents: 0,
    })
    await deps.transactions.save(
      transaction({
        id: 'r1',
        accountId: 'op',
        amount: Money.of(70000),
        description: 'Client Inc',
      }),
    )
    await deps.transactions.save(
      transaction({
        id: 'r2',
        accountId: 'op',
        amount: Money.of(70000),
        invoiceId: 'i1',
      }),
    )
    const summary = await makeCompanySummary(deps)(TENANT)
    expect(summary).toMatchObject({
      cash: { cents: 900000 },
      invoiceCount: 2,
      billed: { cents: 100000 + 5400 },
      dasDue: '2026-11-19',
    })
    expect(summary.annex).toMatch(/III|V/)
    expect(summary.drafts.map(d => [d.customer, d.recurring])).toEqual(
      expect.arrayContaining([
        ['Client Inc', true],
        ['', false],
      ]),
    )
    expect(summary.unbilled).toEqual([
      expect.objectContaining({
        id: 'r1',
        payer: 'Client Inc',
        receivedOn: '2026-10-05',
      }),
    ])
  })
})

describe('consolidated summary', () => {
  it('splits external flows from internal transfers', async () => {
    const deps = fullDeps()
    await deps.accounts.save(
      account({ id: 'pf-1', entityId: 'pf', balance: Money.of(100) }),
    )
    await deps.accounts.save(account({ id: 'pj-1', balance: Money.of(200) }))
    await deps.transactions.save(
      transaction({ id: 'in', accountId: 'pj-1', amount: Money.of(5000) }),
    )
    await deps.transactions.save(
      transaction({ id: 'out', accountId: 'pf-1', amount: Money.of(-700) }),
    )
    await deps.transactions.save(
      transaction({
        id: 'mv',
        accountId: 'pf-1',
        amount: Money.of(900),
        transferGroupId: 'tr',
      }),
    )
    await deps.transfers.save({
      id: 'tr',
      tenantId: TENANT,
      kind: 'PROFIT_DISTRIBUTION',
      amount: Money.of(900),
      at: NOW,
      rail: 'PIX',
      fromAccountId: 'pj-1',
      toAccountId: 'pf-1',
      document: null,
    })
    const summary = await makeConsolidatedSummary(deps)(TENANT)
    expect(summary).toMatchObject({
      personal: { cents: 100 },
      company: { cents: 200 },
      externalIn: { cents: 5000 },
      externalOut: { cents: -700 },
      transfers: [{ id: 'tr', on: '2026-10-08' }],
    })
  })
})
