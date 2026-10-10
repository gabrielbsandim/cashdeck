import { type PrismaClient } from '@prisma/client'
import { describe, expect, it, vi } from 'vitest'
import { type Invoice } from '@cashdeck/application'
import { createTransaction, Money } from '@cashdeck/domain'
import { transactionToRow } from '@/repositories/mappers'
import {
  createPrismaRecords,
  invoiceFromRow,
  invoiceToRow,
  templateToRow,
} from '@/repositories/prisma-records'

const TENANT = 't1'
const NOW = new Date('2026-10-08T12:00:00.000Z')

const DELEGATES = [
  'institution',
  'transaction',
  'connection',
  'internalTransfer',
  'invoice',
  'invoiceClient',
  'budget',
  'category',
  'billAttachment',
  'document',
  'invoiceFile',
  'invoiceTemplate',
  'webhookEvent',
  'creditCardBill',
  'recurrence',
] as const
const METHODS = [
  'upsert',
  'findFirst',
  'findUnique',
  'findMany',
  'create',
  'createMany',
  'deleteMany',
  'updateMany',
] as const

type Delegate = Record<(typeof METHODS)[number], ReturnType<typeof vi.fn>>

function mockClient() {
  const db = Object.fromEntries(
    DELEGATES.map(name => [
      name,
      Object.fromEntries(METHODS.map(method => [method, vi.fn()])),
    ]),
  ) as Record<(typeof DELEGATES)[number], Delegate>
  return { db, repos: createPrismaRecords(db as unknown as PrismaClient) }
}

const transaction = createTransaction({
  id: 'tx1',
  tenantId: TENANT,
  accountId: 'a1',
  amount: Money.of(-500),
  bookedOn: '2026-10-05',
  description: 'Market',
  externalId: 'e1',
  invoiceId: 'i1',
})

const invoice: Invoice = {
  id: 'i1',
  tenantId: TENANT,
  entityId: 'pj',
  clientId: 'c1',
  templateId: null,
  issuer: 'notaas',
  externalId: null,
  number: null,
  status: 'DRAFT',
  amount: Money.of(1000, 'USD'),
  fxRate: 5.4,
  isExport: true,
  competence: '2026-10',
  issueOn: '2026-10-08',
  description: 'Development',
  serviceCode: '01.01',
  pdfUrl: null,
  xmlUrl: null,
  cancelReason: null,
  createdAt: NOW,
}

const invoiceRow = {
  ...invoiceToRow(invoice),
  fxRate: { toString: () => '5.4' },
}

describe('institutions', () => {
  it('finds by id and ensures by name', async () => {
    const { db, repos } = mockClient()
    const row = {
      id: 'b',
      tenantId: TENANT,
      name: 'Bank',
      manual: false,
      code: null,
      connectorId: null,
      imageUrl: null,
      primaryColor: null,
    }
    db.institution.findFirst
      .mockResolvedValueOnce(row)
      .mockResolvedValueOnce(null)
    expect(await repos.institutions.findById(TENANT, 'b')).toEqual({
      id: 'b',
      tenantId: TENANT,
      name: 'Bank',
      manual: false,
      connectorId: null,
      imageUrl: null,
      primaryColor: null,
    })
    expect(await repos.institutions.findById(TENANT, 'x')).toBeNull()
    db.institution.upsert.mockResolvedValueOnce(row)
    const ensured = await repos.institutions.ensure({
      id: 'n',
      tenantId: TENANT,
      name: 'Bank',
      manual: true,
    })
    expect(ensured.id).toBe('b')
    expect(db.institution.upsert.mock.calls[0]?.[0].where).toEqual({
      tenantId_name: { tenantId: TENANT, name: 'Bank' },
    })
    expect(db.institution.upsert.mock.calls[0]?.[0].update).toEqual({})
    db.institution.upsert.mockResolvedValueOnce(row)
    await repos.institutions.ensure({
      id: 'n',
      tenantId: TENANT,
      name: 'Bank',
      manual: false,
      connectorId: 7,
      imageUrl: 'https://logo.example/7.svg',
    })
    const branded = {
      connectorId: 7,
      imageUrl: 'https://logo.example/7.svg',
      primaryColor: null,
    }
    expect(db.institution.upsert.mock.calls[1]?.[0]).toMatchObject({
      create: { id: 'n', ...branded },
      update: branded,
    })
  })
})

