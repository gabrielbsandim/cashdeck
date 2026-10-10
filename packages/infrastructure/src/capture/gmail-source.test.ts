import { describe, expect, it } from 'vitest'
import {
  FakeDocumentTextReader,
  FakeLlmProvider,
  type LlmProvider,
  LlmProviderError,
} from '@cashdeck/application'
import { findPaymentCodes as findCodesInText } from '@cashdeck/domain'
import { BillExtractor, toExtracted } from '@/capture/bill-extractor'
import { documentPasswords, GmailBillSource } from '@/capture/gmail-source'
import {
  BOLETO_LINE,
  credentials,
  DYNAMIC_PIX,
  ENTITY,
  STATIC_PIX,
  TAX_BARCODE,
  TENANT,
  TODAY,
} from '@/testing/provider-fixtures'
import { ScriptedTransport } from '@/testing/scripted-transport'

const API = 'https://gmail.googleapis.com/gmail/v1/users/me'
const TOKEN = 'https://oauth2.googleapis.com/token'
const SPACED_LINE = '00190.00009 02800.012342 56789.012178 9 16050000012345'

function b64(text: string): string {
  return Buffer.from(text).toString('base64url')
}

describe('findCodesInText', () => {
  it('finds a digitable line and a pix code in an e-mail body', () => {
    const text = `Sua fatura vence em breve.\nLinha digitável: ${SPACED_LINE}\nPix copia e cola:\n${STATIC_PIX.slice(0, 40)}\n${STATIC_PIX.slice(40)}\n`
    expect(findCodesInText(text, TODAY)).toEqual({
      barcode: BOLETO_LINE,
      pixCode: STATIC_PIX,
    })
  })

  it('ignores digit runs and pix-looking text that do not validate', () => {
    const broken = `${STATIC_PIX.slice(0, -4)}0000`
    expect(
      findCodesInText(
        `pedido 1234567890123456789012345678901234567890123 ${broken}`,
        TODAY,
      ),
    ).toEqual({ barcode: null, pixCode: null })
    expect(findCodesInText('nada aqui', TODAY)).toEqual({
      barcode: null,
      pixCode: null,
    })
  })
})

describe('toExtracted', () => {
  it('reads amount and due date from the codes before the hints', () => {
    expect(
      toExtracted({ barcode: BOLETO_LINE, pixCode: null }, TODAY, {
        payee: ' Energia ',
        amountCents: 1,
        dueDate: '2026-12-01',
      }),
    ).toEqual({
      barcode: BOLETO_LINE,
      pixCode: null,
      payee: 'Energia',
      amountCents: 12345,
      dueDate: '2026-10-20',
      kind: 'BOLETO',
      taxIds: [],
    })
    expect(
      toExtracted({ barcode: TAX_BARCODE, pixCode: null }, TODAY, {
        dueDate: '2026-10-20',
      }),
    ).toMatchObject({ kind: 'TAX_BARCODE', dueDate: '2026-10-20', payee: null })
    expect(
      toExtracted({ barcode: null, pixCode: DYNAMIC_PIX }, TODAY, {
        amountCents: 500,
        dueDate: '20/10/2026',
      }),
    ).toMatchObject({ kind: 'PIX_QR', amountCents: 100, dueDate: null })
    expect(toExtracted({ barcode: null, pixCode: null }, TODAY)).toBeNull()
  })
})

