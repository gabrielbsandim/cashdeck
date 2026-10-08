import { randomUUID } from 'node:crypto'
import {
  type Clock,
  FakeSecretVault,
  type IdGenerator,
  InMemoryAccountRepository,
  InMemoryAuditLog,
  InMemoryBillRepository,
  InMemoryEntityRepository,
  InMemoryIdempotencyStore,
  InMemoryPayeeDirectory,
  InMemoryPaymentRepository,
  InMemorySecretStore,
  makeCaptureBill,
  makeDescribeBill,
  makeGetBill,
  makeListBills,
  makeMarkBillPaid,
  makeRunDuePayments,
  makeRunPaymentLadder,
  type PaymentRail,
  type PaymentSettings,
  type SecretVault,
  StaticPaymentSettings,
} from '@cashdeck/application'
import { createFinancialEntity, type RailId } from '@cashdeck/domain'
import {
  createLlmProvider,
  createPrismaRepositories,
  defaultRails,
  EnvelopeSecretVault,
  getPrismaClient,
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

function inMemoryRepositories(tenantId: string, settings: PaymentSettings) {
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
  }
}

function repositories(env: ServerEnv, settings: PaymentSettings) {
  if (!env.DATABASE_URL) {
    return inMemoryRepositories(env.CASHDECK_TENANT_ID, settings)
  }
  return createPrismaRepositories(getPrismaClient(env.DATABASE_URL), settings)
}

export function buildContainer(env: ServerEnv = readEnv()) {
  const rails = defaultRails()
  const settings: PaymentSettings = {
    killSwitch: false,
    enabledRails: rails.map(rail => rail.id),
    dailyCapCents: {},
    confirmAboveCents: null,
  }
  const deps = {
    ...repositories(env, settings),
    rails: new Map<RailId, PaymentRail>(rails.map(rail => [rail.id, rail])),
    clock: systemClock,
    ids: uuids,
  }
  const runPaymentLadder = makeRunPaymentLadder(deps)
  return {
    deps,
    llm: createLlmProvider(env),
    vault: secretVault(env),
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
