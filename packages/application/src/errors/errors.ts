export class NotFoundError extends Error {
  readonly code = 'NOT_FOUND'

  constructor(resource: string) {
    super(`${resource} was not found.`)
    this.name = 'NotFoundError'
  }
}

export class ProviderNotConfiguredError extends Error {
  readonly code = 'NOT_CONFIGURED'

  constructor(readonly provider: string) {
    super(`${provider} is not configured.`)
    this.name = 'ProviderNotConfiguredError'
  }
}

export class ProviderError extends Error {
  readonly code = 'PROVIDER_ERROR'

  constructor(
    readonly provider: string,
    message: string,
  ) {
    super(`${provider}: ${message}`)
    this.name = 'ProviderError'
  }
}

export class NotConfiguredSource extends ProviderNotConfiguredError {
  constructor(source: string) {
    super(`The ${source} bill source`)
  }
}
