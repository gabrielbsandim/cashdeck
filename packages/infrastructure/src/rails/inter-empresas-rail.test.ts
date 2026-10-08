import { describe, expect, it } from 'vitest'
import { Money } from '@cashdeck/domain'
import { BankClients } from '@/rails/bank-client'
import { INTER_URLS, InterEmpresasRail } from '@/rails/inter-empresas-rail'
import {
  credentials,
  DYNAMIC_PIX,
  ENTITY,
  payment,
  STATIC_PIX,
  TAX_BARCODE,
  TENANT,
} from '@/testing/provider-fixtures'
import { ScriptedTransport } from '@/testing/scripted-transport'

const HOST = INTER_URLS.production
const API = `${HOST}/banking/v2`
const TOKEN = `${HOST}/oauth/v2/token`
const scope = { tenantId: TENANT, entityId: ENTITY }
const env = {
  INTER_CLIENT_ID: 'client',
  INTER_CLIENT_SECRET: 'secret',
  INTER_CERT: 'cert',
  INTER_KEY: 'key',
}
const darf = {
  cnpjCpf: '11222333000181',
  codigoReceita: '0220',
  periodoApuracao: '2026-09-30',
  referencia: '123',
  nomeEmpresa: 'Empresa Exemplo',
}

function setup(extra: Record<string, string> = {}, withDarf = true) {
  const scripted = new ScriptedTransport().on('POST', TOKEN, {
    json: { access_token: 'tok', expires_in: 3600 },
  })
  const certificates: unknown[] = []
  const rail = new InterEmpresasRail({
    credentials: credentials({ ...env, ...extra }),
    clients: new BankClients(certificate => {
      certificates.push(certificate)
      return scripted.transport
    }),
    darfDetails: withDarf ? async () => darf : undefined,
  })
  return { scripted, rail, certificates }
}

