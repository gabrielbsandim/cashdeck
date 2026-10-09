import { randomUUID } from 'node:crypto'
import {
  type BillSource,
  categorizeAfterSync,
  type ChatConfig,
  type Clock,
  DEFAULT_SAFETY_SETTINGS,
  DEFAULT_CHAT_CONFIG,
  type Deps,
  FakeSecretVault,
  type IdGenerator,
  InMemoryAccountRepository,
  InMemoryAlertRepository,
  InMemoryAttachmentRepository,
  InMemoryAuditLog,
  InMemoryBillRepository,
  InMemoryBudgetRepository,
  InMemoryCardBillRepository,
  InMemoryCategoryRepository,
  InMemoryChatRepository,
  InMemoryConnectionRepository,
  InMemoryDeviceTokenRepository,
  InMemoryDocumentStore,
  InMemoryEntityRepository,
  InMemoryFundingRepository,
  InMemoryIdempotencyStore,
  InMemoryInstitutionRepository,
  InMemoryInvoiceRepository,
  InMemoryPayeeDirectory,
  InMemoryPaymentRepository,
  InMemorySecretStore,
  InMemoryTransactionRepository,
  InMemoryTransferRepository,
  InMemoryWebhookEventStore,
  makeAccountantExport,
  makeAlertEmitter,
  makeAlerts,
  makeAutomation,
  makeCaptureBill,
  makeCaptureFile,
  makeCaptureSources,
  makeCardStatements,
  makeCategorizeTransactions,
  makeChat,
  makeCompanySummary,
  makeConsolidatedSummary,
  makeInsightsOverview,
  makeCreateManualAccount,
  makeDescribeBill,
  makeSetAutoDebit,
  makeDocuments,
  makeGetBill,
  makeGetTransfer,
  makeInvoiceLifecycle,
  makeInvoiceReceipt,
  makeInvoiceTemplates,
  makeIssueInvoice,
  makeInvoiceViews,
  makeIssuerSetup,
  makeListAccounts,
  makeListBills,
  makeListCategories,
  makeListEntities,
  makeUpdateEntity,
  makeListInvoices,
  makeListTransactions,
  makeListTransfers,
  makeMarkBillPaid,
  makeOpenFinance,
  makePayroll,
  makePersonalSummary,
  makePrepareFunding,
  makeProcessWebhookEvents,
  makeRails,
  makeReceipts,
  makeReceiveWebhook,
  makeReconcilePayments,
  makeRecordTransfer,
  makeRecurringInvoices,
  makeRevenue,
  makeRunDailyAlerts,
  makeRunDuePayments,
  makeRunPaymentLadder,
  makeTestIssuer,
  makeUpdateAccount,
  makeUpdateTransaction,
  makeUploadIssuerCertificate,
  type PaymentRail,
  type PaymentSettings,
  type SecretVault,
  StaticPaymentSettings,
  type WebhookProvider,
  type WebhookReader,
  withLadderAlerts,
} from '@cashdeck/application'
import { createFinancialEntity, RAIL_IDS, type RailId } from '@cashdeck/domain'
import {
  createLlmProvider,
  createPrismaAlertStores,
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
  const bills = new InMemoryBillRepository()
  return {
    entities: new InMemoryEntityRepository(sampleEntities(tenantId)),
    accounts: new InMemoryAccountRepository(),
    bills,
    payments: new InMemoryPaymentRepository(bills),
    fundings: new InMemoryFundingRepository(),
    payees: new InMemoryPayeeDirectory(),
    settings: new StaticPaymentSettings(settings),
    audit: new InMemoryAuditLog(),
    idempotency: new InMemoryIdempotencyStore(),
    secrets: new InMemorySecretStore(),
    institutions: new InMemoryInstitutionRepository(),
    transactions: new InMemoryTransactionRepository(),
    cardBills: new InMemoryCardBillRepository(),
    connections: new InMemoryConnectionRepository(),
    transfers: new InMemoryTransferRepository(),
    invoices: new InMemoryInvoiceRepository(),
    budgets: new InMemoryBudgetRepository(),
    attachments: new InMemoryAttachmentRepository(),
    documents: new InMemoryDocumentStore(),
    webhookEvents: new InMemoryWebhookEventStore(),
    alertStore: new InMemoryAlertRepository(),
    devices: new InMemoryDeviceTokenRepository(),
    categories: new InMemoryCategoryRepository(),
    chat: new InMemoryChatRepository(),
  }
}

const clamp = (value: number, min: number, max: number) =>
  Math.min(Math.max(value, min), max)

const numberOr = (value: string | undefined, fallback: number) =>
  value === undefined ? fallback : Number(value)

