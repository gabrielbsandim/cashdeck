import { type Prisma, type PrismaClient } from '@prisma/client'
import {
  type Attachment,
  type AttachmentMeta,
  type AttachmentRepository,
  type BudgetLimit,
  type BudgetRepository,
  type CardBill,
  type CardBillRepository,
  type Connection,
  type ConnectionRepository,
  type DocumentStore,
  type Institution,
  type InstitutionRepository,
  type InternalTransfer,
  type Invoice,
  type InvoiceClient,
  type InvoiceFile,
  type InvoiceFileKind,
  type InvoiceFilter,
  type InvoiceRepository,
  type InvoiceStatus,
  type InvoiceTemplate,
  type Recurrence,
  type RecurrenceRepository,
  type TemplateBilling,
  type WebhookEventStore,
  type WebhookReceived,
  type WebhookSettlement,
  type WebhookProvider,
  type Page,
  type PageRequest,
  type TransactionFilter,
  type TransactionRepository,
  type TransferKind,
  type TransferRepository,
} from '@cashdeck/application'
import { Money, type Transaction } from '@cashdeck/domain'
import {
  PrismaCategoryRepository,
  PrismaChatRepository,
} from '@/repositories/prisma-insights'
import {
  PrismaIndexRateRepository,
  PrismaInvestmentRepository,
} from '@/repositories/prisma-investments'
import {
  fromDbDate,
  toDbDate,
  transactionFromRow,
  type TransactionRow,
  transactionToRow,
} from '@/repositories/mappers'

const json = (value: unknown) => value as Prisma.InputJsonValue

async function paged<T, R>(
  page: PageRequest,
  load: (skip: number, take: number) => Promise<R[]>,
  map: (row: R) => T,
): Promise<Page<T>> {
  const skip = Number(page.cursor ?? 0)
  const rows = await load(skip, page.limit + 1)
  const items = rows.slice(0, page.limit).map(map)
  const hasMore = rows.length > page.limit
  return { items, nextCursor: hasMore ? String(skip + items.length) : null }
}

type InstitutionRow = {
  id: string
  tenantId: string
  name: string
  manual: boolean
  connectorId: number | null
  imageUrl: string | null
  primaryColor: string | null
}

const institutionFromRow = (row: InstitutionRow): Institution => ({
  id: row.id,
  tenantId: row.tenantId,
  name: row.name,
  manual: row.manual,
  connectorId: row.connectorId,
  imageUrl: row.imageUrl,
  primaryColor: row.primaryColor,
})

export class PrismaInstitutionRepository implements InstitutionRepository {
  constructor(private readonly db: PrismaClient) {}

  async findById(tenantId: string, id: string): Promise<Institution | null> {
    const row = await this.db.institution.findFirst({ where: { tenantId, id } })
    return row && institutionFromRow(row)
  }

  async ensure(candidate: Institution): Promise<Institution> {
    const branding = {
      connectorId: candidate.connectorId ?? null,
      imageUrl: candidate.imageUrl ?? null,
      primaryColor: candidate.primaryColor ?? null,
    }
    const row = await this.db.institution.upsert({
      where: {
        tenantId_name: { tenantId: candidate.tenantId, name: candidate.name },
      },
      create: {
        id: candidate.id,
        tenantId: candidate.tenantId,
        name: candidate.name,
        manual: candidate.manual,
        ...branding,
      },
      update: branding.imageUrl ? branding : {},
    })
    return institutionFromRow(row)
  }
}

function categoryWhere(filter: TransactionFilter) {
  return filter.uncategorized ? null : filter.categoryId
}

function searchWhere(search: string | undefined) {
  if (!search) {
    return undefined
  }
  const contains = { contains: search, mode: 'insensitive' as const }
  return [{ description: contains }, { note: contains }]
}

function transactionWhere(tenantId: string, filter: TransactionFilter) {
  return {
    tenantId,
    accountId: filter.accountIds ? { in: [...filter.accountIds] } : undefined,
    bookedOn: {
      gte: filter.from ? toDbDate(filter.from) : undefined,
      lte: filter.to ? toDbDate(filter.to) : undefined,
    },
    categoryId: categoryWhere(filter),
    OR: searchWhere(filter.search),
  }
}

const NEWEST_FIRST = [{ bookedOn: 'desc' as const }, { id: 'asc' as const }]

