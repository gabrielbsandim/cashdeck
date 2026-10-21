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
  InMemoryIndexRateRepository,
  InMemoryInvestmentRepository,
  InMemoryRecurrenceRepository,
  InMemoryCategoryRepository,
  InMemoryChatRepository,
  InMemoryConnectionRepository,
  InMemoryDeviceSessionRepository,
  InMemoryDeviceTokenRepository,
  InMemoryDocumentStore,
  InMemoryEntityRepository,
  InMemoryFundingRepository,
  InMemoryGoalRepository,
  InMemoryIdempotencyStore,
  InMemoryInstitutionRepository,
  InMemoryInvoiceRepository,
  InMemoryPayeeDirectory,
  InMemoryPaymentRepository,
  InMemoryPixContactRepository,
  InMemorySecretStore,
  InMemoryTransactionRepository,
  InMemoryTransferRepository,
  InMemoryWebhookEventStore,
  makeAccountantExport,
  makeAlertEmitter,
  makeAlerts,
  makeAutomation,
  makeBudgets,
  makeCaptureBill,
  makeCaptureFile,
  makeCaptureSources,
  makeCardNotifications,
  makeCardStatements,
  makeCategorizeTransactions,
  makeChat,
  makePixContacts,
  makeCompanySummary,
  makeConsolidatedSummary,
  makeInsightsOverview,
  makeMonthlyInsights,
  makeMonthlyRecap,
  makeListCardBills,
  makeGetCardTimeline,
  makeGoals,
  makeLifePlan,
  makePlanAdvice,
  makeListInvestments,
  makeInvestmentPerformance,
  makeNetWorthFromBalancesAndSnapshots,
  makeSafeToSpend,
  makeSetSpendingPlan,
  makeLoans,
  makeAssets,
  makeVehicleCatalog,
  makeIncomeSources,
  makeListInstallments,
  makeReportJobFailure,
  makeReportJobPartialFailure,
  makeSubscriptions,
  makeCreateCategoryRule,
  makeCategoryReview,
  makeCategoryRules,
  makeCreateManualAccount,
  makeDeviceSessions,
  makeDescribeBill,
  makeSetAutoDebit,
  makeDocuments,
  makeGetBill,
  makeGetTransfer,
  makeInvoiceLifecycle,
  makeInvoiceReceipt,
  makeInvoiceDrafts,
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
  makeMarkBillUnpaid,
  makeRescheduleBill,
  makeOpenFinance,
  makePayroll,
  makeFundingItems,
  makeFundingPlan,
  makeSetDebitAccount,
  makePersonalSummary,
  makePreviewFeed,
  makeRailAccounts,
  makePrepareFunding,
  makeProcessWebhookEvents,
  makeRails,
  makeReceipts,
  makeReceiveWebhook,
  makeValidateWithdrawal,
  makeReconcileBill,
  makeReconcilePayments,
  makeRecordTransfer,
  makeRecurringInvoices,
  makeRevenue,
  makeRequestConfirmations,
  makeRunDailyAlerts,
  makeRunDuePayments,
  makeRunPaymentLadder,
  makeTestIssuer,
  makeUpdateAccount,
  makeHousehold,
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
  createPrismaPlanning,
  createPrismaRecords,
  createPrismaRepositories,
  createProviders,
  EnvelopeSecretVault,
  fetchTransport,
  getPrismaClient,
  SimplePdfWriter,
  GoogleMailboxAuthorizer,
  PrismaDeviceSessionRepository,
  RandomSessionTokens,
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

const isProduction = (env: ServerEnv) =>
  env.NODE_ENV === 'production' || env.VERCEL_ENV === 'production'