describe('transactions', () => {
  it('saves, inserts new ones and pages newest first', async () => {
    const { db, repos } = mockClient()
    await repos.transactions.save(transaction)
    expect(db.transaction.upsert.mock.calls[0]?.[0].create.amountCents).toBe(
      -500n,
    )
    db.transaction.createMany.mockResolvedValueOnce({ count: 1 })
    expect(await repos.transactions.saveNew([transaction])).toBe(1)
    expect(db.transaction.createMany.mock.calls[0]?.[0].skipDuplicates).toBe(
      true,
    )
    db.transaction.findFirst
      .mockResolvedValueOnce(transactionToRow(transaction))
      .mockResolvedValueOnce(null)
    expect(await repos.transactions.findById(TENANT, 'tx1')).toEqual(
      transaction,
    )
    expect(await repos.transactions.findById(TENANT, 'x')).toBeNull()
    const rows = [
      transactionToRow(transaction),
      transactionToRow({ ...transaction, id: 'tx2' }),
    ]
    db.transaction.findMany.mockResolvedValueOnce(rows)
    const page = await repos.transactions.list(
      TENANT,
      { accountIds: ['a1'], from: '2026-10-01', to: '2026-10-31' },
      { limit: 1 },
    )
    expect(page).toMatchObject({ nextCursor: '1' })
    expect(db.transaction.findMany.mock.calls[0]?.[0].where).toEqual({
      tenantId: TENANT,
      accountId: { in: ['a1'] },
      bookedOn: {
        gte: new Date('2026-10-01T00:00:00.000Z'),
        lte: new Date('2026-10-31T00:00:00.000Z'),
      },
    })
    db.transaction.findMany.mockResolvedValueOnce(rows.slice(1))
    expect(
      (await repos.transactions.list(TENANT, {}, { cursor: '1', limit: 1 }))
        .nextCursor,
    ).toBeNull()
    db.transaction.findMany.mockResolvedValueOnce(rows)
    expect(await repos.transactions.all(TENANT, {})).toHaveLength(2)
    expect(db.transaction.findMany.mock.calls[2]?.[0].where).toEqual({
      tenantId: TENANT,
      accountId: undefined,
      bookedOn: { gte: undefined, lte: undefined },
    })
  })

  it('filters by category, uncategorized and text', async () => {
    const { db, repos } = mockClient()
    db.transaction.findMany.mockResolvedValue([])
    await repos.transactions.all(TENANT, { categoryId: 'c1', search: 'sol' })
    expect(db.transaction.findMany.mock.calls[0]?.[0].where).toMatchObject({
      categoryId: 'c1',
      OR: [
        { description: { contains: 'sol', mode: 'insensitive' } },
        { note: { contains: 'sol', mode: 'insensitive' } },
      ],
    })
    await repos.transactions.all(TENANT, {
      categoryId: 'c1',
      uncategorized: true,
    })
    expect(db.transaction.findMany.mock.calls[1]?.[0].where).toMatchObject({
      categoryId: null,
      OR: undefined,
    })
    await repos.transactions.all(TENANT, { provisional: true })
    expect(db.transaction.findMany.mock.calls[2]?.[0].where).toMatchObject({
      provisional: true,
    })
  })

  it('deletes a transaction of the tenant', async () => {
    const { db, repos } = mockClient()
    await repos.transactions.delete(TENANT, 'tx1')
    expect(db.transaction.deleteMany).toHaveBeenCalledWith({
      where: { tenantId: TENANT, id: 'tx1' },
    })
  })

  it('fills the details a stored transaction lacks', async () => {
    const { db, repos } = mockClient()
    const detailed = createTransaction({
      ...transaction,
      merchant: 'Loja',
      counterparty: '11222333000181',
      installment: { number: 2, count: 3, purchaseOn: '2026-08-01' },
    })
    const bare = createTransaction({ ...transaction, externalId: null })
    const filled = createTransaction({ ...detailed, externalId: 'e2' })
    const unseen = createTransaction({ ...detailed, externalId: 'e3' })
    db.transaction.createMany.mockResolvedValueOnce({ count: 0 })
    db.transaction.findMany.mockResolvedValueOnce([
      {
        accountId: 'a1',
        externalId: 'e1',
        merchant: null,
        counterparty: null,
        installmentNumber: null,
      },
      {
        accountId: 'a1',
        externalId: 'e2',
        merchant: 'Loja',
        counterparty: '11222333000181',
        installmentNumber: 2,
      },
    ])
    expect(
      await repos.transactions.saveNew([
        detailed,
        bare,
        transaction,
        filled,
        unseen,
      ]),
    ).toBe(0)
    expect(db.transaction.findMany.mock.calls[0]?.[0].where).toEqual({
      tenantId: { in: [TENANT] },
      externalId: { in: ['e1', 'e2', 'e3'] },
    })
    const calls = db.transaction.updateMany.mock.calls.map(call => call[0])
    expect(calls).toEqual([
      {
        where: {
          tenantId: TENANT,
          accountId: 'a1',
          externalId: 'e1',
          merchant: null,
        },
        data: { merchant: 'Loja' },
      },
      {
        where: {
          tenantId: TENANT,
          accountId: 'a1',
          externalId: 'e1',
          counterparty: null,
        },
        data: { counterparty: '11222333000181' },
      },
      {
        where: {
          tenantId: TENANT,
          accountId: 'a1',
          externalId: 'e1',
          installmentNumber: null,
        },
        data: {
          installmentNumber: 2,
          installmentCount: 3,
          purchaseOn: new Date('2026-08-01T00:00:00.000Z'),
        },
      },
    ])
    db.transaction.findFirst.mockResolvedValueOnce(transactionToRow(detailed))
    expect(await repos.transactions.findById(TENANT, 'tx1')).toEqual(detailed)
    db.transaction.findFirst.mockResolvedValueOnce({
      ...transactionToRow(detailed),
      purchaseOn: null,
    })
    expect(
      (await repos.transactions.findById(TENANT, 'tx1'))?.installment,
    ).toEqual({ number: 2, count: 3, purchaseOn: null })
    db.transaction.findFirst.mockResolvedValueOnce({
      ...transactionToRow(detailed),
      installmentCount: null,
    })
    expect(
      (await repos.transactions.findById(TENANT, 'tx1'))?.installment,
    ).toBeNull()
  })

  it('maps the note and who categorized it', async () => {
    const { db, repos } = mockClient()
    const noted = {
      ...transaction,
      note: 'lunch',
      categoryId: 'c1',
      categorizedBy: 'AI' as const,
      categoryConfidence: 0.8,
    }
    db.transaction.findFirst.mockResolvedValueOnce(transactionToRow(noted))
    expect(await repos.transactions.findById(TENANT, 'tx1')).toEqual(noted)
  })
})

