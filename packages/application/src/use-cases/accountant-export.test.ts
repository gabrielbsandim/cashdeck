import { describe, expect, it } from 'vitest'
import { Money } from '@cashdeck/domain'
import { NotFoundError } from '@/errors/errors'
import {
  account,
  bill,
  fullDeps,
  invoice,
  transaction,
} from '@/testing/deps.test-helpers'
import { NOW, TENANT } from '@/testing/scenario.test-helpers'
import {
  exportRange,
  makeAccountantExport,
  toCsv,
} from '@/use-cases/accountant-export'
import { PAYROLL_COLLECTION } from '@/use-cases/payroll'

async function seeded() {
  const deps = fullDeps()
  await deps.accounts.save(account({ id: 'op', name: 'Operating' }))
  await deps.transactions.save(
    transaction({
      id: 't1',
      accountId: 'op',
      bookedOn: '2026-09-10',
      description: 'Rent, office',
    }),
  )
  await deps.transactions.save(
    transaction({
      id: 'r1',
      accountId: 'op',
      bookedOn: '2026-09-28',
      amount: Money.of(60000),
      invoiceId: 'i1',
    }),
  )
  await deps.invoices.saveClient({
    id: 'client',
    tenantId: TENANT,
    entityId: 'pj',
    name: 'Client "A"',
    taxId: null,
    country: 'US',
  })
  await deps.invoices.save(invoice({ id: 'i1', number: '7' }))
  await deps.invoices.save(
    invoice({
      id: 'i2',
      clientId: 'gone',
      isExport: true,
      amount: Money.of(1000, 'USD'),
      fxRate: 5,
    }),
  )
  await deps.bills.save(
    bill({
      id: 'das',
      entityId: 'pj',
      kind: 'TAX_BARCODE',
      dueDate: '2026-09-20',
    }),
  )
  await deps.bills.save(
    bill({
      id: 'exp',
      entityId: 'pj',
      dueDate: '2026-09-05',
      status: 'PAID',
      paidAt: NOW,
    }),
  )
  await deps.bills.save(
    bill({ id: 'later', entityId: 'pj', dueDate: '2026-10-05' }),
  )
  await deps.bills.save(
    bill({ id: 'early', entityId: 'pj', dueDate: '2026-08-05' }),
  )
  await deps.attachments.save({
    id: 'att',
    tenantId: TENANT,
    billId: 'das',
    fileName: 'das.pdf',
    mimeType: 'application/pdf',
    size: 3,
    createdAt: NOW,
    bytes: new Uint8Array([1, 2, 3]),
  })
  await deps.documents.put(TENANT, PAYROLL_COLLECTION, '2026-09', {
    month: '2026-09',
    proLaboreCents: 150000,
    salariesCents: 0,
    fgtsCents: 0,
  })
  await deps.documents.put(TENANT, PAYROLL_COLLECTION, '2026-08', {
    month: '2026-08',
    proLaboreCents: 150000,
    salariesCents: 0,
    fgtsCents: 0,
  })
  await deps.documents.put(TENANT, PAYROLL_COLLECTION, '2026-03', {
    month: '2026-03',
    proLaboreCents: 1,
    salariesCents: 0,
    fgtsCents: 0,
  })
  return deps
}

