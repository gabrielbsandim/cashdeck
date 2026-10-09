import { randomUUID } from 'node:crypto'
import {
  type BillSource,
  type Clock,
  type Deps,
  FakeSecretVault,
  type IdGenerator,
  InMemoryAccountRepository,
  InMemoryAttachmentRepository,
  InMemoryAuditLog,
  InMemoryBillRepository,
  InMemoryBudgetRepository,
  InMemoryConnectionRepository,
  InMemoryDocumentStore,
  InMemoryEntityRepository,
  InMemoryIdempotencyStore,
  InMemoryInstitutionRepository,
  InMemoryInvoiceRepository,
  InMemoryPayeeDirectory,
  InMemoryPaymentRepository,
  InMemorySecretStore,
  InMemoryTransactionRepository,
  InMemoryTransferRepository,
  makeAccountantExport,
  makeAutomation,
  makeCaptureBill,
  makeCaptureFile,
  makeCaptureSources,
  makeCardStatements,
  makeCompanySummary,
  makeConsolidatedSummary,
  makeCreateManualAccount,
  makeDescribeBill,
  makeDocuments,
  makeGetBill,
  makeGetTransfer,
  makeInvoiceReceipt,
  makeIssueInvoice,
  makeIssuerSetup,
  makeListAccounts,
  makeListBills,
  makeListEntities,
  makeUpdateEntity,
  makeListInvoices,
  makeListTransactions,
  makeListTransfers,
  makeMarkBillPaid,
  makeOpenFinance,
  makePayroll,
  makePersonalSummary,
  makeRails,
  makeReceipts,
  makeReconcilePayments,
  makeRecordTransfer,
  makeRunDuePayments,
  makeRunPaymentLadder,
  makeTestIssuer,
  makeUpdateAccount,
  makeUploadIssuerCertificate,
  type PaymentRail,
  type PaymentSettings,
  type SecretVault,
  StaticPaymentSettings,
} from '@cashdeck/application'
import { createFinancialEntity, RAIL_IDS, type RailId } from '@cashdeck/domain'
import {
  createLlmProvider,
  createPrismaRecords,
  createPrismaRepositories,
  createProviders,
  EnvelopeSecretVault,
  fetchTransport,
  getPrismaClient,
  SimplePdfWriter,
  GoogleMailboxAuthorizer,
  StoredZipWriter,
  X509CertificateInspector,
} from '@cashdeck/infrastructure'
import { readEnv, type ServerEnv } from '@/server/env'

const systemClock: Clock = { now: () => new Date() }
const uuids: IdGenerator = { next: () => randomUUID() }

// Sample entities for the offline store, with public test tax ids; the
// database gets the same ones from the seed script.
function sampleEntities(tenantId: string) {
  return [
    createFinancialEntity({
      id: 'personal',
      tenantId,
      kind: 'PF',
      name: 'Personal',
      taxId: '52998224725',
    }),
    createFinancialEntity({
      id: 'company',
      tenantId,
      kind: 'PJ',
      name: 'Company',
      taxId: '11222333000181',
      taxRegime: 'SIMPLES_NACIONAL',
    }),
  ]
}

function secretVault(env: ServerEnv): SecretVault {
  return env.CASHDECK_MASTER_KEY
    ? new EnvelopeSecretVault(env.CASHDECK_MASTER_KEY)
    : new FakeSecretVault()
}

function inMemoryStores(tenantId: string, settings: PaymentSettings) {
  return {
    entities: new InMemoryEntityRepository(sampleEntities(tenantId)),
    accounts: new InMemoryAccountRepository(),
    bills: new InMemoryBillRepository(),
    payments: new InMemoryPaymentRepository(),
    payees: new InMemoryPayeeDirectory(),
    settings: new StaticPaymentSettings(settings),
    audit: new InMemoryAuditLog(),
    idempotency: new InMemoryIdempotencyStore(),
    secrets: new InMemorySecretStore(),
    institutions: new InMemoryInstitutionRepository(),
    transactions: new InMemoryTransactionRepository(),
    connections: new InMemoryConnectionRepository(),
    transfers: new InMemoryTransferRepository(),
    invoices: new InMemoryInvoiceRepository(),
    budgets: new InMemoryBudgetRepository(),
    attachments: new InMemoryAttachmentRepository(),
    documents: new InMemoryDocumentStore(),
  }
}