describe('connections and transfers', () => {
  it('stores connections and finds them by item', async () => {
    const { db, repos } = mockClient()
    const connection = {
      id: 'c1',
      tenantId: TENANT,
      entityId: 'pf',
      institutionId: 'b',
      provider: 'pluggy',
      itemId: 'item',
      status: 'UPDATED',
      lastSyncAt: null,
    }
    await repos.connections.save(connection)
    expect(db.connection.upsert.mock.calls[0]?.[0].where).toEqual({
      id: 'c1',
      tenantId: TENANT,
    })
    db.connection.findFirst.mockResolvedValueOnce(connection)
    expect(await repos.connections.findById(TENANT, 'c1')).toBe(connection)
    db.connection.findUnique.mockResolvedValueOnce(null)
    expect(
      await repos.connections.findByItemId(TENANT, 'pluggy', 'item'),
    ).toBeNull()
    expect(db.connection.findUnique.mock.calls[0]?.[0].where).toEqual({
      tenantId_provider_itemId: {
        tenantId: TENANT,
        provider: 'pluggy',
        itemId: 'item',
      },
    })
    db.connection.findMany.mockResolvedValueOnce([connection])
    expect(await repos.connections.list(TENANT)).toEqual([connection])
    await repos.connections.delete(TENANT, 'c1')
    expect(db.connection.deleteMany).toHaveBeenCalledWith({
      where: { tenantId: TENANT, id: 'c1' },
    })
  })

  it('stores transfers as cents and lists a range', async () => {
    const { db, repos } = mockClient()
    const transfer = {
      id: 'tr',
      tenantId: TENANT,
      kind: 'PRO_LABORE' as const,
      amount: Money.of(900),
      at: NOW,
      rail: 'PIX',
      fromAccountId: 'a',
      toAccountId: 'b',
      document: null,
    }
    await repos.transfers.save(transfer)
    const row = db.internalTransfer.upsert.mock.calls[0]?.[0].create
    expect(row).toMatchObject({ amountCents: 900n, currency: 'BRL' })
    db.internalTransfer.findFirst
      .mockResolvedValueOnce(row)
      .mockResolvedValueOnce(null)
    expect(await repos.transfers.findById(TENANT, 'tr')).toEqual(transfer)
    expect(await repos.transfers.findById(TENANT, 'x')).toBeNull()
    db.internalTransfer.findMany.mockResolvedValueOnce([row])
    const range = { from: NOW, to: new Date('2026-11-01T03:00:00Z') }
    expect(await repos.transfers.list(TENANT, range)).toEqual([transfer])
    expect(db.internalTransfer.findMany.mock.calls[0]?.[0].where).toEqual({
      tenantId: TENANT,
      at: { gte: range.from, lt: range.to },
    })
  })
})

