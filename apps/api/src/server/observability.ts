import * as Sentry from '@sentry/nextjs'

export function safeLogError(error: unknown): string {
  if (error instanceof Error) {
    return `${error.constructor.name}: ${error.message}`
  }
  return typeof error === 'string' ? error : 'non-Error thrown'
}

// Sentry stays a no-op until instrumentation initialises it with a DSN.
export function reportError(error: unknown, scope: string): void {
  console.error(`[${scope}] ${safeLogError(error)}`)
  Sentry.captureException(error, { tags: { scope } })
}
