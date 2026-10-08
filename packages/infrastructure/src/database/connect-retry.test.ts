import { describe, it, expect, vi } from 'vitest'
import type {
  SqlDriverAdapter,
  SqlDriverAdapterFactory,
  SqlResultSet,
  Transaction,
} from '@prisma/driver-adapter-utils'

import {
  isConnectPermitError,
  withConnectRetry,
} from '@/database/connect-retry'

const RESULT_SET: SqlResultSet = {
  columnNames: ['id'],
  columnTypes: [],
  rows: [['work-1']],
}

const QUERY = { sql: 'SELECT 1', args: [], argTypes: [] }

const PERMIT_MESSAGE =
  'Server error (HTTP status 500): {"message":"Failed to acquire permit to ' +
  'connect to the database. Too many database connection attempts are ' +
  'currently ongoing.","code":"","neon:retryable":false}'

function permitError(): Error {
  return new Error(PERMIT_MESSAGE)
}

function buildTransaction(overrides: Partial<Transaction> = {}): Transaction {
  return {
    provider: 'postgres',
    adapterName: 'test',
    options: { usePhantomQuery: false },
    queryRaw: vi.fn().mockResolvedValue(RESULT_SET),
    executeRaw: vi.fn().mockResolvedValue(1),
    commit: vi.fn().mockResolvedValue(undefined),
    rollback: vi.fn().mockResolvedValue(undefined),
    ...overrides,
  }
}

function buildAdapter(
  overrides: Partial<SqlDriverAdapter> = {},
): SqlDriverAdapter {
  return {
    provider: 'postgres',
    adapterName: 'test',
    queryRaw: vi.fn().mockResolvedValue(RESULT_SET),
    executeRaw: vi.fn().mockResolvedValue(1),
    executeScript: vi.fn().mockResolvedValue(undefined),
    startTransaction: vi.fn().mockResolvedValue(buildTransaction()),
    dispose: vi.fn().mockResolvedValue(undefined),
    ...overrides,
  }
}

function buildFactory(adapter: SqlDriverAdapter): SqlDriverAdapterFactory {
  return {
    provider: 'postgres',
    adapterName: 'test',
    connect: vi.fn().mockResolvedValue(adapter),
  }
}

function fakeSleep() {
  const delays: number[] = []
  const sleep = vi.fn((ms: number) => {
    delays.push(ms)
    return Promise.resolve()
  })
  return { sleep, delays }
}

describe('isConnectPermitError', () => {
  it('matches both sentences of the proxy refusal', () => {
    expect(
      isConnectPermitError(
        new Error('Failed to acquire permit to connect to the database.'),
      ),
    ).toBe(true)
    expect(
      isConnectPermitError(
        new Error(
          'Too many database connection attempts are currently ongoing.',
        ),
      ),
    ).toBe(true)
    expect(isConnectPermitError(permitError())).toBe(true)
  })

  it('does not match an ordinary database error', () => {
    expect(
      isConnectPermitError(
        new Error('duplicate key value violates unique constraint'),
      ),
    ).toBe(false)
    expect(isConnectPermitError(new Error('connection reset'))).toBe(false)
  })

  it('does not throw on a non-Error value', () => {
    expect(isConnectPermitError(undefined)).toBe(false)
    expect(isConnectPermitError({ message: 'nope' })).toBe(false)
  })
})

