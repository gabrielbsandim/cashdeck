import {
  type Account,
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
  FakeInvoiceIssuer,
  FakeLlmProvider,
  FakeOpenFinanceProvider,
  FakeSecretVault,
} from '@/testing/providers'
import {
  InMemoryAttachmentRepository,
  InMemoryBudgetRepository,
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
import { NOW, scenario, TENANT } from '@/testing/scenario.test-helpers'
import {
  FakeArchiveWriter,
  FakeCertificateInspector,
  FakeMailboxAuthorizer,
} from '@/testing/services'

type Options = {
  rails?: PaymentRail[]
  settings?: Partial<PaymentSettings>
  railStatus?: RailStatusReader[]
  billSources?: BillSource[]
  openFinance?: OpenFinanceProvider
  budgets?: InMemoryBudgetRepository
}

export function fullDeps(options: Options = {}) {
  return {
    ...scenario(options.rails, options.settings),
    accounts: new InMemoryAccountRepository(),
    institutions: new InMemoryInstitutionRepository(),
    transactions: new InMemoryTransactionRepository(),
    connections: new InMemoryConnectionRepository(),
    transfers: new InMemoryTransferRepository(),
    invoices: new InMemoryInvoiceRepository(),
    budgets: options.budgets ?? new InMemoryBudgetRepository(),
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
    mailboxAuthorizer: new FakeMailboxAuthorizer(),
    certificates: new FakeCertificateInspector(),
    archives: new FakeArchiveWriter(),
    llm: new FakeLlmProvider(),
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