describe('BillExtractor', () => {
  it('keeps only codes that validate from the model answer', async () => {
    const llm = new FakeLlmProvider()
      .enqueueObject({
        barcode: SPACED_LINE,
        pixCode: STATIC_PIX,
        payee: 'Energia Exemplo',
        amount: '123.45',
        dueDate: '2026-10-08',
      })
      .enqueueObject({ barcode: '123', pixCode: `${STATIC_PIX}X` })
      .enqueueObject({ barcode: '', pixCode: DYNAMIC_PIX, amount: 'abc' })
    const extractor = new BillExtractor(llm)
    const attachment = { mimeType: 'application/pdf', dataBase64: 'JVBERi0=' }
    expect(await extractor.fromAttachment(attachment, TODAY)).toEqual({
      barcode: BOLETO_LINE,
      pixCode: STATIC_PIX,
      payee: 'Energia Exemplo',
      amountCents: 12345,
      dueDate: '2026-10-20',
      kind: 'BOLETO',
      taxIds: [],
    })
    expect(await extractor.fromAttachment(attachment, TODAY)).toBeNull()
    expect(await extractor.fromAttachment(attachment, TODAY)).toMatchObject({
      kind: 'PIX_QR',
      amountCents: 100,
    })
    expect(llm.calls[0]?.messages[0]?.attachments).toEqual([attachment])
    expect(llm.calls[0]?.responseSchema).toBeDefined()
    llm.enqueue({
      text: '',
      toolCalls: [],
      usage: { inputTokens: 0, outputTokens: 0, costMillicents: 0 },
      stopReason: 'end',
    })
    expect(await extractor.fromAttachment(attachment, TODAY)).toBeNull()
  })

  it('takes the codes from the PDF text layer before the model answer', async () => {
    const llm = new FakeLlmProvider().enqueueObject({
      barcode: '123',
      pixCode: STATIC_PIX.slice(0, 90),
      payee: 'Energia Exemplo',
    })
    const text = new FakeDocumentTextReader(
      `Linha ${SPACED_LINE}\nPix\n${STATIC_PIX.slice(0, 50)}\n${STATIC_PIX.slice(50)}`,
    )
    const extractor = new BillExtractor(llm, text)
    const attachment = { mimeType: 'application/pdf', dataBase64: 'JVBERi0=' }
    expect(await extractor.fromAttachment(attachment, TODAY)).toMatchObject({
      barcode: BOLETO_LINE,
      pixCode: STATIC_PIX,
      payee: 'Energia Exemplo',
    })
    expect(text.reads[0]?.mimeType).toBe('application/pdf')
    expect(Buffer.from(text.reads[0]?.bytes ?? []).toString('base64')).toBe(
      'JVBERi0=',
    )
  })

  it('keeps the text layer codes when the model rejects the document', async () => {
    const failing = (code: string): LlmProvider => ({
      name: 'failing',
      modelId: 'failing',
      chat: async () => {
        throw new LlmProviderError('rejected', code)
      },
    })
    const text = new FakeDocumentTextReader(
      `Contribuinte 11.222.333/0001-81\nLinha ${SPACED_LINE}`,
    )
    const attachment = { mimeType: 'application/pdf', dataBase64: 'JVBERi0=' }
    const rejected = new BillExtractor(failing('request_rejected'), text)
    expect(await rejected.fromAttachment(attachment, TODAY)).toMatchObject({
      barcode: BOLETO_LINE,
      payee: null,
    })
    const broken = new BillExtractor(failing('chat_failed'), text)
    await expect(broken.fromAttachment(attachment, TODAY)).rejects.toThrow(
      'rejected',
    )
  })
})

function gmailEnv() {
  return credentials({
    GMAIL_CLIENT_ID: 'cid',
    GMAIL_CLIENT_SECRET: 'cs',
    GMAIL_REFRESH_TOKEN: 'rt',
  })
}

