import {
  type Category,
  type CategoryRule,
  type Transaction,
} from '@cashdeck/domain'
import { type Page, type PageRequest } from '@/ports/repositories'
import {
  type Attachment,
  type AttachmentMeta,
  type AttachmentRepository,
  type BudgetLimit,
  type BudgetRepository,
  type CardBill,
  type CardBillRepository,
  type CategoryRepository,
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
  type InvoiceTemplate,
  type TransactionFilter,
  type TransactionRepository,
  type TransferRepository,
} from '@/ports/records'

const key = (tenantId: string, id: string) => `${tenantId}:${id}`

function paginate<T>(rows: T[], page: PageRequest): Page<T> {
  const start = Number(page.cursor ?? 0)
  const items = rows.slice(start, start + page.limit)
  const end = start + items.length
  return { items, nextCursor: end < rows.length ? String(end) : null }
}

class TenantMap<T extends { tenantId: string; id: string }> {
  protected readonly rows = new Map<string, T>()

  async save(row: T): Promise<void> {
    this.rows.set(key(row.tenantId, row.id), row)
  }

  async findById(tenantId: string, id: string): Promise<T | null> {
    return this.rows.get(key(tenantId, id)) ?? null
  }

  protected of(tenantId: string): T[] {
    return [...this.rows.values()].filter(row => row.tenantId === tenantId)
  }
}

export class InMemoryInstitutionRepository
  extends TenantMap<Institution>
  implements InstitutionRepository
{
  async ensure(candidate: Institution): Promise<Institution> {
    const existing = this.of(candidate.tenantId).find(
      row => row.name === candidate.name,
    )
    if (!existing) {
      await this.save(candidate)
      return candidate
    }
    if (!candidate.imageUrl) {
      return existing
    }
    const branded = {
      ...existing,
      connectorId: candidate.connectorId ?? null,
      imageUrl: candidate.imageUrl,
      primaryColor: candidate.primaryColor ?? null,
    }
    await this.save(branded)
    return branded
  }
}

export class InMemoryCardBillRepository implements CardBillRepository {
  private readonly rows = new Map<string, CardBill>()

  async saveAll(bills: readonly CardBill[]): Promise<void> {
    for (const bill of bills) {
      this.rows.set(`${bill.tenantId}:${bill.accountId}:${bill.dueOn}`, bill)
    }
  }

  async list(
    tenantId: string,
    accountIds: readonly string[],
  ): Promise<CardBill[]> {
    return [...this.rows.values()]
      .filter(
        bill =>
          bill.tenantId === tenantId && accountIds.includes(bill.accountId),
      )
      .sort((a, b) => b.dueOn.localeCompare(a.dueOn))
  }
}

function containsText(transaction: Transaction, search: string): boolean {
  const needle = search.toLowerCase()
  return [transaction.description, transaction.note ?? ''].some(text =>
    text.toLowerCase().includes(needle),
  )
}

function inCategory(transaction: Transaction, filter: TransactionFilter) {
  if (filter.uncategorized) {
    return transaction.categoryId === null
  }
  return !filter.categoryId || transaction.categoryId === filter.categoryId
}

function matches(transaction: Transaction, filter: TransactionFilter): boolean {
  const inAccounts =
    !filter.accountIds || filter.accountIds.includes(transaction.accountId)
  const afterFrom = !filter.from || transaction.bookedOn >= filter.from
  const beforeTo = !filter.to || transaction.bookedOn <= filter.to
  const found = !filter.search || containsText(transaction, filter.search)
  return (
    inAccounts &&
    afterFrom &&
    beforeTo &&
    found &&
    inCategory(transaction, filter)
  )
}

