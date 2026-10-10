import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { Money } from '@cashdeck/domain'
import { getContainer, resetContainer } from '@/server/container'
import { signState } from '@/server/api/auth'
import { GET as authCheck } from '@/app/api/v1/auth/check/route'
import { GET as entities } from '@/app/api/v1/entities/route'
import { GET as homePersonal } from '@/app/api/v1/home/personal/route'
import { GET as fundingPlan } from '@/app/api/v1/home/personal/funding/route'
import { GET as homeCompany } from '@/app/api/v1/home/company/route'
import { GET as homeConsolidated } from '@/app/api/v1/home/consolidated/route'
import { POST as approveDraft } from '@/app/api/v1/home/company/drafts/[invoiceId]/approve/route'
import { POST as invoiceReceipt } from '@/app/api/v1/home/company/unbilled/[transactionId]/invoice/route'
import {
  GET as listAccounts,
  POST as createAccount,
} from '@/app/api/v1/accounts/route'
import { PATCH as updateAccount } from '@/app/api/v1/accounts/[id]/route'
import { GET as listTransactions } from '@/app/api/v1/transactions/route'
import {
  GET as listTransfers,
  POST as recordTransfer,
} from '@/app/api/v1/transfers/route'
import { GET as getTransfer } from '@/app/api/v1/transfers/[id]/route'
import { GET as transferDocument } from '@/app/api/v1/transfers/[id]/document/route'
import { POST as captureBill } from '@/app/api/v1/bills/route'
import { POST as markPaid } from '@/app/api/v1/bills/[id]/mark-paid/route'
import { GET as receipt } from '@/app/api/v1/bills/[id]/receipt/route'
import { GET as receiptPdf } from '@/app/api/v1/bills/[id]/receipt/pdf/route'
import { POST as attach } from '@/app/api/v1/bills/[id]/attachments/route'
import { GET as attachment } from '@/app/api/v1/bills/[id]/attachments/[attachmentId]/route'
import { POST as lookup } from '@/app/api/v1/open-finance/lookup/route'
import {
  GET as connections,
  POST as connect,
} from '@/app/api/v1/open-finance/connections/route'
import { DELETE as disconnect } from '@/app/api/v1/open-finance/connections/[id]/route'
import { POST as syncConnection } from '@/app/api/v1/open-finance/connections/[id]/sync/route'
import { GET as listRails } from '@/app/api/v1/rails/route'
import { DELETE as removeRail } from '@/app/api/v1/rails/[id]/route'
import { POST as authorizeRail } from '@/app/api/v1/rails/[id]/authorize/route'
import {
  GET as railCredentials,
  PUT as saveRailCredentials,
} from '@/app/api/v1/rails/[id]/credentials/route'
import { POST as testRail } from '@/app/api/v1/rails/[id]/test/route'
import { GET as automation } from '@/app/api/v1/automation/route'
import { POST as pause } from '@/app/api/v1/automation/pause/route'
import { POST as resume } from '@/app/api/v1/automation/resume/route'
import { PATCH as automationSettings } from '@/app/api/v1/automation/settings/route'
import { GET as captureSources } from '@/app/api/v1/capture/sources/route'
import { POST as captureFile } from '@/app/api/v1/capture/files/route'
import { POST as oauthStart } from '@/app/api/v1/capture/mailboxes/oauth/start/route'
import { GET as oauthCallback } from '@/app/api/v1/capture/mailboxes/oauth/callback/route'
import { DELETE as removeMailbox } from '@/app/api/v1/capture/mailboxes/[id]/route'
import { POST as readMailbox } from '@/app/api/v1/capture/mailboxes/[id]/read/route'
import { PUT as setDda } from '@/app/api/v1/capture/dda/[entity]/route'
import { GET as listInvoices } from '@/app/api/v1/invoices/route'
import {
  GET as getIssuer,
  PUT as saveIssuer,
} from '@/app/api/v1/invoices/issuer/route'
import { PUT as issuerCertificate } from '@/app/api/v1/invoices/issuer/certificate/route'
import { POST as testIssuer } from '@/app/api/v1/invoices/issuer/test/route'
import { GET as serviceCodes } from '@/app/api/v1/invoices/service-codes/route'
import { GET as payroll } from '@/app/api/v1/payroll/route'
import { PUT as declareAnnex } from '@/app/api/v1/payroll/annex/route'
import { PUT as savePayroll } from '@/app/api/v1/payroll/[month]/route'
import { GET as revenue } from '@/app/api/v1/revenue/route'
import { PUT as saveRevenue } from '@/app/api/v1/revenue/[month]/route'
import { POST as readStatement } from '@/app/api/v1/card-statements/route'
import { GET as latestStatement } from '@/app/api/v1/card-statements/latest/route'
import { GET as getStatement } from '@/app/api/v1/card-statements/[id]/route'
import { POST as statementBill } from '@/app/api/v1/card-statements/[id]/bill/route'
import { POST as generateExport } from '@/app/api/v1/accountant-export/route'
import { GET as exportPlan } from '@/app/api/v1/accountant-export/plan/route'
import { GET as exportHistory } from '@/app/api/v1/accountant-export/history/route'
import { GET as exportDownload } from '@/app/api/v1/accountant-export/[id]/download/route'
import { GET as syncCron } from '@/app/api/cron/open-finance-sync/route'
import { GET as previewCron } from '@/app/api/cron/preview-sync/route'
import { GET as captureCron } from '@/app/api/cron/capture/route'
import { GET as reconcileCron } from '@/app/api/cron/reconcile-payments/route'

