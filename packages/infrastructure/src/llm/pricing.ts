export interface ModelPricing {
  inputUsdPerMTokens: number
  outputUsdPerMTokens: number
}

export const MODEL_PRICING: Record<string, ModelPricing> = {
  'gemini-3.1-flash-lite': {
    inputUsdPerMTokens: 0.25,
    outputUsdPerMTokens: 1.5,
  },
  'gemini-3.5-flash-lite': {
    inputUsdPerMTokens: 0.3,
    outputUsdPerMTokens: 2.5,
  },
  // Launch price; Google doubles it to 1.5 and 7.5 on 2027-01-01.
  'gemini-3.8-flash': {
    inputUsdPerMTokens: 0.75,
    outputUsdPerMTokens: 3.75,
  },
  'gemini-2.5-flash': {
    inputUsdPerMTokens: 0.3,
    outputUsdPerMTokens: 2.5,
  },
  'gemini-2.5-flash-lite': {
    inputUsdPerMTokens: 0.1,
    outputUsdPerMTokens: 0.4,
  },
}

export interface CostInputs {
  modelId: string
  inputTokens: number
  outputTokens: number
  brlPerUsd?: number
}

// Costs are stored in millicents: a single call often costs less than a cent,
// and rounding to cents would sum to zero.
export const MILLICENTS_PER_CENT = 1000

export function calculateCostMillicents(inputs: CostInputs): number {
  const bareModelId = inputs.modelId.includes('/')
    ? inputs.modelId.slice(inputs.modelId.lastIndexOf('/') + 1)
    : inputs.modelId
  const pricing = MODEL_PRICING[bareModelId]
  if (!pricing) return 0
  const brlPerUsd = inputs.brlPerUsd ?? 5
  const usd =
    (inputs.inputTokens / 1_000_000) * pricing.inputUsdPerMTokens +
    (inputs.outputTokens / 1_000_000) * pricing.outputUsdPerMTokens
  return Math.round(usd * brlPerUsd * 100 * MILLICENTS_PER_CENT)
}

export function millicentsToReais(millicents: number): number {
  return millicents / (100 * MILLICENTS_PER_CENT)
}

export function millicentsToBrl(millicents: number): string {
  return millicentsToReais(millicents).toFixed(2)
}

export function formatMillicentsBrl4Decimals(millicents: number): string {
  return millicentsToReais(millicents).toLocaleString('pt-BR', {
    style: 'currency',
    currency: 'BRL',
    minimumFractionDigits: 4,
    maximumFractionDigits: 4,
  })
}
