import {
  FakeLlmProvider,
  type LlmProvider,
  LlmProviderError,
} from '@cashdeck/application'
import { GatewayProvider } from '@/llm/gateway-provider'
import { GeminiProvider } from '@/llm/gemini-provider'

export type LlmEnv = Record<string, string | undefined>

export const DEFAULT_CHAT_MODEL_ID = 'gemini-2.5-flash-lite'
export const DEFAULT_STRONG_MODEL = 'google/gemini-2.5-flash'

function brlPerUsd(env: LlmEnv): number | undefined {
  return env.BRL_PER_USD ? Number(env.BRL_PER_USD) : undefined
}

function gateway(env: LlmEnv): GatewayProvider {
  const primary = `google/${env.GEMINI_MODEL_ID || DEFAULT_CHAT_MODEL_ID}`
  const fallback = env.AI_GATEWAY_FALLBACK_MODEL || DEFAULT_STRONG_MODEL
  return new GatewayProvider({
    models: primary === fallback ? [primary] : [primary, fallback],
    apiKey: env.AI_GATEWAY_API_KEY,
    byokGoogleApiKey: env.GEMINI_API_KEY || undefined,
    brlPerUsd: brlPerUsd(env),
  })
}

function gemini(env: LlmEnv): GeminiProvider {
  return new GeminiProvider({
    apiKey: env.GEMINI_API_KEY ?? '',
    modelId: env.GEMINI_MODEL_ID || undefined,
    brlPerUsd: brlPerUsd(env),
  })
}

const BUILDERS: Record<string, (env: LlmEnv) => LlmProvider> = {
  fake: () => new FakeLlmProvider(),
  gateway,
  gemini,
}

export function createLlmProvider(env: LlmEnv): LlmProvider {
  const choice = (env.LLM_PROVIDER || 'fake').toLowerCase()
  const build = BUILDERS[choice]
  if (!build) {
    throw new LlmProviderError(
      `Unknown LLM_PROVIDER: ${choice}`,
      'unknown_provider',
    )
  }
  return build(env)
}
