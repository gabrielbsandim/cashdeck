import type {
  ConnectionInfo,
  IsolationLevel,
  SqlDriverAdapter,
  SqlDriverAdapterFactory,
  SqlQuery,
  SqlResultSet,
  Transaction,
} from '@prisma/driver-adapter-utils'

import { toError } from '@/database/thrown-value'

async function normalized<TResult>(
  run: () => Promise<TResult>,
): Promise<TResult> {
  try {
    return await run()
  } catch (error) {
    throw toError(error)
  }
}

// The Neon socket can throw a raw ErrorEvent, which frameworks flatten to
// "[object ErrorEvent]"; the adapter is the last place it can become an Error.
export function withNormalizedErrors(
  factory: SqlDriverAdapterFactory,
): SqlDriverAdapterFactory {
  return {
    provider: factory.provider,
    adapterName: factory.adapterName,
    connect: () => normalized(async () => wrapAdapter(await factory.connect())),
  }
}

function wrapAdapter(adapter: SqlDriverAdapter): SqlDriverAdapter {
  const wrapped: SqlDriverAdapter = {
    provider: adapter.provider,
    adapterName: adapter.adapterName,
    queryRaw: (params: SqlQuery): Promise<SqlResultSet> =>
      normalized(() => adapter.queryRaw(params)),
    executeRaw: (params: SqlQuery): Promise<number> =>
      normalized(() => adapter.executeRaw(params)),
    executeScript: (script: string): Promise<void> =>
      normalized(() => adapter.executeScript(script)),
    startTransaction: (isolationLevel?: IsolationLevel): Promise<Transaction> =>
      normalized(async () =>
        wrapTransaction(await adapter.startTransaction(isolationLevel)),
      ),
    dispose: (): Promise<void> => normalized(() => adapter.dispose()),
  }

  const { getConnectionInfo } = adapter
  if (getConnectionInfo) {
    wrapped.getConnectionInfo = (): ConnectionInfo =>
      getConnectionInfo.call(adapter)
  }

  return wrapped
}

function wrapTransaction(transaction: Transaction): Transaction {
  const wrapped: Transaction = {
    provider: transaction.provider,
    adapterName: transaction.adapterName,
    options: transaction.options,
    queryRaw: (params: SqlQuery): Promise<SqlResultSet> =>
      normalized(() => transaction.queryRaw(params)),
    executeRaw: (params: SqlQuery): Promise<number> =>
      normalized(() => transaction.executeRaw(params)),
    commit: (): Promise<void> => normalized(() => transaction.commit()),
    rollback: (): Promise<void> => normalized(() => transaction.rollback()),
  }

  const { createSavepoint, rollbackToSavepoint, releaseSavepoint } = transaction

  if (createSavepoint) {
    wrapped.createSavepoint = (name: string): Promise<void> =>
      normalized(() => createSavepoint.call(transaction, name))
  }
  if (rollbackToSavepoint) {
    wrapped.rollbackToSavepoint = (name: string): Promise<void> =>
      normalized(() => rollbackToSavepoint.call(transaction, name))
  }
  if (releaseSavepoint) {
    wrapped.releaseSavepoint = (name: string): Promise<void> =>
      normalized(() => releaseSavepoint.call(transaction, name))
  }

  return wrapped
}