describe('invoices', () => {
  it('maps the decimal rate and the issue date', () => {
    expect(invoiceFromRow(invoiceRow)).toEqual(invoice)
    expect(invoiceFromRow({ ...invoiceRow, fxRate: null }).fxRate).toBeNull()
    expect(invoiceToRow(invoice)).toMatchObject({
      amountCents: 1000n,
      currency: 'USD',
      issueOn: new Date('2026-10-08T00:00:00.000Z'),
    })
  })

  it('saves, finds, pages and lists invoices and clients', async () => {
    const { db, repos } = mockClient()
    await repos.invoices.save(invoice)
    expect(db.invoice.upsert.mock.calls[0]?.[0].where).toEqual({
      id: 'i1',
      tenantId: TENANT,
    })
    db.invoice.findFirst
      .mockResolvedValueOnce(invoiceRow)
      .mockResolvedValueOnce(null)
    expect(await repos.invoices.findById(TENANT, 'i1')).toEqual(invoice)
    expect(await repos.invoices.findById(TENANT, 'x')).toBeNull()
    db.invoice.findMany.mockResolvedValueOnce([invoiceRow])
    const page = await repos.invoices.list(
      TENANT,
      { status: 'DRAFT', competenceFrom: '2026-10' },
      { limit: 5 },
    )
    expect(page).toEqual({ items: [invoice], nextCursor: null })
    expect(db.invoice.findMany.mock.calls[0]?.[0].where).toEqual({
      tenantId: TENANT,
      entityId: undefined,
      status: 'DRAFT',
      competence: { gte: '2026-10', lte: undefined },
    })
    db.invoice.findMany.mockResolvedValueOnce([invoiceRow])
    expect(await repos.invoices.all(TENANT, {})).toEqual([invoice])
    const client = {
      id: 'c1',
      tenantId: TENANT,
      entityId: 'pj',
      name: 'Client',
      taxId: null,
      country: 'US',
    }
    db.invoiceClient.findFirst
      .mockResolvedValueOnce({ ...client, email: null })
      .mockResolvedValueOnce(null)
      .mockResolvedValueOnce({ ...client, email: 'a@example.com' })
      .mockResolvedValueOnce(null)
    expect(await repos.invoices.findClient(TENANT, 'c1')).toEqual(client)
    expect(await repos.invoices.findClient(TENANT, 'x')).toBeNull()
    expect(
      await repos.invoices.findClientByName(TENANT, 'pj', 'Client'),
    ).toEqual(client)
    expect(
      await repos.invoices.findClientByName(TENANT, 'pj', 'Other'),
    ).toBeNull()
    await repos.invoices.saveClient(client)
    expect(db.invoiceClient.upsert.mock.calls[0]?.[0].create).toEqual(client)
  })
})

