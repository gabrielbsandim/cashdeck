import {
  type BillKind,
  type BillSource as BillSourceKind,
} from '@cashdeck/domain'

export type OpenFinanceConnection = { provider: string; itemId: string }

export type ProviderAccount = {
  externalId: string
  name: string
  type: 'CHECKING' | 'SAVINGS' | 'CREDIT_CARD' | 'INVESTMENT'
  balanceCents: number
  currency: string
}

export type ProviderTransaction = {
  externalId: string
  accountExternalId: string
  amountCents: number
  currency: string
  bookedOn: string
  description: string
}

export type ProviderCheck = { ok: boolean; message: string | null }

export type ProviderItemStatus =
  | 'UPDATED'
  | 'UPDATING'
  | 'LOGIN_ERROR'
  | 'OUTDATED'
  | 'WAITING_USER_INPUT'

export type ProviderItem = {
  itemId: string
  institutionName: string
  status: ProviderItemStatus
  lastUpdatedAt: string | null
}

export interface OpenFinanceProvider {
  getItem(itemId: string): Promise<ProviderItem>
  listAccounts(connection: OpenFinanceConnection): Promise<ProviderAccount[]>
  listTransactions(
    connection: OpenFinanceConnection,
    accountExternalId: string,
    range: { from: string; to: string },
  ): Promise<ProviderTransaction[]>
}

export type ImportFile = { name: string; mimeType: string; bytes: Uint8Array }

export type StatementDraft = {
  format: string
  lines: Array<{ bookedOn: string; description: string; amountCents: number }>
  closingDate: string | null
}

export interface StatementImporter {
  readonly format: string
  canRead(file: ImportFile): boolean
  read(file: ImportFile): Promise<StatementDraft>
}

export type CapturedBill = {
  externalId: string
  paymentCode: string | null
  payee: string | null
  amountCents: number | null
  dueDate: string | null
  kind: BillKind | null
}

export interface BillSource {
  readonly source: BillSourceKind
  fetch(
    tenantId: string,
    entityId: string,
    since: Date,
  ): Promise<CapturedBill[]>
}

export type InvoiceDraft = {
  tenantId: string
  entityId: string
  clientName: string
  clientTaxId: string | null
  serviceCode: string
  description: string
  amountCents: number
  currency: string
  export: boolean
}

export type IssuedInvoice = {
  externalId: string
  number: string | null
  status: 'PROCESSING' | 'ISSUED' | 'REJECTED' | 'CANCELLED'
  pdfUrl: string | null
  xmlUrl: string | null
}

export interface InvoiceIssuer {
  readonly id: string
  issue(draft: InvoiceDraft, idempotencyKey: string): Promise<IssuedInvoice>
  get(externalId: string): Promise<IssuedInvoice>
  cancel(externalId: string, reason: string): Promise<IssuedInvoice>
  check(): Promise<ProviderCheck>
}

export type Notification = {
  tenantId: string
  type: string
  title: string
  body: string
  data: Record<string, string>
}

export interface Notifier {
  notify(notification: Notification): Promise<void>
}

export interface SecretVault {
  seal(plaintext: string, context: string): Promise<string>
  open(sealed: string, context: string): Promise<string>
}
