import {
  type Category,
  type CategoryRule,
  type LocalDate,
  type Money,
  type Transaction,
} from '@cashdeck/domain'
import { type Page, type PageRequest } from '@/ports/repositories'

export type InstitutionBranding = {
  connectorId: number | null
  imageUrl: string | null
  primaryColor: string | null
}

export type Institution = {
  id: string
  tenantId: string
  name: string
  manual: boolean
} & Partial<InstitutionBranding>

export interface InstitutionRepository {
  findById(tenantId: string, id: string): Promise<Institution | null>
  // Returns the stored institution with that name, or saves the candidate;
  // a candidate with a logo refreshes the stored branding.
  ensure(candidate: Institution): Promise<Institution>
}

export type TransactionFilter = {
  accountIds?: readonly string[]
  from?: LocalDate
  to?: LocalDate
  categoryId?: string
  uncategorized?: boolean
  // Case-insensitive substring of the description or the note.
  search?: string
}

export interface TransactionRepository {
  save(transaction: Transaction): Promise<void>
  // Inserts the ones not stored yet, by account and external id, and returns
  // how many; a stored one only takes the merchant and installment it lacks.
  saveNew(transactions: readonly Transaction[]): Promise<number>
  findById(tenantId: string, id: string): Promise<Transaction | null>
  list(
    tenantId: string,
    filter: TransactionFilter,
    page: PageRequest,
  ): Promise<Page<Transaction>>
  all(tenantId: string, filter: TransactionFilter): Promise<Transaction[]>
}

export type Connection = {
  id: string
  tenantId: string
  entityId: string
  institutionId: string
  provider: string
  itemId: string
  status: string
  lastSyncAt: Date | null
}

export interface ConnectionRepository {
  save(connection: Connection): Promise<void>
  findById(tenantId: string, id: string): Promise<Connection | null>
  findByItemId(
    tenantId: string,
    provider: string,
    itemId: string,
  ): Promise<Connection | null>
  list(tenantId: string): Promise<Connection[]>
  delete(tenantId: string, id: string): Promise<void>
}

// A closed card bill; an issuer that reports none leaves the history empty.
export type CardBill = {
  id: string
  tenantId: string
  accountId: string
  externalId: string | null
  closesOn: LocalDate | null
  dueOn: LocalDate
  total: Money
  minimum: Money | null
}

export interface CardBillRepository {
  // One bill per card and due date; a known one is overwritten.
  saveAll(bills: readonly CardBill[]): Promise<void>
  list(tenantId: string, accountIds: readonly string[]): Promise<CardBill[]>
}

export const TRANSFER_KINDS = ['PROFIT_DISTRIBUTION', 'PRO_LABORE'] as const
export type TransferKind = (typeof TRANSFER_KINDS)[number]

export type InternalTransfer = {
  id: string
  tenantId: string
  kind: TransferKind
  amount: Money
  at: Date
  rail: string
  fromAccountId: string
  toAccountId: string
  document: string | null
}

export interface TransferRepository {
  save(transfer: InternalTransfer): Promise<void>
  findById(tenantId: string, id: string): Promise<InternalTransfer | null>
  list(
    tenantId: string,
    range: { from: Date; to: Date },
  ): Promise<InternalTransfer[]>
}

export const INVOICE_STATUSES = [
  'DRAFT',
  'PROCESSING',
  'ISSUED',
  'REJECTED',
  'CANCELLED',
] as const
export type InvoiceStatus = (typeof INVOICE_STATUSES)[number]

export type InvoiceClient = {
  id: string
  tenantId: string
  entityId: string
  name: string
  taxId: string | null
  country: string
}

export type Invoice = {
  id: string
  tenantId: string
  entityId: string
  clientId: string
  templateId: string | null
  issuer: string
  externalId: string | null
  number: string | null
  status: InvoiceStatus
  amount: Money
  // BRL per unit of a foreign currency invoice.
  fxRate: number | null
  isExport: boolean
  competence: string
  issueOn: LocalDate
  description: string
  serviceCode: string
  pdfUrl: string | null
  xmlUrl: string | null
  cancelReason?: string | null
  createdAt: Date
}

