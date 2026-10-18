import {
  addDays,
  createTransaction,
  Money,
  toLocalDate,
  type Transaction,
  ValidationError,
} from '@cashdeck/domain'
import {
  type CaptureNotificationsInput,
  type CapturedNotificationsView,
  notificationReadingSchema,
} from '@/dtos/card-notifications'
import { type LlmToolParameter } from '@/ports/llm-provider'
import { cardChargeCapturedAlert } from '@/use-cases/alert-events'
import { type Deps } from '@/use-cases/deps'
import { required } from '@/use-cases/shared'

// Notifications come from another app's own wording, so they are kept apart
// from any provider's ids.
export const NOTIFICATION_ID_PREFIX = 'notification:'

// Two phones on the same card notify one charge seconds apart, so another
// phone's preview of the same amount this close is that charge again.
const OTHER_PHONE_WINDOW_MS = 10 * 60 * 1000

// Older previews carry no time, and NaN keeps them out of every comparison.
const postedAt = (tx: Transaction) => tx.bookedAt?.getTime() ?? Number.NaN

type Notification = CaptureNotificationsInput['notifications'][number]

const READING_SCHEMA: LlmToolParameter = {
  type: 'object',
  properties: {
    items: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          ref: { type: 'string', description: 'The ref given, like n1' },
          kind: { type: 'string', enum: ['PURCHASE', 'REFUND', 'OTHER'] },
          amount: {
            type: 'number',
            description: 'Total amount in BRL, positive; 0 when OTHER',
          },
          merchant: { type: 'string', description: 'Merchant, or empty' },
          installments: {
            type: 'number',
            description: 'Number of installments, 1 when paid at once',
          },
        },
        required: ['ref', 'kind', 'amount', 'merchant', 'installments'],
      },
    },
  },
  required: ['items'],
}

const SYSTEM = [
  'You read phone notifications from a credit card app.',
  'PURCHASE is an approved charge, REFUND money given back to the card,',
  'OTHER anything else: a declined or pending charge, a bill reminder, an ad.',
  'Return one item per notification and only what its text says.',
].join(' ')

const sanitize = (value: string) => value.replace(/\s+/g, ' ').trim()

type NotificationDeps = Pick<
  Deps,
  'accounts' | 'transactions' | 'llm' | 'ids' | 'alerts'
>

export function makeCardNotifications(deps: NotificationDeps) {
  async function storedAround(
    tenantId: string,
    accountId: string,
    notifications: readonly Notification[],
  ) {
    const earliest = notifications
      .map(item => toLocalDate(new Date(item.postedAt)))
      .sort()[0] as string
    return deps.transactions.all(tenantId, {
      accountIds: [accountId],
      from: addDays(earliest, -1),
    })
  }

  function notifiedByOtherPhone(
    stored: readonly Transaction[],
    source: string,
  ) {
    const others = stored.filter(
      tx =>
        tx.externalId?.startsWith(NOTIFICATION_ID_PREFIX) &&
        !tx.externalId.startsWith(source),
    )
    return (charge: Transaction) =>
      others.some(
        tx =>
          tx.amount.cents === charge.amount.cents &&
          Math.abs(postedAt(tx) - postedAt(charge)) <= OTHER_PHONE_WINDOW_MS,
      )
  }

  async function read(notifications: readonly Notification[]) {
    const lines = notifications.map(
      (item, index) =>
        `n${index + 1}|${sanitize(item.title)}|${sanitize(item.text)}`,
    )
    const reply = await deps.llm.chat({
      system: SYSTEM,
      messages: [
        {
          role: 'user',
          content: `Notifications (ref|title|text):\n${lines.join('\n')}`,
        },
      ],
      tools: [],
      maxInputTokens: 20_000,
      maxOutputTokens: 4_000,
      temperature: 0,
      responseSchema: READING_SCHEMA,
    })
    const parsed = notificationReadingSchema.safeParse(reply.object)
    return parsed.success ? parsed.data.items : []
  }

  return async function capture(
    tenantId: string,
    input: CaptureNotificationsInput,
    deviceId: string,
  ): Promise<CapturedNotificationsView> {
    const account = required(
      await deps.accounts.findById(tenantId, input.accountId),
      'Account',
    )
    if (account.type !== 'CREDIT_CARD') {
      throw new ValidationError('Notifications go to a credit card account.')
    }
    const source = `${NOTIFICATION_ID_PREFIX}${deviceId.slice(0, 8)}:`
    const stored = await storedAround(tenantId, account.id, input.notifications)
    const known = new Set(stored.map(tx => tx.externalId))
    const fresh = input.notifications.filter(
      item => !known.has(`${source}${item.id}`),
    )
    const items = fresh.length > 0 ? await read(fresh) : []
    const answered = new Set<Notification>()
    const candidates = items.flatMap(item => {
      const notification = fresh[Number(item.ref.slice(1)) - 1]
      // A charge in installments lands on the card one installment at a time.
      const cents = Math.round((item.amount * 100) / item.installments)
      if (!notification || answered.has(notification)) {
        return []
      }
      answered.add(notification)
      if (item.kind === 'OTHER' || cents === 0) {
        return []
      }
      const bookedOn = toLocalDate(new Date(notification.postedAt))
      const merchant = sanitize(item.merchant)
      return [
        createTransaction({
          id: deps.ids.next(),
          tenantId,
          accountId: account.id,
          amount: Money.of(item.kind === 'REFUND' ? cents : -cents),
          bookedOn,
          bookedAt: new Date(notification.postedAt),
          description:
            merchant || sanitize(notification.title) || notification.app,
          externalId: `${source}${notification.id}`,
          merchant: merchant || null,
          installment:
            item.installments > 1
              ? { number: 1, count: item.installments, purchaseOn: bookedOn }
              : null,
          provisional: true,
        }),
      ]
    })
    // Read again: the other phone's request may have saved while the model read.
    const repeated = notifiedByOtherPhone(
      await storedAround(tenantId, account.id, input.notifications),
      source,
    )
    const charges = candidates.filter(charge => !repeated(charge))
    const added = await deps.transactions.saveNew(charges)
    for (const charge of charges) {
      await deps.alerts.emit(cardChargeCapturedAlert(tenantId, account, charge))
    }
    return { received: input.notifications.length, added }
  }
}
