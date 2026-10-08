import { describe, expect, it } from 'vitest'
import { Money } from '@cashdeck/domain'
import { C6DdaBillSource } from '@/capture/c6-dda-source'
import { BankClients } from '@/rails/bank-client'
import { C6_HOSTS } from '@/rails/c6-client'
import { C6EmpresasRail } from '@/rails/c6-empresas-rail'
import {
  BOLETO_LINE,
  credentials,
  DYNAMIC_PIX,
  ENTITY,
  payment,
  STATIC_PIX,
  TAX_BARCODE,
  TENANT,
} from '@/testing/provider-fixtures'
import { ScriptedTransport } from '@/testing/scripted-transport'

const API = `${C6_HOSTS.production}/v1/schedule_payments`
const TOKEN = `${C6_HOSTS.production}/v1/auth/`
const scope = { tenantId: TENANT, entityId: ENTITY }
const env = {
  C6_CLIENT_ID: 'c',
  C6_CLIENT_SECRET: 's',
  C6_CERT: 'cert',
  C6_KEY: 'key',
}

function setup(extra: Record<string, string> = {}) {
  const scripted = new ScriptedTransport().on('POST', TOKEN, {
    json: { access_token: 'tok' },
  })
  const clients = new BankClients(() => scripted.transport)
  const creds = credentials({ ...env, ...extra })
  return {
    scripted,
    rail: new C6EmpresasRail({ credentials: creds, clients }),
    dda: new C6DdaBillSource({
      credentials: creds,
      clients,
      now: () => new Date('2026-10-08T12:00:00Z'),
    }),
  }
}

function scriptBatch(scripted: ScriptedTransport, status = 'PROCESSED') {
  scripted
    .on('POST', `${API}/decode`, { status: 201, json: { group_id: 'g1' } })
    .on('GET', `${API}/g1/items`, {
      json: { items: [{ id: 'i1', status, error_message: null }] },
    })
    .on('POST', `${API}/submit`, { status: 204 })
}

