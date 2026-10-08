import { PrismaNeon } from '@prisma/adapter-neon'
import { PrismaPg } from '@prisma/adapter-pg'
import { neonConfig } from '@neondatabase/serverless'

import { isNeonConnectionString } from '@/database/connection-string'

// Plain queries go over HTTP so a failure arrives as a real NeonDbError; the
// flag is process wide, so it is set only on the Neon branch.
function configureNeonTransport(): void {
  neonConfig.poolQueryViaFetch = true
}

export function createRuntimeAdapter(
  connectionString: string,
): PrismaNeon | PrismaPg {
  if (!isNeonConnectionString(connectionString)) {
    return new PrismaPg({ connectionString })
  }

  configureNeonTransport()
  return new PrismaNeon({ connectionString })
}