function stores(env: ServerEnv, settings: PaymentSettings) {
  // In memory on a serverless deploy would drop bills between invocations.
  if (!env.DATABASE_URL && env.VERCEL_ENV) {
    throw new Error('DATABASE_URL is required on a deployed server.')
  }
  if (!env.DATABASE_URL) {
    return inMemoryStores(env.CASHDECK_TENANT_ID, settings)
  }
  const db = getPrismaClient(env.DATABASE_URL)
  return {
    ...createPrismaRepositories(db, settings),
    ...createPrismaRecords(db),
  }
}

export function buildContainer(
  env: ServerEnv = readEnv(),
  source: Record<string, string | undefined> = process.env,
) {
  const vault = secretVault(env)
  const llm = createLlmProvider(env)
  const transport = fetchTransport()
  // Every rail starts enabled: one without credentials reports itself not
  // configured and the ladder moves a step down.
  const base = stores(env, {
    killSwitch: false,
    enabledRails: RAIL_IDS.filter(id => id !== 'ASSISTED'),
    dailyCapCents: {},
    confirmAboveCents: null,
  })
  const providers = createProviders({
    env: source,
    tenantId: env.CASHDECK_TENANT_ID,
    secrets: base.secrets,
    vault,
    transport,
    llm,
  })
  const rails: PaymentRail[] = providers.rails
  const deps: Deps = {
    ...base,
    vault,
    rails: new Map<RailId, PaymentRail>(rails.map(rail => [rail.id, rail])),
    railStatus: providers.railStatus,
    openFinance: providers.openFinance,
    issuer: providers.invoiceIssuer,
    billSources: new Map<string, BillSource>(
      providers.billSources.map(billSource => [billSource.source, billSource]),
    ),
    mailboxAuthorizer: new GoogleMailboxAuthorizer(source, transport),
    certificates: new X509CertificateInspector(),
    archives: new StoredZipWriter(),
    pdfs: new SimplePdfWriter(),
    llm,
    clock: systemClock,
    ids: uuids,
  }
  const runPaymentLadder = makeRunPaymentLadder(deps)
  return {
    deps,
    env,
    llm,
    vault,
    captureBill: makeCaptureBill(deps),
    describeBill: makeDescribeBill(deps),
    getBill: makeGetBill(deps),
    listBills: makeListBills(deps),
    markBillPaid: makeMarkBillPaid(deps),
    runPaymentLadder,
    runDuePayments: makeRunDuePayments({
      ...deps,
      runLadder: runPaymentLadder,
    }),
    reconcilePayments: makeReconcilePayments(deps),
    listEntities: makeListEntities(deps),
    updateEntity: makeUpdateEntity(deps),
    listAccounts: makeListAccounts(deps),
    createManualAccount: makeCreateManualAccount(deps),
    updateAccount: makeUpdateAccount(deps),
    listTransactions: makeListTransactions(deps),
    listTransfers: makeListTransfers(deps),
    getTransfer: makeGetTransfer(deps),
    recordTransfer: makeRecordTransfer(deps),
    personalSummary: makePersonalSummary(deps),
    companySummary: makeCompanySummary(deps),
    consolidatedSummary: makeConsolidatedSummary(deps),
    openFinance: makeOpenFinance(deps),
    rails: makeRails(deps),
    automation: makeAutomation(deps),
    captureSources: makeCaptureSources(deps),
    captureFile: makeCaptureFile(deps),
    documents: makeDocuments(deps),
    issuerSetup: makeIssuerSetup(deps),
    uploadIssuerCertificate: makeUploadIssuerCertificate(deps),
    testIssuer: makeTestIssuer(deps),
    listInvoices: makeListInvoices(deps),
    issueInvoice: makeIssueInvoice(deps),
    invoiceReceipt: makeInvoiceReceipt(deps),
    payroll: makePayroll(deps),
    cardStatements: makeCardStatements(deps),
    receipts: makeReceipts(deps),
    accountantExport: makeAccountantExport(deps),
  }
}

export type Container = ReturnType<typeof buildContainer>

let container: Container | null = null

export function getContainer(): Container {
  container ??= buildContainer()
  return container
}

export function resetContainer(next: Container | null = null): void {
  container = next
}
