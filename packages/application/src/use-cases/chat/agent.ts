import {
  type LlmMessage,
  type LlmProvider,
  type LlmToolCall,
  type LlmToolParameter,
  type LlmUsage,
} from '@/ports/llm-provider'
import { type ChatNotice, type ToolTrace } from '@/ports/chat'
import { type Clock } from '@/ports/system'

export type AgentTool = {
  name: string
  description: string
  parameters: LlmToolParameter
  run(args: Record<string, unknown>): Promise<unknown>
}

export type AgentTurnInput = {
  llm: LlmProvider
  clock: Clock
  system: string
  messages: LlmMessage[]
  tools: readonly AgentTool[]
  maxRounds: number
  budgetMs: number
  maxInputTokens?: number
  maxOutputTokens?: number
}

export type AgentTurnResult = {
  text: string
  notice: ChatNotice | null
  usage: LlmUsage
  tools: ToolTrace[]
}

const describeError = (error: unknown) =>
  error instanceof Error ? error.message : 'The tool failed.'

async function runTool(
  tools: readonly AgentTool[],
  call: LlmToolCall,
): Promise<{ output: unknown; ok: boolean }> {
  const tool = tools.find(candidate => candidate.name === call.name)
  if (!tool) {
    return { output: { error: `Unknown tool ${call.name}.` }, ok: false }
  }
  try {
    return { output: await tool.run(call.arguments), ok: true }
  } catch (error) {
    return { output: { error: describeError(error) }, ok: false }
  }
}

// Bounded by rounds and by wall time; one empty answer is retried, since the
// model sometimes returns nothing after a tool result.
export async function runAgentTurn(
  input: AgentTurnInput,
): Promise<AgentTurnResult> {
  const started = input.clock.now().getTime()
  const messages = [...input.messages]
  const usage: LlmUsage = { inputTokens: 0, outputTokens: 0, costMillicents: 0 }
  const trace: ToolTrace[] = []
  const specs = input.tools.map(({ name, description, parameters }) => ({
    name,
    description,
    parameters,
  }))
  const finish = (notice: ChatNotice | null, text = '') => ({
    text,
    notice,
    usage,
    tools: trace,
  })
  let retried = false
  for (let round = 0; round < input.maxRounds; round += 1) {
    const remaining = input.budgetMs - (input.clock.now().getTime() - started)
    if (remaining <= 0) {
      return finish('TIME_BUDGET')
    }
    const reply = await input.llm.chat({
      system: input.system,
      messages: [...messages],
      tools: specs,
      maxInputTokens: input.maxInputTokens ?? 60_000,
      maxOutputTokens: input.maxOutputTokens ?? 2_000,
      temperature: 0.3,
      timeoutMs: remaining,
    })
    usage.inputTokens += reply.usage.inputTokens
    usage.outputTokens += reply.usage.outputTokens
    usage.costMillicents += reply.usage.costMillicents
    if (reply.toolCalls.length === 0 && reply.text.trim()) {
      return finish(null, reply.text.trim())
    }
    if (reply.toolCalls.length === 0 && retried) {
      return finish('EMPTY')
    }
    if (reply.toolCalls.length === 0) {
      retried = true
      continue
    }
    messages.push({
      role: 'assistant',
      content: reply.text,
      toolCalls: reply.toolCalls,
    })
    for (const call of reply.toolCalls) {
      const { output, ok } = await runTool(input.tools, call)
      trace.push({ name: call.name, arguments: call.arguments, ok })
      messages.push({
        role: 'tool',
        toolCallId: call.id,
        toolName: call.name,
        content: JSON.stringify(output),
      })
    }
  }
  return finish('ROUND_LIMIT')
}
