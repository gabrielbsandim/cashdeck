import { afterEach, describe, expect, it, vi } from 'vitest'
import { z } from 'zod'
import { InvalidTransitionError, ValidationError } from '@cashdeck/domain'
import {
  AmountRequiredError,
  ConflictError,
  NotFoundError,
  ProviderNotConfiguredError,
  QuotaExceededError,
} from '@cashdeck/application'
import { fail, handleError, ok, okPage, readJson } from '@/server/api/respond'
import { reportError, safeLogError } from '@/server/observability'

async function body(response: Response) {
  return { status: response.status, json: await response.json() }
}

afterEach(() => vi.restoreAllMocks())

describe('respond helpers', () => {
  it('wraps data, pages and errors in the envelope', async () => {
    expect(await body(ok({ a: 1 }, 201))).toEqual({
      status: 201,
      json: { data: { a: 1 } },
    })
    expect(await body(okPage([1], 'c'))).toEqual({
      status: 200,
      json: { data: [1], nextCursor: 'c' },
    })
    expect(await body(fail('X', 'y', 418))).toEqual({
      status: 418,
      json: { error: { code: 'X', message: 'y' } },
    })
  })

  it('maps known errors to status codes', async () => {
    const zod = z.object({ a: z.string() }).safeParse({}).error
    const cases: Array<[unknown, number, string]> = [
      [zod, 422, 'VALIDATION_ERROR'],
      [new ValidationError('bad'), 422, 'VALIDATION_ERROR'],
      [new SyntaxError('json'), 400, 'INVALID_JSON'],
      [new NotFoundError('Bill'), 404, 'NOT_FOUND'],
      [
        new InvalidTransitionError('Bill', 'PAID', 'OPEN'),
        409,
        'INVALID_TRANSITION',
      ],
      [new ProviderNotConfiguredError('Inter'), 503, 'NOT_CONFIGURED'],
      [new ConflictError('busy'), 409, 'CONFLICT'],
      [new QuotaExceededError('used up'), 429, 'RATE_LIMITED'],
      [Object.assign(new Error('dup'), { code: 'P2002' }), 409, 'CONFLICT'],
      [Object.assign(new Error('gone'), { code: 'P2025' }), 404, 'NOT_FOUND'],
    ]
    for (const [error, status, code] of cases) {
      const response = await body(handleError(error))
      expect([response.status, response.json.error.code]).toEqual([
        status,
        code,
      ])
    }
  })

  it('answers AMOUNT_REQUIRED with what the client must prompt for', async () => {
    const response = await body(
      handleError(
        new AmountRequiredError({
          field: 'amountCents',
          kind: 'PIX_QR',
          payee: 'Store',
        }),
      ),
    )
    expect(response).toEqual({
      status: 422,
      json: {
        error: {
          code: 'AMOUNT_REQUIRED',
          message: 'This bill needs an amount.',
          details: { field: 'amountCents', kind: 'PIX_QR', payee: 'Store' },
        },
      },
    })
  })

  it('reports anything else as an internal error', async () => {
    const log = vi.spyOn(console, 'error').mockImplementation(() => undefined)
    const response = await body(
      handleError(Object.assign(new Error('boom'), { code: 'P9999' })),
    )
    expect(response).toEqual({
      status: 500,
      json: {
        error: { code: 'INTERNAL_ERROR', message: 'Something went wrong.' },
      },
    })
    expect(log).toHaveBeenCalledWith('[api] Error: boom')
    handleError(null, 'scope')
    expect(log).toHaveBeenLastCalledWith('[scope] non-Error thrown')
  })

  it('describes thrown values safely', () => {
    expect(safeLogError('text')).toBe('text')
    expect(safeLogError(new TypeError('t'))).toBe('TypeError: t')
    const log = vi.spyOn(console, 'error').mockImplementation(() => undefined)
    reportError(42, 'x')
    expect(log).toHaveBeenCalledWith('[x] non-Error thrown')
  })

  it('reads an empty body as an empty object', async () => {
    expect(await readJson(new Request('http://x', { method: 'POST' }))).toEqual(
      {},
    )
    expect(
      await readJson(
        new Request('http://x', { method: 'POST', body: '{"a":1}' }),
      ),
    ).toEqual({
      a: 1,
    })
  })
})
