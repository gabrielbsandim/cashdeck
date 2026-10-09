import { describe, expect, it } from 'vitest'
import {
  ConflictError,
  NotFoundError,
  ProviderNotConfiguredError,
  QuotaExceededError,
  UnauthorizedError,
} from '@/errors/errors'
import { LlmProviderError } from '@/ports/llm-provider'

describe('application errors', () => {
  it('carry codes and readable messages', () => {
    expect(new NotFoundError('Bill')).toMatchObject({
      code: 'NOT_FOUND',
      message: 'Bill was not found.',
      name: 'NotFoundError',
    })
    expect(new ProviderNotConfiguredError('Inter')).toMatchObject({
      code: 'NOT_CONFIGURED',
      provider: 'Inter',
    })
    expect(new UnauthorizedError()).toMatchObject({
      code: 'UNAUTHORIZED',
      name: 'UnauthorizedError',
    })
    expect(new UnauthorizedError('Bad signature.').message).toBe(
      'Bad signature.',
    )
    const cause = new Error('x')
    expect(new LlmProviderError('m', 'c', cause)).toMatchObject({
      code: 'c',
      cause,
    })
    expect(new QuotaExceededError('q')).toMatchObject({
      code: 'RATE_LIMITED',
      name: 'QuotaExceededError',
    })
    expect(new ConflictError('c')).toMatchObject({
      code: 'CONFLICT',
      name: 'ConflictError',
    })
  })
})