export const INVOICE_FILE_KINDS = ['PDF', 'XML'] as const
export type InvoiceFileKind = (typeof INVOICE_FILE_KINDS)[number]

export type InvoiceFile = {
  tenantId: string
  invoiceId: string
  kind: InvoiceFileKind
  fileName: string
  mimeType: string
  size: number
  bytes: Uint8Array
  createdAt: Date
}

export const TEMPLATE_BILLING = ['FIXED', 'HOURLY'] as const
export type TemplateBilling = (typeof TEMPLATE_BILLING)[number]

// An hourly template stores the rate in `amount` and the hours of each cycle.
export type InvoiceTemplate = {
  id: string
  tenantId: string
  entityId: string
  clientId: string
  serviceCode: string
  description: string
  amount: Money
  billing: TemplateBilling
  hours: number | null
  dayOfMonth: number
  active: boolean
}

export type InvoiceFilter = {
  entityId?: string
  status?: InvoiceStatus
  competenceFrom?: string
  competenceTo?: string
}

export interface InvoiceRepository {
  save(invoice: Invoice): Promise<void>
  findById(tenantId: string, id: string): Promise<Invoice | null>
  list(
    tenantId: string,
    filter: InvoiceFilter,
    page: PageRequest,
  ): Promise<Page<Invoice>>
  all(tenantId: string, filter: InvoiceFilter): Promise<Invoice[]>
  findClient(tenantId: string, id: string): Promise<InvoiceClient | null>
  findClientByName(
    tenantId: string,
    entityId: string,
    name: string,
  ): Promise<InvoiceClient | null>
  saveClient(client: InvoiceClient): Promise<void>
  findByExternalId(
    tenantId: string,
    externalId: string,
  ): Promise<Invoice | null>
  saveFile(file: InvoiceFile): Promise<void>
  findFile(
    tenantId: string,
    invoiceId: string,
    kind: InvoiceFileKind,
  ): Promise<InvoiceFile | null>
  saveTemplate(template: InvoiceTemplate): Promise<void>
  findTemplate(tenantId: string, id: string): Promise<InvoiceTemplate | null>
  listTemplates(tenantId: string, entityId: string): Promise<InvoiceTemplate[]>
  deleteTemplate(tenantId: string, id: string): Promise<void>
}

export type BudgetLimit = {
  categoryId: string
  categoryName: string
  limit: Money
}

export interface BudgetRepository {
  list(
    tenantId: string,
    entityId: string,
    month: string,
  ): Promise<BudgetLimit[]>
}

export type AttachmentMeta = {
  id: string
  tenantId: string
  billId: string
  fileName: string
  mimeType: string
  size: number
  createdAt: Date
}

export type Attachment = AttachmentMeta & { bytes: Uint8Array }

export interface AttachmentRepository {
  save(attachment: Attachment): Promise<void>
  list(tenantId: string, billId: string): Promise<AttachmentMeta[]>
  find(tenantId: string, id: string): Promise<Attachment | null>
}

// Small per-tenant documents: settings and drafts that are read whole.
export interface DocumentStore {
  get<T>(tenantId: string, collection: string, id: string): Promise<T | null>
  put<T>(
    tenantId: string,
    collection: string,
    id: string,
    data: T,
  ): Promise<void>
  list<T>(tenantId: string, collection: string): Promise<T[]>
  delete(tenantId: string, collection: string, id: string): Promise<void>
}

export interface CategoryRepository {
  list(tenantId: string): Promise<Category[]>
  findById(tenantId: string, id: string): Promise<Category | null>
  save(category: Category): Promise<void>
  listRules(tenantId: string): Promise<CategoryRule[]>
  saveRule(rule: CategoryRule): Promise<void>
}
