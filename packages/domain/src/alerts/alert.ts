export const ALERT_TYPES = [
  'BILL_CAPTURED',
  'BILL_NEEDS_AMOUNT',
  'BILL_DUE_SOON',
  'PAYMENT_NEEDS_CONFIRMATION',
  'PAYMENT_PAID',
  'PAYMENT_MOVED_DOWN',
  'PAYMENT_ASSISTED',
  'APPROVAL_PENDING',
  'LOW_BALANCE',
  'INVOICE_ISSUED',
  'INVOICE_FAILED',
  'CARD_BILL_CLOSED',
] as const
export type AlertType = (typeof ALERT_TYPES)[number]

export type Alert = {
  readonly id: string
  readonly tenantId: string
  readonly type: AlertType
  readonly entityId: string | null
  readonly billId: string | null
  readonly invoiceId: string | null
  readonly title: string
  readonly body: string
  readonly data: Readonly<Record<string, string>>
  // Same key, same alert: a retried job or a second cron run never repeats it.
  readonly dedupeKey: string | null
  readonly createdAt: Date
  readonly readAt: Date | null
}

export function isAlertType(value: string): value is AlertType {
  return (ALERT_TYPES as readonly string[]).includes(value)
}

export function markAlertRead(alert: Alert, at: Date): Alert {
  if (alert.readAt) {
    return alert
  }
  return { ...alert, readAt: at }
}
