import {
  type HttpMethod,
  type HttpRequest,
  type HttpResponse,
  type Transport,
} from '@/http/transport'

export type ScriptedReply = {
  status?: number
  json?: unknown
  text?: string
  headers?: Record<string, string>
}

type Route = {
  method: HttpMethod
  url: string
  replies: ScriptedReply[]
}

// Tests replay recorded provider answers through this instead of the network.
export class ScriptedTransport {
  readonly requests: HttpRequest[] = []
  private readonly routes: Route[] = []

  on(method: HttpMethod, url: string, ...replies: ScriptedReply[]): this {
    this.routes.push({ method, url, replies })
    return this
  }

  readonly transport: Transport = async request => {
    this.requests.push(request)
    const route = this.routes.find(
      candidate =>
        candidate.method === request.method &&
        request.url.startsWith(candidate.url) &&
        candidate.replies.length > 0,
    )
    if (!route) {
      throw new Error(`No scripted reply for ${request.method} ${request.url}`)
    }
    const reply =
      route.replies.length > 1 ? route.replies.shift() : route.replies[0]
    return toResponse(reply as ScriptedReply)
  }

  last(method: HttpMethod, url: string): HttpRequest {
    const found = [...this.requests]
      .reverse()
      .find(request => request.method === method && request.url.startsWith(url))
    if (!found) {
      throw new Error(`No request was sent to ${method} ${url}`)
    }
    return found
  }

  body(method: HttpMethod, url: string): unknown {
    return JSON.parse(this.last(method, url).body ?? 'null')
  }
}

function toResponse(reply: ScriptedReply): HttpResponse {
  const text =
    reply.text ?? (reply.json === undefined ? '' : JSON.stringify(reply.json))
  return { status: reply.status ?? 200, headers: reply.headers ?? {}, text }
}