const TOKEN = 'test-token-0123456789'
const BOLETO_LINE = '00190000090280001234256789012178916050000012345'
const ITEM = '0b5c3a1e-7d2f-4c8a-9e61-3f2b8d4c5a10'

// Next passes route params as a promise; handlers without params ignore it.
type Handler = (request: Request, context: never) => Promise<Response>

async function call(
  handler: Handler,
  method: string,
  options: {
    body?: unknown
    params?: Record<string, string>
    query?: string
  } = {},
) {
  const request = new Request(
    `http://localhost/api/v1/test${options.query ?? ''}`,
    {
      method,
      headers: { authorization: `Bearer ${TOKEN}` },
      body:
        options.body === undefined ? undefined : JSON.stringify(options.body),
    },
  )
  const context = { params: Promise.resolve(options.params ?? {}) }
  const response = await handler(request, context as never)
  const type = response.headers.get('content-type') ?? ''
  const body = type.includes('json')
    ? await response.json()
    : Buffer.from(await response.arrayBuffer())
  return { status: response.status, body, headers: response.headers }
}

const h = (handler: unknown) => handler as Handler

const upload = (text: string, fileName = 'file.pdf') => ({
  fileName,
  mimeType: 'application/pdf',
  base64: Buffer.from(text).toString('base64'),
})

function stubGmail() {
  vi.stubEnv('GMAIL_CLIENT_ID', 'client-id')
  vi.stubEnv('GMAIL_CLIENT_SECRET', 'client-secret')
  vi.stubEnv('GMAIL_REDIRECT_URI', 'https://api.example.com/callback')
}

const callback = (query: string) =>
  oauthCallback(
    new Request(
      `http://localhost/api/v1/capture/mailboxes/oauth/callback?${query}`,
    ),
  )

beforeEach(() => {
  vi.stubEnv('CASHDECK_API_TOKEN', TOKEN)
  vi.stubEnv('CRON_SECRET', 'cron-secret')
})

afterEach(() => {
  resetContainer()
  vi.unstubAllEnvs()
  vi.unstubAllGlobals()
  vi.restoreAllMocks()
})

describe('auth and entities', () => {
  it('checks the token and lists the entities', async () => {
    const check = await call(h(authCheck), 'GET')
    expect(check.status).toBe(200)
    expect(check.body.data.entities).toHaveLength(2)
    const anonymous = await authCheck(
      new Request('http://localhost/api/v1/auth/check'),
    )
    expect(anonymous.status).toBe(401)
    expect((await call(h(entities), 'GET')).body.data).toHaveLength(2)
  })
})