describe('withConnectRetry', () => {
  it('keeps the factory identity Prisma reads', () => {
    const factory = withConnectRetry(buildFactory(buildAdapter()))

    expect(factory.provider).toBe('postgres')
    expect(factory.adapterName).toBe('test')
  })

  it('passes results through untouched on the happy path', async () => {
    const { sleep } = fakeSleep()
    const adapter = await withConnectRetry(buildFactory(buildAdapter()), {
      sleep,
    }).connect()

    await expect(adapter.queryRaw(QUERY)).resolves.toEqual(RESULT_SET)
    await expect(adapter.executeRaw(QUERY)).resolves.toBe(1)
    expect(sleep).not.toHaveBeenCalled()
  })

  it('retries a permit failure and succeeds when the compute wakes', async () => {
    const queryRaw = vi
      .fn()
      .mockRejectedValueOnce(permitError())
      .mockRejectedValueOnce(permitError())
      .mockResolvedValue(RESULT_SET)
    const { sleep, delays } = fakeSleep()

    const adapter = await withConnectRetry(
      buildFactory(buildAdapter({ queryRaw })),
      { sleep },
    ).connect()

    await expect(adapter.queryRaw(QUERY)).resolves.toEqual(RESULT_SET)
    expect(queryRaw).toHaveBeenCalledTimes(3)
    expect(delays).toEqual([250, 500])
  })

  it('gives up after maxRetries and throws the permit error', async () => {
    const queryRaw = vi.fn().mockRejectedValue(permitError())
    const { sleep } = fakeSleep()

    const adapter = await withConnectRetry(
      buildFactory(buildAdapter({ queryRaw })),
      { sleep, maxRetries: 3 },
    ).connect()

    await expect(adapter.queryRaw(QUERY)).rejects.toThrow(
      /Failed to acquire permit/,
    )
    expect(queryRaw).toHaveBeenCalledTimes(4)
  })

  it('does not retry a non-permit write error', async () => {
    const executeRaw = vi
      .fn()
      .mockRejectedValue(
        new Error('duplicate key value violates unique constraint'),
      )
    const { sleep } = fakeSleep()

    const adapter = await withConnectRetry(
      buildFactory(buildAdapter({ executeRaw })),
      { sleep },
    ).connect()

    await expect(adapter.executeRaw(QUERY)).rejects.toThrow(/unique constraint/)
    expect(executeRaw).toHaveBeenCalledTimes(1)
    expect(sleep).not.toHaveBeenCalled()
  })

  it('retries a permit failure on an autocommit executeRaw', async () => {
    const executeRaw = vi
      .fn()
      .mockRejectedValueOnce(permitError())
      .mockResolvedValue(1)
    const { sleep } = fakeSleep()

    const adapter = await withConnectRetry(
      buildFactory(buildAdapter({ executeRaw })),
      { sleep },
    ).connect()

    await expect(adapter.executeRaw(QUERY)).resolves.toBe(1)
    expect(executeRaw).toHaveBeenCalledTimes(2)
  })

  it('retries a permit failure while opening a transaction', async () => {
    const startTransaction = vi
      .fn()
      .mockRejectedValueOnce(permitError())
      .mockResolvedValue(buildTransaction())
    const { sleep } = fakeSleep()

    const adapter = await withConnectRetry(
      buildFactory(buildAdapter({ startTransaction })),
      { sleep },
    ).connect()

    await expect(adapter.startTransaction()).resolves.toBeDefined()
    expect(startTransaction).toHaveBeenCalledTimes(2)
  })

  it('retries a permit failure while connecting', async () => {
    const connect = vi
      .fn()
      .mockRejectedValueOnce(permitError())
      .mockResolvedValue(buildAdapter())
    const { sleep } = fakeSleep()

    const factory = withConnectRetry(
      { provider: 'postgres', adapterName: 'test', connect },
      { sleep },
    )

    await expect(factory.connect()).resolves.toBeDefined()
    expect(connect).toHaveBeenCalledTimes(2)
  })

  it('never retries a call inside an open transaction', async () => {
    const commit = vi.fn().mockRejectedValue(permitError())
    const { sleep } = fakeSleep()

    const adapter = await withConnectRetry(
      buildFactory(
        buildAdapter({
          startTransaction: vi
            .fn()
            .mockResolvedValue(buildTransaction({ commit })),
        }),
      ),
      { sleep },
    ).connect()
    const transaction = await adapter.startTransaction()

    await expect(transaction.commit()).rejects.toThrow(
      /Failed to acquire permit/,
    )
    expect(commit).toHaveBeenCalledTimes(1)
    expect(sleep).not.toHaveBeenCalled()
  })

  it('does not retry dispose', async () => {
    const dispose = vi.fn().mockRejectedValue(permitError())
    const { sleep } = fakeSleep()

    const adapter = await withConnectRetry(
      buildFactory(buildAdapter({ dispose })),
      { sleep },
    ).connect()

    await expect(adapter.dispose()).rejects.toThrow()
    expect(dispose).toHaveBeenCalledTimes(1)
  })

  it('leaves an unimplemented optional method absent', async () => {
    const adapter = await withConnectRetry(
      buildFactory(buildAdapter()),
    ).connect()

    expect(adapter.getConnectionInfo).toBeUndefined()
  })

  it('delegates getConnectionInfo when the driver has it', async () => {
    const getConnectionInfo = vi.fn().mockReturnValue({ schemaName: 'public' })
    const adapter = await withConnectRetry(
      buildFactory(buildAdapter({ getConnectionInfo })),
    ).connect()

    expect(adapter.getConnectionInfo?.()).toEqual({ schemaName: 'public' })
  })
})
