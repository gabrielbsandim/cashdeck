import { describe, expect, it } from 'vitest'
import { Money, ValidationError } from '@cashdeck/domain'
import { NotFoundError, ProviderError } from '@/errors/errors'
import {
  account,
  base64,
  fullDeps,
  invoice,
  transaction,
} from '@/testing/deps.test-helpers'
import { TENANT } from '@/testing/scenario.test-helpers'
import {
  brlOf,
  certificateStateOf,
  ISSUER_COLLECTION,
  makeInvoiceReceipt,
  makeIssueInvoice,
  makeIssuerSetup,
  makeListInvoices,
  makeTestIssuer,
  makeUploadIssuerCertificate,
  serviceCodeOf,
} from '@/use-cases/invoices'
import { makePayroll } from '@/use-cases/payroll'

const SETUP = {
  kind: 'NATIONAL' as const,
  city: 'São Paulo',
  municipalRegistration: '12345',
  serviceCode: '01.01',
}

const client = {
  id: 'client',
  tenantId: TENANT,
  entityId: 'pj',
  name: 'Client Inc',
  taxId: null,
  country: 'US',
}

describe('issuer setup', () => {
  it('reads nothing, then saves and keeps the certificate facts', async () => {
    const deps = fullDeps()
    const setup = makeIssuerSetup(deps)
    expect(await setup.get(TENANT)).toBeNull()
    const saved = await setup.save(TENANT, SETUP)
    expect(saved).toMatchObject({
      certificateState: null,
      serviceCode: { code: '01.01' },
    })
    const upload = makeUploadIssuerCertificate(deps)
    const withCert = await upload(TENANT, {
      fileName: 'company.pem',
      mimeType: 'application/x-pem-file',
      base64: base64('cert'),
      password: 'secret',
      expiresOn: '2027-01-01',
    })
    expect(withCert).toMatchObject({
      certificateName: 'company.pem',
      certificateExpiresOn: '2027-03-02',
    })
    expect(await deps.secrets.get(TENANT, 'NFSE_CERTIFICATE@pj')).toContain(
      'sealed:NFSE_CERTIFICATE@pj:',
    )
    expect(
      (await setup.save(TENANT, { ...SETUP, city: 'Campinas' }))
        .certificateName,
    ).toBe('company.pem')
    expect((await setup.get(TENANT))?.city).toBe('Campinas')
  })

  it('uses the typed expiry for a pfx and needs a setup first', async () => {
    const deps = fullDeps()
    const upload = makeUploadIssuerCertificate(deps)
    const pfx = {
      fileName: 'company.pfx',
      mimeType: 'application/x-pkcs12',
      base64: base64('cert'),
      password: 'secret',
      expiresOn: '2026-10-20',
    }
    await expect(upload(TENANT, pfx)).rejects.toThrow(NotFoundError)
    await makeIssuerSetup(deps).save(TENANT, SETUP)
    expect((await upload(TENANT, pfx)).certificateState).toBe('EXPIRING_SOON')
  })

  it('grades a certificate and names unknown service codes', () => {
    expect(certificateStateOf('2026-10-01', '2026-10-08')).toBe('EXPIRED')
    expect(certificateStateOf('2027-10-01', '2026-10-08')).toBe('VALID')
    expect(serviceCodeOf('99.99')).toEqual({
      code: '99.99',
      description: '99.99',
    })
  })

  it('tests the issuer and reports a failed check', async () => {
    const deps = fullDeps()
    expect(await makeTestIssuer(deps)()).toEqual({
      protocol: 'OK',
      elapsedMs: 0,
    })
    const failing = {
      ...deps.issuer,
      id: 'fake',
      check: async () => ({ ok: false, message: null }),
    }
    await expect(
      makeTestIssuer({ ...deps, issuer: failing as never })(),
    ).rejects.toThrow(ProviderError)
    const noted = {
      ...failing,
      check: async () => ({ ok: true, message: 'proto-1' }),
    }
    expect(
      (await makeTestIssuer({ ...deps, issuer: noted as never })()).protocol,
    ).toBe('proto-1')
    const refused = {
      ...failing,
      check: async () => ({ ok: false, message: 'expired key' }),
    }
    await expect(
      makeTestIssuer({ ...deps, issuer: refused as never })(),
    ).rejects.toThrow('expired key')
  })
})

