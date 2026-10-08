import { describe, it, expect, vi } from 'vitest'
import { PrismaNeon } from '@prisma/adapter-neon'
import type {
  SqlDriverAdapter,
  SqlDriverAdapterFactory,
  SqlResultSet,
  Transaction,
} from '@prisma/driver-adapter-utils'

import { withNormalizedErrors } from '@/database/normalizing-adapter'

const RESULT_SET: SqlResultSet = {
  columnNames: ['id'],
  columnTypes: [],
  rows: [['work-1']],
}

const QUERY = { sql: 'SELECT 1', args: [], argTypes: [] }

function errorEvent(message = 'connection reset'): object {
  return {
    get message(): string {
      return message
    },
    get [Symbol.toStringTag](): string {
      return 'ErrorEvent'
    },
  }
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

describe('withNormalizedErrors', () => {
  it('passes results through untouched on the happy path', async () => {
    const adapter = await withNormalizedErrors(
      buildFactory(buildAdapter()),
    ).connect()

    await expect(adapter.queryRaw(QUERY)).resolves.toEqual(RESULT_SET)
    await expect(adapter.executeRaw(QUERY)).resolves.toBe(1)
  })

  it('keeps the factory identity Prisma reads', () => {
    const factory = withNormalizedErrors(buildFactory(buildAdapter()))

    expect(factory.provider).toBe('postgres')
    expect(factory.adapterName).toBe('test')
  })

  it('rethrows an Error unchanged, same instance', async () => {
    const original = new Error('unique constraint violated')
    const adapter = await withNormalizedErrors(
      buildFactory(
        buildAdapter({ queryRaw: vi.fn().mockRejectedValue(original) }),
      ),
    ).connect()

    await expect(adapter.queryRaw(QUERY)).rejects.toBe(original)
  })

  it.each([
    ['queryRaw', (a: SqlDriverAdapter) => a.queryRaw(QUERY)],
    ['executeRaw', (a: SqlDriverAdapter) => a.executeRaw(QUERY)],
    ['executeScript', (a: SqlDriverAdapter) => a.executeScript('SELECT 1')],
    ['dispose', (a: SqlDriverAdapter) => a.dispose()],
  ])('normalises an ErrorEvent thrown by %s', async (method, call) => {
    const adapter = await withNormalizedErrors(
      buildFactory(
        buildAdapter({ [method]: vi.fn().mockRejectedValue(errorEvent()) }),
      ),
    ).connect()

    await expect(call(adapter)).rejects.toThrowError(
      expect.objectContaining({
        name: 'ErrorEvent',
        message: 'connection reset',
      }),
    )
  })

  it('normalises an ErrorEvent thrown while connecting', async () => {
    const factory = withNormalizedErrors({
      provider: 'postgres',
      adapterName: 'test',
      connect: vi.fn().mockRejectedValue(errorEvent('handshake failed')),
    })

    await expect(factory.connect()).rejects.toThrowError(
      expect.objectContaining({ message: 'handshake failed' }),
    )
  })

  it('normalises an ErrorEvent thrown while starting a transaction', async () => {
    const adapter = await withNormalizedErrors(
      buildFactory(
        buildAdapter({
          startTransaction: vi.fn().mockRejectedValue(errorEvent()),
        }),
      ),
    ).connect()

    await expect(adapter.startTransaction()).rejects.toThrowError(
      expect.objectContaining({ name: 'ErrorEvent' }),
    )
  })

  it.each([
    ['queryRaw', (t: Transaction) => t.queryRaw(QUERY)],
    ['executeRaw', (t: Transaction) => t.executeRaw(QUERY)],
    ['commit', (t: Transaction) => t.commit()],
    ['rollback', (t: Transaction) => t.rollback()],
  ])(
    'normalises an ErrorEvent thrown by a transaction %s',
    async (method, call) => {
      const adapter = await withNormalizedErrors(
        buildFactory(
          buildAdapter({
            startTransaction: vi.fn().mockResolvedValue(
              buildTransaction({
                [method]: vi.fn().mockRejectedValue(errorEvent()),
              }),
            ),
          }),
        ),
      ).connect()
      const transaction = await adapter.startTransaction()

      await expect(call(transaction)).rejects.toThrowError(
        expect.objectContaining({ name: 'ErrorEvent' }),
      )
    },
  )

  it('forwards the isolation level it was given', async () => {
    const startTransaction = vi.fn().mockResolvedValue(buildTransaction())
    const adapter = await withNormalizedErrors(
      buildFactory(buildAdapter({ startTransaction })),
    ).connect()

    await adapter.startTransaction('SERIALIZABLE')

    expect(startTransaction).toHaveBeenCalledWith('SERIALIZABLE')
  })

  it('leaves an unimplemented optional method absent', async () => {
    const adapter = await withNormalizedErrors(
      buildFactory(buildAdapter()),
    ).connect()

    expect(adapter.getConnectionInfo).toBeUndefined()

    const transaction = await adapter.startTransaction()
    expect(transaction.createSavepoint).toBeUndefined()
    expect(transaction.rollbackToSavepoint).toBeUndefined()
    expect(transaction.releaseSavepoint).toBeUndefined()
  })

  it('delegates the optional methods that do exist', async () => {
    const getConnectionInfo = vi.fn().mockReturnValue({ schemaName: 'public' })
    const createSavepoint = vi.fn().mockResolvedValue(undefined)
    const rollbackToSavepoint = vi.fn().mockResolvedValue(undefined)
    const releaseSavepoint = vi.fn().mockResolvedValue(undefined)

    const adapter = await withNormalizedErrors(
      buildFactory(
        buildAdapter({
          getConnectionInfo,
          startTransaction: vi.fn().mockResolvedValue(
            buildTransaction({
              createSavepoint,
              rollbackToSavepoint,
              releaseSavepoint,
            }),
          ),
        }),
      ),
    ).connect()

    expect(adapter.getConnectionInfo?.()).toEqual({ schemaName: 'public' })

    const transaction = await adapter.startTransaction()
    await transaction.createSavepoint?.('sp1')
    await transaction.rollbackToSavepoint?.('sp1')
    await transaction.releaseSavepoint?.('sp1')

    expect(createSavepoint).toHaveBeenCalledWith('sp1')
    expect(rollbackToSavepoint).toHaveBeenCalledWith('sp1')
    expect(releaseSavepoint).toHaveBeenCalledWith('sp1')
  })

  it('normalises an ErrorEvent thrown by an optional transaction method', async () => {
    const adapter = await withNormalizedErrors(
      buildFactory(
        buildAdapter({
          startTransaction: vi.fn().mockResolvedValue(
            buildTransaction({
              createSavepoint: vi.fn().mockRejectedValue(errorEvent()),
            }),
          ),
        }),
      ),
    ).connect()
    const transaction = await adapter.startTransaction()

    await expect(transaction.createSavepoint?.('sp1')).rejects.toThrowError(
      expect.objectContaining({ name: 'ErrorEvent' }),
    )
  })
})

describe('the Neon adapter keeps poolQueryViaFetch usable', () => {
  it('registers no pool listener that disables the fetch transport', async () => {
    const adapter = await new PrismaNeon({
      connectionString:
        'postgresql://user:secret@ep-x.us-east-2.aws.neon.tech/cashdeck',
    }).connect()

    expect(adapter.underlyingDriver().hasFetchUnsupportedListeners).toBe(false)
  })
})
