import { describe, expect, it } from 'vitest'
import { createPaymentPlan, Money } from '@cashdeck/domain'
import { base64, bill, fullDeps, invoice } from '@/testing/deps.test-helpers'
import { FakeRailStatusReader } from '@/testing/rail-status'
import {
  BOLETO_LINE,
  NOW,
  PIX_NO_AMOUNT,
  TENANT,
} from '@/testing/scenario.test-helpers'
import { makeCaptureBill } from '@/use-cases/capture-bill'
import { makeCaptureSources } from '@/use-cases/capture-sources'
import { makeCardStatements } from '@/use-cases/card-statements'
import { makeInvoiceLifecycle } from '@/use-cases/invoice-lifecycle'
import { makeIssueInvoice } from '@/use-cases/invoices'
import { makeReconcilePayments } from '@/use-cases/reconcile-payments'

describe('alert hooks', () => {
  it('alerts a newly captured bill, not a duplicate', async () => {
    const deps = fullDeps()
    const capture = makeCaptureBill(deps)
    const input = {
      entityId: 'pf',
      source: 'MANUAL' as const,
      paymentCode: BOLETO_LINE,
    }
    await capture(TENANT, input)
    await capture(TENANT, input)
    expect(deps.alerts.types()).toEqual(['BILL_CAPTURED'])
  })

  it('alerts what reconciliation settles', async () => {
    const reader = new FakeRailStatusReader('INTER_EMPRESAS')
      .willReport('pix:paid', {
        outcome: 'PAID',
        endToEndId: null,
        settledAt: null,
      })
      .willReport('pix:failed', {
        outcome: 'FAILED',
        endToEndId: null,
        settledAt: null,
      })
    const deps = fullDeps({ railStatus: [reader] })
    for (const id of ['paid', 'failed']) {
      await deps.bills.save(bill({ id, entityId: 'pj', status: 'PROCESSING' }))
      await deps.payments.savePlan(
        TENANT,
        createPaymentPlan(id, [
          { mode: 'AUTOMATIC', rail: 'INTER_EMPRESAS', method: 'PIX' },
          { mode: 'ASSISTED', rail: 'ASSISTED', method: 'PIX' },
        ]),
      )
      await deps.payments.addAttempt(TENANT, {
        id: `att-${id}`,
        billId: id,
        stepIndex: 0,
        rail: 'INTER_EMPRESAS',
        mode: 'AUTOMATIC',
        method: 'PIX',
        amount: Money.of(12345),
        outcome: 'SUBMITTED',
        reason: null,
        externalId: `pix:${id}`,
        idempotencyKey: `${id}:0:PIX`,
        at: NOW,
      })
    }
    await makeReconcilePayments(deps)(TENANT)
    expect(
      deps.alerts.emitted.map(alert => [alert.type, alert.data.reason]),
    ).toEqual([
      ['PAYMENT_ASSISTED', 'RAIL_FAILED'],
      ['PAYMENT_PAID', undefined],
    ])
  })

  it('alerts an issued invoice', async () => {
    const deps = fullDeps()
    await deps.invoices.saveClient({
      id: 'client',
      tenantId: TENANT,
      entityId: 'pj',
      name: 'Client Co',
      taxId: null,
      country: 'BR',
    })
    await deps.invoices.save(invoice({ id: 'd', status: 'DRAFT' }))
    await makeIssueInvoice(deps)(TENANT, 'd')
    expect(deps.alerts.emitted).toEqual([
      expect.objectContaining({
        type: 'INVOICE_ISSUED',
        data: expect.objectContaining({ client: 'Client Co' }),
      }),
    ])
  })

  it('alerts a mailbox bill skipped for want of an amount', async () => {
    const bills = [
      { payee: 'Water Co', paymentCode: null, pixCode: PIX_NO_AMOUNT },
      { payee: null, paymentCode: null, pixCode: PIX_NO_AMOUNT },
      { payee: null, paymentCode: 'not a code' },
    ].map((bill, index) => ({
      externalId: `m${index}`,
      amountCents: null,
      dueDate: null,
      kind: null,
      ...bill,
    }))
    const deps = fullDeps({
      billSources: [{ source: 'GMAIL', fetch: async () => bills }],
    })
    const capture = makeCaptureSources(deps)
    const mailbox = await capture.completeMailbox(TENANT, 'PF', 'good-code')
    await capture.readMailbox(TENANT, mailbox.id)
    expect(
      deps.alerts.emitted.map(alert => [alert.type, alert.data.payee]),
    ).toEqual([
      ['BILL_NEEDS_AMOUNT', 'Water Co'],
      ['BILL_NEEDS_AMOUNT', 'Uma conta'],
    ])
    expect(deps.alerts.emitted[0]).toMatchObject({
      entityId: 'pf',
      data: { source: 'e-mail' },
      dedupeKey: 'BILL_NEEDS_AMOUNT:pf:GMAIL:m0',
    })
  })

  it('alerts an invoice the issuer settles on polling', async () => {
    const deps = fullDeps()
    for (const [id, status] of [
      ['ext-1', 'REJECTED'],
      ['ext-2', 'PROCESSING'],
    ] as const) {
      deps.issuer.issued.set(id, {
        externalId: id,
        number: null,
        status,
        pdfUrl: null,
        xmlUrl: null,
      })
      await deps.invoices.save(
        invoice({ id, status: 'PROCESSING', externalId: id }),
      )
    }
    await makeInvoiceLifecycle(deps).poll(TENANT)
    expect(deps.alerts.emitted).toEqual([
      expect.objectContaining({
        type: 'INVOICE_FAILED',
        invoiceId: 'ext-1',
        data: expect.objectContaining({ client: '' }),
      }),
    ])
  })

  it('alerts a card statement that was read', async () => {
    const deps = fullDeps()
    deps.llm.enqueueObject({
      card: 'Visa 1234',
      issuer: 'Card Bank',
      closing: '2026-10-01',
      due: '2026-10-25',
      currency: 'BRL',
      rate: 1,
      iofPercent: 0,
      paymentCode: '',
      lines: [],
    })
    await makeCardStatements(deps).read(TENANT, {
      entity: 'PJ',
      fileName: 'statement.pdf',
      mimeType: 'application/pdf',
      base64: base64('pdf'),
    })
    expect(deps.alerts.types()).toEqual(['CARD_BILL_CLOSED'])
  })
})