export class InMemoryTransactionRepository
  extends TenantMap<Transaction>
  implements TransactionRepository
{
  async saveNew(transactions: readonly Transaction[]): Promise<number> {
    let inserted = 0
    for (const candidate of transactions) {
      const stored = this.of(candidate.tenantId).find(
        row =>
          row.accountId === candidate.accountId &&
          row.externalId !== null &&
          row.externalId === candidate.externalId,
      )
      if (!stored) {
        await this.save(candidate)
        inserted += 1
        continue
      }
      await this.save({
        ...stored,
        merchant: stored.merchant ?? candidate.merchant,
        installment: stored.installment ?? candidate.installment,
      })
    }
    return inserted
  }

  async list(
    tenantId: string,
    filter: TransactionFilter,
    page: PageRequest,
  ): Promise<Page<Transaction>> {
    return paginate(await this.all(tenantId, filter), page)
  }

  async all(
    tenantId: string,
    filter: TransactionFilter,
  ): Promise<Transaction[]> {
    return this.of(tenantId)
      .filter(row => matches(row, filter))
      .sort(
        (a, b) =>
          b.bookedOn.localeCompare(a.bookedOn) || a.id.localeCompare(b.id),
      )
  }
}

export class InMemoryConnectionRepository
  extends TenantMap<Connection>
  implements ConnectionRepository
{
  async findByItemId(
    tenantId: string,
    provider: string,
    itemId: string,
  ): Promise<Connection | null> {
    const found = this.of(tenantId).find(
      row => row.provider === provider && row.itemId === itemId,
    )
    return found ?? null
  }

  async list(tenantId: string): Promise<Connection[]> {
    return this.of(tenantId)
  }

  async delete(tenantId: string, id: string): Promise<void> {
    this.rows.delete(key(tenantId, id))
  }
}

export class InMemoryTransferRepository
  extends TenantMap<InternalTransfer>
  implements TransferRepository
{
  async list(
    tenantId: string,
    range: { from: Date; to: Date },
  ): Promise<InternalTransfer[]> {
    return this.of(tenantId)
      .filter(row => row.at >= range.from && row.at < range.to)
      .sort((a, b) => b.at.getTime() - a.at.getTime())
  }
}

function invoiceMatches(invoice: Invoice, filter: InvoiceFilter): boolean {
  return (
    (!filter.entityId || invoice.entityId === filter.entityId) &&
    (!filter.status || invoice.status === filter.status) &&
    (!filter.competenceFrom || invoice.competence >= filter.competenceFrom) &&
    (!filter.competenceTo || invoice.competence <= filter.competenceTo)
  )
}

export class InMemoryInvoiceRepository
  extends TenantMap<Invoice>
  implements InvoiceRepository
{
  private readonly clients = new Map<string, InvoiceClient>()
  private readonly files = new Map<string, InvoiceFile>()
  private readonly templates = new Map<string, InvoiceTemplate>()

  async list(
    tenantId: string,
    filter: InvoiceFilter,
    page: PageRequest,
  ): Promise<Page<Invoice>> {
    return paginate(await this.all(tenantId, filter), page)
  }

  async all(tenantId: string, filter: InvoiceFilter): Promise<Invoice[]> {
    return this.of(tenantId)
      .filter(row => invoiceMatches(row, filter))
      .sort(
        (a, b) =>
          b.issueOn.localeCompare(a.issueOn) || a.id.localeCompare(b.id),
      )
  }

  async findClient(
    tenantId: string,
    id: string,
  ): Promise<InvoiceClient | null> {
    return this.clients.get(key(tenantId, id)) ?? null
  }

  async findClientByName(
    tenantId: string,
    entityId: string,
    name: string,
  ): Promise<InvoiceClient | null> {
    const found = [...this.clients.values()].find(
      client =>
        client.tenantId === tenantId &&
        client.entityId === entityId &&
        client.name === name,
    )
    return found ?? null
  }

  async saveClient(client: InvoiceClient): Promise<void> {
    this.clients.set(key(client.tenantId, client.id), client)
  }

  async findByExternalId(
    tenantId: string,
    externalId: string,
  ): Promise<Invoice | null> {
    const found = this.of(tenantId).find(row => row.externalId === externalId)
    return found ?? null
  }

  async saveFile(file: InvoiceFile): Promise<void> {
    this.files.set(key(file.tenantId, `${file.invoiceId}:${file.kind}`), file)
  }

  async findFile(
    tenantId: string,
    invoiceId: string,
    kind: InvoiceFileKind,
  ): Promise<InvoiceFile | null> {
    return this.files.get(key(tenantId, `${invoiceId}:${kind}`)) ?? null
  }

  async saveTemplate(template: InvoiceTemplate): Promise<void> {
    this.templates.set(key(template.tenantId, template.id), template)
  }

  async findTemplate(
    tenantId: string,
    id: string,
  ): Promise<InvoiceTemplate | null> {
    return this.templates.get(key(tenantId, id)) ?? null
  }

  async listTemplates(
    tenantId: string,
    entityId: string,
  ): Promise<InvoiceTemplate[]> {
    return [...this.templates.values()]
      .filter(row => row.tenantId === tenantId && row.entityId === entityId)
      .sort((a, b) => a.dayOfMonth - b.dayOfMonth || a.id.localeCompare(b.id))
  }

  async deleteTemplate(tenantId: string, id: string): Promise<void> {
    this.templates.delete(key(tenantId, id))
  }
}