describe('money views', () => {
  it('runs accounts, transfers and home end to end', async () => {
    const pf = await call(h(createAccount), 'POST', {
      body: {
        entity: 'PF',
        institution: 'Bank',
        name: 'Checking',
        type: 'CHECKING',
        balanceCents: 10000,
      },
    })
    expect(pf.status).toBe(201)
    const pj = await call(h(createAccount), 'POST', {
      body: {
        entity: 'PJ',
        institution: 'Bank',
        name: 'Operating',
        type: 'CHECKING',
        balanceCents: 50000,
      },
    })
    const patched = await call(h(updateAccount), 'PATCH', {
      body: { cdiPercent: 100 },
      params: { id: pf.body.data.id },
    })
    expect(patched.status).toBe(200)
    const listed = await call(h(listAccounts), 'GET', { query: '?entity=PJ' })
    expect(listed.body.data).toHaveLength(1)
    const transfer = await call(h(recordTransfer), 'POST', {
      body: {
        kind: 'PRO_LABORE',
        amountCents: 1000,
        fromAccountId: pj.body.data.id,
        toAccountId: pf.body.data.id,
      },
    })
    expect(transfer.status).toBe(201)
    const id = transfer.body.data.id
    const document = await call(h(transferDocument), 'GET', { params: { id } })
    expect(document.headers.get('content-type')).toBe('application/pdf')
    expect(document.body.subarray(0, 5).toString()).toBe('%PDF-')
    const fetched = await call(h(getTransfer), 'GET', { params: { id } })
    expect(fetched.body.data.id).toBe(id)
    expect((await call(h(listTransfers), 'GET')).body.data).toHaveLength(1)
    const rows = await call(h(listTransactions), 'GET', { query: '?entity=PF' })
    expect(rows.status).toBe(200)
    const impossible = await call(h(listTransactions), 'GET', {
      query: '?from=2026-13-01&to=2026-02-30',
    })
    expect(impossible.status).toBe(422)
    expect((await call(h(homePersonal), 'GET')).status).toBe(200)
    const funding = await call(h(fundingPlan), 'GET')
    expect(funding.status).toBe(200)
    expect(funding.body.data).toHaveProperty('monthlyAverage')
    expect((await call(h(homeCompany), 'GET')).status).toBe(200)
    expect((await call(h(homeConsolidated), 'GET')).status).toBe(200)
  })

  it('reports a missing draft or receipt to invoice', async () => {
    const draft = await call(h(approveDraft), 'POST', {
      params: { invoiceId: 'missing' },
    })
    expect(draft.status).toBe(404)
    const unbilled = await call(h(invoiceReceipt), 'POST', {
      params: { transactionId: 'missing' },
    })
    expect(unbilled.status).toBe(404)
  })
})

describe('bills, receipts and attachments', () => {
  it('attaches a proof, marks the bill paid and serves the file', async () => {
    const created = await call(h(captureBill), 'POST', {
      body: { entityId: 'company', paymentCode: BOLETO_LINE },
    })
    const id = created.body.data.id
    const added = await call(h(attach), 'POST', {
      body: upload('proof'),
      params: { id },
    })
    expect(added.status).toBe(201)
    const attachmentId = added.body.data.id
    const paid = await call(h(markPaid), 'POST', {
      body: { attachmentId },
      params: { id },
    })
    expect(paid.body.data.status).toBe('PAID')
    const view = await call(h(receipt), 'GET', { params: { id } })
    expect(view.body.data.billId).toBe(id)
    const file = await call(h(attachment), 'GET', {
      params: { id, attachmentId },
    })
    expect(file.headers.get('content-type')).toBe('application/pdf')
    expect(file.headers.get('content-disposition')).toContain('file.pdf')
    expect(file.body.toString()).toBe('proof')
    const pdf = await call(h(receiptPdf), 'GET', { params: { id } })
    expect(pdf.headers.get('content-disposition')).toContain(
      `receipt-${id}.pdf`,
    )
  })
})

describe('open finance', () => {
  it('answers not configured without the aggregator', async () => {
    const found = await call(h(lookup), 'POST', { body: { itemId: ITEM } })
    expect(found.status).toBe(503)
    const linked = await call(h(connect), 'POST', {
      body: { itemId: ITEM, entity: 'PF', accountIds: ['a'] },
    })
    expect(linked.status).toBe(503)
    expect((await call(h(connections), 'GET')).body.data).toEqual([])
    const params = { id: 'missing' }
    expect((await call(h(syncConnection), 'POST', { params })).status).toBe(404)
    expect((await call(h(disconnect), 'DELETE', { params })).status).toBe(404)
  })
})

