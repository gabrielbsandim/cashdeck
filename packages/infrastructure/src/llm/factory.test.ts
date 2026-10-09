import { describe, expect, it } from 'vitest'
import { LlmProviderError } from '@cashdeck/application'
import { createLlmProvider } from '@/llm/factory'

describe('createLlmProvider', () => {
  it('defaults to the fake provider', () => {
    expect(createLlmProvider({}).name).toBe('fake')
  })

  it('builds the gateway with a fallback model', () => {
    const provider = createLlmProvider({
      LLM_PROVIDER: 'Gateway',
      BRL_PER_USD: '5.5',
    })
    expect(provider.name).toBe('gateway')
    expect(provider.modelId).toBe('google/gemini-3.1-flash-lite')
  })

  it('drops the fallback when it equals the primary model', () => {
    const provider = createLlmProvider({
      LLM_PROVIDER: 'gateway',
      GEMINI_MODEL_ID: 'gemini-3.8-flash',
      GEMINI_API_KEY: 'byok',
    })
    expect(provider.modelId).toBe('google/gemini-3.8-flash')
  })

  it('builds the direct Gemini provider', () => {
    const provider = createLlmProvider({
      LLM_PROVIDER: 'gemini',
      GEMINI_API_KEY: 'k',
    })
    expect(provider.modelId).toBe('gemini-3.1-flash-lite')
    expect(() => createLlmProvider({ LLM_PROVIDER: 'gemini' })).toThrow(
      'GEMINI_API_KEY is required',
    )
  })

  it('rejects an unknown provider', () => {
    expect(() => createLlmProvider({ LLM_PROVIDER: 'other' })).toThrow(
      LlmProviderError,
    )
  })
})
