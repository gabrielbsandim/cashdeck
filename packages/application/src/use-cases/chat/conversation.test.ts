import { describe, expect, it } from 'vitest'
import { ValidationError } from '@cashdeck/domain'
import { sendMessageSchema } from '@/dtos/chat'
import { ConflictError, NotFoundError } from '@/errors/errors'
import { type LlmChatResult } from '@/ports/llm-provider'
import { account, base64, fullDeps } from '@/testing/deps.test-helpers'
import { FakePaymentRail } from '@/testing/providers'
import { TENANT } from '@/testing/scenario.test-helpers'
import { ensureCategories } from '@/use-cases/categorization'
import { DEFAULT_CHAT_CONFIG, makeChat } from '@/use-cases/chat/chat'
import { makePixContacts } from '@/use-cases/pix-contacts'

const usage = { inputTokens: 1, outputTokens: 1, costMillicents: 500 }

const say = (text: string): LlmChatResult => ({
  text,
  toolCalls: [],
  usage,
  stopReason: 'end',
})

const use = (name: string, args: Record<string, unknown>): LlmChatResult => ({
  text: '',
  toolCalls: [{ id: `c-${name}`, name, arguments: args }],
  usage,
  stopReason: 'tool_use',
})

async function setup() {
  const deps = fullDeps({ rails: [new FakePaymentRail('ASAAS')] })
  await deps.accounts.save(account({ id: 'pf-1', entityId: 'pf' }))
  await ensureCategories(deps, TENANT)
  const chat = makeChat(deps, DEFAULT_CHAT_CONFIG)
  const contacts = makePixContacts(deps)
  return { deps, chat, contacts }
}

const message = (text: string, extra: Record<string, unknown> = {}) =>
  sendMessageSchema.parse({ text, ...extra })

describe('sending again', () => {
  it('returns the stored reply for a client id it already answered', async () => {
    const { deps, chat } = await setup()
    const thread = await chat.createThread(TENANT, { scope: 'PF' })
    deps.llm.enqueue(say('Oi!'))
    const first = await chat.sendMessage(
      TENANT,
      thread.id,
      message('Oi', { clientId: 'client-0001' }),
    )
    const again = await chat.sendMessage(
      TENANT,
      thread.id,
      message('Oi', { clientId: 'client-0001' }),
    )
    expect(again.messages).toEqual(first.messages)
    expect(deps.llm.calls).toHaveLength(1)
    expect(() => message('Oi', { clientId: 'short' })).toThrow()
  })

  it('answers anew when the stored reply was discarded since', async () => {
    const { deps, chat } = await setup()
    const thread = await chat.createThread(TENANT, { scope: 'PF' })
    deps.llm.enqueue(say('Oi!'))
    const first = await chat.sendMessage(
      TENANT,
      thread.id,
      message('Oi', { clientId: 'client-0002' }),
    )
    const [user, reply] = first.messages
    await deps.chat.deleteMessages(TENANT, thread.id, [reply?.id as string])
    deps.llm.enqueue(say('De novo.'))
    const again = await chat.sendMessage(
      TENANT,
      thread.id,
      message('Oi', { clientId: 'client-0002' }),
    )
    expect(again.messages[0]?.id).not.toBe(user?.id)
    expect(again.messages[1]?.text).toBe('De novo.')
  })
})