describe('GmailBillSource', () => {
  const since = new Date('2026-10-01T00:00:00Z')
  const now = () => new Date('2026-10-08T12:00:00Z')

  it('reads bolepix attachments and bodies into captured bills', async () => {
    const scripted = new ScriptedTransport()
      .on('POST', TOKEN, { json: { access_token: 'gtoken' } })
      .on(
        'GET',
        `${API}/messages?`,
        { json: { messages: [{ id: 'm1' }], nextPageToken: 'p2' } },
        { json: { messages: [{ id: 'm2' }, { id: 'm3' }] } },
      )
      .on('GET', `${API}/messages/m1/attachments/att-1`, {
        json: { data: b64('%PDF fake') },
      })
      .on('GET', `${API}/messages/m1?format=full`, {
        json: {
          id: 'm1',
          payload: {
            mimeType: 'multipart/mixed',
            headers: [
              { name: 'From', value: '"Energia Exemplo" <conta@energia.test>' },
            ],
            parts: [
              {
                mimeType: 'text/plain',
                body: { data: b64(`Linha digitável ${SPACED_LINE}`) },
              },
              {
                mimeType: 'application/pdf',
                filename: 'boleto.pdf',
                body: { attachmentId: 'att-1', size: 1000 },
              },
              {
                mimeType: 'application/pdf',
                filename: 'huge.pdf',
                body: { attachmentId: 'att-2', size: 20 * 1024 * 1024 },
              },
            ],
          },
        },
      })
      .on('GET', `${API}/messages/m2?format=full`, {
        json: {
          id: 'm2',
          payload: {
            mimeType: 'text/html',
            headers: [{ name: 'Subject', value: 'Fatura' }],
            body: { data: b64(`<p>Pix: ${DYNAMIC_PIX}</p>`) },
          },
        },
      })
      .on('GET', `${API}/messages/m3?format=full`, { json: { id: 'm3' } })
    const llm = new FakeLlmProvider().enqueueObject({
      barcode: BOLETO_LINE,
      pixCode: STATIC_PIX,
      payee: 'Energia Exemplo S.A.',
      dueDate: '2026-10-08',
    })
    const source = new GmailBillSource({
      credentials: gmailEnv(),
      transport: scripted.transport,
      extractor: new BillExtractor(llm),
      now,
    })
    expect(source.source).toBe('GMAIL')
    const bills = await source.fetch(TENANT, ENTITY, since)
    expect(bills).toEqual([
      {
        externalId: 'm1:0',
        paymentCode: BOLETO_LINE,
        pixCode: STATIC_PIX,
        payee: 'Energia Exemplo S.A.',
        amountCents: 12345,
        dueDate: '2026-10-20',
        kind: 'BOLETO',
        taxIds: [],
      },
      {
        externalId: 'm2:0',
        paymentCode: DYNAMIC_PIX,
        pixCode: DYNAMIC_PIX,
        payee: null,
        amountCents: 100,
        dueDate: null,
        kind: 'PIX_QR',
        taxIds: [],
      },
    ])
    const list = scripted.requests.find(r =>
      r.url.startsWith(`${API}/messages?`),
    )
    expect(decodeURIComponent(list?.url ?? '')).toContain('after:1790812800')
    expect(scripted.requests.at(-1)?.headers).toMatchObject({
      authorization: 'Bearer gtoken',
    })
    expect(scripted.last('POST', TOKEN).body).toContain(
      'grant_type=refresh_token',
    )
    expect(llm.calls).toHaveLength(1)
  })

  it('reads only the body without an extractor and stops at the limit', async () => {
    const scripted = new ScriptedTransport()
      .on('POST', TOKEN, { json: {} })
      .on('GET', `${API}/messages?`, {
        json: { messages: [{ id: 'm1' }, { id: 'm2' }], nextPageToken: 'more' },
      })
      .on('GET', `${API}/messages/m1?format=full`, {
        json: {
          id: 'm1',
          payload: {
            mimeType: 'multipart/mixed',
            headers: [{ name: 'from', value: '<x@y.test>' }],
            parts: [
              { mimeType: 'text/plain', body: { data: b64(SPACED_LINE) } },
              {
                mimeType: 'image/png',
                body: { attachmentId: 'img', size: 10 },
              },
              { mimeType: 'text/plain', body: {} },
            ],
          },
        },
      })
    const source = new GmailBillSource({
      credentials: gmailEnv(),
      transport: scripted.transport,
      maxMessages: 1,
    })
    const bills = await source.fetch(TENANT, ENTITY, since)
    expect(bills).toEqual([
      expect.objectContaining({
        externalId: 'm1:0',
        payee: null,
        kind: 'BOLETO',
      }),
    ])
  })

  it('reports refused tokens, failed calls and missing credentials', async () => {
    const refused = new ScriptedTransport().on('POST', TOKEN, { status: 400 })
    const source = new GmailBillSource({
      credentials: gmailEnv(),
      transport: refused.transport,
    })
    await expect(source.fetch(TENANT, ENTITY, since)).rejects.toThrow(
      'the refresh token was refused',
    )
    const failing = new ScriptedTransport()
      .on('POST', TOKEN, { json: { access_token: 't' } })
      .on('GET', `${API}/messages?`, { status: 403, text: 'forbidden' })
    const blocked = new GmailBillSource({
      credentials: gmailEnv(),
      transport: failing.transport,
    })
    await expect(blocked.fetch(TENANT, ENTITY, since)).rejects.toThrow(
      'Gmail answered 403',
    )
    const unconfigured = new GmailBillSource({
      credentials: credentials({}),
      transport: refused.transport,
    })
    await expect(unconfigured.fetch(TENANT, ENTITY, since)).rejects.toThrow(
      'Gmail is not configured.',
    )
  })

  it('pairs the barcode of the PDF with the Pix code of the body', async () => {
    const scripted = new ScriptedTransport()
      .on('POST', TOKEN, { json: { access_token: 'gtoken' } })
      .on('GET', `${API}/messages?`, {
        json: { messages: [{ id: 'm1' }, { id: 'm2' }] },
      })
      .on('GET', `${API}/messages/m1/attachments/att-1`, {
        json: { data: b64('%PDF fake') },
      })
      .on('GET', `${API}/messages/m2/attachments/att-2`, {
        json: { data: b64('%PDF fake') },
      })
      .on('GET', `${API}/messages/m1?format=full`, {
        json: {
          id: 'm1',
          payload: {
            mimeType: 'multipart/mixed',
            parts: [
              {
                mimeType: 'text/html',
                body: { data: b64(`<p>Pix copia e cola: ${STATIC_PIX}</p>`) },
              },
              {
                mimeType: 'application/pdf',
                body: { attachmentId: 'att-1', size: 1000 },
              },
            ],
          },
        },
      })
      .on('GET', `${API}/messages/m2?format=full`, {
        json: {
          id: 'm2',
          payload: {
            mimeType: 'multipart/mixed',
            parts: [
              { mimeType: 'text/plain', body: { data: b64(TAX_BARCODE) } },
              {
                mimeType: 'application/pdf',
                body: { attachmentId: 'att-2', size: 1000 },
              },
            ],
          },
        },
      })
    const llm = new FakeLlmProvider()
      .enqueueObject({ barcode: BOLETO_LINE, pixCode: '', payee: 'Energia' })
      .enqueueObject({ barcode: BOLETO_LINE, pixCode: '' })
    const source = new GmailBillSource({
      credentials: gmailEnv(),
      transport: scripted.transport,
      extractor: new BillExtractor(llm),
      now,
    })
    const bills = await source.fetch(TENANT, ENTITY, since)
    expect(bills).toEqual([
      expect.objectContaining({
        externalId: 'm1:0',
        paymentCode: BOLETO_LINE,
        pixCode: STATIC_PIX,
        payee: 'Energia',
        kind: 'BOLETO',
      }),
      expect.objectContaining({ externalId: 'm2:0', paymentCode: BOLETO_LINE }),
      expect.objectContaining({
        externalId: 'm2:1',
        paymentCode: TAX_BARCODE,
        kind: 'TAX_BARCODE',
      }),
    ])
  })

  it('opens an untyped PDF with the digits of the owner tax id', async () => {
    const scripted = new ScriptedTransport()
      .on('POST', TOKEN, { json: { access_token: 'gtoken' } })
      .on('GET', `${API}/messages?`, { json: { messages: [{ id: 'm1' }] } })
      .on('GET', `${API}/messages/m1/attachments/att-1`, {
        json: { data: b64('%PDF locked') },
      })
      .on('GET', `${API}/messages/m1?format=full`, {
        json: {
          id: 'm1',
          payload: {
            mimeType: 'multipart/mixed',
            parts: [
              {
                mimeType: 'text/plain',
                body: {
                  data: b64(`Linha: ${SPACED_LINE}\nCPF: 529.982.247-25`),
                },
              },
              {
                mimeType: 'application/octet-stream',
                filename: 'Conta.PDF',
                body: { attachmentId: 'att-1', size: 1000 },
              },
              {
                mimeType: 'application/octet-stream',
                filename: 'notes.bin',
                body: { attachmentId: 'att-2', size: 1000 },
              },
            ],
          },
        },
      })
    const text = new FakeDocumentTextReader(
      `Contribuinte 11.222.333/0001-81\nLinha ${SPACED_LINE}`,
    )
    const source = new GmailBillSource({
      credentials: gmailEnv(),
      transport: scripted.transport,
      extractor: new BillExtractor(
        new FakeLlmProvider().enqueueObject({}),
        text,
      ),
      now,
    })
    const bills = await source.fetch(TENANT, ENTITY, since, {
      taxId: '52998224725',
    })
    expect(bills).toEqual([
      expect.objectContaining({
        externalId: 'm1:0',
        paymentCode: BOLETO_LINE,
        taxIds: ['11222333000181', '52998224725'],
      }),
    ])
    expect(text.reads).toHaveLength(1)
    expect(text.reads[0]).toMatchObject({
      mimeType: 'application/pdf',
      passwords: ['5299', '52998', '529982', '52998224725'],
    })
  })

  it('derives each password once', () => {
    expect(documentPasswords('1234')).toEqual(['1234'])
  })
})
