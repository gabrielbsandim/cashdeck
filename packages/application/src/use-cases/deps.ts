import { type LlmProvider } from '@/ports/llm-provider'
import { type RailId } from '@cashdeck/domain'
import {
  type BillSource,
  type InvoiceIssuer,
  type OpenFinanceProvider,
  type SecretVault,
} from '@/ports/providers'
import { type RailStatusReader } from '@/ports/rail-status'
import {
  type AttachmentRepository,
  type BudgetRepository,
  type ConnectionRepository,
  type DocumentStore,
  type InstitutionRepository,
  type InvoiceRepository,
  type TransactionRepository,
  type TransferRepository,
} from '@/ports/records'
import {
  type AccountRepository,
  type AuditLog,
  type BillRepository,
  type FinancialEntityRepository,
  type IdempotencyStore,
  type PayeeDirectory,
  type PaymentRepository,
  type PaymentSettingsProvider,
  type SecretStore,
} from '@/ports/repositories'
import {
  type ArchiveWriter,
  type CertificateInspector,
  type MailboxAuthorizer,
  type PdfWriter,
} from '@/ports/services'
import { type Clock, type IdGenerator } from '@/ports/system'
import { type RailRegistry } from '@/use-cases/build-payment-plan'

// Everything a use case may need; each factory picks its own slice.
export type Deps = {
  entities: FinancialEntityRepository
  accounts: AccountRepository
  institutions: InstitutionRepository
  transactions: TransactionRepository
  connections: ConnectionRepository
  transfers: TransferRepository
  invoices: InvoiceRepository
  budgets: BudgetRepository
  attachments: AttachmentRepository
  documents: DocumentStore
  bills: BillRepository
  payments: PaymentRepository
  payees: PayeeDirectory
  settings: PaymentSettingsProvider
  audit: AuditLog
  idempotency: IdempotencyStore
  secrets: SecretStore
  vault: SecretVault
  rails: RailRegistry
  railStatus: ReadonlyMap<RailId, RailStatusReader>
  openFinance: OpenFinanceProvider
  issuer: InvoiceIssuer
  billSources: ReadonlyMap<string, BillSource>
  mailboxAuthorizer: MailboxAuthorizer
  certificates: CertificateInspector
  archives: ArchiveWriter
  pdfs: PdfWriter
  llm: LlmProvider
  clock: Clock
  ids: IdGenerator
}
