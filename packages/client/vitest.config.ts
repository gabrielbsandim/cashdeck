import { fileURLToPath } from 'node:url'
import { defineConfig, mergeConfig } from 'vitest/config'
import { createVitestConfig } from '@cashdeck/config/vitest/base'

export default mergeConfig(
  defineConfig(
    createVitestConfig({
      environment: 'node',
      coverageExclude: ['src/generated/**'],
    }),
  ),
  defineConfig({
    resolve: {
      alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) },
    },
  }),
)