export class PrismaTransactionRepository implements TransactionRepository {
  constructor(private readonly db: PrismaClient) {}

  async save(transaction: Transaction): Promise<void> {
    const row = transactionToRow(transaction)
    await this.db.transaction.upsert({
      where: { id: row.id, tenantId: row.tenantId },
      create: row,
      update: row,
    })
  }

  async saveNew(transactions: readonly Transaction[]): Promise<number> {
    const result = await this.db.transaction.createMany({
      data: transactions.map(transactionToRow),
      skipDuplicates: true,
    })
    if (result.count === transactions.length) {
      return result.count
    }
    await this.fillDetails(transactions)
    return result.count
  }

  // A row stored before the provider sent these details takes them now,
  // without touching what the user edited. One read finds the rows lacking any.
  private async fillDetails(transactions: readonly Transaction[]) {
    const rows = transactions
      .map(transactionToRow)
      .filter(row => row.externalId)
      .filter(row => row.merchant || row.installmentNumber !== null)
    if (rows.length === 0) {
      return
    }
    const stored = await this.db.transaction.findMany({
      where: {
        tenantId: { in: [...new Set(rows.map(row => row.tenantId))] },
        externalId: { in: rows.map(row => row.externalId as string) },
      },
      select: {
        accountId: true,
        externalId: true,
        merchant: true,
        installmentNumber: true,
      },
    })
    const keyOf = (row: { accountId: string; externalId: string | null }) =>
      `${row.accountId}|${row.externalId}`
    const lacking = new Map(stored.map(row => [keyOf(row), row]))
    for (const row of rows) {
      const current = lacking.get(keyOf(row))
      const needs =
        current !== undefined &&
        ((row.merchant !== null && current.merchant === null) ||
          (row.installmentNumber !== null &&
            current.installmentNumber === null))
      if (needs) {
        await this.fillRow(row)
      }
    }
  }

  private async fillRow(row: TransactionRow) {
    const where = {
      tenantId: row.tenantId,
      accountId: row.accountId,
      externalId: row.externalId,
    }
    if (row.merchant) {
      await this.db.transaction.updateMany({
        where: { ...where, merchant: null },
        data: { merchant: row.merchant },
      })
    }
    if (row.installmentNumber !== null) {
      await this.db.transaction.updateMany({
        where: { ...where, installmentNumber: null },
        data: {
          installmentNumber: row.installmentNumber,
          installmentCount: row.installmentCount,
          purchaseOn: row.purchaseOn,
        },
      })
    }
  }

  async findById(tenantId: string, id: string): Promise<Transaction | null> {
    const row = await this.db.transaction.findFirst({ where: { tenantId, id } })
    return row ? transactionFromRow(row) : null
  }

  async list(
    tenantId: string,
    filter: TransactionFilter,
    page: PageRequest,
  ): Promise<Page<Transaction>> {
    return paged(
      page,
      (skip, take) =>
        this.db.transaction.findMany({
          where: transactionWhere(tenantId, filter),
          orderBy: NEWEST_FIRST,
          skip,
          take,
        }),
      transactionFromRow,
    )
  }

  async all(
    tenantId: string,
    filter: TransactionFilter,
  ): Promise<Transaction[]> {
    const rows = await this.db.transaction.findMany({
      where: transactionWhere(tenantId, filter),
      orderBy: NEWEST_FIRST,
    })
    return rows.map(transactionFromRow)
  }
}

export class PrismaConnectionRepository implements ConnectionRepository {
  constructor(private readonly db: PrismaClient) {}

  async save(connection: Connection): Promise<void> {
    await this.db.connection.upsert({
      where: { id: connection.id, tenantId: connection.tenantId },
      create: connection,
      update: connection,
    })
  }

  async findById(tenantId: string, id: string): Promise<Connection | null> {
    return this.db.connection.findFirst({ where: { tenantId, id } })
  }

  async findByItemId(
    tenantId: string,
    provider: string,
    itemId: string,
  ): Promise<Connection | null> {
    return this.db.connection.findUnique({
      where: { tenantId_provider_itemId: { tenantId, provider, itemId } },
    })
  }

  async list(tenantId: string): Promise<Connection[]> {
    return this.db.connection.findMany({
      where: { tenantId },
      orderBy: { id: 'asc' },
    })
  }

  async delete(tenantId: string, id: string): Promise<void> {
    await this.db.connection.deleteMany({ where: { tenantId, id } })
  }
}

