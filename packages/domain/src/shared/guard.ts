import { ValidationError } from '@/shared/domain-error'

export const guard = {
  notEmpty(value: string, field: string): string {
    const trimmed = value.trim()
    if (trimmed.length === 0) {
      throw new ValidationError(`${field} must not be empty.`)
    }
    return trimmed
  },

  oneOf<T extends string>(
    value: string,
    allowed: readonly T[],
    field: string,
  ): T {
    if (!(allowed as readonly string[]).includes(value)) {
      throw new ValidationError(
        `${field} must be one of ${allowed.join(', ')}.`,
      )
    }
    return value as T
  },
}
