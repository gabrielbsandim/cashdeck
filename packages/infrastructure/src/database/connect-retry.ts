import type {
  ConnectionInfo,
  IsolationLevel,
  SqlDriverAdapter,
  SqlDriverAdapterFactory,
  SqlQuery,
  SqlResultSet,
  Transaction,
} from '@prisma/driver-adapter-utils'

const DEFAULT_MAX_RETRIES = 3
const DEFAULT_BASE_DELAY_MS = 250

export interface ConnectRetryOptions {
  maxRetries?: number
  baseDelayMs?: number
  sleep?: (ms: number) => Promise<void>
}

interface ResolvedOptions {
  maxRetries: number
  baseDelayMs: number
  sleep: (ms: number) => Promise<void>
}

const realSleep = (ms: number): Promise<void> =>
  new Promise(resolve => setTimeout(resolve, ms))

function resolveOptions(options: ConnectRetryOptions): ResolvedOptions {
  return {
    maxRetries: options.maxRetries ?? DEFAULT_MAX_RETRIES,
    baseDelayMs: options.baseDelayMs ?? DEFAULT_BASE_DELAY_MS,
    sleep: options.sleep ?? realSleep,
  }
}

function messageOf(error: unknown): string {
  if (error instanceof Error) {
    return error.message
  }
  return typeof error === 'string' ? error : ''
}

// Neon leaves the fields empty for a 500, so the message is all there is.
export function isConnectPermitError(error: unknown): boolean {
  const lower = messageOf(error).toLowerCase()
  return (
    lower.includes('failed to acquire permit to connect') ||
    lower.includes('too many database connection attempts')
  )
}

async function retryingConnect<TResult>(
  run: () => Promise<TResult>,
  options: ResolvedOptions,
): Promise<TResult> {
  for (let attempt = 0; ; attempt++) {
    const outcome = await run().then(
      value => ({ ok: true as const, value }),
      (error: unknown) => ({ ok: false as const, error }),
    )
    if (outcome.ok) {
      return outcome.value
    }
    if (attempt >= options.maxRetries || !isConnectPermitError(outcome.error)) {
      throw outcome.error
    }
    await options.sleep(options.baseDelayMs * 2 ** attempt)
  }
}

// Only connection attempts are retried: a refused permit proves nothing ran, so
// a retry cannot duplicate a write. Calls inside a transaction are left alone.
export function withConnectRetry(
  factory: SqlDriverAdapterFactory,
  options: ConnectRetryOptions = {},
): SqlDriverAdapterFactory {
  const resolved = resolveOptions(options)
  return {
    provider: factory.provider,
    adapterName: factory.adapterName,
    connect: () =>
      retryingConnect(
        async () => wrapAdapter(await factory.connect(), resolved),
        resolved,
      ),
  }
}

function wrapAdapter(
  adapter: SqlDriverAdapter,
  options: ResolvedOptions,
): SqlDriverAdapter {
  const wrapped: SqlDriverAdapter = {
    provider: adapter.provider,
    adapterName: adapter.adapterName,
    queryRaw: (params: SqlQuery): Promise<SqlResultSet> =>
      retryingConnect(() => adapter.queryRaw(params), options),
    executeRaw: (params: SqlQuery): Promise<number> =>
      retryingConnect(() => adapter.executeRaw(params), options),
    executeScript: (script: string): Promise<void> =>
      retryingConnect(() => adapter.executeScript(script), options),
    startTransaction: (isolationLevel?: IsolationLevel): Promise<Transaction> =>
      retryingConnect(() => adapter.startTransaction(isolationLevel), options),
    dispose: (): Promise<void> => adapter.dispose(),
  }

  const { getConnectionInfo } = adapter
  if (getConnectionInfo) {
    wrapped.getConnectionInfo = (): ConnectionInfo =>
      getConnectionInfo.call(adapter)
  }

  return wrapped
}
