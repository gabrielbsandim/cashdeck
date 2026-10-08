export type LlmRole = 'user' | 'assistant' | 'tool'

export type LlmAttachment = { mimeType: string; dataBase64: string }

export type LlmToolCall = {
  id: string
  name: string
  arguments: Record<string, unknown>
}

export type LlmMessage = {
  role: LlmRole
  content: string
  toolCallId?: string
  toolName?: string
  toolCalls?: LlmToolCall[]
  attachments?: LlmAttachment[]
}

export type LlmToolParameter = {
  type: 'string' | 'number' | 'boolean' | 'object' | 'array'
  description?: string
  enum?: string[]
  properties?: Record<string, LlmToolParameter>
  items?: LlmToolParameter
  required?: string[]
}

export type LlmTool = {
  name: string
  description: string
  parameters: LlmToolParameter
}

export type LlmStopReason = 'end' | 'max_tokens' | 'tool_use' | 'safety'

export type LlmUsage = {
  inputTokens: number
  outputTokens: number
  // Thousandths of a cent: one call routinely costs less than a whole cent.
  costMillicents: number
}

export type LlmChatParams = {
  system: string
  messages: LlmMessage[]
  tools: LlmTool[]
  maxInputTokens: number
  maxOutputTokens: number
  temperature?: number
  responseSchema?: LlmToolParameter
  timeoutMs?: number
}

export type LlmChatResult = {
  text: string
  toolCalls: LlmToolCall[]
  usage: LlmUsage
  stopReason: LlmStopReason
  rawFinishReason?: string
  object?: unknown
}

export interface LlmProvider {
  readonly name: string
  readonly modelId: string
  chat(params: LlmChatParams): Promise<LlmChatResult>
}

export class LlmProviderError extends Error {
  constructor(
    message: string,
    readonly code: string,
    override readonly cause?: unknown,
  ) {
    super(message)
    this.name = 'LlmProviderError'
  }
}

// Gemini rejects JSON mode and function calling in one request; every adapter,
// the fake included, refuses it here so the mistake fails before it is paid for.
export function assertSchemaWithoutTools(params: LlmChatParams): void {
  if (params.responseSchema && params.tools.length > 0) {
    throw new LlmProviderError(
      'responseSchema and tools cannot be used in the same call',
      'schema_with_tools',
    )
  }
}
