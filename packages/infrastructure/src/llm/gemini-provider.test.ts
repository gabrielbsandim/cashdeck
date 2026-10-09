import { describe, expect, it, vi } from 'vitest'

import { GeminiProvider, truncateMessages } from '@/llm/gemini-provider'
import { LlmProviderError } from '@cashdeck/application'
import type { LlmChatParams, LlmMessage } from '@cashdeck/application'

type SchemaNode = {
  type: string
  enum?: string[]
  required?: string[]
  description?: string
  items: SchemaNode
  properties: { [name: string]: SchemaNode } & Record<
    'merchant' | 'items' | 'name',
    SchemaNode
  >
}

function jsonResponse(body: unknown, init: ResponseInit = {}): Response {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
    ...init,
  })
}

const baseParams: LlmChatParams = {
  system: 'be helpful',
  messages: [{ role: 'user', content: 'oi' }],
  tools: [],
  maxInputTokens: 4_000,
  maxOutputTokens: 1_000,
}

function makeProvider(fetchImpl: typeof fetch): GeminiProvider {
  return new GeminiProvider({ apiKey: 'k', fetchImpl })
}

describe('GeminiProvider: config', () => {
  it('throws when apiKey is missing', () => {
    expect(() => new GeminiProvider({ apiKey: '' })).toThrow(LlmProviderError)
  })

  it('uses gemini-3.1-flash-lite by default', () => {
    const provider = new GeminiProvider({ apiKey: 'k' })
    expect(provider.modelId).toBe('gemini-3.1-flash-lite')
  })

  it('respects a custom modelId', () => {
    const provider = new GeminiProvider({ apiKey: 'k', modelId: 'foo' })
    expect(provider.modelId).toBe('foo')
  })
})

