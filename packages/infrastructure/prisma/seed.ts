import { fileURLToPath } from 'node:url'
import { createFinancialEntity, RAIL_IDS } from '@cashdeck/domain'
import { createPrismaClient } from '../src/database/client'
import { createPrismaRepositories } from '../src/repositories/prisma-repositories'

try {
  process.loadEnvFile(fileURLToPath(new URL('../../../.env', import.meta.url)))
} catch {
  // The variables may come from the shell instead.
}

const connectionString = process.env.DATABASE_URL
if (!connectionString) {
  throw new Error('DATABASE_URL is required to seed.')
}
const tenantId = process.env.CASHDECK_TENANT_ID ?? 'local'

const entities = [
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

const db = createPrismaClient(connectionString)
const repos = createPrismaRepositories(db, {
  killSwitch: false,
  enabledRails: [],
  dailyCapCents: {},
  confirmAboveCents: null,
})

async function seed() {
  await db.tenant.upsert({
    where: { id: tenantId },
    create: { id: tenantId, name: 'Local' },
    update: {},
  })
  for (const entity of entities) {
    await repos.entities.save(entity)
    const settings = {
      enabledRails: RAIL_IDS.filter(rail => rail !== 'ASSISTED'),
    }
    await db.paymentSettings.upsert({
      where: { tenantId_entityId: { tenantId, entityId: entity.id } },
      create: { tenantId, entityId: entity.id, ...settings },
      update: settings,
    })
  }
  console.log(`Seeded tenant ${tenantId} with ${entities.length} entities.`)
}

seed().finally(() => db.$disconnect())
