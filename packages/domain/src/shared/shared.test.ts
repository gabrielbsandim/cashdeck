import { describe, expect, it } from 'vitest'
import {
  DomainError,
  InvalidTransitionError,
  ValidationError,
} from '@/shared/domain-error'
import { guard } from '@/shared/guard'
import { digitAt, onlyDigits } from '@/shared/digits'

describe('domain errors', () => {
  it('exposes stable codes and names', () => {
    const validation = new ValidationError('boom')
    expect(validation).toBeInstanceOf(DomainError)
    expect(validation.code).toBe('VALIDATION_ERROR')
    expect(validation.name).toBe('ValidationError')

    const transition = new InvalidTransitionError('Bill', 'PAID', 'OPEN')
    expect(transition.code).toBe('INVALID_TRANSITION')
    expect(transition.message).toBe('Bill cannot move from PAID to OPEN.')
  })
})

describe('guard', () => {
  it('trims non empty values and rejects blank ones', () => {
    expect(guard.notEmpty('  a  ', 'Field')).toBe('a')
    expect(() => guard.notEmpty('  ', 'Field')).toThrow(ValidationError)
  })

  it('accepts allowed values and rejects the rest', () => {
    expect(guard.oneOf('a', ['a', 'b'] as const, 'Field')).toBe('a')
    expect(() => guard.oneOf('c', ['a', 'b'] as const, 'Field')).toThrow(
      'Field must be one of a, b.',
    )
  })
})

describe('digits', () => {
  it('strips non digits and reads a digit', () => {
    expect(onlyDigits('12.3-4 5')).toBe('12345')
    expect(digitAt('9876', 2)).toBe(7)
  })
})