describe('GeminiProvider: chat', () => {
  it('returns text and usage on a normal response', async () => {
    const fetchMock = vi.fn(async () =>
      jsonResponse({
        candidates: [
          {
            content: { parts: [{ text: 'hello!' }] },
            finishReason: 'STOP',
          },
        ],
        usageMetadata: { promptTokenCount: 10, candidatesTokenCount: 5 },
      }),
    )

    const provider = makeProvider(fetchMock as unknown as typeof fetch)
    const result = await provider.chat(baseParams)

    expect(result.text).toBe('hello!')
    expect(result.stopReason).toBe('end')
    expect(result.usage.inputTokens).toBe(10)
    expect(result.usage.outputTokens).toBe(5)
    expect(result.usage.costMillicents).toBeGreaterThanOrEqual(0)
  })

  it('extracts tool calls and reports tool_use stop reason', async () => {
    const fetchMock = vi.fn(async () =>
      jsonResponse({
        candidates: [
          {
            content: {
              parts: [{ functionCall: { name: 'lookup', args: { id: '1' } } }],
            },
            finishReason: 'STOP',
          },
        ],
      }),
    )
    const provider = makeProvider(fetchMock as unknown as typeof fetch)

    const result = await provider.chat({
      ...baseParams,
      tools: [
        {
          name: 'lookup',
          description: 'look it up',
          parameters: { type: 'object' },
        },
      ],
    })

    expect(result.toolCalls).toHaveLength(1)
    expect(result.toolCalls[0]).toMatchObject({
      name: 'lookup',
      arguments: { id: '1' },
    })
    expect(result.stopReason).toBe('tool_use')
  })

  it('falls back to empty arguments when functionCall has no args', async () => {
    const fetchMock = vi.fn(async () =>
      jsonResponse({
        candidates: [
          {
            content: { parts: [{ functionCall: { name: 'ping' } }] },
            finishReason: 'STOP',
          },
        ],
      }),
    )
    const provider = makeProvider(fetchMock as unknown as typeof fetch)

    const result = await provider.chat({
      ...baseParams,
      tools: [
        { name: 'ping', description: '', parameters: { type: 'object' } },
      ],
    })
    expect(result.toolCalls[0]?.arguments).toEqual({})
  })

  it('maps known finish reasons', async () => {
    const fetchMock = vi.fn(async () =>
      jsonResponse({
        candidates: [
          { content: { parts: [{ text: '' }] }, finishReason: 'MAX_TOKENS' },
        ],
      }),
    )
    const provider = makeProvider(fetchMock as unknown as typeof fetch)
    const result = await provider.chat(baseParams)
    expect(result.stopReason).toBe('max_tokens')
  })

  it('falls back to end for unknown finish reasons', async () => {
    const fetchMock = vi.fn(async () =>
      jsonResponse({
        candidates: [
          { content: { parts: [{ text: 'x' }] }, finishReason: 'OTHER' },
        ],
      }),
    )
    const provider = makeProvider(fetchMock as unknown as typeof fetch)
    const result = await provider.chat(baseParams)
    expect(result.stopReason).toBe('end')
    expect(result.rawFinishReason).toBe('OTHER')
  })

  it('handles missing finishReason and missing usageMetadata', async () => {
    const fetchMock = vi.fn(async () =>
      jsonResponse({ candidates: [{ content: { parts: [{ text: 'x' }] } }] }),
    )
    const provider = makeProvider(fetchMock as unknown as typeof fetch)
    const result = await provider.chat(baseParams)
    expect(result.stopReason).toBe('end')
    expect(result.usage.inputTokens).toBe(0)
    expect(result.usage.outputTokens).toBe(0)
  })

  it('throws on non-2xx responses', async () => {
    const fetchMock = vi.fn(async () => new Response('oops', { status: 500 }))
    const provider = makeProvider(fetchMock as unknown as typeof fetch)
    await expect(provider.chat(baseParams)).rejects.toThrow(LlmProviderError)
  })

  it('marks a 400 as a rejected request and other failures as chat_failed', async () => {
    const rejected = vi.fn(async () => new Response('bad', { status: 400 }))
    await expect(
      makeProvider(rejected as unknown as typeof fetch).chat(baseParams),
    ).rejects.toMatchObject({ code: 'request_rejected' })
    const failed = vi.fn(async () => new Response('oops', { status: 500 }))
    await expect(
      makeProvider(failed as unknown as typeof fetch).chat(baseParams),
    ).rejects.toMatchObject({ code: 'chat_failed' })
  })

  it('still throws when reading the error body fails', async () => {
    const brokenResponse = new Response('', { status: 500 })
    Object.defineProperty(brokenResponse, 'text', {
      value: () => Promise.reject(new Error('broken')),
    })
    const fetchMock = vi.fn(async () => brokenResponse)
    const provider = makeProvider(fetchMock as unknown as typeof fetch)
    await expect(provider.chat(baseParams)).rejects.toThrow(LlmProviderError)
  })

  it('throws when there is no candidate', async () => {
    const fetchMock = vi.fn(async () => jsonResponse({ candidates: [] }))
    const provider = makeProvider(fetchMock as unknown as typeof fetch)
    await expect(provider.chat(baseParams)).rejects.toThrow(LlmProviderError)
  })

  it('handles candidate with no content parts', async () => {
    const fetchMock = vi.fn(async () =>
      jsonResponse({ candidates: [{ finishReason: 'STOP' }] }),
    )
    const provider = makeProvider(fetchMock as unknown as typeof fetch)
    const result = await provider.chat(baseParams)
    expect(result.text).toBe('')
    expect(result.toolCalls).toHaveLength(0)
  })

  it('serializes assistant and tool messages with proper Gemini roles', async () => {
    const fetchMock = vi.fn(async () =>
      jsonResponse({ candidates: [{ content: { parts: [{ text: 'ok' }] } }] }),
    )
    const provider = makeProvider(fetchMock as unknown as typeof fetch)

    await provider.chat({
      ...baseParams,
      messages: [
        { role: 'user', content: 'hi' },
        { role: 'assistant', content: 'how can I help' },
        { role: 'tool', content: 'tool output', toolName: 'lookup' },
        { role: 'user', content: 'bye' },
      ],
    })

    const call = fetchMock.mock.calls[0] as unknown as [unknown, RequestInit]
    const sentBody = JSON.parse(String(call[1].body)) as {
      contents: { role: string }[]
    }
    expect(sentBody.contents.map(c => c.role)).toEqual([
      'user',
      'model',
      'user',
      'user',
    ])
  })

  it('serializes tool message as functionResponse with the tool name', async () => {
    const fetchMock = vi.fn(async () =>
      jsonResponse({ candidates: [{ content: { parts: [{ text: 'ok' }] } }] }),
    )
    const provider = makeProvider(fetchMock as unknown as typeof fetch)

    await provider.chat({
      ...baseParams,
      messages: [
        { role: 'user', content: 'list works' },
        {
          role: 'tool',
          toolName: 'listBills',
          content: '{"works":[{"name":"Alpha"}]}',
        },
      ],
    })

    const call = fetchMock.mock.calls[0] as unknown as [unknown, RequestInit]
    const sentBody = JSON.parse(String(call[1].body)) as {
      contents: {
        role: string
        parts: {
          functionResponse?: { name: string; response: Record<string, unknown> }
        }[]
      }[]
    }
    const toolPart = sentBody.contents[1]!.parts[0]
    expect(toolPart!.functionResponse?.name).toBe('listBills')
    expect(toolPart!.functionResponse?.response).toEqual({
      works: [{ name: 'Alpha' }],
    })
  })

  it('wraps non-JSON tool content in a result field', async () => {
    const fetchMock = vi.fn(async () =>
      jsonResponse({ candidates: [{ content: { parts: [{ text: 'ok' }] } }] }),
    )
    const provider = makeProvider(fetchMock as unknown as typeof fetch)

    await provider.chat({
      ...baseParams,
      messages: [
        { role: 'user', content: 'hi' },
        { role: 'tool', toolName: 'noop', content: 'plain text' },
      ],
    })

    const call = fetchMock.mock.calls[0] as unknown as [unknown, RequestInit]
    const sentBody = JSON.parse(String(call[1].body)) as {
      contents: {
        parts: { functionResponse?: { response: Record<string, unknown> } }[]
      }[]
    }
    expect(sentBody.contents[1]!.parts[0]!.functionResponse?.response).toEqual({
      result: 'plain text',
    })
  })

  it('wraps JSON primitives/arrays in a result field', async () => {
    const fetchMock = vi.fn(async () =>
      jsonResponse({ candidates: [{ content: { parts: [{ text: 'ok' }] } }] }),
    )
    const provider = makeProvider(fetchMock as unknown as typeof fetch)

    await provider.chat({
      ...baseParams,
      messages: [
        { role: 'user', content: 'hi' },
        { role: 'tool', toolName: 'count', content: '42' },
        { role: 'tool', toolName: 'list', content: '[1,2,3]' },
      ],
    })

    const call = fetchMock.mock.calls[0] as unknown as [unknown, RequestInit]
    const sentBody = JSON.parse(String(call[1].body)) as {
      contents: {
        parts: { functionResponse?: { response: Record<string, unknown> } }[]
      }[]
    }
    expect(sentBody.contents[1]!.parts[0]!.functionResponse?.response).toEqual({
      result: 42,
    })
    expect(sentBody.contents[2]!.parts[0]!.functionResponse?.response).toEqual({
      result: [1, 2, 3],
    })
  })

  it('falls back to a generic tool name when toolName is missing', async () => {
    const fetchMock = vi.fn(async () =>
      jsonResponse({ candidates: [{ content: { parts: [{ text: 'ok' }] } }] }),
    )
    const provider = makeProvider(fetchMock as unknown as typeof fetch)

    await provider.chat({
      ...baseParams,
      messages: [
        { role: 'user', content: 'hi' },
        { role: 'tool', content: '{"ok":true}' },
      ],
    })

    const call = fetchMock.mock.calls[0] as unknown as [unknown, RequestInit]
    const sentBody = JSON.parse(String(call[1].body)) as {
      contents: { parts: { functionResponse?: { name: string } }[] }[]
    }
    expect(sentBody.contents[1]!.parts[0]!.functionResponse?.name).toBe('tool')
  })

  it('emits an assistant turn with functionCall parts when toolCalls are present', async () => {
    const fetchMock = vi.fn(async () =>
      jsonResponse({ candidates: [{ content: { parts: [{ text: 'ok' }] } }] }),
    )
    const provider = makeProvider(fetchMock as unknown as typeof fetch)

    await provider.chat({
      ...baseParams,
      messages: [
        { role: 'user', content: 'list works' },
        {
          role: 'assistant',
          content: '',
          toolCalls: [
            {
              id: 'call_1',
              name: 'listBills',
              arguments: { status: 'active' },
            },
          ],
        },
        { role: 'tool', toolName: 'listBills', content: '{"works":[]}' },
      ],
    })

    const call = fetchMock.mock.calls[0] as unknown as [unknown, RequestInit]
    const sentBody = JSON.parse(String(call[1].body)) as {
      contents: {
        role: string
        parts: {
          text?: string
          functionCall?: { name: string; args: Record<string, unknown> }
        }[]
      }[]
    }
    expect(sentBody.contents[1]!.role).toBe('model')
    const fcPart = sentBody.contents[1]!.parts.find(p => p.functionCall)
    expect(fcPart?.functionCall?.name).toBe('listBills')
    expect(fcPart?.functionCall?.args).toEqual({ status: 'active' })
  })

  it('includes assistant text alongside functionCall parts when both exist', async () => {
    const fetchMock = vi.fn(async () =>
      jsonResponse({ candidates: [{ content: { parts: [{ text: 'ok' }] } }] }),
    )
    const provider = makeProvider(fetchMock as unknown as typeof fetch)

    await provider.chat({
      ...baseParams,
      messages: [
        { role: 'user', content: 'hi' },
        {
          role: 'assistant',
          content: 'one moment',
          toolCalls: [{ id: 'c1', name: 'getDashboardSummary', arguments: {} }],
        },
        { role: 'tool', toolName: 'getDashboardSummary', content: '{}' },
      ],
    })

    const call = fetchMock.mock.calls[0] as unknown as [unknown, RequestInit]
    const sentBody = JSON.parse(String(call[1].body)) as {
      contents: { parts: { text?: string; functionCall?: unknown }[] }[]
    }
    const parts = sentBody.contents[1]!.parts
    expect(parts.some(p => p.text === 'one moment')).toBe(true)
    expect(parts.some(p => p.functionCall)).toBe(true)
  })

  it('serializes user attachments as inlineData parts after the text part', async () => {
    const fetchMock = vi.fn(async () =>
      jsonResponse({ candidates: [{ content: { parts: [{ text: 'ok' }] } }] }),
    )
    const provider = makeProvider(fetchMock as unknown as typeof fetch)

    await provider.chat({
      ...baseParams,
      messages: [
        {
          role: 'user',
          content: 'extract this',
          attachments: [{ mimeType: 'application/pdf', dataBase64: 'QUJD' }],
        },
      ],
    })

    const call = fetchMock.mock.calls[0] as unknown as [unknown, RequestInit]
    const sentBody = JSON.parse(String(call[1].body)) as {
      contents: {
        parts: {
          text?: string
          inlineData?: { mimeType: string; data: string }
        }[]
      }[]
    }
    const parts = sentBody.contents[0]!.parts
    expect(parts[0]!.text).toBe('extract this')
    expect(parts[1]!.inlineData).toEqual({
      mimeType: 'application/pdf',
      data: 'QUJD',
    })
  })

  it('omits inlineData parts when a message has no attachments', async () => {
    const fetchMock = vi.fn(async () =>
      jsonResponse({ candidates: [{ content: { parts: [{ text: 'ok' }] } }] }),
    )
    const provider = makeProvider(fetchMock as unknown as typeof fetch)

    await provider.chat(baseParams)

    const call = fetchMock.mock.calls[0] as unknown as [unknown, RequestInit]
    const sentBody = JSON.parse(String(call[1].body)) as {
      contents: { parts: { inlineData?: unknown }[] }[]
    }
    expect(sentBody.contents[0]!.parts.some(p => p.inlineData)).toBe(false)
  })

  it('omits tools key from the body when no tools are passed', async () => {
    const fetchMock = vi.fn(async () =>
      jsonResponse({ candidates: [{ content: { parts: [{ text: 'ok' }] } }] }),
    )
    const provider = makeProvider(fetchMock as unknown as typeof fetch)
    await provider.chat(baseParams)

    const call = fetchMock.mock.calls[0] as unknown as [unknown, RequestInit]
    const sentBody = JSON.parse(String(call[1].body)) as { tools?: unknown }
    expect(sentBody.tools).toBeUndefined()
  })
})

