import base from '@cashdeck/config/eslint/base'

export default [
  ...base,
  {
    ignores: ['apps/**', 'packages/**', 'design/**'],
  },
  {
    files: ['**/*.cjs'],
    languageOptions: {
      sourceType: 'commonjs',
      globals: {
        module: 'writable',
        require: 'readonly',
        __dirname: 'readonly',
      },
    },
  },
]
