import { fileURLToPath } from 'node:url'
import { defineConfig, mergeConfig } from 'vitest/config'
import { createVitestConfig } from '@cashdeck/config/vitest/base'

export default mergeConfig(
  defineConfig(
    createVitestConfig({
      environment: 'node',
      coverageExclude: ['src/database/client.ts'],
    }),
  ),
  defineConfig({
    resolve: {
      alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) },
    },
  }),
)