describe('C6EmpresasRail', () => {
  it('serves the company bank approval step for boleto and pix', () => {
    const { rail } = setup()
    expect(rail.id).toBe('C6_EMPRESAS')
    expect(rail.supports('PIX_QR', 'PJ')).toBe(true)
    expect(rail.supports('TAX_BARCODE', 'PJ')).toBe(false)
    expect(rail.supports('BOLETO', 'PF')).toBe(false)
  })

  it('decodes, checks and submits a batch for approval in the bank', async () => {
    const { scripted, rail } = setup({ C6_UPLOADER_NAME: 'Finance' })
    scriptBatch(scripted)
    const result = await rail.pay(payment({ pixCode: DYNAMIC_PIX }))
    expect(result).toEqual({
      outcome: 'PENDING_APPROVAL',
      externalId: 'g1/i1',
      reason: null,
    })
    expect(scripted.body('POST', `${API}/decode`)).toEqual({
      items: [
        {
          content: DYNAMIC_PIX,
          amount: 123.45,
          description: 'Energia Exemplo',
          transaction_date: '2026-10-08',
        },
      ],
    })
    expect(scripted.body('POST', `${API}/submit`)).toEqual({
      group_id: 'g1',
      uploader_name: 'Finance',
    })
    expect(scripted.last('POST', TOKEN).body).not.toContain('scope=')
  })

  it('sends a pix key or a boleto line as content', async () => {
    const { scripted, rail } = setup()
    scriptBatch(scripted)
    await rail.pay(payment({ kind: 'PIX_KEY', code: '529.982.247-25' }))
    expect(scripted.body('POST', `${API}/decode`)).toMatchObject({
      items: [{ content: '52998224725' }],
    })
    await rail.pay(payment())
    expect(scripted.body('POST', `${API}/decode`)).toMatchObject({
      items: [{ content: BOLETO_LINE }],
    })
  })

  it('fails before submitting when a code is wrong or unreadable', async () => {
    const { scripted, rail } = setup()
    const mismatch = await rail.pay(
      payment({ kind: 'PIX_QR', code: STATIC_PIX, amount: Money.of(1) }),
    )
    expect(mismatch).toEqual({
      outcome: 'FAILED',
      reason: 'PIX_AMOUNT_MISMATCH',
    })
    scriptBatch(scripted, 'DECODE_ERROR')
    expect((await rail.pay(payment())).reason).toBe(
      'C6 could not read the payment.',
    )
    expect(scripted.requests.some(r => r.url === `${API}/submit`)).toBe(false)
  })

  it('maps refusals at each call', async () => {
    const decode = setup()
    decode.scripted.on('POST', `${API}/decode`, {
      status: 400,
      json: { message: 'Conteúdo inválido' },
    })
    expect((await decode.rail.pay(payment())).reason).toBe('Conteúdo inválido')
    const items = setup()
    items.scripted
      .on('POST', `${API}/decode`, { json: {} })
      .on('GET', `${API}/`, { status: 404, json: { detail: 'Grupo' } })
    expect((await items.rail.pay(payment())).reason).toBe('Grupo')
    const submit = setup()
    submit.scripted
      .on('POST', `${API}/decode`, { json: { group_id: 'g1' } })
      .on('GET', `${API}/g1/items`, { json: {} })
      .on('POST', `${API}/submit`, { status: 400, text: '' })
    expect((await submit.rail.pay(payment())).reason).toBe(
      'C6 refused the request (400).',
    )
    const down = setup()
    down.scripted.on('POST', `${API}/decode`, { status: 500 })
    await expect(down.rail.pay(payment())).rejects.toThrow(
      'C6 Empresas answered 500',
    )
  })

  it('tracks an item after approval', async () => {
    const { scripted, rail } = setup({
      C6_ENVIRONMENT: 'sandbox',
      C6_TOKEN_URL: 'https://auth.test/token',
    })
    const sandbox = `${C6_HOSTS.sandbox}/v1/schedule_payments`
    scripted
      .on('POST', 'https://auth.test/token', { json: { access_token: 'tok' } })
      .on(
        'GET',
        `${sandbox}/g1/items`,
        { json: { items: [{ id: 'i1', status: 'SCHEDULED' }] } },
        {
          json: {
            items: [{ id: 'i1', status: 'ERROR', error_message: 'Saldo' }],
          },
        },
        { json: { items: [] } },
        { status: 400, json: {} },
      )
    expect(await rail.status('g1/i1', scope)).toEqual({
      outcome: 'SUBMITTED',
      externalId: 'g1/i1',
      reason: null,
      endToEndId: null,
      settledAt: null,
    })
    expect(await rail.status('g1/i1', scope)).toMatchObject({
      outcome: 'FAILED',
      reason: 'Saldo',
    })
    expect((await rail.status('g1/i1', scope)).outcome).toBe('PENDING_APPROVAL')
    expect((await rail.status('g1/i1', scope)).outcome).toBe('FAILED')
    await expect(rail.status('', scope)).rejects.toThrow('does not know')
  })

  it('checks access through the DDA query', async () => {
    const { scripted, rail } = setup()
    scripted.on(
      'GET',
      `${API}/query`,
      { json: { items: [] } },
      { status: 403, json: { message: 'Sem acesso' } },
    )
    expect(await rail.check()).toEqual({ ok: true, message: null })
    expect(await rail.check()).toEqual({
      ok: false,
      message: 'C6 Empresas check failed: Sem acesso',
    })
  })
})

describe('C6DdaBillSource', () => {
  it('turns open DDA bonds into captured bills', async () => {
    const { scripted, dda } = setup()
    scripted.on('GET', `${API}/query`, {
      json: {
        items: [
          {
            amount: 123.45,
            beneficiary_name: 'Fornecedor',
            content: BOLETO_LINE,
            due_date: '2026-10-10',
          },
          { amount: 0, content: TAX_BARCODE },
          { amount: 10, content: '123' },
          { amount: 10 },
        ],
      },
    })
    expect(dda.source).toBe('DDA')
    const bills = await dda.fetch(TENANT, ENTITY)
    expect(bills).toEqual([
      {
        externalId: `dda:${BOLETO_LINE}`,
        paymentCode: BOLETO_LINE,
        pixCode: null,
        payee: 'Fornecedor',
        amountCents: 12345,
        dueDate: '2026-10-10',
        kind: 'BOLETO',
      },
      expect.objectContaining({
        kind: 'TAX_BARCODE',
        amountCents: null,
        payee: null,
        dueDate: null,
      }),
      expect.objectContaining({ kind: 'BOLETO', paymentCode: '123' }),
    ])
  })

  it('fails loudly when the query is refused', async () => {
    const { scripted, dda } = setup()
    scripted.on(
      'GET',
      `${API}/query`,
      { status: 403, json: { message: 'Sem DDA' } },
      { json: {} },
    )
    await expect(dda.fetch(TENANT, ENTITY)).rejects.toThrow('Sem DDA')
    expect(await dda.fetch(TENANT, ENTITY)).toEqual([])
    const unconfigured = new C6DdaBillSource({ credentials: credentials({}) })
    await expect(unconfigured.fetch(TENANT, ENTITY)).rejects.toThrow(
      'C6 Empresas is not configured.',
    )
  })
})
