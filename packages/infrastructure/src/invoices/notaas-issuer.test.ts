import { createHmac } from 'node:crypto'
import { describe, expect, it } from 'vitest'
import { type InvoiceDraft } from '@cashdeck/application'
import {
  NOTAAS_URL,
  NotaasIssuer,
  verifyNotaasSignature,
} from '@/invoices/notaas-issuer'
import { credentials, ENTITY, TENANT } from '@/testing/provider-fixtures'
import { ScriptedTransport } from '@/testing/scripted-transport'

const domestic: InvoiceDraft = {
  tenantId: TENANT,
  entityId: ENTITY,
  clientName: 'Cliente Exemplo Ltda',
  clientTaxId: '11.222.333/0001-81',
  serviceCode: '010101',
  description: 'Desenvolvimento de software',
  amountCents: 500000,
  currency: 'BRL',
  export: false,
}

const exported: InvoiceDraft = {
  ...domestic,
  clientName: 'Example Inc',
  clientTaxId: 'EIN-12-3456789',
  amountCents: 100000,
  currency: 'USD',
  brlAmountCents: 540000,
  export: true,
}

function issuer(scripted: ScriptedTransport, env: Record<string, string> = {}) {
  return new NotaasIssuer({
    credentials: credentials({
      NOTAAS_API_KEY: 'nk',
      NOTAAS_ALIQUOTA_ISS: '2',
      ...env,
    }),
    transport: scripted.transport,
    now: () => new Date('2026-10-08T12:00:00Z'),
  })
}

describe('NotaasIssuer', () => {
  it('emits a domestic invoice with the idempotency key as reference', async () => {
    const scripted = new ScriptedTransport().on(
      'POST',
      `${NOTAAS_URL}/emitir`,
      {
        status: 202,
        json: { queued: true, invoiceId: 'inv-1', status: 'queued' },
      },
    )
    const result = await issuer(scripted, {
      NOTAAS_LOCAL_PRESTACAO: '3530607',
    }).issue(domestic, 'invoice-key')
    expect(result).toEqual({
      externalId: 'inv-1',
      number: null,
      status: 'PROCESSING',
      pdfUrl: null,
      xmlUrl: null,
    })
    expect(scripted.body('POST', `${NOTAAS_URL}/emitir`)).toEqual({
      tomador: { cnpj: '11222333000181', nome: 'Cliente Exemplo Ltda' },
      servico: {
        descricao: 'Desenvolvimento de software',
        codigo: '010101',
        localPrestacao: '3530607',
      },
      valores: { total: 5000, aliquotaIss: 2 },
      competencia: '2026-10',
      referencia: 'invoice-key',
    })
    expect(scripted.last('POST', `${NOTAAS_URL}/emitir`).headers).toMatchObject(
      {
        'x-api-key': 'nk',
      },
    )
  })

  it('emits to a person and an export client in foreign currency', async () => {
    const scripted = new ScriptedTransport().on(
      'POST',
      `${NOTAAS_URL}/emitir`,
      {
        json: { invoiceId: 'inv-2', status: 'queued' },
      },
    )
    const nfse = issuer(scripted, { NOTAAS_EXPORT_COUNTRY: 'GB' })
    await nfse.issue({ ...domestic, clientTaxId: '529.982.247-25' }, 'k1')
    expect(scripted.body('POST', `${NOTAAS_URL}/emitir`)).toMatchObject({
      tomador: { cpf: '52998224725' },
    })
    await nfse.issue(exported, 'k2')
    expect(scripted.body('POST', `${NOTAAS_URL}/emitir`)).toMatchObject({
      tomador: {
        nome: 'Example Inc',
        nif: 'EIN-12-3456789',
        endereco: { pais: 'GB', uf: 'EX' },
      },
      valores: {
        total: 5400,
        aliquotaIss: 0,
        exportacao: {
          paisResultado: 'GB',
          codigoMoeda: '220',
          valorServicoMoeda: 1000,
        },
      },
    })
    await issuer(scripted).issue(
      { ...exported, clientTaxId: null, currency: 'BRL', amountCents: 300000 },
      'k3',
    )
    expect(scripted.body('POST', `${NOTAAS_URL}/emitir`)).toMatchObject({
      tomador: { nome: 'Example Inc', endereco: { pais: 'US' } },
      valores: { total: 3000, exportacao: { paisResultado: 'US' } },
    })
  })

  it('refuses drafts it cannot express', async () => {
    const nfse = issuer(new ScriptedTransport())
    await expect(
      nfse.issue({ ...domestic, clientTaxId: null }, 'k'),
    ).rejects.toThrow('needs the client CPF or CNPJ')
    await expect(
      nfse.issue({ ...exported, brlAmountCents: null }, 'k'),
    ).rejects.toThrow('needs its BRL total')
    await expect(
      nfse.issue({ ...exported, currency: 'JPY' }, 'k'),
    ).rejects.toThrow('no currency code for JPY')
    const noRate = issuer(new ScriptedTransport(), {})
    const missing = new NotaasIssuer({
      credentials: credentials({ NOTAAS_API_KEY: 'nk' }),
      transport: new ScriptedTransport().transport,
    })
    await expect(missing.issue(domestic, 'k')).rejects.toThrow(
      'Notaas is not configured.',
    )
    expect(noRate.id).toBe('notaas')
  })

  it('reads the status with the documents once issued', async () => {
    const scripted = new ScriptedTransport()
      .on('GET', `${NOTAAS_URL}/invoices/inv-1/status`, {
        json: {
          invoiceId: 'inv-1',
          status: 'issued',
          numeroNfe: 42,
          pdfUrl: 'https://cdn.test/inv-1.pdf',
          xmlUrl: 'https://cdn.test/inv-1.xml',
        },
      })
      .on('GET', `${NOTAAS_URL}/invoices/inv-2/status`, {
        json: { status: 'error', errorMessage: 'E0039' },
      })
      .on('GET', `${NOTAAS_URL}/invoices/inv-3/status`, {
        json: { status: 'new', numeroNfe: null },
      })
    const nfse = issuer(scripted)
    expect(await nfse.get('inv-1')).toEqual({
      externalId: 'inv-1',
      number: '42',
      status: 'ISSUED',
      pdfUrl: 'https://cdn.test/inv-1.pdf',
      xmlUrl: 'https://cdn.test/inv-1.xml',
    })
    expect(await nfse.get('inv-2')).toMatchObject({
      externalId: 'inv-2',
      status: 'REJECTED',
    })
    expect((await nfse.get('inv-3')).status).toBe('PROCESSING')
  })

  it('cancels with a reason and returns the new status', async () => {
    const scripted = new ScriptedTransport()
      .on('POST', `${NOTAAS_URL}/cancelar`, { json: {} })
      .on('GET', `${NOTAAS_URL}/invoices/inv-1/status`, {
        json: { invoiceId: 'inv-1', status: 'cancelled' },
      })
    const nfse = issuer(scripted)
    const result = await nfse.cancel('inv-1', 'Valor emitido incorretamente')
    expect(result.status).toBe('CANCELLED')
    expect(scripted.body('POST', `${NOTAAS_URL}/cancelar`)).toEqual({
      invoiceId: 'inv-1',
      motivo: 'Valor emitido incorretamente',
    })
    await expect(nfse.cancel('inv-1', 'curto')).rejects.toThrow('15 to 255')
  })

  it('reports provider errors and checks the api key', async () => {
    const scripted = new ScriptedTransport().on(
      'GET',
      `${NOTAAS_URL}/webhooks/endpoints`,
      { json: [] },
      { status: 401, json: { error: 'invalid key' } },
      { status: 500, json: { message: 'down' } },
      { status: 500, text: 'oops' },
    )
    const nfse = issuer(scripted)
    expect(await nfse.check()).toEqual({ ok: true, message: null })
    expect(await nfse.check()).toEqual({
      ok: false,
      message: 'Notaas check failed: Notaas answered 401: invalid key',
    })
    expect((await nfse.check()).message).toContain('down')
    expect((await nfse.check()).message).toContain('request refused')
  })
})

