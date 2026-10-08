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
