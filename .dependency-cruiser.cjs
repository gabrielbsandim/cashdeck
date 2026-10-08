/** @type {import('dependency-cruiser').IConfiguration} */
module.exports = {
  forbidden: [
    {
      name: 'domain-is-pure',
      comment:
        'The domain depends on nothing outside itself, npm packages included.',
      severity: 'error',
      from: { path: '^packages/domain/src' },
      to: {
        pathNot: ['^packages/domain/src'],
        dependencyTypesNot: ['core', 'type-only'],
      },
    },
    {
      name: 'domain-no-node-io',
      severity: 'error',
      from: { path: '^packages/domain/src' },
      to: { dependencyTypes: ['core'] },
    },
    {
      name: 'application-depends-on-domain-only',
      severity: 'error',
      from: { path: '^packages/application/src' },
      to: {
        path: '^(packages/(infrastructure|client|i18n)|apps)/',
      },
    },
    {
      name: 'application-allowed-packages',
      severity: 'error',
      from: { path: '^packages/application/src' },
      to: { dependencyTypes: ['npm'], pathNot: ['node_modules/(zod)/'] },
    },
    {
      name: 'infrastructure-not-into-apps',
      severity: 'error',
      from: { path: '^packages/infrastructure/src' },
      to: { path: '^apps/' },
    },
    {
      name: 'routes-use-the-container',
      comment:
        'Route handlers reach adapters only through the composition root.',
      severity: 'error',
      from: { path: '^apps/api/src/app' },
      to: { path: '^packages/infrastructure/' },
    },
    {
      name: 'no-circular',
      severity: 'error',
      from: {},
      to: { circular: true },
    },
  ],
  options: {
    doNotFollow: { path: 'node_modules' },
    exclude: { path: '(^|/)(dist|coverage|\\.next|generated)/' },
    tsPreCompilationDeps: true,
    tsConfig: { fileName: 'tsconfig.depcruise.json' },
    enhancedResolveOptions: {
      exportsFields: ['exports'],
      conditionNames: ['import', 'types', 'default'],
    },
  },
}
