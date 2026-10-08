import { describe, it, expect } from 'vitest'

import {
  describeThrownValue,
  readOpaqueTag,
  toError,
} from '@/database/thrown-value'

class ErrorEventStub {
  #message: string
  #filename: string | undefined
  #error: unknown

  constructor(message = '', filename?: string, error?: unknown) {
    this.#message = message
    this.#filename = filename
    this.#error = error
  }

  get type(): string {
    return 'error'
  }

  get message(): string {
    return this.#message
  }

  get filename(): string | undefined {
    return this.#filename
  }

  get error(): unknown {
    return this.#error
  }

  get [Symbol.toStringTag](): string {
    return 'ErrorEvent'
  }
}

describe('the shape this module exists for', () => {
  it('reproduces the shape Next.js chokes on', () => {
    const event = new ErrorEventStub('connection reset')

    expect(Object.prototype.toString.call(event)).toBe('[object ErrorEvent]')
    expect('name' in event).toBe(false)
    expect('message' in event).toBe(true)
    expect(`${event}`).toBe('[object ErrorEvent]')
  })

  it('produces a value Next.js will forward instead of stringifying', () => {
    const normalized = toError(new ErrorEventStub('connection reset'))

    const survivesGetProperError =
      typeof normalized === 'object' &&
      normalized !== null &&
      'name' in normalized &&
      'message' in normalized

    expect(survivesGetProperError).toBe(true)
    expect(`${normalized}`).not.toContain('[object')
    expect(`${normalized}`).toBe('ErrorEvent: connection reset')
  })
})

describe('toError', () => {
  it('returns an Error untouched, stack included', () => {
    const original = new Error('boom')

    expect(toError(original)).toBe(original)
    expect(toError(original).stack).toBe(original.stack)
  })

  it('keeps the subclass of an Error it passes through', () => {
    class DriverAdapterError extends Error {}
    const original = new DriverAdapterError('unique constraint')

    expect(toError(original)).toBe(original)
  })

  it('rebuilds an ErrorEvent into an Error named after its class', () => {
    const event = new ErrorEventStub('connection reset by peer')
    const normalized = toError(event)

    expect(normalized).toBeInstanceOf(Error)
    expect(normalized.name).toBe('ErrorEvent')
    expect(normalized.message).toBe('connection reset by peer')
    expect(normalized.stack).toBeTruthy()
  })

  it('keeps the original as the cause', () => {
    const event = new ErrorEventStub('connection reset')

    expect(toError(event).cause).toBe(event)
  })

  it('unwraps the real Error an ErrorEvent carries, keeping its stack', () => {
    const underlying = new Error('ECONNRESET')
    const event = new ErrorEventStub('', undefined, underlying)

    const normalized = toError(event)

    expect(normalized).toBe(underlying)
    expect(normalized.stack).toBe(underlying.stack)
  })

  it('survives an ErrorEvent whose error getter throws', () => {
    const hostile = {
      get error(): never {
        throw new Error('nope')
      },
      get [Symbol.toStringTag](): string {
        return 'ErrorEvent'
      },
    }

    expect(() => toError(hostile)).not.toThrow()
    expect(toError(hostile).name).toBe('ErrorEvent')
  })

  it('turns a thrown string into an Error carrying it', () => {
    const normalized = toError('went wrong')

    expect(normalized).toBeInstanceOf(Error)
    expect(normalized.name).toBe('String')
    expect(normalized.message).toBe('went wrong')
    expect(normalized.cause).toBe('went wrong')
  })

  it('reports what a bare object was carrying', () => {
    const normalized = toError({ code: 7, detail: 'no such table' })

    expect(normalized.name).toBe('Object')
    expect(normalized.message).toBe('{"code":7,"detail":"no such table"}')
  })

  it('falls back to the endpoint when an ErrorEvent has no message', () => {
    const event = new ErrorEventStub('', 'wss://ep-x.aws.neon.tech/v2')

    expect(toError(event).message).toBe('thrown at wss://ep-x.aws.neon.tech/v2')
  })

  it('still names the class when an ErrorEvent carries nothing at all', () => {
    expect(toError(new ErrorEventStub()).message).toBe('ErrorEvent thrown')
  })
})

describe('readOpaqueTag', () => {
  it.each([
    ['[object ErrorEvent]', 'ErrorEvent'],
    ['[object Object]', 'Object'],
    ['[object Null]', 'Null'],
  ])('reads the class Next.js discarded from %j', (message, tag) => {
    expect(readOpaqueTag(new Error(message))).toBe(tag)
  })

  it.each([
    ['an ordinary message', 'connection reset'],
    ['a message that merely contains the pattern', 'saw [object Foo] once'],
    ['an empty message', ''],
    ['a tag with no class', '[object ]'],
  ])('returns nothing for %s', (_label, message) => {
    expect(readOpaqueTag(new Error(message))).toBeUndefined()
  })

  it.each([
    ['a string', 'boom'],
    ['an object', { message: '[object Foo]' }],
  ])('returns nothing for %s that is not an Error', (_label, value) => {
    expect(readOpaqueTag(value)).toBeUndefined()
  })
})

describe('describeThrownValue', () => {
  it('names an Error by its own name', () => {
    expect(describeThrownValue(new TypeError('bad'))).toEqual({
      type: 'TypeError',
      message: 'bad',
    })
  })

  it.each([
    ['null', null, 'Null', 'null'],
    ['undefined', undefined, 'Undefined', 'undefined'],
    ['a number', 7, 'Number', '7'],
    ['a boolean', false, 'Boolean', 'false'],
  ])('describes %s', (_label, value, type, message) => {
    expect(describeThrownValue(value)).toEqual({ type, message })
  })

  it('caps the message so a payload cannot become the issue title', () => {
    const { message } = describeThrownValue('x'.repeat(1_000))

    expect(message).toHaveLength(300)
  })

  it('survives a getter that throws', () => {
    const hostile = {
      get message(): string {
        throw new Error('nope')
      },
    }

    expect(() => describeThrownValue(hostile)).not.toThrow()
    expect(describeThrownValue(hostile).message).toBeTruthy()
  })

  it('survives a circular object JSON cannot serialise', () => {
    const circular: Record<string, unknown> = { code: 7 }
    circular.self = circular

    expect(describeThrownValue(circular)).toEqual({
      type: 'Object',
      message: 'Object thrown',
    })
  })

  it('survives a BigInt JSON cannot serialise', () => {
    expect(describeThrownValue({ size: BigInt(1) }).message).toBe(
      'Object thrown',
    )
  })

  it('does not report an empty message for an object serialising to {}', () => {
    expect(describeThrownValue(Object.create(null))).toEqual({
      type: 'Object',
      message: 'Object thrown',
    })
  })
})
