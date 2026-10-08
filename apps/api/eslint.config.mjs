import nextVitals from 'eslint-config-next/core-web-vitals'
import nextTs from 'eslint-config-next/typescript'

const config = [
  {
    ignores: ['.next/**', 'coverage/**', 'node_modules/**', 'next-env.d.ts'],
  },
  ...nextVitals,
  ...nextTs,
  {
    rules: {
      '@typescript-eslint/consistent-type-imports': [
        'error',
        { prefer: 'type-imports', fixStyle: 'inline-type-imports' },
      ],
      '@typescript-eslint/no-unused-vars': [
        'error',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_' },
      ],
      'no-else-return': ['error', { allowElseIf: false }],
      'no-nested-ternary': 'error',
      'max-depth': ['error', 2],
    },
  },
]

export default config
