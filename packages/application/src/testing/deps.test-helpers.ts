import {
  type Account,
  type Alert,
  type Bill,
  createBill,
  createAccount,
  createTransaction,
  Money,
  type RailId,
  type Transaction,
} from '@cashdeck/domain'
import { type Invoice } from '@/ports/records'
import { type PaymentRail } from '@/ports/payment-rail'
import { type BillSource, type OpenFinanceProvider } from '@/ports/providers'
import { type RailStatusReader } from '@/ports/rail-status'
import { type PaymentSettings } from '@/ports/repositories'
import {
  InMemoryAlertRepository,
  InMemoryDeviceTokenRepository,
  RecordingAlertEmitter,
} from '@/testing/alerts'
import {
  FakeInvoiceIssuer,
  FakeLlmProvider,
  FakeNotifier,
  FakeOpenFinanceProvider,
  FakePixLocationResolver,
  FakeSecretVault,
} from '@/testing/providers'
import {
  InMemoryAttachmentRepository,
  InMemoryBudgetRepository,
  InMemoryCardBillRepository,
  InMemoryRecurrenceRepository,
  InMemoryCategoryRepository,
  InMemoryConnectionRepository,
  InMemoryDocumentStore,
  InMemoryInstitutionRepository,
  InMemoryInvoiceRepository,
  InMemoryTransactionRepository,
  InMemoryTransferRepository,
} from '@/testing/records'
import {
  InMemoryAccountRepository,
  InMemorySecretStore,
} from '@/testing/repositories'
import { type WebhookProvider, type WebhookReader } from '@/ports/webhooks'
import { InMemoryChatRepository } from '@/testing/chat'
import { InMemoryInvestmentRepository } from '@/testing/investments'
import { NOW, scenario, TENANT } from '@/testing/scenario.test-helpers'
import { InMemoryWebhookEventStore } from '@/testing/webhooks'
import {
  FakeArchiveWriter,
  FakeCertificateInspector,
  FakeDocumentTextReader,
  FakeMailboxAuthorizer,
  FakePdfWriter,
} from '@/testing/services'

type Options = {
  rails?: PaymentRail[]
  settings?: Partial<PaymentSettings>
  railStatus?: RailStatusReader[]
  billSources?: BillSource[]
  openFinance?: OpenFinanceProvider
  pixLocations?: FakePixLocationResolver
  documentText?: FakeDocumentTextReader
  budgets?: InMemoryBudgetRepository
  webhooks?: WebhookReader[]
}

export function fullDeps(options: Options = {}) {
  return {
    ...scenario(options.rails, options.settings),
    accounts: new InMemoryAccountRepository(),
    institutions: new InMemoryInstitutionRepository(),
    transactions: new InMemoryTransactionRepository(),
    cardBills: new InMemoryCardBillRepository(),
    investments: new InMemoryInvestmentRepository(),
    recurrences: new InMemoryRecurrenceRepository(),
    connections: new InMemoryConnectionRepository(),
    transfers: new InMemoryTransferRepository(),
    invoices: new InMemoryInvoiceRepository(),
    budgets: options.budgets ?? new InMemoryBudgetRepository(),
    categories: new InMemoryCategoryRepository(),
    chat: new InMemoryChatRepository(),
    attachments: new InMemoryAttachmentRepository(),
    documents: new InMemoryDocumentStore(),
    secrets: new InMemorySecretStore(),
    vault: new FakeSecretVault(),
    railStatus: new Map<RailId, RailStatusReader>(
      (options.railStatus ?? []).map(reader => [reader.id, reader]),
    ),
    openFinance:
      options.openFinance ??
      (new FakeOpenFinanceProvider() as OpenFinanceProvider),
    issuer: new FakeInvoiceIssuer(),
    billSources: new Map<string, BillSource>(
      (options.billSources ?? []).map(source => [source.source, source]),
    ),
    pixLocations: options.pixLocations ?? new FakePixLocationResolver(),
    documentText: options.documentText ?? new FakeDocumentTextReader(),
    webhooks: new Map<WebhookProvider, WebhookReader>(
      (options.webhooks ?? []).map(reader => [reader.provider, reader]),
    ),
    webhookEvents: new InMemoryWebhookEventStore(),
    mailboxAuthorizer: new FakeMailboxAuthorizer(),
    certificates: new FakeCertificateInspector(),
    archives: new FakeArchiveWriter(),
    pdfs: new FakePdfWriter(),
    llm: new FakeLlmProvider(),
    alertStore: new InMemoryAlertRepository(),
    devices: new InMemoryDeviceTokenRepository(),
    notifier: new FakeNotifier(),
    alerts: new RecordingAlertEmitter(),
  }
}

export const base64 = (text: string) => btoa(text)

export function account(overrides: Partial<Account> & { id: string }): Account {
  return createAccount({
    tenantId: TENANT,
    entityId: 'pj',
    institutionId: 'inst',
    name: `Account ${overrides.id}`,
    type: 'CHECKING',
    origin: 'MANUAL',
    balance: Money.of(10000),
    ...overrides,
  })
}

export function transaction(
  overrides: Partial<Transaction> & { id: string; accountId: string },
): Transaction {
  return createTransaction({
    tenantId: TENANT,
    amount: Money.of(-5000),
    bookedOn: '2026-10-05',
    description: 'Purchase',
    ...overrides,
  })
}

export function alert(
  overrides: Partial<Alert> & Pick<Alert, 'id' | 'type'>,
): Alert {
  return {
    tenantId: TENANT,
    entityId: 'pf',
    billId: null,
    invoiceId: null,
    title: 'Title',
    body: 'Body',
    data: {},
    dedupeKey: null,
    createdAt: new Date(0),
    readAt: null,
    ...overrides,
  }
}

export function invoice(overrides: Partial<Invoice> & { id: string }): Invoice {
  return {
    tenantId: TENANT,
    entityId: 'pj',
    clientId: 'client',
    templateId: null,
    issuer: 'fake',
    externalId: null,
    number: null,
    status: 'ISSUED',
    amount: Money.of(100000),
    fxRate: null,
    isExport: false,
    competence: '2026-09',
    issueOn: '2026-09-30',
    description: 'Software development',
    serviceCode: '01.01',
    pdfUrl: null,
    xmlUrl: null,
    createdAt: NOW,
    ...overrides,
  }
}

export function bill(overrides: Partial<Bill> & { id: string }): Bill {
  return {
    ...createBill({
      id: overrides.id,
      tenantId: TENANT,
      entityId: 'pf',
      kind: 'BOLETO',
      source: 'MANUAL',
      payee: 'Supplier',
      amount: Money.of(12345),
      dueDate: '2026-10-20',
      code: `code-${overrides.id}`,
      createdAt: NOW,
    }),
    ...overrides,
  }
}
