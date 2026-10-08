import { defineConfig } from 'prisma/config'

try {
  process.loadEnvFile('../../.env')
} catch {
  // No .env file: variables come from the environment (CI, hosting).
}

// Migrations take a session advisory lock, which leaks on a pooled connection;
// prefer the direct URL, or derive Neon's by dropping the pooler host segment.
function directDatabaseUrl(): string {
  const url =
    process.env.DATABASE_URL_UNPOOLED ?? process.env.DATABASE_URL ?? ''
  return url.replace('-pooler.', '.')
}

export default defineConfig({
  schema: 'prisma/schema.prisma',
  datasource: { url: directDatabaseUrl() },
})