describe('truncateMessages', () => {
  it('returns the input untouched when empty', () => {
    expect(truncateMessages([], 100)).toEqual([])
  })

  it('keeps all messages when they fit', () => {
    const messages: LlmMessage[] = [
      { role: 'user', content: 'a'.repeat(40) },
      { role: 'assistant', content: 'b'.repeat(40) },
      { role: 'user', content: 'c'.repeat(40) },
    ]
    expect(truncateMessages(messages, 1_000)).toHaveLength(3)
  })

  it('drops oldest messages when the cap is exceeded', () => {
    const messages: LlmMessage[] = [
      { role: 'user', content: 'a'.repeat(40) },
      { role: 'assistant', content: 'b'.repeat(40) },
      { role: 'user', content: 'c'.repeat(40) },
      { role: 'assistant', content: 'd'.repeat(40) },
      { role: 'user', content: 'e'.repeat(40) },
    ]
    const trimmed = truncateMessages(messages, 25)
    expect(trimmed).toHaveLength(2)
    expect(trimmed[trimmed.length - 1]?.content.startsWith('e')).toBe(true)
  })

  it('returns just the last message when it alone exceeds the cap', () => {
    const messages: LlmMessage[] = [
      { role: 'user', content: 'old' },
      { role: 'user', content: 'a'.repeat(4_000) },
    ]
    const trimmed = truncateMessages(messages, 100)
    expect(trimmed).toHaveLength(1)
    expect(trimmed[0]?.content.length).toBe(4_000)
  })

  it("keeps the person's message when this turn's tool results pass the cap", () => {
    const question: LlmMessage = {
      role: 'user',
      content: 'Pode fechar assim mesmo',
    }
    const messages: LlmMessage[] = [
      { role: 'user', content: 'a'.repeat(400) },
      { role: 'assistant', content: 'b'.repeat(400) },
      question,
      {
        role: 'assistant',
        content: '',
        toolCalls: [{ id: 'c1', name: 'finalize_diary', arguments: {} }],
      },
      {
        role: 'tool',
        content: 'r'.repeat(396),
        toolCallId: 'c1',
        toolName: 'finalize_diary',
      },
    ]

    const trimmed = truncateMessages(messages, 100)

    expect(trimmed).toContainEqual(question)
    expect(trimmed.at(-1)?.role).toBe('tool')
    expect(trimmed[0]).toEqual(question)
  })

  describe("this turn's tool results past the cap", () => {
    const question: LlmMessage = {
      role: 'user',
      content: 'how are all my accounts?',
    }
    const RESULT_CHARS = 16_000

    function result(n: number): LlmMessage {
      return {
        role: 'tool',
        content: `{"status":"ok","n":${n}}${'r'.repeat(RESULT_CHARS)}`,
        toolCallId: `c${n}`,
        toolName: 'get_work_detail',
      }
    }

    function call(ids: number[]): LlmMessage {
      return {
        role: 'assistant',
        content: '',
        toolCalls: ids.map(n => ({
          id: `c${n}`,
          name: 'get_work_detail',
          arguments: {},
        })),
      }
    }

    function approximate(messages: LlmMessage[]): number {
      return messages.reduce(
        (sum, message) =>
          sum +
          Math.ceil(
            (
              message.content +
              (message.toolCalls?.length
                ? JSON.stringify(message.toolCalls)
                : '')
            ).length / 4,
          ),
        0,
      )
    }

    const ten = Array.from({ length: 10 }, (_, i) => i + 1)

    it.each([
      [
        'one round each',
        [question, ...ten.flatMap(n => [call([n]), result(n)])],
      ],
      ['one round with ten calls', [question, call(ten), ...ten.map(result)]],
    ])('bound the turn under the cap, over %s', (_shape, messages) => {
      const trimmed = truncateMessages(messages, 8_000)

      expect(approximate(trimmed)).toBeLessThanOrEqual(8_000)
      expect(trimmed[0]).toEqual(question)
      expect(trimmed.filter(m => m.role === 'tool')).toHaveLength(10)
      expect(trimmed.map(m => m.toolCallId ?? m.role)).toEqual(
        messages.map(m => m.toolCallId ?? m.role),
      )
    })

    it('clips the oldest results first and keeps how each one opens', () => {
      const messages = [question, ...ten.flatMap(n => [call([n]), result(n)])]

      const trimmed = truncateMessages(messages, 8_000)
      const results = trimmed.filter(m => m.role === 'tool')

      expect(results[0]!.content.length).toBeLessThan(
        results.at(-1)!.content.length,
      )
      expect(results.at(-1)!.content).toBe(result(10).content)
      expect(results[0]!.content.startsWith('{"status":"ok","n":1}')).toBe(true)
    })
  })

  it('never sends a tool result without the call that asked for it', () => {
    const messages: LlmMessage[] = [
      { role: 'user', content: 'x'.repeat(40) },
      { role: 'assistant', content: 'y'.repeat(40) },
      { role: 'user', content: 'what is the balance of both accounts?' },
      {
        role: 'assistant',
        content: '',
        toolCalls: [
          { id: 'c1', name: 'get_financial_summary', arguments: {} },
          { id: 'c2', name: 'get_financial_summary', arguments: {} },
        ],
      },
      { role: 'tool', content: 'r'.repeat(40), toolCallId: 'c1' },
      { role: 'tool', content: 's'.repeat(40), toolCallId: 'c2' },
    ]

    const trimmed = truncateMessages(messages, 15)

    const orphans = trimmed.filter(
      (message, index) =>
        message.role === 'tool' &&
        !trimmed
          .slice(0, index)
          .some(earlier =>
            earlier.toolCalls?.some(call => call.id === message.toolCallId),
          ),
    )
    expect(trimmed.some(message => message.role === 'tool')).toBe(true)
    expect(orphans).toEqual([])
  })

  it('drops a two-call exchange whole when the budget fits only its second result', () => {
    const exchange: LlmMessage[] = [
      {
        role: 'assistant',
        content: '',
        toolCalls: [
          { id: 'c1', name: 'get_financial_summary', arguments: {} },
          { id: 'c2', name: 'get_financial_summary', arguments: {} },
        ],
      },
      { role: 'tool', content: 'r'.repeat(400), toolCallId: 'c1' },
      { role: 'tool', content: 's'.repeat(40), toolCallId: 'c2' },
    ]
    const messages: LlmMessage[] = [
      { role: 'user', content: 'what is the balance of both accounts?' },
      ...exchange,
      { role: 'assistant', content: 'a'.repeat(40) },
      { role: 'user', content: 'u'.repeat(40) },
    ]

    const trimmed = truncateMessages(messages, 35)

    expect(trimmed.map(message => message.content)).toEqual([
      'a'.repeat(40),
      'u'.repeat(40),
    ])
    expect(trimmed[0]?.role).not.toBe('tool')
    expect(trimmed.some(message => message.role === 'tool')).toBe(false)
    expect(trimmed.some(message => message.toolCalls?.length)).toBe(false)
  })

  it("counts a tool call's arguments against the cap", () => {
    const messages: LlmMessage[] = [
      { role: 'user', content: 'record the expense' },
      {
        role: 'assistant',
        content: '',
        toolCalls: [
          {
            id: 'c1',
            name: 'create_financial_entry',
            arguments: { description: 'z'.repeat(2_000) },
          },
        ],
      },
      { role: 'tool', content: '{"status":"created"}', toolCallId: 'c1' },
      { role: 'assistant', content: 'Recorded.' },
      { role: 'user', content: 'obrigado' },
    ]

    const trimmed = truncateMessages(messages, 100)

    expect(trimmed.some(message => message.toolCalls?.length)).toBe(false)
    expect(trimmed.at(-1)?.content).toBe('obrigado')
  })

  it('keeps a trailing tool exchange whole when no user message exists', () => {
    const call: LlmMessage = {
      role: 'assistant',
      content: '',
      toolCalls: [
        { id: 'c1', name: 'get_work_detail', arguments: {} },
        { id: 'c2', name: 'get_work_detail', arguments: {} },
      ],
    }
    const first: LlmMessage = {
      role: 'tool',
      content: 'r'.repeat(400),
      toolCallId: 'c1',
    }
    const second: LlmMessage = {
      role: 'tool',
      content: 's'.repeat(400),
      toolCallId: 'c2',
    }
    const messages: LlmMessage[] = [
      { role: 'assistant', content: 'a'.repeat(40) },
      call,
      first,
      second,
    ]

    const trimmed = truncateMessages(messages, 10)

    expect(trimmed).toEqual([call, first, second])
  })

  it('anchors on the last message when nothing but assistant text exists', () => {
    const messages: LlmMessage[] = [
      { role: 'assistant', content: 'a'.repeat(400) },
      { role: 'assistant', content: 'b'.repeat(40) },
    ]

    const trimmed = truncateMessages(messages, 10)

    expect(trimmed.map(message => message.content)).toEqual(['b'.repeat(40)])
  })
})

