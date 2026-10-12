export type HttpMethod = 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE'

export type HttpRequest = {
  method: HttpMethod
  url: string
  headers?: Record<string, string>
  body?: string
}

export type HttpResponse = {
  status: number
  headers: Record<string, string>
  text: string
  // The raw body, for documents that are not text (an invoice PDF).
  bytes?: Uint8Array
}

export type Transport = (request: HttpRequest) => Promise<HttpResponse>

export function fetchTransport(fetchImpl: typeof fetch = fetch): Transport {
  return async request => {
    const response = await fetchImpl(request.url, {
      method: request.method,
      headers: request.headers,
      body: request.body,
    })
    const headers: Record<string, string> = {}
    response.headers.forEach((value, key) => {
      headers[key] = value
    })
    const bytes = new Uint8Array(await response.arrayBuffer())
    const text = new TextDecoder().decode(bytes)
    return { status: response.status, headers, text, bytes }
  }
}

export class ProviderHttpError extends Error {
  readonly code = 'PROVIDER_HTTP_ERROR'

  constructor(
    readonly provider: string,
    readonly status: number,
    detail: string,
  ) {
    super(`${provider} answered ${status}: ${detail}`)
    this.name = 'ProviderHttpError'
  }
}

export type Call = {
  method: HttpMethod
  url: string
  headers?: Record<string, string>
  json?: unknown
  form?: Record<string, string>
}

function encodeBody(call: Call): { body?: string; type?: string } {
  if (call.form) {
    return {
      body: new URLSearchParams(call.form).toString(),
      type: 'application/x-www-form-urlencoded',
    }
  }
  if (call.json === undefined) {
    return {}
  }
  return { body: JSON.stringify(call.json), type: 'application/json' }
}

export async function send(
  transport: Transport,
  call: Call,
): Promise<HttpResponse> {
  const { body, type } = encodeBody(call)
  const headers = { accept: 'application/json', ...call.headers }
  return transport({
    method: call.method,
    url: call.url,
    headers: type ? { 'content-type': type, ...headers } : headers,
    body,
  })
}

export function readJson<T>(response: HttpResponse): T {
  if (response.text.trim().length === 0) {
    return {} as T
  }
  return JSON.parse(response.text) as T
}

export function isSuccess(response: HttpResponse): boolean {
  return response.status >= 200 && response.status < 300
}

export function isClientError(response: HttpResponse): boolean {
  return response.status >= 400 && response.status < 500
}

export function isAuthError(response: HttpResponse): boolean {
  return response.status === 401 || response.status === 403
}

export function safeJson(text: string): unknown {
  try {
    return JSON.parse(text)
  } catch {
    return null
  }
}

const CODE_KEYS = new Set([
  'code',
  'errorcode',
  'error_code',
  'error',
  'status',
])
const CODE_VALUE = /^(?=.*[A-Za-z])[\w.-]{1,64}$/

function errorCodes(value: unknown, depth = 0): string[] {
  if (depth > 3 || value === null || typeof value !== 'object') {
    return []
  }
  return Object.entries(value).flatMap(([key, inner]) =>
    typeof inner === 'string' && CODE_KEYS.has(key.toLowerCase())
      ? [inner].filter(code => CODE_VALUE.test(code))
      : errorCodes(inner, depth + 1),
  )
}

// A provider body can echo tax ids, keys, tokens and amounts, so what reaches
// an error or a log is only the error codes it names, never the body itself.
export function bodySummary(text: string): string {
  const codes = [...new Set(errorCodes(safeJson(text)))].slice(0, 5)
  return codes.length > 0 ? codes.join(', ') : `${text.length}-byte body`
}

export function toCents(value: number | string | null | undefined): number {
  if (value === null || value === undefined || value === '') {
    return 0
  }
  return Math.round(Number(value) * 100)
}

export function toDecimal(cents: number): number {
  return Math.round(cents) / 100
}

export function toDecimalString(cents: number): string {
  return toDecimal(cents).toFixed(2)
}
