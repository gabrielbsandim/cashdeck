import {
  type BillKind,
  type BillSource as BillSourceKind,
  type LocalDate,
  type Money,
} from '@cashdeck/domain'
import { type DeviceLocale } from '@/ports/alerts'

export type OpenFinanceConnection = { provider: string; itemId: string }

export type ProviderCreditLine = {
  limitCents: number
  availableCents: number
  closesOn: string | null
  dueOn: string | null
  brand: string | null
}

export type ProviderAccount = {
  externalId: string
  name: string
  type: 'CHECKING' | 'SAVINGS' | 'CREDIT_CARD' | 'INVESTMENT'
  balanceCents: number
  currency: string
  numberSuffix?: string | null
  credit?: ProviderCreditLine | null
}

export type ProviderInstallment = {
  number: number
  count: number
  purchaseOn: string | null
}

export type ProviderTransaction = {
  externalId: string
  accountExternalId: string
  amountCents: number
  currency: string
  bookedOn: string
  description: string
  merchant?: string | null
  installment?: ProviderInstallment | null
}

// A closed card bill as the issuer reports it.
export type ProviderBill = {
  externalId: string
  closesOn: string | null
  dueOn: string
  totalCents: number
  minimumCents: number | null
  currency: string
}

// The institution behind an item, with the logo the provider hosts.
export type ProviderConnector = {
  id: number
  name: string
  imageUrl: string | null
  primaryColor: string | null
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
  connector?: ProviderConnector | null
}

export interface OpenFinanceProvider {
  getItem(itemId: string): Promise<ProviderItem>
  listAccounts(connection: OpenFinanceConnection): Promise<ProviderAccount[]>
  listTransactions(
    connection: OpenFinanceConnection,
    accountExternalId: string,
    range: { from: string; to: string },
  ): Promise<ProviderTransaction[]>
  listBills(
    connection: OpenFinanceConnection,
    accountExternalId: string,
  ): Promise<ProviderBill[]>
  // Every institution the provider can connect, to name aggregated accounts.
  listConnectors(): Promise<ProviderConnector[]>
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
  // Most boletos now print a Pix BR Code too; the ladder prefers it when set.
  pixCode?: string | null
  payee: string | null
  amountCents: number | null
  dueDate: string | null
  kind: BillKind | null
}

// The charge behind a dynamic BR Code, read from its location (field 26.25).
export type PixCharge = {
  amount: Money | null
  dueDate: LocalDate | null
  key: string | null
  payee: string | null
  txid: string | null
}

export interface PixLocationResolver {
  // Null when the location answers nothing readable; never blocks a capture.
  resolve(location: string): Promise<PixCharge | null>
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
  // Issuers report in BRL; a foreign currency invoice carries its converted total.
  brlAmountCents?: number | null
  export: boolean
  // From RBT12 and Fator R; null leaves the rate to the issuer settings.
  issRatePercent?: number | null
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
  // Fetches a document URL the issuer returned (PDF or XML of an invoice).
  download(url: string): Promise<Uint8Array>
  check(): Promise<ProviderCheck>
}

export type NotificationText = { title: string; body: string }

export type Notification = {
  tenantId: string
  type: string
  title: string
  body: string
  localized: Record<DeviceLocale, NotificationText>
  data: Record<string, string>
}

export interface Notifier {
  notify(notification: Notification): Promise<void>
}

export interface SecretVault {
  seal(plaintext: string, context: string): Promise<string>
  open(sealed: string, context: string): Promise<string>
}
