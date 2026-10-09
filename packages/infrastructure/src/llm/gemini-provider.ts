import {
  LlmProviderError,
  assertSchemaWithoutTools,
  type LlmProvider,
} from '@cashdeck/application'
import { calculateCostMillicents } from '@/llm/pricing'
import type {
  LlmChatParams,
  LlmChatResult,
  LlmMessage,
  LlmToolParameter,
  LlmStopReason,
  LlmTool,
  LlmToolCall,
} from '@cashdeck/application'

const GEMINI_BASE_URL = 'https://generativelanguage.googleapis.com/v1beta'

export interface GeminiProviderConfig {
  apiKey: string
  modelId?: string
  brlPerUsd?: number
  fetchImpl?: typeof fetch
}

interface GeminiPart {
  text?: string
  inlineData?: { mimeType: string; data: string }
  functionCall?: { name: string; args: Record<string, unknown> }
  functionResponse?: { name: string; response: Record<string, unknown> }
}

interface GeminiContent {
  role: 'user' | 'model'
  parts: GeminiPart[]
}

interface GeminiResponse {
  candidates?: {
    content?: { parts?: GeminiPart[] }
    finishReason?: string
  }[]
  usageMetadata?: {
    promptTokenCount?: number
    candidatesTokenCount?: number
  }
}

const FINISH_REASON_MAP: Record<string, LlmStopReason> = {
  STOP: 'end',
  MAX_TOKENS: 'max_tokens',
  SAFETY: 'safety',
  RECITATION: 'safety',
  TOOL_USE: 'tool_use',
}

export class GeminiProvider implements LlmProvider {
  readonly name = 'gemini'

  readonly modelId: string

  private readonly fetchImpl: typeof fetch

  constructor(private readonly config: GeminiProviderConfig) {
    if (!config.apiKey) {
      throw new LlmProviderError(
        'GEMINI_API_KEY is required',
        'missing_api_key',
      )
    }
    this.modelId = config.modelId || 'gemini-3.8-flash'
    this.fetchImpl = config.fetchImpl ?? fetch
  }

