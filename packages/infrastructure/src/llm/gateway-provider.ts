import {
  Output,
  generateText,
  jsonSchema,
  tool,
  type GenerateTextResult,
  type JSONValue,
  type ModelMessage,
} from 'ai'
import type { JSONSchema7 } from '@ai-sdk/provider'

import { truncateMessages } from '@/llm/gemini-provider'
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
  LlmStopReason,
  LlmTool,
} from '@cashdeck/application'

type GenerateTextFn = (
  args: Record<string, unknown>,
) => Promise<GenerateTextResult<Record<string, never>, never>>

export interface GatewayProviderConfig {
  models: string[]
  apiKey?: string
  byokGoogleApiKey?: string
  brlPerUsd?: number
  generate?: GenerateTextFn
}

const FINISH_REASON_MAP: Record<string, LlmStopReason> = {
  stop: 'end',
  length: 'max_tokens',
  'content-filter': 'safety',
  'tool-calls': 'tool_use',
}

// Production path: AI Gateway with model fallbacks and optional BYOK, behind the
// same port as the direct Gemini adapter.
export class GatewayProvider implements LlmProvider {
  readonly name = 'gateway'

  readonly modelId: string

  private readonly models: string[]

  private readonly generate: GenerateTextFn

  constructor(private readonly config: GatewayProviderConfig) {
    if (!config.models.length) {
      throw new LlmProviderError(
        'GatewayProvider requires at least one model',
        'missing_model',
      )
    }
    this.models = config.models
    this.modelId = config.models[0]!
    this.generate =
      config.generate ?? (generateText as unknown as GenerateTextFn)
    if (config.apiKey) process.env.AI_GATEWAY_API_KEY = config.apiKey
  }

  async chat(params: LlmChatParams): Promise<LlmChatResult> {
    assertSchemaWithoutTools(params)

    const trimmed = truncateMessages(params.messages, params.maxInputTokens)
    const [primary, ...fallbacks] = this.models

    const gatewayOptions: Record<string, unknown> = {}
    if (fallbacks.length) gatewayOptions.models = fallbacks
    if (this.config.byokGoogleApiKey) {
      gatewayOptions.byok = {
        google: [{ apiKey: this.config.byokGoogleApiKey }],
      }
    }

    let result: GenerateTextResult<Record<string, never>, never>
    try {
      result = await this.generate({
        model: primary,
        system: params.system,
        messages: trimmed.map(toModelMessage),
        tools: params.tools.length ? toAiTools(params.tools) : undefined,
        ...(params.responseSchema
          ? {
              output: Output.object({
                schema: jsonSchema(
                  params.responseSchema as unknown as JSONSchema7,
                ),
              }),
            }
          : {}),
        maxOutputTokens: params.maxOutputTokens,
        temperature: params.temperature ?? 0.7,
        ...(params.timeoutMs
          ? {
              abortSignal: AbortSignal.timeout(params.timeoutMs),
              maxRetries: 1,
            }
          : {}),
        ...(Object.keys(gatewayOptions).length
          ? { providerOptions: { gateway: gatewayOptions } }
          : {}),
      })
    } catch (err) {
      throw new LlmProviderError(
        `AI Gateway rejected the request: ${err instanceof Error ? err.message : 'unknown error'}`,
        'chat_failed',
        err,
      )
    }

    const toolCalls = (result.toolCalls ?? []).map(call => ({
      id: call.toolCallId,
      name: call.toolName,
      arguments: (call.input ?? {}) as Record<string, unknown>,
    }))
    const inputTokens = result.usage?.inputTokens ?? 0
    const outputTokens = result.usage?.outputTokens ?? 0
    const stopReason: LlmStopReason =
      toolCalls.length > 0
        ? 'tool_use'
        : (FINISH_REASON_MAP[result.finishReason ?? 'stop'] ?? 'end')
    const rawFinishReason = result.rawFinishReason ?? result.finishReason

    return {
      text: result.text ?? '',
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
      ...(rawFinishReason ? { rawFinishReason } : {}),
      ...(params.responseSchema
        ? { object: readStructuredAnswer(result) }
        : {}),
    }
  }
}

function readStructuredAnswer(result: {
  experimental_output?: unknown
  text?: string
}): unknown {
  const output = readOutputField(result)
  if (output !== undefined) return output
  try {
    return JSON.parse(result.text ?? '')
  } catch {
    throw new LlmProviderError(
      'AI Gateway returned no structured answer for a schema request',
      'schema_response_invalid',
    )
  }
}

function readOutputField(result: { experimental_output?: unknown }): unknown {
  try {
    return result.experimental_output
  } catch {
    return undefined
  }
}

function toModelMessage(message: LlmMessage): ModelMessage {
  if (message.role === 'tool') {
    return {
      role: 'tool',
      content: [
        {
          type: 'tool-result',
          toolCallId: message.toolCallId ?? message.toolName ?? 'tool',
          toolName: message.toolName ?? 'tool',
          output: {
            type: 'json',
            value: parseToolResponse(message.content) as JSONValue,
          },
        },
      ],
    }
  }

  if (message.role === 'assistant' && message.toolCalls?.length) {
    return {
      role: 'assistant',
      content: [
        ...(message.content
          ? [{ type: 'text' as const, text: message.content }]
          : []),
        ...message.toolCalls.map(call => ({
          type: 'tool-call' as const,
          toolCallId: call.id,
          toolName: call.name,
          input: call.arguments,
        })),
      ],
    }
  }

  if (message.role === 'assistant') {
    return { role: 'assistant', content: message.content }
  }

  if (message.attachments?.length) {
    return {
      role: 'user',
      content: [
        { type: 'text', text: message.content },
        ...message.attachments.map(attachment => ({
          type: 'file' as const,
          mediaType: attachment.mimeType,
          data: attachment.dataBase64,
        })),
      ],
    }
  }

  return { role: 'user', content: message.content }
}

function toAiTools(tools: LlmTool[]): Record<string, ReturnType<typeof tool>> {
  const out: Record<string, ReturnType<typeof tool>> = {}
  for (const t of tools) {
    out[t.name] = tool({
      description: t.description,
      inputSchema: jsonSchema(t.parameters as unknown as JSONSchema7),
    })
  }
  return out
}

function parseToolResponse(content: string): unknown {
  try {
    return JSON.parse(content) as unknown
  } catch {
    return { result: content }
  }
}