describe('invoices', () => {
  it('converts a foreign amount to BRL', () => {
    expect(
      brlOf(invoice({ id: 'a', amount: Money.of(1000, 'USD'), fxRate: 5 }))
        .cents,
    ).toBe(5000)
    expect(
      brlOf(invoice({ id: 'b', amount: Money.of(1000, 'USD') })).cents,
    ).toBe(0)
  })

  it('lists the company invoices with the client name', async () => {
    const deps = fullDeps()
    await deps.invoices.saveClient(client)
    await deps.invoices.save(invoice({ id: 'i1', templateId: 'tpl' }))
    await deps.invoices.save(
      invoice({ id: 'i2', clientId: 'gone', competence: '2026-08' }),
    )
    const list = makeListInvoices(deps)
    const page = await list(TENANT, { limit: 50 })
    expect(page.items.map(i => [i.id, i.client, i.recurring])).toEqual([
      ['i1', 'Client Inc', true],
      ['i2', '', false],
    ])
    expect(
      (await list(TENANT, { limit: 50, month: '2026-08', status: 'ISSUED' }))
        .items,
    ).toHaveLength(1)
  })

  it('issues a draft once, with its BRL total', async () => {
    const deps = fullDeps()
    await deps.invoices.saveClient(client)
    await deps.invoices.save(invoice({ id: 'd', status: 'DRAFT' }))
    const issue = makeIssueInvoice(deps)
    const issued = await issue(TENANT, 'd')
    expect(issued).toMatchObject({
      status: 'ISSUED',
      number: '1',
      externalId: 'invoice:d',
    })
    expect(deps.audit.events.at(-1)).toMatchObject({ action: 'invoice.issue' })
    await expect(issue(TENANT, 'd')).rejects.toThrow(ValidationError)
    await expect(issue(TENANT, 'nope')).rejects.toThrow(NotFoundError)
    await deps.invoices.save(
      invoice({ id: 'orphan', status: 'DRAFT', clientId: 'gone' }),
    )
    await expect(issue(TENANT, 'orphan')).rejects.toThrow(NotFoundError)
  })

  it('invoices a company income for its payer', async () => {
    const deps = fullDeps()
    await deps.accounts.save(account({ id: 'op' }))
    await deps.accounts.save(account({ id: 'pf-1', entityId: 'pf' }))
    await deps.transactions.save(
      transaction({
        id: 'r1',
        accountId: 'op',
        amount: Money.of(5000),
        description: 'Client Inc',
      }),
    )
    await deps.transactions.save(
      transaction({
        id: 'r2',
        accountId: 'op',
        amount: Money.of(6000),
        description: 'Client Inc',
      }),
    )
    await deps.transactions.save(transaction({ id: 'out', accountId: 'op' }))
    await deps.transactions.save(
      transaction({ id: 'pf', accountId: 'pf-1', amount: Money.of(1) }),
    )
    const receipt = makeInvoiceReceipt(deps)
    await expect(receipt(TENANT, 'r1')).rejects.toThrow(NotFoundError)
    await deps.documents.put(TENANT, ISSUER_COLLECTION, 'pj', {
      ...SETUP,
      certificateName: null,
      certificateExpiresOn: null,
      certificateFingerprint: null,
    })
    const first = await receipt(TENANT, 'r1')
    expect(first).toMatchObject({
      status: 'ISSUED',
      competence: '2026-10',
      isExport: false,
    })
    expect((await deps.transactions.findById(TENANT, 'r1'))?.invoiceId).toBe(
      first.id,
    )
    const second = await receipt(TENANT, 'r2')
    expect(second.clientId).toBe(first.clientId)
    await expect(receipt(TENANT, 'r1')).rejects.toThrow(
      'already has an invoice',
    )
    await expect(receipt(TENANT, 'out')).rejects.toThrow(ValidationError)
    await expect(receipt(TENANT, 'pf')).rejects.toThrow(ValidationError)
    await expect(receipt(TENANT, 'nope')).rejects.toThrow(NotFoundError)
  })
})

describe('payroll', () => {
  it('saves a month and shows the sheet with twelve months of revenue', async () => {
    const deps = fullDeps()
    const payroll = makePayroll(deps)
    const empty = await payroll.sheet(TENANT)
    expect(empty.current).toMatchObject({
      month: '2026-10-01',
      proLabore: { cents: 0 },
    })
    await deps.invoices.save(invoice({ id: 'i', competence: '2026-05' }))
    await payroll.save(TENANT, '2026-09', {
      proLaboreCents: 1,
      salariesCents: 2,
      fgtsCents: 3,
    })
    const sheet = await payroll.save(TENANT, '2026-10', {
      proLaboreCents: 500000,
      salariesCents: 0,
      fgtsCents: 0,
    })
    expect(sheet.current.proLabore.cents).toBe(500000)
    expect(sheet.history.map(entry => entry.month)).toEqual(['2026-09-01'])
    expect(sheet.revenue12.cents).toBe(100000)
  })
})