describe('accountant export', () => {
  it('resolves the periods', () => {
    expect(exportRange({ period: 'LAST_MONTH' }, '2026-10-08')).toEqual({
      from: '2026-09-01',
      to: '2026-09-30',
    })
    expect(exportRange({ period: 'LAST_QUARTER' }, '2026-10-08')).toEqual({
      from: '2026-07-01',
      to: '2026-09-30',
    })
    expect(exportRange({ period: 'LAST_QUARTER' }, '2026-12-31')).toEqual({
      from: '2026-07-01',
      to: '2026-09-30',
    })
    expect(exportRange({ period: 'LAST_QUARTER' }, '2026-02-10')).toEqual({
      from: '2025-10-01',
      to: '2025-12-31',
    })
    expect(
      exportRange(
        { period: 'CUSTOM', from: '2026-01-15', to: '2026-02-10' },
        '2026-10-08',
      ),
    ).toEqual({ from: '2026-01-15', to: '2026-02-10' })
  })

  it('quotes CSV cells that need it', () => {
    expect(
      toCsv(
        ['a', 'b'],
        [
          ['x,y', null],
          ['say "hi"', 3],
        ],
      ),
    ).toBe('a,b\n"x,y",\n"say ""hi""",3\n')
  })

  it('plans the last month with counts and sizes', async () => {
    const deps = await seeded()
    const plan = await makeAccountantExport(deps).plan(TENANT, {
      period: 'LAST_MONTH',
    })
    expect(plan.from).toBe('2026-09-01')
    expect(
      plan.items.map(item => [
        item.kind,
        item.count,
        item.unit,
        item.files,
        item.selectedByDefault,
      ]),
    ).toEqual([
      ['STATEMENTS', 1, 'ACCOUNTS', 1, true],
      ['INVOICES', 2, 'DOCUMENTS', 1, true],
      ['TAX_GUIDES', 1, 'DOCUMENTS', 2, true],
      ['EXPENSES', 1, 'DOCUMENTS', 1, true],
      ['PAYROLL', 1, 'MONTHS', 1, true],
      ['RECONCILIATION', 1, 'MONTHS', 1, false],
    ])
    expect(plan.items[2]?.bytes).toBeGreaterThan(3)
  })

  it('generates, lists and downloads an export', async () => {
    const deps = await seeded()
    const exporter = makeAccountantExport(deps)
    const first = await exporter.generate(TENANT, {
      period: 'LAST_MONTH',
      items: ['TAX_GUIDES', 'INVOICES', 'RECONCILIATION', 'INVOICES'],
      sentTo: 'accountant@example.com',
    })
    expect(first).toEqual({
      id: first.id,
      month: '2026-09-01',
      sentOn: '2026-10-08',
      to: 'accountant@example.com',
      downloadPath: `/api/v1/accountant-export/${first.id}/download`,
    })
    deps.clock.set(new Date('2026-10-09T12:00:00Z'))
    const second = await exporter.generate(TENANT, {
      period: 'LAST_QUARTER',
      items: ['PAYROLL', 'STATEMENTS', 'EXPENSES'],
    })
    expect(second.to).toBeNull()
    expect((await exporter.history(TENANT)).map(record => record.id)).toEqual([
      second.id,
      first.id,
    ])
    const zip = await exporter.download(TENANT, first.id)
    expect(zip.fileName).toBe('cashdeck-2026-09-01-2026-09-30.zip')
    const entries = deps.archives.archives[0] ?? []
    expect(entries.map(entry => entry.name)).toEqual([
      'tax-guides.csv',
      'tax-guides/att-das.pdf',
      'invoices.csv',
      'reconciliation.csv',
    ])
    expect(entries[2]?.content).toContain('"Client ""A"""')
    expect(entries[3]?.content).toContain('2026-09,2,1050.00,600.00,450.00')
    await exporter.download(TENANT, second.id)
    expect(deps.archives.archives[1]?.[0]?.content).toMatch(
      /2026-08,.*\n2026-09,/,
    )
    expect(deps.archives.archives[1]?.map(entry => entry.name)).toEqual([
      'payroll.csv',
      'statements.csv',
      'expenses.csv',
    ])
    await expect(exporter.download(TENANT, 'nope')).rejects.toThrow(
      NotFoundError,
    )
  })

  it('skips an attachment that disappeared', async () => {
    const deps = await seeded()
    deps.attachments.find = async () => null
    const exporter = makeAccountantExport(deps)
    const record = await exporter.generate(TENANT, {
      period: 'LAST_MONTH',
      items: ['TAX_GUIDES'],
    })
    await exporter.download(TENANT, record.id)
    expect(deps.archives.archives[0]?.map(entry => entry.name)).toEqual([
      'tax-guides.csv',
    ])
  })
})
