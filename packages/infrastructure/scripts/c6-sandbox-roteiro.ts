import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { homedir, tmpdir } from 'node:os'
import { join } from 'node:path'
import { mtlsTransport } from '../src/http/mtls-transport'
import {
  type Call,
  safeJson,
  send,
  type Transport,
} from '../src/http/transport'
import { C6_HOSTS, C6_PARTNER_HEADERS } from '../src/rails/c6-client'

// The C6 Developers roteiro asks for each status and body as answered by the
// sandbox, so this keeps them raw and masks only the token and the secret.

type Outcome = {
  id: string
  title: string
  expected: number
  request: { method: string; url: string; body: unknown }
  status: number | null
  body: unknown
  error: string | null
}

type Item = { id?: string; status?: string }

const HOST = C6_HOSTS.sandbox
const PAYMENTS = `${HOST}/v1/schedule_payments`
const STATEMENT = `${HOST}/v1/statement`

// Sample barcodes from the schedule-payments spec, so the decode has boletos
// to read even when the sandbox DDA is empty.
const SPEC_BARCODES = [
  { content: '33695969000000123450000003048720009224128213', amount: 123.45 },
  { content: '33691991800000005000000003048720009765974213', amount: 50 },
]

function option(name: string, fallback: string): string {
  const index = process.argv.indexOf(`--${name}`)
  return index === -1 ? fallback : (process.argv[index + 1] ?? fallback)
}

function readSecret(dir: string, file: string): string {
  return readFileSync(join(dir, file), 'utf8').trim()
}

function maskToken(body: unknown): unknown {
  if (!body || typeof body !== 'object' || !('access_token' in body)) {
    return body
  }
  const token = String((body as { access_token: unknown }).access_token)
  return { ...body, access_token: `${token.slice(0, 8)}...(masked)` }
}

function isoDate(date: Date): string {
  return date.toISOString().slice(0, 10)
}

class Roteiro {
  readonly outcomes: Outcome[] = []
  private token = ''

  constructor(private readonly transport: Transport) {}

  async run(
    id: string,
    title: string,
    expected: number,
    call: Call,
    shown: unknown = call.json ?? null,
  ): Promise<Outcome> {
    const headers = this.token
      ? { ...C6_PARTNER_HEADERS, authorization: `Bearer ${this.token}` }
      : {}
    const outcome: Outcome = {
      id,
      title,
      expected,
      request: { method: call.method, url: call.url, body: shown },
      status: null,
      body: null,
      error: null,
    }
    try {
      const response = await send(this.transport, {
        ...call,
        headers: { ...headers, ...call.headers },
      })
      outcome.status = response.status
      outcome.body = safeJson(response.text) ?? response.text
    } catch (error) {
      outcome.error = error instanceof Error ? error.message : String(error)
    }
    this.outcomes.push(outcome)
    console.log(
      `${id} ${outcome.status ?? outcome.error} (expected ${expected})`,
    )
    return outcome
  }

  authorize(body: unknown): void {
    const token = (body as { access_token?: string } | null)?.access_token
    this.token = token ?? ''
  }

  masked(): Outcome[] {
    return this.outcomes.map(outcome =>
      outcome.id === 'AT_01'
        ? { ...outcome, body: maskToken(outcome.body) }
        : outcome,
    )
  }
}

async function groupItems(roteiro: Roteiro, groupId: string): Promise<Item[]> {
  for (let attempt = 1; attempt <= 5; attempt += 1) {
    const listed = await roteiro.run(
      'AP_03',
      'Obter todos os itens de um grupo de pagamentos',
      200,
      { method: 'GET', url: `${PAYMENTS}/${groupId}/items` },
    )
    const items = (listed.body as { items?: Item[] } | null)?.items ?? []
    if (items.length > 0 || attempt === 5) {
      return items
    }
    roteiro.outcomes.pop()
    await new Promise(resolve => setTimeout(resolve, 2000))
  }
  return []
}