type TransferRow = Omit<InternalTransfer, 'amount' | 'kind'> & {
  kind: string
  amountCents: bigint
  currency: string
}

const transferFromRow = (row: TransferRow): InternalTransfer => ({
  id: row.id,
  tenantId: row.tenantId,
  kind: row.kind as TransferKind,
  amount: Money.of(Number(row.amountCents), row.currency),
  at: row.at,
  rail: row.rail,
  fromAccountId: row.fromAccountId,
  toAccountId: row.toAccountId,
  document: row.document,
})

export class PrismaTransferRepository implements TransferRepository {
  constructor(private readonly db: PrismaClient) {}

  async save(transfer: InternalTransfer): Promise<void> {
    const { amount, ...rest } = transfer
    const row = {
      ...rest,
      amountCents: BigInt(amount.cents),
      currency: amount.currency,
    }
    await this.db.internalTransfer.upsert({
      where: { id: row.id, tenantId: row.tenantId },
      create: row,
      update: row,
    })
  }

  async findById(
    tenantId: string,
    id: string,
  ): Promise<InternalTransfer | null> {
    const row = await this.db.internalTransfer.findFirst({
      where: { tenantId, id },
    })
    return row ? transferFromRow(row) : null
  }

  async list(
    tenantId: string,
    range: { from: Date; to: Date },
  ): Promise<InternalTransfer[]> {
    const rows = await this.db.internalTransfer.findMany({
      where: { tenantId, at: { gte: range.from, lt: range.to } },
      orderBy: { at: 'desc' },
    })
    return rows.map(transferFromRow)
  }
}

type InvoiceRow = Omit<Invoice, 'amount' | 'fxRate' | 'issueOn' | 'status'> & {
  status: InvoiceStatus
  amountCents: bigint
  currency: string
  fxRate: { toString(): string } | null
  issueOn: Date
}

export function invoiceFromRow(row: InvoiceRow): Invoice {
  return {
    id: row.id,
    tenantId: row.tenantId,
    entityId: row.entityId,
    clientId: row.clientId,
    templateId: row.templateId,
    issuer: row.issuer,
    externalId: row.externalId,
    number: row.number,
    status: row.status,
    amount: Money.of(Number(row.amountCents), row.currency),
    fxRate: row.fxRate === null ? null : Number(row.fxRate.toString()),
    isExport: row.isExport,
    competence: row.competence,
    issueOn: fromDbDate(row.issueOn),
    description: row.description,
    serviceCode: row.serviceCode,
    pdfUrl: row.pdfUrl,
    xmlUrl: row.xmlUrl,
    cancelReason: row.cancelReason ?? null,
    createdAt: row.createdAt,
  }
}

export function invoiceToRow(invoice: Invoice) {
  const { amount, issueOn, ...rest } = invoice
  return {
    ...rest,
    amountCents: BigInt(amount.cents),
    currency: amount.currency,
    issueOn: toDbDate(issueOn),
  }
}

function invoiceWhere(tenantId: string, filter: InvoiceFilter) {
  return {
    tenantId,
    entityId: filter.entityId,
    status: filter.status,
    competence: { gte: filter.competenceFrom, lte: filter.competenceTo },
  }
}

const NEWEST_INVOICE = [{ issueOn: 'desc' as const }, { id: 'asc' as const }]

type ClientRow = Omit<InvoiceClient, 'country'> & {
  country: string
  email: string | null
}

const clientFromRow = (row: ClientRow): InvoiceClient => ({
  id: row.id,
  tenantId: row.tenantId,
  entityId: row.entityId,
  name: row.name,
  taxId: row.taxId,
  country: row.country,
})

type TemplateRow = Omit<InvoiceTemplate, 'amount' | 'billing' | 'hours'> & {
  amountCents: bigint
  currency: string
  billing: string
  hours: { toString(): string } | null
}

export function templateFromRow(row: TemplateRow): InvoiceTemplate {
  return {
    id: row.id,
    tenantId: row.tenantId,
    entityId: row.entityId,
    clientId: row.clientId,
    serviceCode: row.serviceCode,
    description: row.description,
    amount: Money.of(Number(row.amountCents), row.currency),
    billing: row.billing as TemplateBilling,
    hours: row.hours === null ? null : Number(row.hours.toString()),
    dayOfMonth: row.dayOfMonth,
    active: row.active,
  }
}

