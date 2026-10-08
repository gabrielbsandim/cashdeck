import { PrismaClient } from '@prisma/client'
import { withConnectRetry } from '@/database/connect-retry'
import { withNormalizedErrors } from '@/database/normalizing-adapter'
import { createRuntimeAdapter } from '@/database/runtime-adapter'

const globalForPrisma = globalThis as unknown as { prisma?: PrismaClient }

// Retry wraps normalization so the value it matches on is already an Error.
export function createPrismaClient(connectionString: string): PrismaClient {
  const adapter = withConnectRetry(
    withNormalizedErrors(createRuntimeAdapter(connectionString)),
  )
  return new PrismaClient({
    adapter,
    log:
      process.env.NODE_ENV === 'development'
        ? ['query', 'error', 'warn']
        : ['error'],
  })
}

export function getPrismaClient(connectionString: string): PrismaClient {
  const client = globalForPrisma.prisma ?? createPrismaClient(connectionString)
  if (process.env.NODE_ENV !== 'production') {
    globalForPrisma.prisma = client
  }
  return client
}
