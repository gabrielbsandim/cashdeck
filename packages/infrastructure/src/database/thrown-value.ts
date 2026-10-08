interface ErrorEventLike {
  message?: unknown
  error?: unknown
  filename?: unknown
}

const MAX_MESSAGE_LENGTH = 300

export interface ThrownValueDescription {
  type: string
  message: string
}

export function describeThrownValue(value: unknown): ThrownValueDescription {
  let type = 'NonError'
  let message: string | undefined

  try {
    type = classify(value)
    message = readMessage(value)
  } catch {
    // A throwing getter: keep whatever was resolved before it.
  }

  return {
    type,
    message: message?.slice(0, MAX_MESSAGE_LENGTH) || `${type} thrown`,
  }
}

export function toError(value: unknown): Error {
  if (value instanceof Error) return value

  const nested = readNestedError(value)
  if (nested) return nested

  const { type, message } = describeThrownValue(value)
  const error = new Error(message, { cause: value })
  error.name = type

  return error
}

const OPAQUE_MESSAGE = /^\[object (\w+)\]$/

export function readOpaqueTag(value: unknown): string | undefined {
  if (!(value instanceof Error)) return undefined

  return OPAQUE_MESSAGE.exec(value.message)?.[1]
}

function classify(value: unknown): string {
  if (value instanceof Error) return value.name || 'Error'

  return Object.prototype.toString.call(value).slice(8, -1)
}

function readMessage(value: unknown): string | undefined {
  if (typeof value === 'string') return value
  if (value === null || typeof value !== 'object') return String(value)

  const candidate = value as ErrorEventLike

  if (typeof candidate.message === 'string' && candidate.message) {
    return candidate.message
  }

  const nested = readNestedError(value)
  if (nested?.message) return nested.message

  if (typeof candidate.filename === 'string' && candidate.filename) {
    return `thrown at ${candidate.filename}`
  }

  return serializeProperties(value)
}

function readNestedError(value: unknown): Error | undefined {
  if (value === null || typeof value !== 'object') return undefined

  try {
    const nested = (value as ErrorEventLike).error
    return nested instanceof Error ? nested : undefined
  } catch {
    return undefined
  }
}

function serializeProperties(value: object): string | undefined {
  try {
    const serialized = JSON.stringify(value)
    return serialized && serialized !== '{}' ? serialized : undefined
  } catch {
    return undefined
  }
}