describe('rails and automation', () => {
  it('stores rail credentials and tests the rail', async () => {
    const list = await call(h(listRails), 'GET', { query: '?entity=PF' })
    expect(list.status).toBe(200)
    const params = { id: 'PF.ASAAS.PIX_API' }
    const saved = await call(h(saveRailCredentials), 'PUT', {
      body: { apiKey: 'key-1234' },
      params,
    })
    expect(saved.status).toBe(200)
    expect((await call(h(railCredentials), 'GET', { params })).status).toBe(200)
    expect((await call(h(authorizeRail), 'POST', { params })).status).toBe(200)
    expect((await call(h(testRail), 'POST', { params })).status).toBe(200)
    expect((await call(h(removeRail), 'DELETE', { params })).status).toBe(200)
  })

  it('pauses, resumes and tunes automation', async () => {
    expect((await call(h(automation), 'GET')).status).toBe(200)
    expect((await call(h(pause), 'POST')).status).toBe(200)
    expect((await call(h(resume), 'POST')).status).toBe(200)
    const tuned = await call(h(automationSettings), 'PATCH', {
      body: { entity: 'PJ', confirmAboveCents: 100000 },
    })
    expect(tuned.status).toBe(200)
  })
})

describe('capture sources', () => {
  it('captures a bill from a shared file read by the AI', async () => {
    const { llm } = getContainer().deps
    vi.spyOn(llm, 'chat').mockResolvedValue({
      text: '',
      toolCalls: [],
      usage: { inputTokens: 0, outputTokens: 0, costMillicents: 0 },
      stopReason: 'end',
      object: {
        paymentCode: BOLETO_LINE,
        pixCode: '',
        payee: 'Supplier',
        amount: 0,
        dueDate: '',
      },
    })
    const body = { ...upload('bill'), entity: 'PJ' }
    const created = await call(h(captureFile), 'POST', { body })
    expect([created.status, created.body.data.payee]).toEqual([201, 'Supplier'])
    expect((await call(h(captureFile), 'POST', { body })).status).toBe(200)
    const invalid = await call(h(captureFile), 'POST', {
      body: { entity: 'PJ' },
    })
    expect(invalid.status).toBe(422)
  })

  it('needs the Gmail app before starting OAuth', async () => {
    const start = await call(h(oauthStart), 'POST', { body: { entity: 'PF' } })
    expect(start.status).toBe(503)
  })

  it('rejects a forged state and a failing exchange', async () => {
    stubGmail()
    const started = await call(h(oauthStart), 'POST', {
      body: { entity: 'PF' },
    })
    const state = new URL(started.body.data.url).searchParams.get('state')
    const forged = await callback('code=c&state=forged.sig')
    expect(forged.headers.get('location')).toBe(
      'cashdeck://capture?error=INVALID_STATE',
    )
    vi.spyOn(console, 'error').mockImplementation(() => undefined)
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => new Response('denied', { status: 400 })),
    )
    const refused = await callback(
      `code=c&state=${encodeURIComponent(state ?? '')}`,
    )
    expect(refused.headers.get('location')).toBe(
      'cashdeck://capture?error=AUTHORIZATION_FAILED',
    )
  })

  it('stores a mailbox from a valid callback and toggles DDA', async () => {
    stubGmail()
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string) =>
        String(url).includes('token')
          ? Response.json({ access_token: 'at', refresh_token: 'rt' })
          : Response.json({ email: 'mailbox@example.com' }),
      ),
    )
    const state = signState({ tenantId: 'local', entity: 'PF' }, new Date())
    const done = await callback(`code=c&state=${encodeURIComponent(state)}`)
    expect(done.headers.get('location')).toBe('cashdeck://capture?connected=1')
    const sources = await call(h(captureSources), 'GET')
    expect(sources.status).toBe(200)
    const mailbox = sources.body.data.mailboxes[0]
    expect(mailbox.address).toBe('mailbox@example.com')
    const dda = await call(h(setDda), 'PUT', {
      body: { enabled: true },
      params: { entity: 'PJ' },
    })
    expect(dda.status).toBe(200)
    const missing = { params: { id: 'missing' } }
    expect((await call(h(readMailbox), 'POST', missing)).status).toBe(404)
    const removed = await call(h(removeMailbox), 'DELETE', {
      params: { id: mailbox.id },
    })
    expect(removed.status).toBe(200)
  })
})

