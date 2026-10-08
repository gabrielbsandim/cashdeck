import js from '@eslint/js'
import tseslint from 'typescript-eslint'

export default tseslint.config(
  {
    ignores: [
      '**/dist/**',
      '**/.next/**',
      '**/coverage/**',
      '**/node_modules/**',
      '**/src/generated/**',
      '**/next-env.d.ts',
      // tsup and vitest write a temporary module next to their config while
      // loading it; a parallel lint would otherwise fail when it vanishes.
      '**/tsup.config.bundled_*.mjs',
      '**/*.timestamp-*.mjs',
    ],
  },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    rules: {
      '@typescript-eslint/no-unused-vars': [
        'error',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_' },
      ],
      '@typescript-eslint/consistent-type-imports': [
        'error',
        { prefer: 'type-imports', fixStyle: 'inline-type-imports' },
      ],
      '@typescript-eslint/no-explicit-any': 'error',
      'no-else-return': ['error', { allowElseIf: false }],
      'no-nested-ternary': 'error',
      'max-depth': ['error', 2],
    },
  },
)