export class InMemoryBudgetRepository implements BudgetRepository {
  constructor(
    private readonly budgets: Array<
      BudgetLimit & { tenantId: string; entityId: string; month: string }
    > = [],
  ) {}

  async list(
    tenantId: string,
    entityId: string,
    month: string,
  ): Promise<BudgetLimit[]> {
    return this.budgets
      .filter(
        row =>
          row.tenantId === tenantId &&
          row.entityId === entityId &&
          row.month === month,
      )
      .map(row => ({
        categoryId: row.categoryId,
        categoryName: row.categoryName,
        limit: row.limit,
      }))
  }
}

export class InMemoryAttachmentRepository
  extends TenantMap<Attachment>
  implements AttachmentRepository
{
  async list(tenantId: string, billId: string): Promise<AttachmentMeta[]> {
    return this.of(tenantId)
      .filter(row => row.billId === billId)
      .map(({ bytes: _bytes, ...meta }) => meta)
  }

  async find(tenantId: string, id: string): Promise<Attachment | null> {
    return this.findById(tenantId, id)
  }
}

export class InMemoryDocumentStore implements DocumentStore {
  private readonly rows = new Map<string, unknown>()

  private static id(tenantId: string, collection: string, id: string) {
    return `${tenantId}\u0000${collection}\u0000${id}`
  }

  async get<T>(
    tenantId: string,
    collection: string,
    id: string,
  ): Promise<T | null> {
    const found = this.rows.get(
      InMemoryDocumentStore.id(tenantId, collection, id),
    )
    return found === undefined ? null : (structuredClone(found) as T)
  }

  async put<T>(
    tenantId: string,
    collection: string,
    id: string,
    data: T,
  ): Promise<void> {
    this.rows.set(
      InMemoryDocumentStore.id(tenantId, collection, id),
      structuredClone(data),
    )
  }

  async list<T>(tenantId: string, collection: string): Promise<T[]> {
    const prefix = InMemoryDocumentStore.id(tenantId, collection, '')
    return [...this.rows.entries()]
      .filter(([id]) => id.startsWith(prefix))
      .map(([, data]) => structuredClone(data) as T)
  }

  async delete(
    tenantId: string,
    collection: string,
    id: string,
  ): Promise<void> {
    this.rows.delete(InMemoryDocumentStore.id(tenantId, collection, id))
  }
}

export class InMemoryCategoryRepository
  extends TenantMap<Category>
  implements CategoryRepository
{
  private readonly rules = new Map<string, CategoryRule>()

  async list(tenantId: string): Promise<Category[]> {
    return this.of(tenantId)
  }

  async listRules(tenantId: string): Promise<CategoryRule[]> {
    return [...this.rules.values()].filter(rule => rule.tenantId === tenantId)
  }

  async saveRule(rule: CategoryRule): Promise<void> {
    this.rules.set(key(rule.tenantId, rule.id), rule)
  }
}
