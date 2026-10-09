import { describe, expect, it } from 'vitest'
import { FakeLlmProvider } from '@/testing/providers'
import { FixedClock } from '@/testing/system'
import { type AgentTool, runAgentTurn } from '@/use-cases/chat/agent'
import { type LlmChatResult } from '@/ports/llm-provider'

const NOW = new Date('2026-10-08T12:00:00Z')
const usage = { inputTokens: 10, outputTokens: 5, costMillicents: 7 }

const reply = (overrides: Partial<LlmChatResult>): LlmChatResult => ({
  text: '',
  toolCalls: [],
  usage,
  stopReason: 'end',
  ...overrides,
})

const call = (name: string, args: Record<string, unknown> = {}) =>
  reply({ toolCalls: [{ id: `call-${name}`, name, arguments: args }] })

function setup(clock = new FixedClock(NOW)) {
  const llm = new FakeLlmProvider()
  const ran: Array<Record<string, unknown>> = []
  const tools: AgentTool[] = [
    {
      name: 'echo',
      description: 'Echo',
      parameters: { type: 'object', properties: {} },
      run: async args => {
        ran.push(args)
        return { echoed: args }
      },
    },
    {
      name: 'broken',
      description: 'Fails',
      parameters: { type: 'object', properties: {} },
      run: async () => {
        throw new Error('no data')
      },
    },
    {
      name: 'weird',
      description: 'Throws a string',
      parameters: { type: 'object', properties: {} },
      run: async () => {
        throw 'odd'
      },
    },
  ]
  const run = (maxRounds = 4, budgetMs = 10_000) =>
    runAgentTurn({
      llm,
      clock,
      system: 'system',
      messages: [{ role: 'user', content: 'hello' }],
      tools,
      maxRounds,
      budgetMs,
    })
  return { llm, ran, run, clock }
}

describe('runAgentTurn', () => {
  it('runs tools until the model answers, adding up the usage', async () => {
    const { llm, ran, run } = setup()
    llm
      .enqueue(call('echo', { a: 1 }))
      .enqueue(
        reply({
          toolCalls: [
            { id: 'x', name: 'broken', arguments: {} },
            { id: 'y', name: 'missing', arguments: {} },
            { id: 'z', name: 'weird', arguments: {} },
          ],
        }),
      )
      .enqueue(reply({ text: '  Done.  ' }))
    const result = await run()
    expect(result).toEqual({
      text: 'Done.',
      notice: null,
      usage: { inputTokens: 30, outputTokens: 15, costMillicents: 21 },
      tools: [
        { name: 'echo', arguments: { a: 1 }, ok: true },
        { name: 'broken', arguments: {}, ok: false },
        { name: 'missing', arguments: {}, ok: false },
        { name: 'weird', arguments: {}, ok: false },
      ],
    })
    expect(ran).toEqual([{ a: 1 }])
    const last = llm.calls[2]?.messages ?? []
    expect(last.map(m => m.role)).toEqual([
      'user',
      'assistant',
      'tool',
      'assistant',
      'tool',
      'tool',
      'tool',
    ])
    expect(last[4]?.content).toBe('{"error":"no data"}')
    expect(last[5]?.content).toBe('{"error":"Unknown tool missing."}')
    expect(last[6]?.content).toBe('{"error":"The tool failed."}')
    expect(llm.calls[0]?.tools.map(t => t.name)).toEqual([
      'echo',
      'broken',
      'weird',
    ])
    expect(llm.calls[0]?.timeoutMs).toBe(10_000)
  })

  it('retries one empty answer, then gives up with a notice', async () => {
    const { llm, run } = setup()
    llm.enqueue(reply({})).enqueue(reply({ text: 'Hi' }))
    expect((await run()).text).toBe('Hi')
    llm.enqueue(reply({})).enqueue(reply({ text: ' ' }))
    expect((await run()).notice).toBe('EMPTY')
  })

  it('stops at the round limit and at the time budget', async () => {
    const { llm, run, clock } = setup()
    llm.enqueue(call('echo')).enqueue(call('echo'))
    expect(await run(2)).toMatchObject({ notice: 'ROUND_LIMIT', text: '' })
    const slow = setup(clock)
    slow.llm.chat = async params => {
      clock.set(new Date(NOW.getTime() + 20_000))
      slow.llm.calls.push(params)
      return call('echo')
    }
    expect(await slow.run(4, 10_000)).toMatchObject({ notice: 'TIME_BUDGET' })
    expect(slow.llm.calls).toHaveLength(1)
  })
})