  async chat(params: LlmChatParams): Promise<LlmChatResult> {
    assertSchemaWithoutTools(params)

    const trimmedMessages = truncateMessages(
      params.messages,
      params.maxInputTokens,
    )

    const body = {
      systemInstruction: { role: 'system', parts: [{ text: params.system }] },
      contents: trimmedMessages.map(toGeminiContent),
      generationConfig: {
        maxOutputTokens: params.maxOutputTokens,
        temperature: params.temperature ?? 0.7,
        ...(params.responseSchema
          ? {
              responseMimeType: 'application/json',
              responseSchema: toGeminiSchema(params.responseSchema),
            }
          : {}),
      },
      tools: params.tools.length
        ? [{ functionDeclarations: params.tools.map(toGeminiTool) }]
        : undefined,
    }

    const response = await this.fetchImpl(
      `${GEMINI_BASE_URL}/models/${this.modelId}:generateContent?key=${encodeURIComponent(this.config.apiKey)}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
        ...(params.timeoutMs
          ? { signal: AbortSignal.timeout(params.timeoutMs) }
          : {}),
      },
    )
    if (!response.ok) {
      const text = await response.text().catch(() => '')
      throw new LlmProviderError(
        `Gemini API rejected the request: ${response.status} ${text}`,
        'chat_failed',
      )
    }
    const data = (await response.json()) as GeminiResponse
    const candidate = data.candidates?.[0]
    if (!candidate) {
      throw new LlmProviderError(
        'Gemini response missing candidate',
        'chat_response_invalid',
      )
    }

    const parts = candidate.content?.parts ?? []
    const text = parts
      .map(part => part.text ?? '')
      .filter(Boolean)
      .join('')
    const toolCalls = extractToolCalls(parts)
    const inputTokens = data.usageMetadata?.promptTokenCount ?? 0
    const outputTokens = data.usageMetadata?.candidatesTokenCount ?? 0
    const stopReason =
      toolCalls.length > 0
        ? 'tool_use'
        : (FINISH_REASON_MAP[candidate.finishReason ?? 'STOP'] ?? 'end')

    return {
      text,
      toolCalls,
      usage: {
        inputTokens,
        outputTokens,
        costMillicents: calculateCostMillicents({
          modelId: this.modelId,
          inputTokens,
          outputTokens,
          brlPerUsd: this.config.brlPerUsd,
        }),
      },
      stopReason,
      ...(candidate.finishReason
        ? { rawFinishReason: candidate.finishReason }
        : {}),
      ...(params.responseSchema
        ? { object: parseStructuredAnswer(text, stopReason) }
        : {}),
    }
  }
}

function parseStructuredAnswer(
  text: string,
  stopReason: LlmStopReason,
): unknown {
  try {
    return JSON.parse(text)
  } catch {
    if (stopReason === 'max_tokens') {
      throw new LlmProviderError(
        'Structured answer was cut off by the output token limit',
        'schema_response_truncated',
      )
    }
    throw new LlmProviderError(
      'Gemini answered JSON mode with something that is not JSON',
      'schema_response_invalid',
    )
  }
}

function toGeminiSchema(schema: LlmToolParameter): Record<string, unknown> {
  const out: Record<string, unknown> = { type: schema.type.toUpperCase() }
  if (schema.description) out.description = schema.description
  if (schema.enum) out.enum = schema.enum
  if (schema.required) out.required = schema.required
  if (schema.items) out.items = toGeminiSchema(schema.items)
  if (schema.properties) {
    const properties: Record<string, unknown> = {}
    for (const [name, property] of Object.entries(schema.properties)) {
      properties[name] = toGeminiSchema(property)
    }
    out.properties = properties
  }
  return out
}

function approximateTokens(text: string): number {
  return Math.ceil(text.length / 4)
}

function messageTokens(message: LlmMessage): number {
  const calls = message.toolCalls?.length
    ? JSON.stringify(message.toolCalls)
    : ''
  return approximateTokens(message.content + calls)
}

function unitTokens(unit: LlmMessage[]): number {
  return unit.reduce((sum, message) => sum + messageTokens(message), 0)
}

// The turn being answered keeps every message (its oldest tool results clipped);
// older messages leave whole, and a tool result never travels without its call.
export function truncateMessages(
  messages: LlmMessage[],
  maxInputTokens: number,
): LlmMessage[] {
  if (messages.length === 0) return messages
  const start = currentTurnStart(messages)
  const tail = clipToolResults(messages.slice(start), maxInputTokens)
  let total = unitTokens(tail)
  const head: LlmMessage[] = []
  const units = groupToolExchanges(messages.slice(0, start))
  for (let i = units.length - 1; i >= 0; i -= 1) {
    const unit = units[i]!
    const cost = unitTokens(unit)
    if (total + cost > maxInputTokens) break
    total += cost
    head.unshift(...unit)
  }
  return [...head, ...tail]
}

const MIN_CLIPPED_RESULT_TOKENS = 200
const CLIPPED_MARK = '…[truncated]'

function clipToolResults(
  turn: LlmMessage[],
  maxInputTokens: number,
): LlmMessage[] {
  let over = unitTokens(turn) - maxInputTokens
  const clipped: LlmMessage[] = []
  for (const message of turn) {
    const tokens = messageTokens(message)
    const keep = Math.max(MIN_CLIPPED_RESULT_TOKENS, tokens - over)
    if (over <= 0 || message.role !== 'tool' || keep >= tokens) {
      clipped.push(message)
      continue
    }
    over -= tokens - keep
    const content = message.content.slice(0, keep * 4 - CLIPPED_MARK.length)
    clipped.push({ ...message, content: `${content}${CLIPPED_MARK}` })
  }
  return clipped
}

function currentTurnStart(messages: LlmMessage[]): number {
  const lastUser = messages.findLastIndex(message => message.role === 'user')
  if (lastUser >= 0) return lastUser
  let start = messages.length - 1
  while (start > 0 && messages[start]!.role === 'tool') start -= 1
  return start
}

function groupToolExchanges(messages: LlmMessage[]): LlmMessage[][] {
  const units: LlmMessage[][] = []
  for (const message of messages) {
    const open = units.at(-1)
    if (message.role === 'tool' && open?.[0]?.toolCalls?.length) {
      open.push(message)
      continue
    }
    units.push([message])
  }
  return units
}

function toGeminiContent(message: LlmMessage): GeminiContent {
  if (message.role === 'tool') {
    return {
      role: 'user',
      parts: [
        {
          functionResponse: {
            name: message.toolName ?? 'tool',
            response: parseToolResponse(message.content),
          },
        },
      ],
    }
  }
  if (message.role === 'assistant' && message.toolCalls?.length) {
    const parts: GeminiPart[] = []
    if (message.content) parts.push({ text: message.content })
    for (const call of message.toolCalls) {
      parts.push({ functionCall: { name: call.name, args: call.arguments } })
    }
    return { role: 'model', parts }
  }
  const parts: GeminiPart[] = [{ text: message.content }]
  for (const attachment of message.attachments ?? []) {
    parts.push({
      inlineData: {
        mimeType: attachment.mimeType,
        data: attachment.dataBase64,
      },
    })
  }
  return {
    role: message.role === 'assistant' ? 'model' : 'user',
    parts,
  }
}

function parseToolResponse(content: string): Record<string, unknown> {
  try {
    const parsed = JSON.parse(content) as unknown
    if (
      parsed !== null &&
      typeof parsed === 'object' &&
      !Array.isArray(parsed)
    ) {
      return parsed as Record<string, unknown>
    }
    return { result: parsed }
  } catch {
    return { result: content }
  }
}

function toGeminiTool(tool: LlmTool): {
  name: string
  description: string
  parameters: unknown
} {
  return {
    name: tool.name,
    description: tool.description,
    parameters: tool.parameters,
  }
}

function extractToolCalls(parts: GeminiPart[]): LlmToolCall[] {
  const calls: LlmToolCall[] = []
  parts.forEach((part, index) => {
    if (part.functionCall) {
      calls.push({
        id: `call_${index}`,
        name: part.functionCall.name,
        arguments: part.functionCall.args ?? {},
      })
    }
  })
  return calls
}
