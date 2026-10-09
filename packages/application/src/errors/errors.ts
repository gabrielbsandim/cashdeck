import { type BillKind } from '@cashdeck/domain'

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

export type AmountRequiredDetails = {
  field: 'amountCents'
  kind: BillKind
  payee: string | null
}

// The client prompts for the amount and sends the same capture again with it.
export class AmountRequiredError extends Error {
  readonly code = 'AMOUNT_REQUIRED'

  constructor(readonly details: AmountRequiredDetails) {
    super('This bill needs an amount.')
    this.name = 'AmountRequiredError'
  }
}

export class UnauthorizedError extends Error {
  readonly code = 'UNAUTHORIZED'

  constructor(message = 'The request could not be authenticated.') {
    super(message)
    this.name = 'UnauthorizedError'
  }
}