describe('invoices and payroll', () => {
  it('sets up the issuer and saves payroll', async () => {
    expect((await call(h(getIssuer), 'GET')).status).toBe(200)
    const saved = await call(h(saveIssuer), 'PUT', {
      body: {
        kind: 'NATIONAL',
        city: 'Sao Paulo',
        municipalRegistration: '123',
        serviceCode: '01.01',
      },
    })
    expect(saved.status).toBe(200)
    const certificate = await call(h(issuerCertificate), 'PUT', {
      body: {
        ...upload('not a certificate', 'company.pfx'),
        password: 'secret',
        expiresOn: '2027-01-01',
      },
    })
    expect(certificate.status).toBe(200)
    const tested = await call(h(testIssuer), 'POST')
    expect([tested.status, tested.body.error.code]).toEqual([
      502,
      'PROVIDER_ERROR',
    ])
    expect((await call(h(serviceCodes), 'GET')).status).toBe(200)
    const invoices = await call(h(listInvoices), 'GET', {
      query: '?month=2026-10',
    })
    expect(invoices.status).toBe(200)
    const sheet = await call(h(savePayroll), 'PUT', {
      body: { proLaboreCents: 1, salariesCents: 0, fgtsCents: 0 },
      params: { month: '2026-09' },
    })
    expect(sheet.status).toBe(200)
    expect((await call(h(payroll), 'GET')).status).toBe(200)
    const declared = await call(h(declareAnnex), 'PUT', {
      body: { annex: 'III' },
    })
    expect([declared.status, declared.body.data.declaredAnnex]).toEqual([
      200,
      'III',
    ])
    const bad = await call(h(savePayroll), 'PUT', {
      body: {},
      params: { month: 'x' },
    })
    expect(bad.status).toBe(422)
    const entered = await call(h(saveRevenue), 'PUT', {
      body: { domesticCents: 1_600_000, exportCents: 0 },
      params: { month: '2026-09' },
    })
    expect(entered.status).toBe(200)
    expect((await call(h(revenue), 'GET')).status).toBe(200)
  })

  it('approves a stored draft once the issuer answers', async () => {
    const deps = getContainer().deps
    await deps.invoices.saveClient({
      id: 'client',
      tenantId: 'local',
      entityId: 'company',
      name: 'Client',
      taxId: null,
      country: 'BR',
    })
    await deps.invoices.save({
      id: 'draft',
      tenantId: 'local',
      entityId: 'company',
      clientId: 'client',
      templateId: null,
      issuer: 'notaas',
      externalId: null,
      number: null,
      status: 'DRAFT',
      amount: Money.of(1000),
      fxRate: null,
      isExport: false,
      competence: '2026-10',
      issueOn: '2026-10-08',
      description: 'Work',
      serviceCode: '01.01',
      pdfUrl: null,
      xmlUrl: null,
      createdAt: new Date(),
    } as never)
    const approved = await call(h(approveDraft), 'POST', {
      params: { invoiceId: 'draft' },
    })
    expect(approved.status).toBeGreaterThanOrEqual(200)
  })
})

describe('card statements and accountant export', () => {
  it('reads statements and bills a stored one', async () => {
    const read = await call(h(readStatement), 'POST', {
      body: { ...upload('pdf'), entity: 'PF' },
    })
    expect(read.status).toBeGreaterThanOrEqual(400)
    expect((await call(h(latestStatement), 'GET')).status).toBe(200)
    expect(
      (await call(h(getStatement), 'GET', { params: { id: 'missing' } }))
        .status,
    ).toBe(404)
    expect(
      (
        await call(h(statementBill), 'POST', {
          body: { lineIds: ['l1'], pixKey: 'billing@example.com' },
          params: { id: 'missing' },
        })
      ).status,
    ).toBe(404)
  })

  it('plans, generates and downloads an export', async () => {
    const plan = await call(h(exportPlan), 'GET', {
      query: '?period=LAST_MONTH',
    })
    expect(plan.status).toBe(200)
    const created = await call(h(generateExport), 'POST', {
      body: { period: 'LAST_MONTH', items: ['INVOICES'] },
    })
    expect(created.status).toBe(201)
    expect((await call(h(exportHistory), 'GET')).body.data).toHaveLength(1)
    const zip = await call(h(exportDownload), 'GET', {
      params: { id: created.body.data.id },
    })
    expect(zip.headers.get('content-type')).toBe('application/zip')
    expect(zip.body.readUInt32LE(0)).toBe(0x04034b50)
  })
})

describe('crons', () => {
  it('syncs, captures and reconciles', async () => {
    const cron = (handler: unknown) =>
      h(handler)(
        new Request('http://localhost/api/cron/job', {
          headers: { authorization: 'Bearer cron-secret' },
        }),
        {} as never,
      )
    expect((await cron(syncCron)).status).toBe(200)
    expect((await cron(previewCron)).status).toBe(200)
    expect((await cron(captureCron)).status).toBe(200)
    expect((await cron(reconcileCron)).status).toBe(200)
  })
})
