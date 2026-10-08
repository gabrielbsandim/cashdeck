import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vitest/config'

// Integration runs opt in to the repo env file and fall back to the app
// database, so the default unit gate never needs a network.
try {
  process.loadEnvFile(fileURLToPath(new URL('../../.env', import.meta.url)))
} catch {
  // Without an env file the integration suite skips itself.
}
process.env.DATABASE_TEST_URL ??= process.env.DATABASE_URL

export default defineConfig({
  test: {
    environment: 'node',
    include: ['src/**/*.integration.test.ts'],
    testTimeout: 30_000,
    hookTimeout: 30_000,
  },
  resolve: {
    alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) },
  },
})