export function templateToRow(template: InvoiceTemplate) {
  const { amount, ...rest } = template
  return {
    ...rest,
    amountCents: BigInt(amount.cents),
    currency: amount.currency,
  }
}

export class PrismaInvoiceRepository implements InvoiceRepository {
  constructor(private readonly db: PrismaClient) {}

  async save(invoice: Invoice): Promise<void> {
    const row = invoiceToRow(invoice)
    await this.db.invoice.upsert({
      where: { id: row.id, tenantId: row.tenantId },
      create: row,
      update: row,
    })
  }

  async findById(tenantId: string, id: string): Promise<Invoice | null> {
    const row = await this.db.invoice.findFirst({ where: { tenantId, id } })
    return row ? invoiceFromRow(row) : null
  }

  async list(
    tenantId: string,
    filter: InvoiceFilter,
    page: PageRequest,
  ): Promise<Page<Invoice>> {
    return paged(
      page,
      (skip, take) =>
        this.db.invoice.findMany({
          where: invoiceWhere(tenantId, filter),
          orderBy: NEWEST_INVOICE,
          skip,
          take,
        }),
      invoiceFromRow,
    )
  }

  async all(tenantId: string, filter: InvoiceFilter): Promise<Invoice[]> {
    const rows = await this.db.invoice.findMany({
      where: invoiceWhere(tenantId, filter),
      orderBy: NEWEST_INVOICE,
    })
    return rows.map(invoiceFromRow)
  }

  async findClient(
    tenantId: string,
    id: string,
  ): Promise<InvoiceClient | null> {
    const row = await this.db.invoiceClient.findFirst({
      where: { tenantId, id },
    })
    return row ? clientFromRow(row) : null
  }

  async findClientByName(
    tenantId: string,
    entityId: string,
    name: string,
  ): Promise<InvoiceClient | null> {
    const row = await this.db.invoiceClient.findFirst({
      where: { tenantId, entityId, name },
      orderBy: { id: 'asc' },
    })
    return row ? clientFromRow(row) : null
  }

  async saveClient(client: InvoiceClient): Promise<void> {
    await this.db.invoiceClient.upsert({
      where: { id: client.id, tenantId: client.tenantId },
      create: client,
      update: client,
    })
  }

  async findByExternalId(
    tenantId: string,
    externalId: string,
  ): Promise<Invoice | null> {
    const row = await this.db.invoice.findFirst({
      where: { tenantId, externalId },
      orderBy: { createdAt: 'desc' },
    })
    return row ? invoiceFromRow(row) : null
  }

  async saveFile(file: InvoiceFile): Promise<void> {
    const data = { ...file, bytes: Uint8Array.from(file.bytes) }
    await this.db.invoiceFile.upsert({
      where: {
        tenantId_invoiceId_kind: {
          tenantId: file.tenantId,
          invoiceId: file.invoiceId,
          kind: file.kind,
        },
      },
      create: data,
      update: data,
    })
  }

  async findFile(
    tenantId: string,
    invoiceId: string,
    kind: InvoiceFileKind,
  ): Promise<InvoiceFile | null> {
    const row = await this.db.invoiceFile.findUnique({
      where: { tenantId_invoiceId_kind: { tenantId, invoiceId, kind } },
    })
    return (
      row && {
        ...row,
        kind: row.kind as InvoiceFileKind,
        bytes: new Uint8Array(row.bytes),
      }
    )
  }

  async saveTemplate(template: InvoiceTemplate): Promise<void> {
    const row = templateToRow(template)
    await this.db.invoiceTemplate.upsert({
      where: { id: row.id, tenantId: row.tenantId },
      create: row,
      update: row,
    })
  }

  async findTemplate(
    tenantId: string,
    id: string,
  ): Promise<InvoiceTemplate | null> {
    const row = await this.db.invoiceTemplate.findFirst({
      where: { tenantId, id },
    })
    return row ? templateFromRow(row) : null
  }

  async listTemplates(
    tenantId: string,
    entityId: string,
  ): Promise<InvoiceTemplate[]> {
    const rows = await this.db.invoiceTemplate.findMany({
      where: { tenantId, entityId },
      orderBy: [{ dayOfMonth: 'asc' }, { id: 'asc' }],
    })
    return rows.map(templateFromRow)
  }

