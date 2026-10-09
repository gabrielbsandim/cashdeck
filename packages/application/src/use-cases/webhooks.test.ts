import { describe, expect, it } from 'vitest'
import { Money, type PaymentAttempt } from '@cashdeck/domain'
import { NotFoundError, UnauthorizedError } from '@/errors/errors'
import { type WebhookDelivery, type WebhookEvent } from '@/ports/webhooks'
import { bill, fullDeps, invoice } from '@/testing/deps.test-helpers'
import { FakeOpenFinanceProvider } from '@/testing/providers'
import { FakeRailStatusReader } from '@/testing/rail-status'
import { NOW, TENANT } from '@/testing/scenario.test-helpers'
import { FakeWebhookReader } from '@/testing/webhooks'
import {
  makeProcessWebhookEvents,
  makeReceiveWebhook,
} from '@/use-cases/webhooks'

const delivery = (token = 'test-token'): WebhookDelivery => ({
  provider: 'asaas',
  headers: { 'x-test-token': token },
  query: {},
  rawBody: '{}',
})

const attempt: PaymentAttempt = {
  id: 'att-1',
  billId: 'paid',
  stepIndex: 0,
  rail: 'ASAAS',
  mode: 'AUTOMATIC',
  method: 'PIX',
  amount: Money.of(12345),
  outcome: 'SUBMITTED',
  reason: null,
  externalId: 'transfer:tr-1',
  idempotencyKey: 'paid:0:PIX',
  at: NOW,
}

describe('receiveWebhook', () => {
  it('authenticates and drops replayed events', async () => {
    const events: WebhookEvent[] = [
      { eventId: 'e1', type: 'TRANSFER_DONE', kind: 'IGNORED' },
      { eventId: 'e1', type: 'TRANSFER_DONE', kind: 'IGNORED' },
      { eventId: 'e2', type: 'TRANSFER_DONE', kind: 'IGNORED' },
    ]
    const deps = fullDeps({
      webhooks: [new FakeWebhookReader('asaas', events)],
    })
    const receive = makeReceiveWebhook(deps)
    expect(await receive(TENANT, delivery())).toEqual({
      events: [events[0], events[2]],
      duplicates: 1,
    })
    expect((await receive(TENANT, delivery())).duplicates).toBe(3)
    await expect(receive(TENANT, delivery('forged'))).rejects.toThrow(
      UnauthorizedError,
    )
    await expect(
      receive(TENANT, { ...delivery(), provider: 'pluggy' }),
    ).rejects.toThrow(NotFoundError)
  })
})

describe('processWebhookEvents', () => {
  it('reconciles, syncs and refreshes what each event names', async () => {
    const asaas = new FakeRailStatusReader('ASAAS').willReport(
      'transfer:tr-1',
      {
        outcome: 'PAID',
        externalId: 'transfer:tr-1',
        endToEndId: 'E2E',
        settledAt: null,
      },
    )
    const deps = fullDeps({
      railStatus: [asaas],
      openFinance: new FakeOpenFinanceProvider(),
    })
    await deps.bills.save(bill({ id: 'paid', status: 'PROCESSING' }))
    await deps.payments.addAttempt(TENANT, attempt)
    await deps.connections.save({
      id: 'conn',
      tenantId: TENANT,
      entityId: 'pf',
      institutionId: 'inst',
      provider: 'pluggy',
      itemId: 'item-1',
      status: 'UPDATED',
      lastSyncAt: null,
    })
    deps.issuer.issued.set('nf-1', {
      externalId: 'nf-1',
      number: '9',
      status: 'ISSUED',
      pdfUrl: null,
      xmlUrl: null,
    })
    await deps.invoices.save(
      invoice({ id: 'inv', status: 'PROCESSING', externalId: 'nf-1' }),
    )
    const process = makeProcessWebhookEvents(deps)
    const outcomes = await process(TENANT, [
      {
        eventId: 'p1',
        type: 'TRANSFER_DONE',
        kind: 'PAYMENT',
        rail: 'ASAAS',
        reference: 'tr-1',
      },
      {
        eventId: 'p2',
        type: 'TRANSFER_DONE',
        kind: 'PAYMENT',
        rail: 'ASAAS',
        reference: 'tr-9',
      },
      {
        eventId: 'o1',
        type: 'item/updated',
        kind: 'OPEN_FINANCE_ITEM',
        itemId: 'item-1',
      },
      {
        eventId: 'o2',
        type: 'item/updated',
        kind: 'OPEN_FINANCE_ITEM',
        itemId: 'item-9',
      },
      {
        eventId: 'n1',
        type: 'nfse.issued',
        kind: 'INVOICE',
        externalId: 'nf-1',
      },
      {
        eventId: 'n2',
        type: 'nfse.issued',
        kind: 'INVOICE',
        externalId: 'nf-9',
      },
      { eventId: 'x1', type: 'PAYMENT_CREATED', kind: 'IGNORED' },
    ])
    expect(outcomes.map(o => [o.eventId, o.outcome])).toEqual([
      ['p1', 'DONE'],
      ['p2', 'UNKNOWN'],
      ['o1', 'DONE'],
      ['o2', 'UNKNOWN'],
      ['n1', 'DONE'],
      ['n2', 'UNKNOWN'],
      ['x1', 'IGNORED'],
    ])
    expect((await deps.bills.findById(TENANT, 'paid'))?.status).toBe('PAID')
    expect(
      (await deps.connections.findById(TENANT, 'conn'))?.lastSyncAt,
    ).toEqual(NOW)
    expect((await deps.invoices.findById(TENANT, 'inv'))?.status).toBe('ISSUED')
  })

  it('reports a failing event and moves on', async () => {
    const broken = new FakeRailStatusReader('ASAAS')
    broken.status = async () => {
      throw new Error('timeout')
    }
    const deps = fullDeps({ railStatus: [broken] })
    await deps.bills.save(bill({ id: 'paid', status: 'PROCESSING' }))
    await deps.payments.addAttempt(TENANT, attempt)
    deps.issuer.get = async () => {
      throw new Error('down')
    }
    await deps.invoices.save(invoice({ id: 'inv', externalId: 'nf-1' }))
    const outcomes = await makeProcessWebhookEvents(deps)(TENANT, [
      {
        eventId: 'p1',
        type: 'T',
        kind: 'PAYMENT',
        rail: 'ASAAS',
        reference: 'tr-1',
      },
      { eventId: 'n1', type: 'T', kind: 'INVOICE', externalId: 'nf-1' },
    ])
    expect(outcomes).toEqual([
      {
        eventId: 'p1',
        kind: 'PAYMENT',
        outcome: 'FAILED',
        reason: 'Error: timeout',
      },
      {
        eventId: 'n1',
        kind: 'INVOICE',
        outcome: 'FAILED',
        reason: 'Error: down',
      },
    ])
  })
})
