export abstract class DomainError extends Error {
  abstract readonly code: string

  constructor(message: string) {
    super(message)
    this.name = new.target.name
  }
}

export class ValidationError extends DomainError {
  readonly code = 'VALIDATION_ERROR'
}

export class InvalidTransitionError extends DomainError {
  readonly code = 'INVALID_TRANSITION'

  constructor(entity: string, from: string, to: string) {
    super(`${entity} cannot move from ${from} to ${to}.`)
  }
}