  async deleteTemplate(tenantId: string, id: string): Promise<void> {
    await this.db.invoiceTemplate.deleteMany({ where: { tenantId, id } })
  }
}

export class PrismaWebhookEventStore implements WebhookEventStore {
  constructor(private readonly db: PrismaClient) {}

  // skipDuplicates turns a replay into a zero count instead of a P2002 error.
  async remember(
    tenantId: string,
    provider: WebhookProvider,
    event: WebhookReceived,
    receivedAt: Date,
  ): Promise<boolean> {
    const result = await this.db.webhookEvent.createMany({
      data: [{ tenantId, provider, ...event, receivedAt }],
      skipDuplicates: true,
    })
    return result.count === 1
  }

  async settle(
    tenantId: string,
    provider: WebhookProvider,
    eventId: string,
    settlement: WebhookSettlement,
  ): Promise<void> {
    await this.db.webhookEvent.updateMany({
      where: { tenantId, provider, eventId },
      data: settlement,
    })
  }
}

export class PrismaBudgetRepository implements BudgetRepository {
  constructor(private readonly db: PrismaClient) {}

  async list(
    tenantId: string,
    entityId: string,
    month: string,
  ): Promise<BudgetLimit[]> {
    const budgets = await this.db.budget.findMany({
      where: { tenantId, entityId, month },
      orderBy: { categoryId: 'asc' },
    })
    const categories = await this.db.category.findMany({
      where: { tenantId, id: { in: budgets.map(budget => budget.categoryId) } },
    })
    const names = new Map(
      categories.map(category => [category.id, category.name]),
    )
    return budgets.map(budget => ({
      categoryId: budget.categoryId,
      categoryName: names.get(budget.categoryId) ?? budget.categoryId,
      limit: Money.of(Number(budget.limitCents)),
    }))
  }
}

const ATTACHMENT_META = {
  id: true,
  tenantId: true,
  billId: true,
  fileName: true,
  mimeType: true,
  size: true,
  createdAt: true,
} as const

export class PrismaAttachmentRepository implements AttachmentRepository {
  constructor(private readonly db: PrismaClient) {}

  async save(attachment: Attachment): Promise<void> {
    await this.db.billAttachment.create({
      data: { ...attachment, bytes: Uint8Array.from(attachment.bytes) },
    })
  }

  async list(tenantId: string, billId: string): Promise<AttachmentMeta[]> {
    return this.db.billAttachment.findMany({
      where: { tenantId, billId },
      select: ATTACHMENT_META,
      orderBy: { createdAt: 'asc' },
    })
  }

  async find(tenantId: string, id: string): Promise<Attachment | null> {
    const row = await this.db.billAttachment.findFirst({
      where: { tenantId, id },
    })
    return row && { ...row, bytes: new Uint8Array(row.bytes) }
  }
}

export class PrismaDocumentStore implements DocumentStore {
  constructor(private readonly db: PrismaClient) {}

  async get<T>(
    tenantId: string,
    collection: string,
    id: string,
  ): Promise<T | null> {
    const row = await this.db.document.findUnique({
      where: { tenantId_collection_id: { tenantId, collection, id } },
    })
    return row ? (row.data as T) : null
  }

  async put<T>(
    tenantId: string,
    collection: string,
    id: string,
    data: T,
  ): Promise<void> {
    await this.db.document.upsert({
      where: { tenantId_collection_id: { tenantId, collection, id } },
      create: { tenantId, collection, id, data: json(data) },
      update: { data: json(data) },
    })
  }

  async list<T>(tenantId: string, collection: string): Promise<T[]> {
    const rows = await this.db.document.findMany({
      where: { tenantId, collection },
      orderBy: { id: 'asc' },
    })
    return rows.map(row => row.data as T)
  }

  async delete(
    tenantId: string,
    collection: string,
    id: string,
  ): Promise<void> {
    await this.db.document.deleteMany({ where: { tenantId, collection, id } })
  }
}

export class PrismaCardBillRepository implements CardBillRepository {
  constructor(private readonly db: PrismaClient) {}