describe('regenerate', () => {
  it('edits a message, drops what came after and answers again', async () => {
    const { deps, chat } = await setup()
    const thread = await chat.createThread(TENANT, { scope: 'PF' })
    deps.llm.enqueue(say('Primeira.'))
    const first = await chat.sendMessage(TENANT, thread.id, message('Oi'))
    deps.llm
      .enqueue(
        use('send_pix', { name: 'Ana', pixKey: 'ana@example.com', amount: 10 }),
      )
      .enqueue(say('Confirme.'))
    const second = await chat.sendMessage(
      TENANT,
      thread.id,
      message('Pix de 10 pra Ana'),
    )
    const action = second.messages[1]?.actions[0]
    expect(action?.status).toBe('PENDING')

    deps.llm.enqueue(say('Editada.'))
    const firstId = first.messages[0]?.id as string
    const edited = await chat.regenerate(TENANT, thread.id, firstId, {
      text: 'Olá',
    })
    expect(
      edited.messages.map(m => [m.id === firstId, m.role, m.text]),
    ).toEqual([
      [true, 'user', 'Olá'],
      [false, 'assistant', 'Editada.'],
    ])
    const stored = await chat.listMessages(TENANT, thread.id, { limit: 10 })
    expect(stored.items.map(m => m.text)).toEqual(['Olá', 'Editada.'])
    expect(
      (await deps.chat.findAction(TENANT, action?.id as string))?.status,
    ).toBe('CANCELLED')
    const [listed] = (await chat.listThreads(TENANT, { limit: 1 })).items
    expect(listed?.title).toBe('Olá')
    expect(deps.llm.calls.at(-1)?.messages).toHaveLength(1)
  })

  it('sends a message again as it was, with its files', async () => {
    const { deps, chat } = await setup()
    const thread = await chat.createThread(TENANT, { scope: 'PF' })
    deps.llm.enqueue(say('Ok.'))
    await chat.sendMessage(TENANT, thread.id, message('Oi'))
    deps.llm.enqueue(say('Erro?'))
    const sent = await chat.sendMessage(
      TENANT,
      thread.id,
      message('Veja', {
        attachments: [
          {
            fileName: 'bill.pdf',
            mimeType: 'application/pdf',
            base64: base64('pdf'),
          },
        ],
      }),
    )
    deps.llm.enqueue(say('Agora sim.'))
    const retried = await chat.regenerate(
      TENANT,
      thread.id,
      sent.messages[0]?.id as string,
      {},
    )
    expect(retried.messages[0]?.text).toBe('Veja')
    expect(retried.messages[0]?.attachments).toHaveLength(1)
    expect(retried.messages[1]?.text).toBe('Agora sim.')
    const call = deps.llm.calls.at(-1)
    expect(call?.messages.at(-1)?.attachments).toEqual([
      { mimeType: 'application/pdf', dataBase64: base64('pdf') },
    ])
    expect(call?.messages).toHaveLength(3)
    const [listed] = (await chat.listThreads(TENANT, { limit: 1 })).items
    expect(listed?.title).toBe('Oi')

    deps.llm.enqueue(say('Do começo.'))
    const firstId = (await chat.listMessages(TENANT, thread.id, { limit: 1 }))
      .items[0]?.id as string
    await chat.regenerate(TENANT, thread.id, firstId, {})
    expect(await deps.chat.listAttachments(TENANT, thread.id)).toEqual([])
    expect(listed?.title).toBe('Oi')
  })

  it('pays from the entity the user picked, if it still exists', async () => {
    const { deps, chat } = await setup()
    const thread = await chat.createThread(TENANT, { scope: 'ALL' })
    deps.llm
      .enqueue(
        use('send_pix', { name: 'Ana', pixKey: 'ana@example.com', amount: 1 }),
      )
      .enqueue(say('Ok.'))
    const turn = await chat.sendMessage(TENANT, thread.id, message('Pix'))
    deps.entities.list = async () => []
    const failed = await chat.confirmAction(
      TENANT,
      turn.messages[1]?.actions[0]?.id as string,
      { entity: 'PJ' },
    )
    expect(failed).toMatchObject({
      status: 'FAILED',
      error: 'Entity was not found.',
    })
  })

  it('only takes a message the user sent in the thread', async () => {
    const { deps, chat } = await setup()
    const thread = await chat.createThread(TENANT, { scope: 'PF' })
    const other = await chat.createThread(TENANT, { scope: 'PF' })
    deps.llm.enqueue(say('Oi!'))
    const sent = await chat.sendMessage(TENANT, thread.id, message('Oi'))
    const [user, reply] = sent.messages
    await expect(
      chat.regenerate(TENANT, thread.id, reply?.id as string, {}),
    ).rejects.toThrow(ValidationError)
    await expect(
      chat.regenerate(TENANT, other.id, user?.id as string, {}),
    ).rejects.toThrow(NotFoundError)
    await expect(
      chat.regenerate(TENANT, thread.id, 'missing', {}),
    ).rejects.toThrow(NotFoundError)
    await expect(
      chat.regenerate(TENANT, thread.id, user?.id as string, { text: '  ' }),
    ).rejects.toThrow('Send a text or an attachment.')
  })
})

