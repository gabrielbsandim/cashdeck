import { Agent, request as httpsRequest } from 'node:https'
import { type ClientRequest, type IncomingMessage } from 'node:http'
import { type Transport } from '@/http/transport'

export type ClientCertificate = {
  cert: string
  key: string
  passphrase?: string
  ca?: string
}

type RequestImpl = (
  url: string,
  options: {
    method: string
    headers?: Record<string, string>
    agent: unknown
  },
  callback: (response: IncomingMessage) => void,
) => ClientRequest

export type MtlsOptions = {
  request?: RequestImpl
  agent?: unknown
}

function flatten(headers: IncomingMessage['headers']): Record<string, string> {
  const flat: Record<string, string> = {}
  for (const [key, value] of Object.entries(headers)) {
    flat[key] = Array.isArray(value) ? value.join(', ') : String(value)
  }
  return flat
}

// Banks that pay through an API (Inter, C6) authenticate the client by its TLS
// certificate, which fetch cannot present; node:https can.
export function mtlsTransport(
  certificate: ClientCertificate,
  options: MtlsOptions = {},
): Transport {
  const agent = options.agent ?? new Agent({ ...certificate })
  const request = options.request ?? (httpsRequest as unknown as RequestImpl)
  return input =>
    new Promise((resolve, reject) => {
      const outgoing = request(
        input.url,
        { method: input.method, headers: input.headers, agent },
        response => {
          const chunks: Buffer[] = []
          response.on('data', (chunk: Buffer) => chunks.push(chunk))
          response.on('error', reject)
          response.on('end', () =>
            resolve({
              status: response.statusCode ?? 0,
              headers: flatten(response.headers),
              text: Buffer.concat(chunks).toString('utf8'),
            }),
          )
        },
      )
      outgoing.on('error', reject)
      outgoing.end(input.body)
    })
}
