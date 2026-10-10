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
    expect(deps.webhookEvents.find(TENANT, 'asaas', 'e1')).toEqual({
      eventId: 'e1',
      type: 'TRANSFER_DONE',
      subjectId: null,
      receivedAt: NOW,
      outcome: null,
      reason: null,
      processedAt: null,
    })
    await expect(receive(TENANT, delivery('forged'))).rejects.toThrow(
      UnauthorizedError,
    )
    await expect(
      receive(TENANT, { ...delivery(), provider: 'pluggy' }),
    ).rejects.toThrow(NotFoundError)
  })

  it('stores the type and what each event names', async () => {
    const events: WebhookEvent[] = [
      {
        eventId: 'p',
        type: 'T',
        kind: 'PAYMENT',
        rail: 'ASAAS',
        reference: 'r',
      },
      {
        eventId: 'o',
        type: 'item/updated',
        kind: 'OPEN_FINANCE_ITEM',
        itemId: 'i',
      },
      { eventId: 'n', type: 'T', kind: 'INVOICE', externalId: 'x' },
      { eventId: 'g', type: 'item/error', kind: 'IGNORED', subject: 'i' },
    ]
    const deps = fullDeps({
      webhooks: [new FakeWebhookReader('asaas', events)],
    })
    await makeReceiveWebhook(deps)(TENANT, delivery())
    expect(
      events.map(e => deps.webhookEvents.find(TENANT, 'asaas', e.eventId)),
    ).toEqual([
      expect.objectContaining({ type: 'T', subjectId: 'r' }),
      expect.objectContaining({ type: 'item/updated', subjectId: 'i' }),
      expect.objectContaining({ type: 'T', subjectId: 'x' }),
      expect.objectContaining({ type: 'item/error', subjectId: 'i' }),
    ])
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
    const outcomes = await process(TENANT, 'pluggy', [
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

  it('records the outcome of each event it handled', async () => {
    const down = new FakeOpenFinanceProvider()
    down.listAccounts = async () => {
      throw new Error('down')
    }
    const deps = fullDeps({ openFinance: down })
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
    const events: WebhookEvent[] = [
      {
        eventId: 'o1',
        type: 'item/updated',
        kind: 'OPEN_FINANCE_ITEM',
        itemId: 'item-1',
      },
      { eventId: 'x1', type: 'item/error', kind: 'IGNORED', subject: 'item-1' },
    ]
    for (const event of events) {
      await deps.webhookEvents.remember(
        TENANT,
        'pluggy',
        { eventId: event.eventId, type: event.type, subjectId: 'item-1' },
        NOW,
      )
    }
    await makeProcessWebhookEvents(deps)(TENANT, 'pluggy', events)
    expect(deps.webhookEvents.find(TENANT, 'pluggy', 'o1')).toMatchObject({
      outcome: 'FAILED',
      reason: 'Error: down',
      processedAt: NOW,
    })
    expect(deps.webhookEvents.find(TENANT, 'pluggy', 'x1')).toMatchObject({
      outcome: 'IGNORED',
      reason: null,
    })
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
    const outcomes = await makeProcessWebhookEvents(deps)(TENANT, 'asaas', [
      {
        eventId: 'p1',
        type: 'T',
        kind: 'PAYMENT',
        rail: 'ASAAS',
        reference: 'tr-1',
      },
      { eventId: 'n1', type: 'T', kind: 'INVOICE', externalId: 'nf-1' },
    ])
    expect(deps.webhookEvents.find(TENANT, 'asaas', 'p1')).toBeNull()
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
