import { describe, expect, it } from 'vitest'
import { ALERT_TYPES, type Alert, Money } from '@cashdeck/domain'
import { NotFoundError } from '@/errors/errors'
import { type AlertInput } from '@/ports/alerts'
import {
  InMemoryAlertRepository,
  InMemoryDeviceTokenRepository,
  RecordingAlertEmitter,
} from '@/testing/alerts'
import { bill, invoice } from '@/testing/deps.test-helpers'
import { FakeNotifier } from '@/testing/providers'
import { InMemoryDocumentStore } from '@/testing/records'
import { InMemoryAuditLog } from '@/testing/repositories'
import { NOW, TENANT } from '@/testing/scenario.test-helpers'
import { FixedClock, SequentialIdGenerator } from '@/testing/system'
import {
  ALERT_TEXTS,
  assistedAlert,
  billAlert,
  cardClosedAlert,
  emitAlert,
  formatDay,
  formatMoney,
  invoiceAlert,
  manualMethod,
} from '@/use-cases/alert-events'
import {
  makeAlertEmitter,
  makeAlerts,
  mutedAlertTypes,
} from '@/use-cases/alerts'

class BrokenNotifier extends FakeNotifier {
  override async notify(): Promise<void> {
    throw new Error('push refused')
  }
}

class BrokenAlertStore extends InMemoryAlertRepository {
  override async add(): Promise<boolean> {
    throw new Error('database down')
  }
}

function setup(notifier = new FakeNotifier()) {
  const deps = {
    alertStore: new InMemoryAlertRepository(),
    devices: new InMemoryDeviceTokenRepository(),
    documents: new InMemoryDocumentStore(),
    notifier,
    audit: new InMemoryAuditLog(),
    clock: new FixedClock(NOW),
    ids: new SequentialIdGenerator('a'),
  }
  return {
    deps,
    emitter: makeAlertEmitter(deps),
    alerts: makeAlerts(deps),
  }
}

const due = billAlert(
  'BILL_DUE_SOON',
  bill({ id: 'b1', payee: 'Power company', dueDate: '2026-10-09' }),
)

describe('alert text', () => {
  it('formats money and days for pt-BR', () => {
    expect(formatMoney(Money.of(12345))).toBe('R$ 123,45')
    expect(formatMoney(Money.of(1000, 'USD'))).toBe('US$ 10,00')
    expect(formatDay('2026-10-09')).toBe('09/10')
  })

  it('writes a title and body for every type', () => {
    const data = {
      payee: 'Supplier',
      amount: 'R$ 1,00',
      dueDate: '09/10',
      rail: 'Asaas',
      method: 'PIX',
      shortfall: 'R$ 5,00',
      invoice: 'Nota 7',
      client: 'Client',
      card: 'Card Bank Visa',
      closing: '01/10',
      source: 'DDA',
    }
    for (const type of ALERT_TYPES) {
      const text = ALERT_TEXTS[type](data)
      expect(text.title.length).toBeGreaterThan(0)
      expect(text.body).not.toContain('undefined')
    }
  })

  it('tells how to pay a bill by hand', () => {
    const pix = bill({ id: 'p', pixCode: 'pix-payload' })
    const barcode = bill({ id: 'c' })
    const none = bill({ id: 'n', code: null, payee: null })
    expect([pix, barcode, none].map(manualMethod)).toEqual([
      'PIX',
      'BARCODE',
      'NONE',
    ])
    expect(assistedAlert(pix, 'NOT_CONFIGURED').data).toMatchObject({
      method: 'PIX',
      hasPixCode: 'true',
      reason: 'NOT_CONFIGURED',
    })
    expect(assistedAlert(none, null).data).toMatchObject({
      payee: 'Conta',
      hasPixCode: 'false',
      reason: '',
    })
  })

  it('alerts issued and rejected invoices only', () => {
    expect(
      invoiceAlert(invoice({ id: 'i', number: '7' }), 'Client'),
    ).toMatchObject({
      type: 'INVOICE_ISSUED',
      invoiceId: 'i',
      data: { invoice: 'Nota 7', client: 'Client' },
    })
    expect(
      invoiceAlert(invoice({ id: 'r', status: 'REJECTED' }), 'Client')?.data
        .invoice,
    ).toBe('Nota')
    expect(
      invoiceAlert(invoice({ id: 'p', status: 'PROCESSING' }), 'Client'),
    ).toBeNull()
  })

  it('names the closed card statement', () => {
    expect(
      cardClosedAlert(TENANT, {
        id: 's1',
        entityId: 'pj',
        card: 'Visa 1234',
        issuer: 'Card Bank',
        closing: '2026-10-01',
        due: '2026-10-25',
      }),
    ).toMatchObject({
      type: 'CARD_BILL_CLOSED',
      data: { card: 'Card Bank Visa 1234', closing: '01/10' },
    })
  })

  it('emits through the hook only when wired', async () => {
    const recorder = new RecordingAlertEmitter()
    await emitAlert(undefined, due)
    await emitAlert(recorder, null)
    await emitAlert(recorder, due)
    expect(recorder.types()).toEqual(['BILL_DUE_SOON'])
  })
})

