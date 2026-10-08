import type { ViteUserConfig } from 'vitest/config'

type CoverageThreshold = {
  lines: number
  functions: number
  branches: number
  statements: number
}

const DEFAULT_THRESHOLD: CoverageThreshold = {
  lines: 95,
  functions: 95,
  branches: 95,
  statements: 95,
}

type CreateVitestConfigOptions = {
  environment?: 'node' | 'jsdom'
  setupFiles?: string[]
  include?: string[]
  coverageInclude?: string[]
  coverageExclude?: string[]
  threshold?: Partial<CoverageThreshold>
}

export function createVitestConfig(
  options: CreateVitestConfigOptions = {},
): ViteUserConfig {
  const {
    environment = 'node',
    setupFiles = [],
    include = ['src/**/*.test.ts'],
    coverageInclude = ['src/**/*.ts'],
    coverageExclude = [],
    threshold = {},
  } = options

  return {
    test: {
      globals: true,
      environment,
      setupFiles,
      include,
      pool: 'forks',
      coverage: {
        provider: 'v8',
        reporter: ['text', 'html', 'lcov'],
        // Without this a red run skips the report and every threshold with it.
        reportOnFailure: true,
        include: coverageInclude,
        exclude: [
          'src/**/*.test.ts',
          'src/**/index.ts',
          'src/**/*.types.ts',
          'src/**/*.d.ts',
          ...coverageExclude,
        ],
        thresholds: { ...DEFAULT_THRESHOLD, ...threshold },
      },
    },
  }
}