describe('budgets, attachments and documents', () => {
  it('names each budget by its category', async () => {
    const { db, repos } = mockClient()
    db.budget.findMany.mockResolvedValueOnce([
      { categoryId: 'food', limitCents: 10000n },
      { categoryId: 'gone', limitCents: 500n },
    ])
    db.category.findMany.mockResolvedValueOnce([{ id: 'food', name: 'Food' }])
    expect(await repos.budgets.list(TENANT, 'pf', '2026-10')).toEqual([
      { categoryId: 'food', categoryName: 'Food', limit: Money.of(10000) },
      { categoryId: 'gone', categoryName: 'gone', limit: Money.of(500) },
    ])
    expect(db.category.findMany.mock.calls[0]?.[0].where).toEqual({
      tenantId: TENANT,
      id: { in: ['food', 'gone'] },
    })
  })

  it('stores attachment bytes and lists only metadata', async () => {
    const { db, repos } = mockClient()
    const attachment = {
      id: 'f1',
      tenantId: TENANT,
      billId: 'b1',
      fileName: 'a.pdf',
      mimeType: 'application/pdf',
      size: 2,
      createdAt: NOW,
      bytes: new Uint8Array([1, 2]),
    }
    await repos.attachments.save(attachment)
    expect(db.billAttachment.create.mock.calls[0]?.[0].data.bytes).toEqual(
      new Uint8Array([1, 2]),
    )
    db.billAttachment.findMany.mockResolvedValueOnce([])
    expect(await repos.attachments.list(TENANT, 'b1')).toEqual([])
    expect(
      db.billAttachment.findMany.mock.calls[0]?.[0].select,
    ).not.toHaveProperty('bytes')
    db.billAttachment.findFirst
      .mockResolvedValueOnce(attachment)
      .mockResolvedValueOnce(null)
    expect(await repos.attachments.find(TENANT, 'f1')).toEqual(attachment)
    expect(await repos.attachments.find(TENANT, 'x')).toBeNull()
  })

  it('reads and writes documents by collection', async () => {
    const { db, repos } = mockClient()
    const where = {
      tenantId_collection_id: {
        tenantId: TENANT,
        collection: 'issuer',
        id: 'pj',
      },
    }
    db.document.findUnique
      .mockResolvedValueOnce({ data: { city: 'X' } })
      .mockResolvedValueOnce(null)
    expect(await repos.documents.get(TENANT, 'issuer', 'pj')).toEqual({
      city: 'X',
    })
    expect(await repos.documents.get(TENANT, 'issuer', 'pf')).toBeNull()
    expect(db.document.findUnique.mock.calls[0]?.[0].where).toEqual(where)
    await repos.documents.put(TENANT, 'issuer', 'pj', { city: 'Y' })
    expect(db.document.upsert.mock.calls[0]?.[0]).toEqual({
      where,
      create: {
        tenantId: TENANT,
        collection: 'issuer',
        id: 'pj',
        data: { city: 'Y' },
      },
      update: { data: { city: 'Y' } },
    })
    db.document.findMany.mockResolvedValueOnce([{ data: 1 }, { data: 2 }])
    expect(await repos.documents.list(TENANT, 'issuer')).toEqual([1, 2])
    await repos.documents.delete(TENANT, 'issuer', 'pj')
    expect(db.document.deleteMany).toHaveBeenCalledWith({
      where: { tenantId: TENANT, collection: 'issuer', id: 'pj' },
    })
  })
})