export function chatConfig(env: ServerEnv): ChatConfig {
  const defaults = DEFAULT_CHAT_CONFIG
  return {
    enabled: env.CHAT_ENABLED === 'true',
    dailyTurnLimit: numberOr(
      env.CHAT_DAILY_TURN_LIMIT,
      defaults.dailyTurnLimit,
    ),
    dailyCostLimitMillicents:
      numberOr(
        env.CHAT_DAILY_COST_LIMIT_CENTS,
        defaults.dailyCostLimitMillicents / 1000,
      ) * 1000,
    maxRounds: clamp(numberOr(env.CHAT_MAX_ROUNDS, defaults.maxRounds), 1, 12),
    // Below the route maxDuration of 60 s, with room to save the reply.
    turnBudgetMs: clamp(
      numberOr(env.CHAT_TURN_BUDGET_MS, defaults.turnBudgetMs),
      1000,
      50_000,
    ),
    historyLimit: defaults.historyLimit,
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
    ...createPrismaAlertStores(db),
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
    ...DEFAULT_SAFETY_SETTINGS,
  })
  const providers = createProviders({
    env: source,
    tenantId: env.CASHDECK_TENANT_ID,
    secrets: base.secrets,
    vault,
    transport,
    llm,
    deviceTokens: async tenantId =>
      (await base.devices.list(tenantId)).map(device => ({
        token: device.token,
        locale: device.locale,
      })),
    onInvalidToken: async (tenantId, token) => {
      await base.devices.remove(tenantId, token)
    },
  })
  const alerts = makeAlertEmitter({
    ...base,
    notifier: providers.notifier,
    clock: systemClock,
    ids: uuids,
  })
  const rails: PaymentRail[] = providers.rails
  const deps: Deps = {
    ...base,
    vault,
    rails: new Map<RailId, PaymentRail>(rails.map(rail => [rail.id, rail])),
    railStatus: providers.railStatus,
    funder: providers.reserveFunder,
    openFinance: providers.openFinance,
    issuer: providers.invoiceIssuer,
    billSources: new Map<string, BillSource>(
      providers.billSources.map(billSource => [billSource.source, billSource]),
    ),
    pixLocations: providers.pixLocations,
    documentText: providers.documentText,
    webhooks: new Map<WebhookProvider, WebhookReader>(
      providers.webhooks.map(reader => [reader.provider, reader]),
    ),
    mailboxAuthorizer: new GoogleMailboxAuthorizer(source, transport),
    certificates: new X509CertificateInspector(),
    archives: new StoredZipWriter(),
    pdfs: new SimplePdfWriter(),
    llm,
    notifier: providers.notifier,
    alerts,
    clock: systemClock,
    ids: uuids,
  }
  const runPaymentLadder = withLadderAlerts(makeRunPaymentLadder(deps), alerts)
  const categorizeTransactions = makeCategorizeTransactions(deps)
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
    setAutoDebit: makeSetAutoDebit(deps, makeGetBill(deps)),
    runPaymentLadder,
    runDuePayments: makeRunDuePayments({
      ...deps,
      runLadder: runPaymentLadder,
      prepareFunding: makePrepareFunding(deps),
    }),
    reconcilePayments: makeReconcilePayments(deps),
    listEntities: makeListEntities(deps),
    updateEntity: makeUpdateEntity(deps),
    listAccounts: makeListAccounts(deps),
    createManualAccount: makeCreateManualAccount(deps),
    updateAccount: makeUpdateAccount(deps),
    listTransactions: makeListTransactions(deps),
    updateTransaction: makeUpdateTransaction(deps),
    listCategories: makeListCategories(deps),
    categorizeTransactions,
    chat: makeChat(deps, chatConfig(env)),
    listTransfers: makeListTransfers(deps),
    getTransfer: makeGetTransfer(deps),
    recordTransfer: makeRecordTransfer(deps),
    personalSummary: makePersonalSummary(deps),
    companySummary: makeCompanySummary(deps),
    consolidatedSummary: makeConsolidatedSummary(deps),
    insightsOverview: makeInsightsOverview(deps),
    openFinance: categorizeAfterSync(
      makeOpenFinance(deps),
      categorizeTransactions,
    ),
    rails: makeRails(deps),
    automation: makeAutomation(deps),
    captureSources: makeCaptureSources(deps),
    captureFile: makeCaptureFile(deps),
    documents: makeDocuments(deps),
    issuerSetup: makeIssuerSetup(deps),
    uploadIssuerCertificate: makeUploadIssuerCertificate(deps),
    testIssuer: makeTestIssuer(deps),
    listInvoices: makeListInvoices(deps),
    invoiceViews: makeInvoiceViews(deps),
    issueInvoice: makeIssueInvoice(deps),
    invoiceReceipt: makeInvoiceReceipt(deps),
    invoiceLifecycle: makeInvoiceLifecycle(deps),
    invoiceTemplates: makeInvoiceTemplates(deps),
    recurringInvoices: makeRecurringInvoices(deps),
    receiveWebhook: makeReceiveWebhook(deps),
    processWebhookEvents: makeProcessWebhookEvents(deps),
    payroll: makePayroll(deps),
    revenue: makeRevenue(deps),
    cardStatements: makeCardStatements(deps),
    receipts: makeReceipts(deps),
    accountantExport: makeAccountantExport(deps),
    alerts: makeAlerts(deps),
    runDailyAlerts: makeRunDailyAlerts(deps),
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