describe('alert emitter', () => {
  it('stores the alert and pushes it with its references', async () => {
    const notifier = new FakeNotifier()
    const { deps, emitter } = setup(notifier)
    const alert = await emitter.emit(due)
    expect(alert).toMatchObject({
      id: 'a_1',
      title: 'Conta vence amanhã',
      body: 'Power company · R$ 123,45 ainda não foi paga.',
      billId: 'b1',
      invoiceId: null,
      readAt: null,
    })
    expect(notifier.sent).toEqual([
      expect.objectContaining({
        type: 'BILL_DUE_SOON',
        data: expect.objectContaining({
          alertId: 'a_1',
          billId: 'b1',
          entityId: 'pf',
        }),
      }),
    ])
    expect(notifier.sent[0]?.data).not.toHaveProperty('invoiceId')
    expect(deps.audit.events.at(-1)).toMatchObject({
      action: 'alert.push',
      result: 'SENT',
    })
    expect(await emitter.emit(due)).toBeNull()
    expect(notifier.sent).toHaveLength(1)
  })

  it('keeps a muted type in the inbox without a push', async () => {
    const notifier = new FakeNotifier()
    const { deps, emitter, alerts } = setup(notifier)
    await alerts.updateSettings(TENANT, { muted: { BILL_DUE_SOON: true } })
    const bare: AlertInput = {
      tenantId: TENANT,
      type: 'BILL_DUE_SOON',
      data: due.data,
    }
    expect(await emitter.emit(bare)).toMatchObject({
      entityId: null,
      billId: null,
      dedupeKey: null,
    })
    expect(notifier.sent).toHaveLength(0)
    expect(await deps.alertStore.unreadCount(TENANT)).toBe(1)
  })

  it('records a failed push and still keeps the alert', async () => {
    const { deps, emitter } = setup(new BrokenNotifier())
    expect(await emitter.emit(due)).not.toBeNull()
    expect(deps.audit.events.at(-1)).toMatchObject({
      result: 'FAILED',
      details: { reason: 'Error: push refused' },
    })
  })

  it('never throws at the caller', async () => {
    const deps = { ...setup().deps, alertStore: new BrokenAlertStore() }
    expect(await makeAlertEmitter(deps).emit(due)).toBeNull()
  })
})

