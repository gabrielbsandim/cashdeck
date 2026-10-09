import { fileURLToPath } from 'node:url'
import {
  createFinancialEntity,
  RAIL_IDS,
  type TaxRegime,
} from '@cashdeck/domain'
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

const env = process.env
// Placeholder public test tax ids keep a fresh install bootable; set the real
// ones through these variables or PATCH /api/v1/entities/{id}.
const entities = [
  createFinancialEntity({
    id: 'personal',
    tenantId,
    kind: 'PF',
    name: env.CASHDECK_PF_NAME || 'Personal',
    taxId: env.CASHDECK_PF_TAX_ID || '52998224725',
  }),
  createFinancialEntity({
    id: 'company',
    tenantId,
    kind: 'PJ',
    name: env.CASHDECK_PJ_NAME || 'Company',
    taxId: env.CASHDECK_PJ_TAX_ID || '11222333000181',
    taxRegime: (env.CASHDECK_PJ_TAX_REGIME as TaxRegime) || 'SIMPLES_NACIONAL',
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
    if (await repos.entities.findById(tenantId, entity.id)) {
      continue
    }
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