  async saveAll(bills: readonly CardBill[]): Promise<void> {
    for (const bill of bills) {
      const row = {
        externalId: bill.externalId,
        closingDate: bill.closesOn ? toDbDate(bill.closesOn) : null,
        totalCents: BigInt(bill.total.cents),
        minimumCents: bill.minimum ? BigInt(bill.minimum.cents) : null,
        currency: bill.total.currency,
      }
      await this.db.creditCardBill.upsert({
        where: {
          tenantId_accountId_dueDate: {
            tenantId: bill.tenantId,
            accountId: bill.accountId,
            dueDate: toDbDate(bill.dueOn),
          },
        },
        create: {
          id: bill.id,
          tenantId: bill.tenantId,
          accountId: bill.accountId,
          dueDate: toDbDate(bill.dueOn),
          ...row,
        },
        update: row,
      })
    }
  }

  async list(
    tenantId: string,
    accountIds: readonly string[],
  ): Promise<CardBill[]> {
    const rows = await this.db.creditCardBill.findMany({
      where: { tenantId, accountId: { in: [...accountIds] } },
      orderBy: { dueDate: 'desc' },
    })
    return rows.map(row => ({
      id: row.id,
      tenantId: row.tenantId,
      accountId: row.accountId,
      externalId: row.externalId,
      closesOn: row.closingDate ? fromDbDate(row.closingDate) : null,
      dueOn: fromDbDate(row.dueDate),
      total: Money.of(Number(row.totalCents), row.currency),
      minimum:
        row.minimumCents === null
          ? null
          : Money.of(Number(row.minimumCents), row.currency),
    }))
  }
}

type RecurrenceRow = {
  id: string
  tenantId: string
  entityId: string
  key: string
  description: string
  amountCents: bigint
  dayOfMonth: number
  confirmed: boolean
  dismissed: boolean
  lastSeenOn: Date | null
}

const recurrenceFromRow = (row: RecurrenceRow): Recurrence => ({
  id: row.id,
  tenantId: row.tenantId,
  entityId: row.entityId,
  key: row.key,
  name: row.description,
  amount: Money.of(Number(row.amountCents)),
  dayOfMonth: row.dayOfMonth,
  status: row.dismissed ? 'DISMISSED' : 'CONFIRMED',
  lastSeenOn: row.lastSeenOn ? fromDbDate(row.lastSeenOn) : null,
})

export class PrismaRecurrenceRepository implements RecurrenceRepository {
  constructor(private readonly db: PrismaClient) {}

  async list(tenantId: string): Promise<Recurrence[]> {
    const rows = await this.db.recurrence.findMany({ where: { tenantId } })
    return rows.map(recurrenceFromRow)
  }

  async findById(tenantId: string, id: string): Promise<Recurrence | null> {
    const row = await this.db.recurrence.findFirst({ where: { tenantId, id } })
    return row && recurrenceFromRow(row)
  }

  async save(recurrence: Recurrence): Promise<Recurrence> {
    const fields = {
      description: recurrence.name,
      amountCents: BigInt(recurrence.amount.cents),
      dayOfMonth: recurrence.dayOfMonth,
      confirmed: recurrence.status === 'CONFIRMED',
      dismissed: recurrence.status === 'DISMISSED',
      lastSeenOn: recurrence.lastSeenOn
        ? toDbDate(recurrence.lastSeenOn)
        : null,
    }
    const row = await this.db.recurrence.upsert({
      where: {
        tenantId_entityId_key: {
          tenantId: recurrence.tenantId,
          entityId: recurrence.entityId,
          key: recurrence.key,
        },
      },
      create: {
        id: recurrence.id,
        tenantId: recurrence.tenantId,
        entityId: recurrence.entityId,
        key: recurrence.key,
        ...fields,
      },
      update: fields,
    })
    return recurrenceFromRow(row)
  }
}

export function createPrismaRecords(db: PrismaClient) {
  return {
    institutions: new PrismaInstitutionRepository(db),
    transactions: new PrismaTransactionRepository(db),
    cardBills: new PrismaCardBillRepository(db),
    investments: new PrismaInvestmentRepository(db),
    indexRates: new PrismaIndexRateRepository(db),
    recurrences: new PrismaRecurrenceRepository(db),
    connections: new PrismaConnectionRepository(db),
    transfers: new PrismaTransferRepository(db),
    invoices: new PrismaInvoiceRepository(db),
    budgets: new PrismaBudgetRepository(db),
    attachments: new PrismaAttachmentRepository(db),
    documents: new PrismaDocumentStore(db),
    webhookEvents: new PrismaWebhookEventStore(db),
    categories: new PrismaCategoryRepository(db),
    chat: new PrismaChatRepository(db),
  }
}
