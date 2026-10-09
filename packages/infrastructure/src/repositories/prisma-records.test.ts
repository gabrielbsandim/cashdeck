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
] as const
const METHODS = [
  'upsert',
  'findFirst',
  'findUnique',
  'findMany',
  'create',
  'createMany',
  'deleteMany',
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
    }
    db.institution.findFirst
      .mockResolvedValueOnce(row)
      .mockResolvedValueOnce(null)
    expect(await repos.institutions.findById(TENANT, 'b')).toEqual({
      id: 'b',
      tenantId: TENANT,
      name: 'Bank',
      manual: false,
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
    expect(await repos.webhookEvents.remember(TENANT, 'asaas', 'e1', NOW)).toBe(
      true,
    )
    expect(await repos.webhookEvents.remember(TENANT, 'asaas', 'e1', NOW)).toBe(
      false,
    )
    expect(db.webhookEvent.createMany.mock.calls[0]?.[0]).toEqual({
      data: [
        { tenantId: TENANT, provider: 'asaas', eventId: 'e1', receivedAt: NOW },
      ],
      skipDuplicates: true,
    })
  })
})
