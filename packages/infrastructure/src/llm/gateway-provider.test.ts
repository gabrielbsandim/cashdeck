import { describe, expect, it, vi } from 'vitest'

import { GatewayProvider } from '@/llm/gateway-provider'
import { LlmProviderError } from '@cashdeck/application'
import type { LlmChatParams } from '@cashdeck/application'

function baseParams(over: Partial<LlmChatParams> = {}): LlmChatParams {
  return {
    system: 'You are an assistant.',
    messages: [{ role: 'user', content: 'oi' }],
    tools: [],
    maxInputTokens: 8000,
    maxOutputTokens: 1000,
    ...over,
  }
}

function fakeResult(over: Record<string, unknown> = {}) {
  return {
    text: 'hello',
    toolCalls: [],
    usage: { inputTokens: 100, outputTokens: 50 },
    finishReason: 'stop',
    ...over,
  }
}

describe('GatewayProvider', () => {
  it('requires at least one model', () => {
    expect(() => new GatewayProvider({ models: [] })).toThrow(LlmProviderError)
  })

  it('calls the primary model and maps the result + cost', async () => {
    const generate = vi.fn(async () => fakeResult())
    const provider = new GatewayProvider({
      models: ['google/gemini-2.5-flash-lite'],
      generate: generate as never,
    })

    const result = await provider.chat(baseParams())

    expect(generate).toHaveBeenCalledOnce()
    const args = (generate.mock.calls[0]! as unknown[])[0] as Record<
      string,
      unknown
    >
    expect(args.model).toBe('google/gemini-2.5-flash-lite')
    expect(args.system).toBe('You are an assistant.')
    expect(result.text).toBe('hello')
    expect(result.usage.inputTokens).toBe(100)
    expect(result.usage.outputTokens).toBe(50)
    expect(result.usage.costMillicents).toBeGreaterThanOrEqual(0)
    expect(result.stopReason).toBe('end')
  })

  it('passes fallback models and BYOK in providerOptions', async () => {
    const generate = vi.fn(async () => fakeResult())
    const provider = new GatewayProvider({
      models: ['google/gemini-2.5-flash-lite', 'google/gemini-2.5-flash'],
      byokGoogleApiKey: 'g-key',
      generate: generate as never,
    })

    await provider.chat(baseParams())

    const args = (generate.mock.calls[0]! as unknown[])[0] as {
      providerOptions: { gateway: { models: string[]; byok: unknown } }
    }
    expect(args.providerOptions.gateway.models).toEqual([
      'google/gemini-2.5-flash',
    ])
    expect(args.providerOptions.gateway.byok).toEqual({
      google: [{ apiKey: 'g-key' }],
    })
  })

  it('omits providerOptions when there is no fallback and no BYOK', async () => {
    const generate = vi.fn(async () => fakeResult())
    const provider = new GatewayProvider({
      models: ['google/gemini-2.5-flash-lite'],
      generate: generate as never,
    })

    await provider.chat(baseParams())

    const args = (generate.mock.calls[0]! as unknown[])[0] as Record<
      string,
      unknown
    >
    expect(args.providerOptions).toBeUndefined()
  })

  it('maps tools to AI SDK tools and reports tool_use', async () => {
    const generate = vi.fn(async () =>
      fakeResult({
        text: '',
        toolCalls: [
          { toolCallId: 'c1', toolName: 'list_bills', input: { status: 'ok' } },
        ],
        finishReason: 'tool-calls',
      }),
    )
    const provider = new GatewayProvider({
      models: ['google/gemini-2.5-flash-lite'],
      generate: generate as never,
    })

    const result = await provider.chat(
      baseParams({
        tools: [
          {
            name: 'list_bills',
            description: 'Lists bills',
            parameters: { type: 'object', properties: {} },
          },
        ],
      }),
    )

    const args = (generate.mock.calls[0]! as unknown[])[0] as {
      tools: Record<string, unknown>
    }
    expect(Object.keys(args.tools)).toEqual(['list_bills'])
    expect(result.toolCalls).toEqual([
      { id: 'c1', name: 'list_bills', arguments: { status: 'ok' } },
    ])
    expect(result.stopReason).toBe('tool_use')
  })

  it('maps user attachments, assistant tool calls and tool results to model messages', async () => {
    const generate = vi.fn(async () => fakeResult())
    const provider = new GatewayProvider({
      models: ['google/gemini-2.5-flash-lite'],
      generate: generate as never,
    })

    await provider.chat(
      baseParams({
        messages: [
          {
            role: 'user',
            content: 'transcreva',
            attachments: [{ mimeType: 'audio/ogg', dataBase64: 'AAA' }],
          },
          {
            role: 'assistant',
            content: '',
            toolCalls: [{ id: 'c1', name: 'list_bills', arguments: {} }],
          },
          {
            role: 'tool',
            content: '{"ok":true}',
            toolCallId: 'c1',
            toolName: 'list_bills',
          },
        ],
      }),
    )

    const args = (generate.mock.calls[0]! as unknown[])[0] as {
      messages: unknown[]
    }
    const [userMsg, assistantMsg, toolMsg] = args.messages as Array<{
      role: string
      content: Array<Record<string, unknown>>
    }>
    expect(userMsg!.role).toBe('user')
    expect(userMsg!.content[1]).toMatchObject({
      type: 'file',
      mediaType: 'audio/ogg',
      data: 'AAA',
    })
    expect(assistantMsg!.content[0]).toMatchObject({
      type: 'tool-call',
      toolCallId: 'c1',
      toolName: 'list_bills',
    })
    expect(toolMsg!.content[0]).toMatchObject({
      type: 'tool-result',
      toolCallId: 'c1',
      output: { type: 'json', value: { ok: true } },
    })
  })

  it('maps a plain assistant message and a tool result with invalid JSON', async () => {
    const generate = vi.fn(async () => fakeResult())
    const provider = new GatewayProvider({
      models: ['google/gemini-2.5-flash-lite'],
      generate: generate as never,
    })

    await provider.chat(
      baseParams({
        messages: [
          { role: 'user', content: 'oi' },
          { role: 'assistant', content: 'tudo certo' },
          {
            role: 'assistant',
            content: 'vou checar',
            toolCalls: [{ id: 'c1', name: 'list_bills', arguments: {} }],
          },
          { role: 'tool', content: 'not-json', toolName: 'list_bills' },
        ],
      }),
    )

    const args = (generate.mock.calls[0]! as unknown[])[0] as {
      messages: unknown[]
    }
    const msgs = args.messages as Array<{
      role: string
      content: unknown
    }>
    expect(msgs[1]).toEqual({ role: 'assistant', content: 'tudo certo' })
    const withCall = msgs[2]!.content as Array<Record<string, unknown>>
    expect(withCall[0]).toMatchObject({ type: 'text', text: 'vou checar' })
    const toolContent = msgs[3]!.content as Array<Record<string, unknown>>
    expect(toolContent[0]).toMatchObject({
      type: 'tool-result',
      toolCallId: 'list_bills',
      output: { type: 'json', value: { result: 'not-json' } },
    })
  })

  it('defaults an unknown/missing finish reason to end', async () => {
    const unknown = new GatewayProvider({
      models: ['google/gemini-2.5-flash-lite'],
      generate: (async () => fakeResult({ finishReason: 'error' })) as never,
    })
    expect((await unknown.chat(baseParams())).stopReason).toBe('end')

    const missing = new GatewayProvider({
      models: ['google/gemini-2.5-flash-lite'],
      generate: (async () => ({ text: 'x', usage: {} })) as never,
    })
    expect((await missing.chat(baseParams())).stopReason).toBe('end')
  })

  it("passes the provider's own finish reason through", async () => {
    const provider = new GatewayProvider({
      models: ['google/gemini-2.5-flash-lite'],
      generate: (async () =>
        fakeResult({
          text: '',
          finishReason: 'other',
          rawFinishReason: 'MALFORMED_FUNCTION_CALL',
        })) as never,
    })

    const result = await provider.chat(baseParams())

    expect(result.stopReason).toBe('end')
    expect(result.rawFinishReason).toBe('MALFORMED_FUNCTION_CALL')
  })

  it('falls back to the unified finish reason when the provider gave none', async () => {
    const provider = new GatewayProvider({
      models: ['google/gemini-2.5-flash-lite'],
      generate: (async () => fakeResult({ finishReason: 'length' })) as never,
    })

    expect((await provider.chat(baseParams())).rawFinishReason).toBe('length')
  })

  it('maps finish reasons (length → max_tokens, content-filter → safety)', async () => {
    const len = new GatewayProvider({
      models: ['google/gemini-2.5-flash-lite'],
      generate: (async () => fakeResult({ finishReason: 'length' })) as never,
    })
    expect((await len.chat(baseParams())).stopReason).toBe('max_tokens')

    const safe = new GatewayProvider({
      models: ['google/gemini-2.5-flash-lite'],
      generate: (async () =>
        fakeResult({ finishReason: 'content-filter' })) as never,
    })
    expect((await safe.chat(baseParams())).stopReason).toBe('safety')
  })

  it('wraps generate failures in LlmProviderError', async () => {
    const provider = new GatewayProvider({
      models: ['google/gemini-2.5-flash-lite'],
      generate: (async () => {
        throw new Error('boom')
      }) as never,
    })
    await expect(provider.chat(baseParams())).rejects.toBeInstanceOf(
      LlmProviderError,
    )
  })

  it('falls back to empty/zero when result fields are missing', async () => {
    const provider = new GatewayProvider({
      models: ['google/gemini-2.5-flash-lite'],
      generate: (async () => ({ finishReason: 'stop' })) as never,
    })
    const result = await provider.chat(baseParams())
    expect(result.text).toBe('')
    expect(result.toolCalls).toEqual([])
    expect(result.usage.inputTokens).toBe(0)
  })
})