describe('pix in the chat', () => {
  it('pays a saved contact named with an @ mention', async () => {
    const { deps, chat, contacts } = await setup()
    const ana = await contacts.create(TENANT, {
      name: 'Ana Souza',
      pixKey: 'ana@example.com',
    })
    const thread = await chat.createThread(TENANT, { scope: 'PF' })
    deps.llm
      .enqueue(use('send_pix', { contactId: ana.id, amount: 50.5 }))
      .enqueue(say('Confirme o Pix.'))
    const turn = await chat.sendMessage(
      TENANT,
      thread.id,
      message('Manda 50,50 pro @ana.souza e pro @ze'),
    )
    expect(deps.llm.calls[0]?.messages.at(-1)?.content).toContain(
      `[mentioned contact @ana.souza id=${ana.id} name="Ana Souza"]\n[@ze is not a saved contact]`,
    )
    const action = turn.messages[1]?.actions[0]
    expect(action).toMatchObject({
      tool: 'SEND_PIX',
      entity: 'PF',
      needsEntity: false,
      details: {
        payee: 'Ana Souza',
        amount: { cents: 5050, currency: 'BRL' },
        pixKey: 'ana@example.com',
        pixKeyType: 'EMAIL',
        contactHandle: 'ana.souza',
        newContact: false,
      },
    })
    const confirmed = await chat.confirmAction(TENANT, action?.id as string, {})
    expect(confirmed.status).toBe('CONFIRMED')
    expect(confirmed.result?.contactId).toBe(ana.id)
    const bill = await deps.bills.findById(
      TENANT,
      confirmed.result?.billId as string,
    )
    expect(bill).toMatchObject({
      kind: 'PIX_KEY',
      source: 'CHAT',
      entityId: 'pf',
      payee: 'Ana Souza',
      code: 'ana@example.com',
    })
    expect(bill?.amount.cents).toBe(5050)
    expect(bill?.status).not.toBe('OPEN')
    expect((await contacts.list(TENANT))[0]?.timesPaid).toBe(1)
  })

  it('finds contacts and saves a new one only when the user confirms', async () => {
    const { deps, chat, contacts } = await setup()
    await contacts.create(TENANT, {
      name: 'Joana Lima',
      pixKey: 'joana@example.com',
    })
    const thread = await chat.createThread(TENANT, { scope: 'ALL' })
    deps.llm
      .enqueue(use('find_pix_contacts', { query: 'jo' }))
      .enqueue(
        use('send_pix', {
          name: 'João Alves',
          pixKey: '(11) 98765-4321',
          amount: 20,
        }),
      )
      .enqueue(say('Confirme.'))
    const turn = await chat.sendMessage(
      TENANT,
      thread.id,
      message('Pix de 20 pro João, chave (11) 98765-4321'),
    )
    const found = JSON.parse(deps.llm.calls[1]?.messages.at(-1)?.content ?? '')
    expect(found).toEqual([
      {
        id: expect.any(String),
        name: 'Joana Lima',
        handle: '@joana.lima',
        keyType: 'EMAIL',
        key: '******.com',
        timesPaid: 0,
      },
    ])
    const action = turn.messages[1]?.actions[0]
    expect(action).toMatchObject({
      needsEntity: true,
      entity: null,
      details: {
        payee: 'João Alves',
        pixKey: '+5511987654321',
        pixKeyType: 'PHONE',
        contactHandle: 'joao.alves',
        newContact: true,
      },
    })
    expect(await contacts.list(TENANT)).toHaveLength(1)
    const confirmed = await chat.confirmAction(TENANT, action?.id as string, {
      entity: 'PF',
    })
    expect(confirmed.status).toBe('CONFIRMED')
    const saved = await contacts.list(TENANT, '@joao')
    expect(saved[0]).toMatchObject({
      id: confirmed.result?.contactId,
      handle: 'joao.alves',
      timesPaid: 1,
    })
  })

  it('fails the action when the contact is gone and rejects a bad request', async () => {
    const { deps, chat, contacts } = await setup()
    const ana = await contacts.create(TENANT, {
      name: 'Ana',
      pixKey: 'ana@example.com',
    })
    const thread = await chat.createThread(TENANT, { scope: 'PF' })
    deps.llm
      .enqueue(use('send_pix', { amount: 10 }))
      .enqueue(use('find_pix_contacts', { query: 'x' }))
      .enqueue(use('send_pix', { contactId: ana.id, amount: 10 }))
      .enqueue(say('Confirme.'))
    const turn = await chat.sendMessage(TENANT, thread.id, message('Pix'))
    expect(deps.llm.calls[1]?.messages.at(-1)?.content).toContain(
      'Give the contactId',
    )
    expect(deps.llm.calls[2]?.messages.at(-1)?.content).toBe('[]')
    const action = turn.messages[1]?.actions[0]
    await contacts.remove(TENANT, ana.id)
    const failed = await chat.confirmAction(TENANT, action?.id as string, {})
    expect(failed).toMatchObject({
      status: 'FAILED',
      error: 'Contact was not found.',
    })
  })

  it('sends one Pix when two confirmations race', async () => {
    const { deps, chat, contacts } = await setup()
    const ana = await contacts.create(TENANT, {
      name: 'Ana',
      pixKey: 'ana@example.com',
    })
    const thread = await chat.createThread(TENANT, { scope: 'PF' })
    deps.llm
      .enqueue(use('send_pix', { contactId: ana.id, amount: 10 }))
      .enqueue(say('Confirme.'))
    const turn = await chat.sendMessage(TENANT, thread.id, message('Pix'))
    const id = turn.messages[1]?.actions[0]?.id as string
    const [first, second] = await Promise.allSettled([
      chat.confirmAction(TENANT, id, {}),
      chat.confirmAction(TENANT, id, {}),
    ])
    expect(first).toMatchObject({
      status: 'fulfilled',
      value: { status: 'CONFIRMED' },
    })
    expect(second).toMatchObject({ status: 'rejected' })
    expect((second as PromiseRejectedResult).reason).toBeInstanceOf(
      ConflictError,
    )
    const bills = await deps.bills.list(TENANT, {}, { limit: 10 })
    expect(bills.items.filter(bill => bill.source === 'CHAT')).toHaveLength(1)
  })

  it('reads an action stored before the Pix fields existed', async () => {
    const { deps, chat } = await setup()
    const thread = await chat.createThread(TENANT, { scope: 'PF' })
    deps.llm
      .enqueue(
        use('send_pix', { name: 'Ana', pixKey: 'ana@example.com', amount: 1 }),
      )
      .enqueue(say('Ok.'))
    const turn = await chat.sendMessage(TENANT, thread.id, message('Pix'))
    const stored = await deps.chat.findAction(
      TENANT,
      turn.messages[1]?.actions[0]?.id as string,
    )
    const { pixKey: _key, ...older } = stored?.details ?? {}
    await deps.chat.saveAction({
      ...stored!,
      details: older as never,
      result: { billId: 'b1' } as never,
    })
    const [, reply] = (await chat.listMessages(TENANT, thread.id, { limit: 5 }))
      .items
    expect(reply?.actions[0]?.details.pixKey).toBeNull()
    expect(reply?.actions[0]?.result).toEqual({
      billId: 'b1',
      invoiceId: null,
      ruleId: null,
      updated: null,
      contactId: null,
    })
  })
})
