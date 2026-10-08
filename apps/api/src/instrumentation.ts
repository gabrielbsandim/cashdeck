import * as Sentry from '@sentry/nextjs'

// Error reporting is opt in: without SENTRY_DSN nothing is initialised and no
// data leaves the deployment.
export async function register(): Promise<void> {
  const dsn = process.env.SENTRY_DSN
  if (!dsn) {
    return
  }
  Sentry.init({ dsn, tracesSampleRate: 0, sendDefaultPii: false })
}

export const onRequestError = Sentry.captureRequestError