function withThrowingOutput<T extends object>(result: T): T {
  Object.defineProperty(result, 'experimental_output', {
    get() {
      throw new Error('No output generated.')
    },
  })
  return result
}

describe('GatewayProvider: structured output', () => {
  const SCHEMA: LlmChatParams['responseSchema'] = {
    type: 'object',
    properties: { merchant: { type: 'string' } },
    required: ['merchant'],
  }

  it('passes an output spec and returns the typed answer', async () => {
    const generate = vi.fn(async () =>
      fakeResult({ experimental_output: { merchant: 'market' } }),
    )
    const provider = new GatewayProvider({
      models: ['google/gemini-2.5-flash-lite'],
      generate: generate as never,
    })

    const result = await provider.chat(baseParams({ responseSchema: SCHEMA }))

    const args = (generate.mock.calls[0]! as unknown[])[0] as Record<
      string,
      unknown
    >
    expect(args.output).toBeDefined()
    expect(result.object).toEqual({ merchant: 'market' })
  })

  it('falls back to the text when the SDK leaves no output field', async () => {
    const generate = vi.fn(async () =>
      fakeResult({ text: '{"merchant":"sunny"}' }),
    )
    const provider = new GatewayProvider({
      models: ['google/gemini-2.5-flash-lite'],
      generate: generate as never,
    })

    const result = await provider.chat(baseParams({ responseSchema: SCHEMA }))

    expect(result.object).toEqual({ merchant: 'sunny' })
  })

  it('falls back when reading the output field throws, as the real SDK does', async () => {
    const generate = vi.fn(async () =>
      withThrowingOutput(fakeResult({ text: '{"merchant":"cloudy"}' })),
    )
    const provider = new GatewayProvider({
      models: ['google/gemini-2.5-flash-lite'],
      generate: generate as never,
    })

    const result = await provider.chat(baseParams({ responseSchema: SCHEMA }))

    expect(result.object).toEqual({ merchant: 'cloudy' })
  })

  it('fails clearly when neither the field nor the text carries an answer', async () => {
    const generate = vi.fn(async () =>
      withThrowingOutput(fakeResult({ text: 'desculpa' })),
    )
    const provider = new GatewayProvider({
      models: ['google/gemini-2.5-flash-lite'],
      generate: generate as never,
    })

    await expect(
      provider.chat(baseParams({ responseSchema: SCHEMA })),
    ).rejects.toThrow(LlmProviderError)
  })

  it('sends no output spec, and returns no object, without a schema', async () => {
    const generate = vi.fn(async () => fakeResult())
    const provider = new GatewayProvider({
      models: ['google/gemini-2.5-flash-lite'],
      generate: generate as never,
    })

    const result = await provider.chat(baseParams())

    const args = (generate.mock.calls[0]! as unknown[])[0] as Record<
      string,
      unknown
    >
    expect(args.output).toBeUndefined()
    expect(result).not.toHaveProperty('object')
  })

  it('bounds the call and trims the retries when a timeout is asked for', async () => {
    const generate = vi.fn(async () => fakeResult())
    const provider = new GatewayProvider({
      models: ['google/gemini-2.5-flash-lite'],
      generate: generate as never,
    })

    await provider.chat(baseParams({ timeoutMs: 8_000 }))

    const args = (generate.mock.calls[0]! as unknown[])[0] as Record<
      string,
      unknown
    >
    expect(args.abortSignal).toBeInstanceOf(AbortSignal)
    expect(args.maxRetries).toBe(1)
  })

  it('leaves the SDK defaults alone when no timeout is asked for', async () => {
    const generate = vi.fn(async () => fakeResult())
    const provider = new GatewayProvider({
      models: ['google/gemini-2.5-flash-lite'],
      generate: generate as never,
    })

    await provider.chat(baseParams())

    const args = (generate.mock.calls[0]! as unknown[])[0] as Record<
      string,
      unknown
    >
    expect(args.abortSignal).toBeUndefined()
    expect(args.maxRetries).toBeUndefined()
  })

  it('refuses a schema and tools together, like the direct provider', async () => {
    const generate = vi.fn(async () => fakeResult())
    const provider = new GatewayProvider({
      models: ['google/gemini-2.5-flash-lite'],
      generate: generate as never,
    })

    await expect(
      provider.chat(
        baseParams({
          responseSchema: SCHEMA,
          tools: [
            { name: 't', description: 'd', parameters: { type: 'object' } },
          ],
        }),
      ),
    ).rejects.toThrow(LlmProviderError)
    expect(generate).not.toHaveBeenCalled()
  })
})