function markdown(outcomes: Outcome[]): string {
  const sections = outcomes.map(outcome =>
    [
      `## ${outcome.id} ${outcome.title}`,
      '',
      `- Request: \`${outcome.request.method} ${outcome.request.url}\``,
      `- Expected: ${outcome.expected}`,
      `- Status: ${outcome.status ?? `no answer (${outcome.error})`}`,
      '',
      '```json',
      JSON.stringify(outcome.body, null, 2),
      '```',
    ].join('\n'),
  )
  return `# C6 sandbox roteiro\n\n${sections.join('\n\n')}\n`
}

async function main(): Promise<void> {
  const credentials = option(
    'credentials',
    join(homedir(), '.config/cashdeck/c6-sandbox'),
  )
  const out = option('out', join(tmpdir(), 'c6-roteiro'))
  const roteiro = new Roteiro(
    mtlsTransport({
      cert: readSecret(credentials, 'cert.pem'),
      key: readSecret(credentials, 'key.pem'),
    }),
  )
  const pixKey = readSecret(credentials, 'pix_key')

  const auth = await roteiro.run(
    'AT_01',
    'Geração do token de sessão',
    200,
    {
      method: 'POST',
      url: `${HOST}/v1/auth/`,
      form: {
        client_id: readSecret(credentials, 'client_id'),
        client_secret: readSecret(credentials, 'client_secret'),
        grant_type: 'client_credentials',
      },
    },
    {
      client_id: '(masked)',
      client_secret: '(masked)',
      grant_type: 'client_credentials',
    },
  )
  roteiro.authorize(auth.body)

  const dda = await roteiro.run(
    'AP_02',
    'Consultar DDA para obter boletos pendentes de pagamento',
    200,
    { method: 'GET', url: `${PAYMENTS}/query` },
  )
  const bonds =
    (dda.body as { items?: { content?: string; amount?: number }[] } | null)
      ?.items ?? []
  const fromDda = bonds
    .filter(bond => bond.content && bond.amount)
    .slice(0, 1)
    .map(bond => ({ content: bond.content, amount: bond.amount }))

  const decoded = await roteiro.run(
    'AP_01',
    'Enviar grupo de pagamentos para decode',
    201,
    {
      method: 'POST',
      url: `${PAYMENTS}/decode`,
      json: {
        items: [
          ...SPEC_BARCODES,
          ...fromDda,
          { content: pixKey, amount: 1.0 },
          { content: pixKey, amount: 2.0 },
        ],
      },
    },
  )
  const groupId =
    (decoded.body as { group_id?: string } | null)?.group_id ?? 'missing'

  const ids = (await groupItems(roteiro, groupId)).map(item => item.id ?? '')
  const [first = 'missing', second = 'missing', third = 'missing'] = ids

  await roteiro.run(
    'AP_04',
    'Remover uma lista de pagamentos de um grupo',
    204,
    {
      method: 'DELETE',
      url: `${PAYMENTS}/${groupId}/items`,
      json: [{ id: first }, { id: second }],
    },
  )
  await roteiro.run('AP_05', 'Remover um pagamento específico do grupo', 204, {
    method: 'DELETE',
    url: `${PAYMENTS}/${groupId}/items/${third}`,
  })
  await roteiro.run('AP_06', 'Enviar grupo de pagamentos para aprovação', 204, {
    method: 'POST',
    url: `${PAYMENTS}/submit`,
    json: { group_id: groupId, uploader_name: 'Cashdeck' },
  })

  await roteiro.run('E_01', 'Consulta de saldo', 200, {
    method: 'GET',
    url: `${STATEMENT}/balance`,
  })
  const today = new Date()
  const start = new Date(today.getTime() - 29 * 24 * 60 * 60 * 1000)
  await roteiro.run('E_02', 'Consulta de extrato', 200, {
    method: 'GET',
    url: `${STATEMENT}/?start_date=${isoDate(start)}&end_date=${isoDate(today)}`,
  })

  mkdirSync(out, { recursive: true })
  const outcomes = roteiro.masked()
  writeFileSync(
    join(out, 'results.json'),
    `${JSON.stringify(outcomes, null, 2)}\n`,
  )
  writeFileSync(join(out, 'results.md'), markdown(outcomes))
  console.log(`Results written to ${out}`)
}

main().catch((error: unknown) => {
  console.error(error)
  process.exitCode = 1
})