describe('invoice documents and templates', () => {
  it('finds by external id and stores the documents', async () => {
    const { db, repos } = mockClient()
    db.invoice.findFirst
      .mockResolvedValueOnce(invoiceRow)
      .mockResolvedValueOnce(null)
    expect(await repos.invoices.findByExternalId(TENANT, 'ext')).toEqual(
      invoice,
    )
    expect(db.invoice.findFirst.mock.calls[0]?.[0].where).toEqual({
      tenantId: TENANT,
      externalId: 'ext',
    })
    expect(await repos.invoices.findByExternalId(TENANT, 'x')).toBeNull()
    const file = {
      tenantId: TENANT,
      invoiceId: 'i1',
      kind: 'PDF' as const,
      fileName: 'nfse-1.pdf',
      mimeType: 'application/pdf',
      size: 3,
      bytes: new Uint8Array([1, 2, 3]),
      createdAt: NOW,
    }
    await repos.invoices.saveFile(file)
    expect(db.invoiceFile.upsert.mock.calls[0]?.[0].where).toEqual({
      tenantId_invoiceId_kind: {
        tenantId: TENANT,
        invoiceId: 'i1',
        kind: 'PDF',
      },
    })
    db.invoiceFile.findUnique
      .mockResolvedValueOnce({ ...file, bytes: Buffer.from([1, 2, 3]) })
      .mockResolvedValueOnce(null)
    expect(await repos.invoices.findFile(TENANT, 'i1', 'PDF')).toEqual(file)
    expect(await repos.invoices.findFile(TENANT, 'i1', 'XML')).toBeNull()
  })

  it('saves, finds, lists and deletes templates', async () => {
    const { db, repos } = mockClient()
    const template = {
      id: 't1',
      tenantId: TENANT,
      entityId: 'pj',
      clientId: 'c1',
      serviceCode: '01.01',
      description: 'Development',
      amount: Money.of(15000, 'USD'),
      billing: 'HOURLY' as const,
      hours: 120.5,
      dayOfMonth: 5,
      active: true,
    }
    await repos.invoices.saveTemplate(template)
    expect(db.invoiceTemplate.upsert.mock.calls[0]?.[0].create).toMatchObject({
      amountCents: 15000n,
      currency: 'USD',
      hours: 120.5,
    })
    const row = {
      ...templateToRow(template),
      hours: { toString: () => '120.5' },
    }
    db.invoiceTemplate.findFirst
      .mockResolvedValueOnce(row)
      .mockResolvedValueOnce(null)
    expect(await repos.invoices.findTemplate(TENANT, 't1')).toEqual(template)
    expect(await repos.invoices.findTemplate(TENANT, 'x')).toBeNull()
    db.invoiceTemplate.findMany.mockResolvedValueOnce([
      { ...row, hours: null, billing: 'FIXED' },
    ])
    expect(await repos.invoices.listTemplates(TENANT, 'pj')).toEqual([
      { ...template, hours: null, billing: 'FIXED' },
    ])
    await repos.invoices.deleteTemplate(TENANT, 't1')
    expect(db.invoiceTemplate.deleteMany.mock.calls[0]?.[0].where).toEqual({
      tenantId: TENANT,
      id: 't1',
    })
  })
})

describe('webhook events', () => {
  it('remembers an event id once', async () => {
    const { db, repos } = mockClient()
    db.webhookEvent.createMany
      .mockResolvedValueOnce({ count: 1 })
      .mockResolvedValueOnce({ count: 0 })
    const event = { eventId: 'e1', type: 'item/updated', subjectId: 'item-1' }
    expect(
      await repos.webhookEvents.remember(TENANT, 'pluggy', event, NOW),
    ).toBe(true)
    expect(
      await repos.webhookEvents.remember(TENANT, 'pluggy', event, NOW),
    ).toBe(false)
    expect(db.webhookEvent.createMany.mock.calls[0]?.[0]).toEqual({
      data: [
        {
          tenantId: TENANT,
          provider: 'pluggy',
          eventId: 'e1',
          type: 'item/updated',
          subjectId: 'item-1',
          receivedAt: NOW,
        },
      ],
      skipDuplicates: true,
    })
  })

  it('settles an event with its outcome', async () => {
    const { db, repos } = mockClient()
    db.webhookEvent.updateMany.mockResolvedValue({ count: 1 })
    const settlement = {
      outcome: 'FAILED' as const,
      reason: 'Error: down',
      processedAt: NOW,
    }
    await repos.webhookEvents.settle(TENANT, 'pluggy', 'e1', settlement)
    expect(db.webhookEvent.updateMany.mock.calls[0]?.[0]).toEqual({
      where: { tenantId: TENANT, provider: 'pluggy', eventId: 'e1' },
      data: settlement,
    })
  })
})