describe('GeminiProvider: structured output', () => {
  const SCHEMA: LlmChatParams['responseSchema'] = {
    type: 'object',
    properties: {
      merchant: { type: 'string', enum: ['sunny', 'market'] },
      items: {
        type: 'array',
        items: {
          type: 'object',
          properties: { name: { type: 'string' } },
          required: ['name'],
        },
      },
    },
    required: ['merchant'],
  }

  function sentBody(mock: { mock: { calls: unknown[] } }): {
    generationConfig: Record<string, unknown>
  } {
    const [, init] = mock.mock.calls[0] as [string, RequestInit]
    return JSON.parse(init.body as string)
  }

  function schemaProvider(text: string, finishReason = 'STOP') {
    const fetchMock = vi.fn(async () =>
      jsonResponse({
        candidates: [{ content: { parts: [{ text }] }, finishReason }],
        usageMetadata: { promptTokenCount: 10, candidatesTokenCount: 5 },
      }),
    )
    return { fetchMock, provider: makeProvider(fetchMock as never) }
  }

  it('asks for JSON mode and returns the answer parsed', async () => {
    const { fetchMock, provider } = schemaProvider(
      '{"merchant":"market","items":[{"name":"Coffee"}]}',
    )

    const result = await provider.chat({
      ...baseParams,
      responseSchema: SCHEMA,
    })

    const body = sentBody(fetchMock)
    expect(body.generationConfig.responseMimeType).toBe('application/json')
    expect(result.object).toEqual({
      merchant: 'market',
      items: [{ name: 'Coffee' }],
    })
    expect(result.text).toContain('market')
  })

  it('translates the schema into the dialect Gemini wants, recursively', async () => {
    const { fetchMock, provider } = schemaProvider('{"merchant":"sunny"}')

    await provider.chat({ ...baseParams, responseSchema: SCHEMA })

    const body = sentBody(fetchMock)
    const sent = body.generationConfig.responseSchema as SchemaNode
    expect(sent.type).toBe('OBJECT')
    expect(sent.properties.merchant.type).toBe('STRING')
    expect(sent.properties.merchant.enum).toEqual(['sunny', 'market'])
    expect(sent.properties.items.type).toBe('ARRAY')
    expect(sent.properties.items.items.type).toBe('OBJECT')
    expect(sent.properties.items.items.properties.name.type).toBe('STRING')
    expect(sent.required).toEqual(['merchant'])
  })

  it('sends no JSON mode at all when no schema is asked for', async () => {
    const { fetchMock, provider } = schemaProvider('hello')

    const result = await provider.chat(baseParams)

    const body = sentBody(fetchMock)
    expect(body.generationConfig).not.toHaveProperty('responseMimeType')
    expect(body.generationConfig).not.toHaveProperty('responseSchema')
    expect(result).not.toHaveProperty('object')
  })

  it('refuses a schema and tools in the same call, before spending anything', async () => {
    const { fetchMock, provider } = schemaProvider('{}')

    await expect(
      provider.chat({
        ...baseParams,
        responseSchema: SCHEMA,
        tools: [
          { name: 't', description: 'd', parameters: { type: 'object' } },
        ],
      }),
    ).rejects.toThrow(LlmProviderError)
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it('names a truncated answer instead of calling it malformed', async () => {
    const { provider } = schemaProvider('{"merchant":"rai', 'MAX_TOKENS')

    await expect(
      provider.chat({ ...baseParams, responseSchema: SCHEMA }),
    ).rejects.toThrow(/cut off/)
  })

  it('fails clearly when JSON mode answers with prose', async () => {
    const { provider } = schemaProvider('sorry, I did not understand')

    await expect(
      provider.chat({ ...baseParams, responseSchema: SCHEMA }),
    ).rejects.toThrow(/not JSON/)
  })
})

describe('GeminiProvider: request ceiling', () => {
  it('passes an abort signal when the caller asks for a timeout', async () => {
    const fetchImpl = vi.fn(async () =>
      jsonResponse({
        candidates: [{ content: { parts: [{ text: 'oi' }] } }],
        usageMetadata: { promptTokenCount: 1, candidatesTokenCount: 1 },
      }),
    )
    const provider = makeProvider(fetchImpl as unknown as typeof fetch)

    await provider.chat({ ...baseParams, timeoutMs: 8_000 })

    const init = (fetchImpl.mock.calls[0] as unknown[])[1] as RequestInit
    expect(init.signal).toBeInstanceOf(AbortSignal)
  })

  it('sends no signal when none was asked for', async () => {
    const fetchImpl = vi.fn(async () =>
      jsonResponse({
        candidates: [{ content: { parts: [{ text: 'oi' }] } }],
        usageMetadata: { promptTokenCount: 1, candidatesTokenCount: 1 },
      }),
    )
    const provider = makeProvider(fetchImpl as unknown as typeof fetch)

    await provider.chat(baseParams)

    const init = (fetchImpl.mock.calls[0] as unknown[])[1] as RequestInit
    expect(init.signal).toBeUndefined()
  })
})
