import { type PixCharge, type PixLocationResolver } from '@cashdeck/application'
import { Money } from '@cashdeck/domain'
import { isSuccess, send, type Transport } from '@/http/transport'

export type PixLocationResolverDeps = {
  transport: Transport
  timeoutMs?: number
}

type LocationPayload = {
  txid?: unknown
  chave?: unknown
  calendario?: { dataDeVencimento?: unknown }
  valor?: { original?: unknown; final?: unknown }
  recebedor?: { nome?: unknown }
}

const DEFAULT_TIMEOUT_MS = 5_000
const DATE = /^\d{4}-\d{2}-\d{2}$/
const IPV4 = /^\d{1,3}(\.\d{1,3}){3}$/
// Field 26.25 holds at most 77 characters, a host and a path without scheme.
const MAX_LOCATION_LENGTH = 77

// The location comes from a scanned code, so only a public https host name is
// fetched: no IP literal, port, credentials or single label host.
export function locationUrl(location: string): string | null {
  if (location.length > MAX_LOCATION_LENGTH || /\s/.test(location)) {
    return null
  }
  try {
    const url = new URL(`https://${location}`)
    const plainHost =
      url.hostname.includes('.') &&
      !IPV4.test(url.hostname) &&
      !url.hostname.startsWith('[')
    const plain = plainHost && url.port === '' && url.username === ''
    return plain ? url.toString() : null
  } catch {
    return null
  }
}

function payloadOf(jws: string): LocationPayload | null {
  const parts = jws.trim().split('.')
  if (parts.length !== 3) {
    return null
  }
  try {
    const decoded: unknown = JSON.parse(
      Buffer.from(parts[1] ?? '', 'base64url').toString('utf8'),
    )
    return typeof decoded === 'object' && decoded !== null
      ? (decoded as LocationPayload)
      : null
  } catch {
    return null
  }
}

const text = (value: unknown) =>
  typeof value === 'string' && value.trim() ? value.trim() : null

function amountOf(value: unknown): Money | null {
  const decimal = text(value)
  if (!decimal) {
    return null
  }
  try {
    const amount = Money.fromDecimal(decimal)
    return amount.isPositive() ? amount : null
  } catch {
    return null
  }
}

// A cobv reports the amount due today (fines and discounts applied) as final.
function toCharge(payload: LocationPayload): PixCharge {
  const due = text(payload.calendario?.dataDeVencimento)
  return {
    amount: amountOf(payload.valor?.final) ?? amountOf(payload.valor?.original),
    dueDate: due && DATE.test(due) ? due : null,
    key: text(payload.chave),
    payee: text(payload.recebedor?.nome),
    txid: text(payload.txid),
  }
}

function withTimeout<T>(work: Promise<T>, ms: number): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined
  const expired = new Promise<never>((_, reject) => {
    timer = setTimeout(
      () => reject(new Error(`Pix location timed out after ${ms} ms.`)),
      ms,
    )
  })
  return Promise.race([work, expired]).finally(() => clearTimeout(timer))
}

// Reads the JWS the location serves. The signature is not verified: the charge
// only fills fields of a bill, and the paying bank resolves the same location.
export class JwsPixLocationResolver implements PixLocationResolver {
  constructor(private readonly deps: PixLocationResolverDeps) {}

  async resolve(location: string): Promise<PixCharge | null> {
    const url = locationUrl(location)
    if (!url) {
      return null
    }
    const response = await withTimeout(
      send(this.deps.transport, {
        method: 'GET',
        url,
        headers: { accept: 'application/jose, application/json' },
      }),
      this.deps.timeoutMs ?? DEFAULT_TIMEOUT_MS,
    )
    if (!isSuccess(response)) {
      return null
    }
    const payload = payloadOf(response.text)
    return payload ? toCharge(payload) : null
  }
}
