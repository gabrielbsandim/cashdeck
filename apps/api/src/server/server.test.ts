import { randomBytes } from 'node:crypto'
import { readdirSync, readFileSync } from 'node:fs'
import { dirname, join, relative } from 'node:path'
import { fileURLToPath } from 'node:url'
import { afterEach, describe, expect, it, vi } from 'vitest'
import {
  EnvelopeSecretVault,
  PrismaBillRepository,
} from '@cashdeck/infrastructure'
import {
  buildContainer,
  getContainer,
  resetContainer,
} from '@/server/container'
import { readEnv } from '@/server/env'
import { runCronJob } from '@/server/api/cron'
import { buildOpenApiDocument } from '@/server/api/openapi'
import { resolveTenant } from '@/server/api/tenant'

afterEach(() => {
  vi.unstubAllEnvs()
  resetContainer()
})

describe('env and tenant', () => {
  it('defaults the tenant', () => {
    expect(readEnv({}).CASHDECK_TENANT_ID).toBe('local')
    vi.stubEnv('CASHDECK_TENANT_ID', 'home')
    expect(resolveTenant(new Request('http://x'))).toBe('home')
  })
})

describe('container', () => {
  it('memoises the container and uses the envelope vault when keyed', async () => {
    expect(getContainer()).toBe(getContainer())
    const keyed = buildContainer(
      readEnv({ CASHDECK_MASTER_KEY: randomBytes(32).toString('base64') }),
    )
    expect(keyed.vault).toBeInstanceOf(EnvelopeSecretVault)
    expect(keyed.llm.name).toBe('fake')
  })

  it('switches to the Prisma repositories when a database is configured', () => {
    const offline = buildContainer(readEnv({}))
    expect(offline.deps.bills).not.toBeInstanceOf(PrismaBillRepository)
    const online = buildContainer(
      readEnv({ DATABASE_URL: 'postgresql://user:pass@localhost:5432/test' }),
    )
    expect(online.deps.bills).toBeInstanceOf(PrismaBillRepository)
  })

  it('refuses to keep data in memory on a deployed server', () => {
    expect(() => buildContainer(readEnv({ VERCEL_ENV: 'production' }))).toThrow(
      'DATABASE_URL is required',
    )
  })
})

describe('runCronJob', () => {
  const request = (auth?: string) =>
    new Request('http://x/api/cron/job', {
      headers: auth ? { authorization: auth } : {},
    })

  it('refuses calls without the configured secret', async () => {
    expect(
      (await runCronJob(request('Bearer s'), 'job', async () => ({}))).status,
    ).toBe(401)
    vi.stubEnv('CRON_SECRET', 'secret')
    expect(
      (await runCronJob(request('Bearer wrong!'), 'job', async () => ({})))
        .status,
    ).toBe(401)
    expect((await runCronJob(request(), 'job', async () => ({}))).status).toBe(
      401,
    )
  })

  it('runs the job and reports failures', async () => {
    vi.stubEnv('CRON_SECRET', 'secret')
    const done = await runCronJob(
      request('Bearer secret'),
      'job',
      async () => ({ sent: 2 }),
    )
    expect((await done.json()).data).toMatchObject({ source: 'job', sent: 2 })
    vi.spyOn(console, 'error').mockImplementation(() => undefined)
    const failed = await runCronJob(
      request('Bearer secret'),
      'job',
      async () => {
        throw new Error('boom')
      },
    )
    expect(failed.status).toBe(500)
  })
})

const API = fileURLToPath(new URL('../app/api', import.meta.url))
const V1 = join(API, 'v1')

function routeFiles(dir: string): string[] {
  return readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
    const path = join(dir, entry.name)
    if (entry.isDirectory()) {
      return routeFiles(path)
    }
    return entry.name === 'route.ts' ? [path] : []
  })
}

describe('openapi', () => {
  it('describes every v1 route and method', () => {
    const document = buildOpenApiDocument()
    const operations = routeFiles(V1)
      .filter(file => !file.includes('/openapi/'))
      .flatMap(file => {
        const path = relative(V1, dirname(file)).replace(/\[(\w+)\]/g, '{$1}')
        const source = readFileSync(file, 'utf8')
        return [
          ...source.matchAll(
            /export (?:const|function|async function) (GET|POST|PUT|PATCH|DELETE)\b/g,
          ),
        ].map(([, method]) => `${String(method).toLowerCase()} /${path}`)
      })
      .sort()
    const documented = Object.entries(document.paths)
      .flatMap(([path, methods]) =>
        Object.keys(methods).map(method => `${method} ${path}`),
      )
      .sort()
    expect(documented).toEqual(operations)
    expect(operations.length).toBeGreaterThan(50)
  })
})

// Routes outside the bearer guard, each with its own proof of origin.
const UNGUARDED: Record<string, RegExp> = {
  'v1/health': /export function GET/,
  'v1/openapi': /export function GET/,
  'v1/capture/mailboxes/oauth/callback': /verifyState/,
}

describe('route guards', () => {
  it('guards every route with the token, a cron secret or a webhook proof', () => {
    const unguarded = routeFiles(API).filter(file => {
      const path = relative(API, dirname(file))
      const source = readFileSync(file, 'utf8')
      if (path.startsWith('cron/')) {
        return !source.includes('runCronJob(')
      }
      if (path.startsWith('webhooks/')) {
        return !source.includes('webhookRoute(')
      }
      const exception = UNGUARDED[path]
      const guard = exception ?? /\broute(<[^>]*>)?\(/
      return !guard.test(source)
    })
    expect(unguarded).toEqual([])
  })
})