describe('InterEmpresasRail', () => {
  it('covers every company bill kind', () => {
    const { rail } = setup()
    expect(rail.id).toBe('INTER_EMPRESAS')
    expect(rail.supports('DARF_NO_BARCODE', 'PJ')).toBe(true)
    expect(rail.supports('BOLETO', 'PF')).toBe(false)
  })

  it('pays a bolepix by its copy and paste code over mTLS', async () => {
    const { scripted, rail, certificates } = setup({ INTER_ACCOUNT: '12345' })
    scripted.on('POST', `${API}/pix`, {
      json: { tipoRetorno: 'PROCESSADO', codigoSolicitacao: 'sol-1' },
    })
    const result = await rail.pay(payment({ pixCode: DYNAMIC_PIX }))
    expect(result).toEqual({
      outcome: 'SUBMITTED',
      externalId: 'pix:sol-1',
      reason: null,
    })
    expect(certificates).toEqual([{ cert: 'cert', key: 'key' }])
    const sent = scripted.last('POST', `${API}/pix`)
    expect(sent.headers).toMatchObject({
      authorization: 'Bearer tok',
      'x-conta-corrente': '12345',
      'x-id-idempotente': 'bill-1:0',
    })
    expect(JSON.parse(sent.body ?? '')).toEqual({
      valor: 123.45,
      descricao: 'Energia Exemplo',
      destinatario: { tipo: 'PIX_COPIA_E_COLA', pixCopiaECola: DYNAMIC_PIX },
    })
    const token = scripted.last('POST', TOKEN)
    expect(token.body).toContain('grant_type=client_credentials')
    expect(token.body).toContain('pagamento-pix.write')
  })

  it('waits for approval when the account requires it', async () => {
    const { scripted, rail } = setup()
    scripted.on('POST', `${API}/pix`, {
      json: { tipoRetorno: 'APROVACAO', codigoSolicitacao: 's2' },
    })
    const result = await rail.pay(payment({ kind: 'PIX_QR', code: STATIC_PIX }))
    expect(result.outcome).toBe('PENDING_APPROVAL')
    const mismatch = await rail.pay(
      payment({ kind: 'PIX_QR', code: STATIC_PIX, amount: Money.of(1) }),
    )
    expect(mismatch).toEqual({
      outcome: 'FAILED',
      reason: 'PIX_AMOUNT_MISMATCH',
    })
  })

  it('sends a pix to a key', async () => {
    const { scripted, rail } = setup()
    scripted.on('POST', `${API}/pix`, {
      json: { tipoRetorno: 'AGENDADO', codigoSolicitacao: 's3' },
    })
    await rail.pay(payment({ kind: 'PIX_KEY', code: '11.222.333/0001-81' }))
    expect(scripted.body('POST', `${API}/pix`)).toMatchObject({
      destinatario: { tipo: 'CHAVE', chave: '11222333000181' },
    })
  })

  it('pays boletos and tax guides by barcode', async () => {
    const { scripted, rail } = setup()
    scripted.on('POST', `${API}/pagamento`, {
      json: { statusPagamento: 'REALIZADO', codigoTransacao: 'tx-1' },
    })
    const result = await rail.pay(
      payment({ kind: 'TAX_BARCODE', code: TAX_BARCODE }),
    )
    expect(result).toEqual({
      outcome: 'PAID',
      externalId: 'pagamento:tx-1',
      reason: null,
    })
    expect(scripted.body('POST', `${API}/pagamento`)).toEqual({
      codBarraLinhaDigitavel: TAX_BARCODE,
      valorPagar: '123.45',
      dataVencimento: '2026-10-08',
    })
  })

  it('pays a DARF without barcode from its details', async () => {
    const { scripted, rail } = setup()
    scripted.on('POST', `${API}/pagamento/darf`, {
      json: { tipoRetorno: 'APROVACAO_PAGAMENTO', codigoSolicitacao: 'd-1' },
    })
    const result = await rail.pay(
      payment({ kind: 'DARF_NO_BARCODE', code: null }),
    )
    expect(result).toEqual({
      outcome: 'PENDING_APPROVAL',
      externalId: 'darf:d-1',
      reason: null,
    })
    expect(scripted.body('POST', `${API}/pagamento/darf`)).toEqual({
      ...darf,
      dataVencimento: '2026-10-08',
      descricao: 'Energia Exemplo',
      valorPrincipal: 123.45,
    })
    const missing = setup({}, false)
    const refused = await missing.rail.pay(
      payment({ kind: 'DARF_NO_BARCODE', code: null }),
    )
    expect(refused).toEqual({
      outcome: 'FAILED',
      reason: 'DARF_DETAILS_MISSING',
    })
  })

  it('maps refusals and outages', async () => {
    const { scripted, rail } = setup()
    scripted.on(
      'POST',
      `${API}/pagamento`,
      {
        status: 400,
        json: {
          title: 'Bad',
          detail: 'Boleto vencido',
          violacoes: [{ razao: 'Linha inválida' }],
        },
      },
      { status: 422, json: { title: 'Unprocessable', detail: 'Sem saldo' } },
      { status: 400, json: { title: 'Only title' } },
      { status: 409, text: '' },
      { status: 502, text: 'bad gateway' },
    )
    expect((await rail.pay(payment())).reason).toBe('Linha inválida')
    expect((await rail.pay(payment())).reason).toBe('Sem saldo')
    expect((await rail.pay(payment())).reason).toBe('Only title')
    expect((await rail.pay(payment())).reason).toBe(
      'Inter refused the request (409).',
    )
    await expect(rail.pay(payment())).rejects.toThrow(
      'Inter Empresas answered 502',
    )
    scripted.on('POST', `${API}/pix`, {
      status: 400,
      json: { detail: 'Chave inexistente' },
    })
    const pix = await rail.pay(payment({ kind: 'PIX_KEY', code: 'a@b.co' }))
    expect(pix.reason).toBe('Chave inexistente')
    const darfSetup = setup()
    darfSetup.scripted.on('POST', `${API}/pagamento/darf`, {
      status: 400,
      json: { detail: 'Receita inválida' },
    })
    const darfResult = await darfSetup.rail.pay(
      payment({ kind: 'DARF_NO_BARCODE', code: null }),
    )
    expect(darfResult.reason).toBe('Receita inválida')
  })

  it('renews the token once when the bank answers 401', async () => {
    const { scripted, rail } = setup()
    scripted.on(
      'POST',
      `${API}/pagamento`,
      { status: 401 },
      { json: { statusPagamento: 'AGENDADO', codigoTransacao: 'tx-2' } },
    )
    expect((await rail.pay(payment())).outcome).toBe('SUBMITTED')
    expect(scripted.requests.filter(r => r.url === TOKEN)).toHaveLength(2)
  })

  it('reads the status of pix, boleto and DARF payments', async () => {
    const { scripted, rail } = setup()
    scripted
      .on('GET', `${API}/pix/sol-1`, {
        json: {
          transacaoPix: {
            status: 'PAGO',
            endToEnd: 'E0000000020261008',
            dataHoraMovimento: '2026-10-08T12:00',
          },
        },
      })
      .on('GET', `${API}/pix/sol-2`, { json: {} })
      .on('GET', `${API}/pix/sol-3`, {
        status: 404,
        json: { detail: 'Não encontrado' },
      })
      .on('GET', `${API}/pix/sol-4`, {
        json: { transacaoPix: { status: 'PAGO' } },
      })
      .on('GET', `${API}/pagamento?codigoTransacao=tx-1`, {
        json: [{ statusPagamento: 'PAGO', dataPagamento: '2026-10-08' }],
      })
      .on('GET', `${API}/pagamento?codigoTransacao=tx-2`, {
        json: [{ statusPagamento: 'PAGO' }],
      })
      .on('GET', `${API}/pagamento/darf?codigoSolicitacao=d-1`, { json: [] })
      .on('GET', `${API}/pagamento/darf?codigoSolicitacao=d-2`, {
        status: 400,
        json: { detail: 'x' },
      })
    expect(await rail.status('pix:sol-1', scope)).toEqual({
      outcome: 'PAID',
      externalId: 'pix:sol-1',
      reason: null,
      endToEndId: 'E0000000020261008',
      settledAt: '2026-10-08T12:00',
    })
    expect(await rail.status('pix:sol-2', scope)).toMatchObject({
      outcome: 'SUBMITTED',
      endToEndId: null,
    })
    expect(await rail.status('pix:sol-3', scope)).toMatchObject({
      outcome: 'FAILED',
      reason: 'Não encontrado',
    })
    expect(await rail.status('pix:sol-4', scope)).toMatchObject({
      outcome: 'PAID',
      settledAt: null,
    })
    expect(await rail.status('pagamento:tx-1', scope)).toMatchObject({
      outcome: 'PAID',
      settledAt: '2026-10-08',
    })
    expect(await rail.status('pagamento:tx-2', scope)).toMatchObject({
      settledAt: null,
    })
    expect(await rail.status('darf:d-1', scope)).toMatchObject({
      outcome: 'SUBMITTED',
      settledAt: null,
    })
    expect((await rail.status('darf:d-2', scope)).outcome).toBe('FAILED')
    await expect(rail.status('boleto:1', scope)).rejects.toThrow(
      'does not know',
    )
  })

  it('checks the balance in the sandbox and reports missing credentials', async () => {
    const { scripted, rail } = setup({ INTER_ENVIRONMENT: 'sandbox' })
    const sandbox = INTER_URLS.sandbox
    scripted
      .on('POST', `${sandbox}/oauth/v2/token`, { json: { access_token: 'sb' } })
      .on(
        'GET',
        `${sandbox}/banking/v2/saldo`,
        { json: { disponivel: 10 } },
        { status: 403, json: { detail: 'Escopo' } },
      )
    expect(await rail.check()).toEqual({ ok: true, message: null })
    expect(await rail.check()).toEqual({
      ok: false,
      message: 'Inter Empresas check failed: Escopo',
    })
    const none = new InterEmpresasRail({ credentials: credentials({}) })
    expect(await none.check()).toEqual({
      ok: false,
      message: 'Inter Empresas is not configured.',
    })
  })

  it('surfaces a refused token request', async () => {
    const scripted = new ScriptedTransport().on(
      'POST',
      TOKEN,
      { status: 400, json: {} },
      { json: {} },
    )
    const rail = new InterEmpresasRail({
      credentials: credentials(env),
      clients: new BankClients(() => scripted.transport),
    })
    await expect(rail.pay(payment())).rejects.toThrow(
      'the token request was refused',
    )
    await expect(rail.pay(payment())).rejects.toThrow('no access_token')
  })
})