describe('alert inbox', () => {
  async function seeded() {
    const context = setup()
    for (const id of ['b1', 'b2', 'b3']) {
      context.deps.clock.set(new Date(NOW.getTime() + Number(id[1]) * 1000))
      await context.emitter.emit(billAlert('BILL_CAPTURED', bill({ id })))
    }
    return context
  }

  it('lists newest first, pages and filters unread', async () => {
    const { alerts } = await seeded()
    const first = await alerts.list(TENANT, { limit: 2 })
    expect(first.items.map(alert => alert.billId)).toEqual(['b3', 'b2'])
    expect(first.nextCursor).toBe('2')
    const rest = await alerts.list(TENANT, { limit: 2, cursor: '2' })
    expect(rest).toMatchObject({ nextCursor: null })
    await alerts.markRead(TENANT, first.items[0]!.id)
    const unread = await alerts.list(TENANT, { limit: 10, unread: 'true' })
    expect(unread.items.map(alert => alert.billId)).toEqual(['b2', 'b1'])
    expect(await alerts.unreadCount(TENANT)).toEqual({ unread: 2 })
  })

  it('marks one read once and all read at the time it is asked', async () => {
    const { deps, alerts } = await seeded()
    const [newest] = (await alerts.list(TENANT, { limit: 1 })).items
    const read = await alerts.markRead(TENANT, newest!.id)
    deps.clock.set(new Date('2026-10-09T12:00:00Z'))
    expect((await alerts.markRead(TENANT, newest!.id)).readAt).toBe(read.readAt)
    expect(await alerts.markAllRead(TENANT)).toEqual({ updated: 2 })
    expect(await alerts.markAllRead(TENANT)).toEqual({ updated: 0 })
    expect(await alerts.markAllRead('other')).toEqual({ updated: 0 })
    await expect(alerts.markRead(TENANT, 'nope')).rejects.toThrow(NotFoundError)
  })

  it('mutes and unmutes types', async () => {
    const { deps, alerts } = setup()
    expect((await alerts.settings(TENANT)).types).toHaveLength(
      ALERT_TYPES.length,
    )
    await alerts.updateSettings(TENANT, {
      muted: { PAYMENT_PAID: true, BILL_CAPTURED: true },
    })
    const view = await alerts.updateSettings(TENANT, {
      muted: { BILL_CAPTURED: false },
    })
    expect(view.types.filter(type => type.muted)).toEqual([
      { type: 'PAYMENT_PAID', muted: true },
    ])
    expect(await mutedAlertTypes(deps.documents, TENANT)).toEqual([
      'PAYMENT_PAID',
    ])
  })

  it('registers, refreshes and removes device tokens', async () => {
    const { deps, alerts } = setup()
    const first = await alerts.registerDevice(TENANT, {
      token: 'device-1',
      platform: 'ANDROID',
    })
    expect(first).toEqual({
      token: 'device-1',
      platform: 'ANDROID',
      createdAt: NOW.toISOString(),
      lastSeenAt: NOW.toISOString(),
    })
    deps.clock.set(new Date('2026-10-09T12:00:00Z'))
    const again = await alerts.registerDevice(TENANT, {
      token: 'device-1',
      platform: 'ANDROID',
    })
    expect(again).toMatchObject({
      createdAt: NOW.toISOString(),
      lastSeenAt: '2026-10-09T12:00:00.000Z',
    })
    expect(await alerts.removeDevice('other', 'device-1')).toEqual({
      removed: false,
    })
    expect(await alerts.removeDevice(TENANT, 'device-1')).toEqual({
      removed: true,
    })
    expect(await deps.devices.list(TENANT)).toEqual([])
  })
})

describe('alert fakes', () => {
  it('records emitted alerts and repeats nothing with a key', async () => {
    const recorder = new RecordingAlertEmitter()
    const bare = { tenantId: TENANT, type: 'LOW_BALANCE' as const, data: {} }
    expect(await recorder.emit(bare)).toMatchObject({
      entityId: null,
      dedupeKey: null,
    })
    expect(await recorder.emit(bare)).not.toBeNull()
    expect(await recorder.emit(due)).toMatchObject({ billId: 'b1' })
    expect(await recorder.emit(due)).toBeNull()
    expect(recorder.types()).toEqual([
      'LOW_BALANCE',
      'LOW_BALANCE',
      'BILL_DUE_SOON',
    ])
  })

  it('keeps alerts without a key apart and tenants apart', async () => {
    const store = new InMemoryAlertRepository()
    const alert: Alert = {
      id: 'x',
      tenantId: TENANT,
      type: 'LOW_BALANCE',
      entityId: null,
      billId: null,
      invoiceId: null,
      title: 't',
      body: 'b',
      data: {},
      dedupeKey: null,
      createdAt: NOW,
      readAt: null,
    }
    expect(await store.add(alert)).toBe(true)
    expect(await store.add({ ...alert, id: 'y' })).toBe(true)
    expect(await store.add({ ...alert, id: 'z', tenantId: 'other' })).toBe(true)
    expect(
      (await store.list(TENANT, {}, { limit: 5 })).items.map(row => row.id),
    ).toEqual(['x', 'y'])
    expect(await store.findById('other', 'x')).toBeNull()
    expect(await store.unreadCount(TENANT)).toBe(2)
  })
})