describe('NotaasIssuer documents', () => {
  it('downloads its own documents with the key and others without', async () => {
    const pdf = new Uint8Array([0x25, 0x50, 0x44, 0x46, 0xff])
    const scripted = new ScriptedTransport()
      .on('GET', `${NOTAAS_URL}/invoices/inv-1/pdf`, { bytes: pdf })
      .on('GET', 'https://cdn.test/inv-1.xml', { text: '<nfse/>' })
      .on('GET', 'https://cdn.test/gone.pdf', { status: 404 })
    const nfse = issuer(scripted)
    expect(await nfse.download(`${NOTAAS_URL}/invoices/inv-1/pdf`)).toEqual(pdf)
    expect(
      scripted.last('GET', `${NOTAAS_URL}/invoices/inv-1/pdf`).headers,
    ).toEqual({ 'x-api-key': 'nk' })
    const xml = await nfse.download('https://cdn.test/inv-1.xml')
    expect(new TextDecoder().decode(xml)).toBe('<nfse/>')
    expect(scripted.last('GET', 'https://cdn.test/inv-1.xml').headers).toEqual(
      {},
    )
    await expect(nfse.download('https://cdn.test/gone.pdf')).rejects.toThrow(
      'Notaas answered 404: download refused',
    )
  })
})

describe('verifyNotaasSignature', () => {
  it('accepts only the HMAC of the raw body', () => {
    const body = '{"event":"nfse.issued","data":{"invoiceId":"inv-1"}}'
    const digest = createHmac('sha256', 'whsec').update(body).digest('hex')
    expect(verifyNotaasSignature(body, `sha256=${digest}`, 'whsec')).toBe(true)
    expect(verifyNotaasSignature(`${body} `, `sha256=${digest}`, 'whsec')).toBe(
      false,
    )
    expect(verifyNotaasSignature(body, `sha256=abcd`, 'whsec')).toBe(false)
    expect(verifyNotaasSignature(body, digest, 'whsec')).toBe(false)
    expect(verifyNotaasSignature(body, null, 'whsec')).toBe(false)
  })
})