describe('card bills', () => {
  it('upserts by due date and lists newest first', async () => {
    const { db, repos } = mockClient()
    const bill = {
      id: 'b1',
      tenantId: TENANT,
      accountId: 'card',
      externalId: 'x1',
      closesOn: '2026-09-20',
      dueOn: '2026-09-27',
      total: Money.of(42_050),
      minimum: Money.of(5_000),
    }
    await repos.cardBills.saveAll([
      bill,
      { ...bill, id: 'b2', closesOn: null, minimum: null },
    ])
    const [first, second] = db.creditCardBill.upsert.mock.calls.map(
      call => call[0],
    )
    expect(first).toMatchObject({
      where: {
        tenantId_accountId_dueDate: {
          tenantId: TENANT,
          accountId: 'card',
          dueDate: new Date('2026-09-27T00:00:00.000Z'),
        },
      },
      create: { id: 'b1', totalCents: 42_050n, minimumCents: 5_000n },
      update: { closingDate: new Date('2026-09-20T00:00:00.000Z') },
    })
    expect(second.update).toMatchObject({
      closingDate: null,
      minimumCents: null,
    })
    db.creditCardBill.findMany.mockResolvedValueOnce([
      {
        id: 'b1',
        tenantId: TENANT,
        accountId: 'card',
        externalId: 'x1',
        closingDate: new Date('2026-09-20T00:00:00.000Z'),
        dueDate: new Date('2026-09-27T00:00:00.000Z'),
        totalCents: 42_050n,
        minimumCents: 5_000n,
        currency: 'BRL',
      },
      {
        id: 'b2',
        tenantId: TENANT,
        accountId: 'card',
        externalId: null,
        closingDate: null,
        dueDate: new Date('2026-08-27T00:00:00.000Z'),
        totalCents: 100n,
        minimumCents: null,
        currency: 'BRL',
      },
    ])
    expect(await repos.cardBills.list(TENANT, ['card'])).toEqual([
      bill,
      {
        ...bill,
        id: 'b2',
        externalId: null,
        closesOn: null,
        dueOn: '2026-08-27',
        total: Money.of(100),
        minimum: null,
      },
    ])
    expect(db.creditCardBill.findMany.mock.calls[0]?.[0]).toEqual({
      where: { tenantId: TENANT, accountId: { in: ['card'] } },
      orderBy: { dueDate: 'desc' },
    })
  })
})

describe('recurrences', () => {
  it('keeps one per entity and key with its decision', async () => {
    const { db, repos } = mockClient()
    const row = {
      id: 'r1',
      tenantId: TENANT,
      entityId: 'pf',
      key: 'musica exemplo',
      description: 'MUSICA EXEMPLO',
      amountCents: 2_390n,
      dayOfMonth: 12,
      confirmed: true,
      dismissed: false,
      lastSeenOn: new Date('2026-09-12T00:00:00.000Z'),
    }
    const recurrence = {
      id: 'r1',
      tenantId: TENANT,
      entityId: 'pf',
      key: 'musica exemplo',
      name: 'MUSICA EXEMPLO',
      amount: Money.of(2_390),
      dayOfMonth: 12,
      status: 'CONFIRMED' as const,
      lastSeenOn: '2026-09-12',
    }
    db.recurrence.upsert.mockResolvedValueOnce(row)
    expect(await repos.recurrences.save({ ...recurrence, id: 'new' })).toEqual(
      recurrence,
    )
    expect(db.recurrence.upsert.mock.calls[0]?.[0]).toMatchObject({
      where: {
        tenantId_entityId_key: {
          tenantId: TENANT,
          entityId: 'pf',
          key: 'musica exemplo',
        },
      },
      create: { id: 'new', confirmed: true, dismissed: false },
      update: { amountCents: 2_390n },
    })
    db.recurrence.upsert.mockResolvedValueOnce({
      ...row,
      confirmed: false,
      dismissed: true,
      lastSeenOn: null,
    })
    expect(
      await repos.recurrences.save({
        ...recurrence,
        status: 'DISMISSED',
        lastSeenOn: null,
      }),
    ).toMatchObject({ status: 'DISMISSED', lastSeenOn: null })
    expect(db.recurrence.upsert.mock.calls[1]?.[0].update).toMatchObject({
      dismissed: true,
      lastSeenOn: null,
    })
    db.recurrence.findMany.mockResolvedValueOnce([row])
    expect(await repos.recurrences.list(TENANT)).toEqual([recurrence])
    db.recurrence.findFirst
      .mockResolvedValueOnce(row)
      .mockResolvedValueOnce(null)
    expect(await repos.recurrences.findById(TENANT, 'r1')).toEqual(recurrence)
    expect(await repos.recurrences.findById(TENANT, 'x')).toBeNull()
  })
})
