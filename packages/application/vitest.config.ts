import { fileURLToPath } from 'node:url'
import { defineConfig, mergeConfig } from 'vitest/config'
import { createVitestConfig } from '@cashdeck/config/vitest/base'

export default mergeConfig(
  defineConfig(
    createVitestConfig({
      environment: 'node',
      coverageExclude: ['src/**/*.test-helpers.ts'],
      threshold: { lines: 100, functions: 100, branches: 100, statements: 100 },
    }),
  ),
  defineConfig({
    resolve: {
      alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) },
    },
  }),
)