// The fake vault keeps secrets readable, so production refuses to start
// without the master key instead of storing provider credentials unsealed.
function secretVault(env: ServerEnv): SecretVault {
  if (env.CASHDECK_MASTER_KEY) {
    return new EnvelopeSecretVault(env.CASHDECK_MASTER_KEY)
  }
  if (isProduction(env)) {
    throw new Error('CASHDECK_MASTER_KEY is required in production.')
  }
  return new FakeSecretVault()
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
    investments: new InMemoryInvestmentRepository(),
    indexRates: new InMemoryIndexRateRepository(),
    recurrences: new InMemoryRecurrenceRepository(),
    connections: new InMemoryConnectionRepository(),
    transfers: new InMemoryTransferRepository(),
    invoices: new InMemoryInvoiceRepository(),
    budgets: new InMemoryBudgetRepository(),
    goals: new InMemoryGoalRepository(),
    attachments: new InMemoryAttachmentRepository(),
    documents: new InMemoryDocumentStore(),
    webhookEvents: new InMemoryWebhookEventStore(),
    alertStore: new InMemoryAlertRepository(),
    devices: new InMemoryDeviceTokenRepository(),
    categories: new InMemoryCategoryRepository(),
    chat: new InMemoryChatRepository(),
    pixContacts: new InMemoryPixContactRepository(),
    sessions: new InMemoryDeviceSessionRepository(),
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
    ...createPrismaPlanning(db),
    ...createPrismaAlertStores(db),
    sessions: new PrismaDeviceSessionRepository(db),
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
    preview: providers.preview,
    marketData: providers.marketData,
    vehiclePrices: providers.vehiclePrices,
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
  const previewFeed = makePreviewFeed(deps)
  const openFinance = categorizeAfterSync(
    makeOpenFinance(deps),
    categorizeTransactions,
  )
  return {
    deps,
    env,
    llm,
    vault,
    reportJobFailure: makeReportJobFailure({ alerts, clock: systemClock }),
    reportJobPartialFailure: makeReportJobPartialFailure({
      alerts,
      clock: systemClock,
    }),
    captureBill: makeCaptureBill(deps),
    describeBill: makeDescribeBill(deps),
    getBill: makeGetBill(deps),
    listBills: makeListBills(deps),
    markBillPaid: makeMarkBillPaid(deps),
    markBillUnpaid: makeMarkBillUnpaid(deps),
    rescheduleBill: makeRescheduleBill(deps),
    setAutoDebit: makeSetAutoDebit(deps, makeGetBill(deps)),
    runPaymentLadder,
    runDuePayments: makeRunDuePayments({
      ...deps,
      runLadder: runPaymentLadder,
      prepareFunding: makePrepareFunding(deps),
    }),
    reconcilePayments: makeReconcilePayments(deps),
    reconcileBill: makeReconcileBill(deps),
    listEntities: makeListEntities(deps),
    updateEntity: makeUpdateEntity(deps),
    listAccounts: makeListAccounts(deps),
    createManualAccount: makeCreateManualAccount(deps),
    updateAccount: makeUpdateAccount(deps),
    listTransactions: makeListTransactions(deps),
    updateTransaction: makeUpdateTransaction(deps),
    listCategories: makeListCategories(deps),
    createCategoryRule: makeCreateCategoryRule(deps),
    categoryRules: makeCategoryRules(deps),
    categoryReview: makeCategoryReview(deps),
    categorizeTransactions,
    chat: makeChat(deps, chatConfig(env)),
    pixContacts: makePixContacts(deps),
    listTransfers: makeListTransfers(deps),
    getTransfer: makeGetTransfer(deps),
    recordTransfer: makeRecordTransfer(deps),
    personalSummary: makePersonalSummary(deps),
    fundingPlan: makeFundingPlan(deps),
    safeToSpend: makeSafeToSpend(deps),
    setSpendingPlan: makeSetSpendingPlan(deps),
    incomeSources: makeIncomeSources(deps),
    household: makeHousehold(deps),
    loans: makeLoans(deps),
    assets: makeAssets(deps),
    vehicles: makeVehicleCatalog(deps),
    netWorth: makeNetWorthFromBalancesAndSnapshots(deps),
    fundingItems: makeFundingItems(deps),
    setDebitAccount: makeSetDebitAccount(deps),
    companySummary: makeCompanySummary(deps),
    consolidatedSummary: makeConsolidatedSummary(deps),
    insightsOverview: makeInsightsOverview(deps),
    monthlyInsights: makeMonthlyInsights(deps),
    monthlyRecap: makeMonthlyRecap(deps),
    listInstallments: makeListInstallments(deps),
    listCardBills: makeListCardBills(deps),
    getCardTimeline: makeGetCardTimeline(deps),
    listInvestments: makeListInvestments(deps),
    investmentPerformance: makeInvestmentPerformance(deps),
    subscriptions: makeSubscriptions(deps),
    openFinance,
    railAccounts: makeRailAccounts(deps, openFinance.sync),
    previewFeed: {
      // New previews get a category like any synced movement.
      async sync(tenantId: string) {
        const result = await previewFeed.sync(tenantId)
        if (result.previews > 0) {
          await categorizeTransactions(tenantId).catch(() => null)
        }
        return result
      },
    },
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
    invoiceDrafts: makeInvoiceDrafts(deps),
    recurringInvoices: makeRecurringInvoices(deps),
    receiveWebhook: makeReceiveWebhook(deps),
    processWebhookEvents: makeProcessWebhookEvents(deps),
    validateWithdrawal: makeValidateWithdrawal(deps),
    payroll: makePayroll(deps),
    revenue: makeRevenue(deps),
    cardStatements: makeCardStatements(deps),
    captureNotifications: makeCardNotifications(deps),
    receipts: makeReceipts(deps),
    accountantExport: makeAccountantExport(deps),
    alerts: makeAlerts(deps),
    sessions: makeDeviceSessions({
      ...deps,
      sessions: base.sessions,
      sessionTokens: new RandomSessionTokens(),
    }),
    runDailyAlerts: makeRunDailyAlerts(deps),
    requestConfirmations: makeRequestConfirmations(deps),
    goals: makeGoals(deps),
    lifePlan: makeLifePlan(deps),
    planAdvice: makePlanAdvice(deps),
    budgets: makeBudgets(deps),
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
