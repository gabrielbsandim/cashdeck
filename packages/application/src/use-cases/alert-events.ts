import {
  type AlertType,
  type Bill,
  type LocalDate,
  type Money,
  type RailId,
  toLocalDate,
} from '@cashdeck/domain'
import {
  type AlertEmitter,
  type AlertInput,
  type DeviceLocale,
} from '@/ports/alerts'
import { type Invoice, type InvoiceStatus } from '@/ports/records'
import { type Clock } from '@/ports/system'

type AlertData = Record<string, string>
type AlertText = { title: string; body: string }

export const RAIL_NAMES: Record<RailId, string> = {
  MERCADO_PAGO_PAYOUTS: 'Mercado Pago',
  ASAAS: 'Asaas',
  INTER_EMPRESAS: 'Inter Empresas',
  C6_EMPRESAS: 'C6 Empresas',
  ASSISTED: 'pagamento assistido',
}

const MANUAL_HINT: Record<string, string> = {
  PIX: 'use o Pix copia e cola no app do banco.',
  BARCODE: 'use o código de barras no app do banco.',
  NONE: 'pague pelo app do banco e marque como paga.',
}

const MANUAL_HINT_EN: Record<string, string> = {
  PIX: 'use the Pix copy and paste in your bank app.',
  BARCODE: 'use the barcode in your bank app.',
  NONE: 'pay in your bank app and mark it as paid.',
}

const SOURCE_NAMES_EN: Record<string, string> = { GMAIL: 'email', DDA: 'DDA' }

const due = (d: AlertData) => `${d.payee} · ${d.amount}`

const invoiceEn = (d: AlertData) =>
  d.number ? `Invoice ${d.number}` : 'Invoice'

// The inbox keeps the pt-BR text; each push device gets its own locale.
export const ALERT_TEXTS: Record<AlertType, (d: AlertData) => AlertText> = {
  BILL_CAPTURED: d => ({
    title: 'Nova conta capturada',
    body: `${due(d)}, vence em ${d.dueDate}.`,
  }),
  BILL_NEEDS_AMOUNT: d => ({
    title: 'Conta sem valor',
    body: `${d.payee} chegou por ${d.source} sem valor; registre a conta no app.`,
  }),
  BILL_DUE_SOON: d => ({
    title: 'Conta vence amanhã',
    body: `${due(d)} ainda não foi paga.`,
  }),
  PAYMENT_NEEDS_CONFIRMATION: d => ({
    title: 'Confirme o pagamento',
    body: `${due(d)} precisa da sua confirmação antes de ser paga.`,
  }),
  PAYMENT_PAID: d => ({
    title: 'Conta paga',
    body: `${due(d)} foi paga.`,
  }),
  PAYMENT_MOVED_DOWN: d => ({
    title: 'Pagamento mudou de caminho',
    body: `${due(d)}: ${d.rail} falhou, a conta seguiu para o próximo passo.`,
  }),
  PAYMENT_ASSISTED: d => ({
    title: 'Pague manualmente',
    body: `${due(d)}: ${MANUAL_HINT[`${d.method}`]}`,
  }),
  APPROVAL_PENDING: d => ({
    title: 'Aprovação pendente no banco',
    body: `${due(d)} aguarda sua aprovação no internet banking.`,
  }),
  LOW_BALANCE: d => ({
    title: 'Saldo baixo na reserva',
    body: `Faltam ${d.shortfall} na reserva para as contas até ${d.dueDate}.`,
  }),
  INVOICE_ISSUED: d => ({
    title: 'Nota fiscal emitida',
    body: `${d.invoice} para ${d.client} · ${d.amount}.`,
  }),
  INVOICE_FAILED: d => ({
    title: 'Nota fiscal não emitida',
    body: `${d.invoice} para ${d.client} · ${d.amount} foi recusada.`,
  }),
  CARD_BILL_CLOSED: d => ({
    title: 'Fatura do cartão fechou',
    body: `${d.card}: fechou em ${d.closing}, vence em ${d.dueDate}.`,
  }),
  JOB_FAILED: d => ({
    title: 'Rotina automática falhou',
    body: `${d.job} não terminou: ${d.error}`,
  }),
  UNUSUAL_PURCHASE: d => ({
    title: 'Compra fora do padrão',
    body: `${d.merchant} · ${d.amount} em ${d.day}, cerca de ${d.times}x o habitual (${d.usual}).`,
  }),
  SUBSCRIPTION_CHANGED: d =>
    d.change === 'DUPLICATE'
      ? {
          title: 'Assinatura cobrada em dobro',
          body: `${d.name} foi cobrada ${d.count} vezes no mesmo mês (${d.amount} cada).`,
        }
      : {
          title: 'Assinatura ficou mais cara',
          body: `${d.name} passou de ${d.previous} para ${d.amount} (+${d.percent}%).`,
        },
  CARD_BILL_ABOVE_AVERAGE: d => ({
    title: 'Fatura acima da média',
    body: `${d.card}: ${d.amount}, ${d.percent}% acima da média de ${d.average}; vence em ${d.dueDate}.`,
  }),
  BANK_SYNC_STALE: d => ({
    title: 'Banco sem sincronizar',
    body: d.hours
      ? `${d.institution} não sincroniza há ${d.hours} h; reconecte em Ajustes.`
      : `${d.institution} precisa de atenção para voltar a sincronizar.`,
  }),
  INVOICE_NOT_ISSUED: d => ({
    title: 'Nota não emitida',
    body: `A nota de ${d.client} · ${d.amount} costuma sair até ${d.day} e ainda não foi emitida.`,
  }),
}

export const ALERT_TEXTS_EN: Record<AlertType, (d: AlertData) => AlertText> = {
  BILL_CAPTURED: d => ({
    title: 'New bill captured',
    body: `${due(d)}, due ${d.dueDate}.`,
  }),
  BILL_NEEDS_AMOUNT: d => ({
    title: 'Bill without an amount',
    body: `${d.payee} arrived by ${SOURCE_NAMES_EN[`${d.sourceKind}`] ?? d.source} without an amount; add the bill in the app.`,
  }),
  BILL_DUE_SOON: d => ({
    title: 'Bill due tomorrow',
    body: `${due(d)} is still unpaid.`,
  }),
  PAYMENT_NEEDS_CONFIRMATION: d => ({
    title: 'Confirm the payment',
    body: `${due(d)} needs your confirmation before it is paid.`,
  }),
  PAYMENT_PAID: d => ({
    title: 'Bill paid',
    body: `${due(d)} was paid.`,
  }),
  PAYMENT_MOVED_DOWN: d => ({
    title: 'Payment changed route',
    body: `${due(d)}: ${d.rail} failed, the bill moved to the next step.`,
  }),
  PAYMENT_ASSISTED: d => ({
    title: 'Pay manually',
    body: `${due(d)}: ${MANUAL_HINT_EN[`${d.method}`]}`,
  }),
  APPROVAL_PENDING: d => ({
    title: 'Approval pending in the bank',
    body: `${due(d)} awaits your approval in internet banking.`,
  }),
  LOW_BALANCE: d => ({
    title: 'Low reserve balance',
    body: `${d.shortfall} short in the reserve for the bills due by ${d.dueDate}.`,
  }),
  INVOICE_ISSUED: d => ({
    title: 'Invoice issued',
    body: `${invoiceEn(d)} to ${d.client} · ${d.amount}.`,
  }),
  INVOICE_FAILED: d => ({
    title: 'Invoice not issued',
    body: `${invoiceEn(d)} to ${d.client} · ${d.amount} was rejected.`,
  }),
  CARD_BILL_CLOSED: d => ({
    title: 'Card bill closed',
    body: `${d.card}: closed on ${d.closing}, due ${d.dueDate}.`,
  }),
  JOB_FAILED: d => ({
    title: 'Scheduled job failed',
    body: `${d.job} did not finish: ${d.error}`,
  }),
  UNUSUAL_PURCHASE: d => ({
    title: 'Unusual purchase',
    body: `${d.merchant} · ${d.amount} on ${d.day}, about ${d.times}x the usual (${d.usual}).`,
  }),
  SUBSCRIPTION_CHANGED: d =>
    d.change === 'DUPLICATE'
      ? {
          title: 'Subscription charged twice',
          body: `${d.name} was charged ${d.count} times in the same month (${d.amount} each).`,
        }
      : {
          title: 'Subscription got pricier',
          body: `${d.name} went from ${d.previous} to ${d.amount} (+${d.percent}%).`,
        },
  CARD_BILL_ABOVE_AVERAGE: d => ({
    title: 'Card bill above average',
    body: `${d.card}: ${d.amount}, ${d.percent}% above the ${d.average} average; due ${d.dueDate}.`,
  }),
  BANK_SYNC_STALE: d => ({
    title: 'Bank not syncing',
    body: d.hours
      ? `${d.institution} has not synced for ${d.hours} h; reconnect it in Settings.`
      : `${d.institution} needs attention to sync again.`,
  }),
  INVOICE_NOT_ISSUED: d => ({
    title: 'Invoice not issued',
    body: `The invoice to ${d.client} · ${d.amount} usually goes out by ${d.day} and was not issued yet.`,
  }),
}

const TEXTS_BY_LOCALE: Record<
  DeviceLocale,
  Record<AlertType, (d: AlertData) => AlertText>
> = { pt: ALERT_TEXTS, en: ALERT_TEXTS_EN }

export function alertText(
  type: AlertType,
  data: AlertData,
  locale: DeviceLocale,
): AlertText {
  return TEXTS_BY_LOCALE[locale][type](data)
}

export function formatMoney(money: Money): string {
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: money.currency,
  }).format(money.cents / 100)
}

export function formatDay(day: LocalDate): string {
  const [, month, date] = day.split('-')
  return `${date}/${month}`
}

export function manualMethod(bill: Bill): string {
  if (bill.pixCode) {
    return 'PIX'
  }
  return bill.code ? 'BARCODE' : 'NONE'
}

export function billAlert(
  type: AlertType,
  bill: Bill,
  extra: AlertData = {},
  dedupeKey = `${type}:${bill.id}`,
): AlertInput {
  return {
    tenantId: bill.tenantId,
    type,
    entityId: bill.entityId,
    billId: bill.id,
    data: {
      payee: bill.payee ?? 'Conta',
      amount: formatMoney(bill.amount),
      dueDate: formatDay(bill.dueDate),
      ...extra,
    },
    dedupeKey,
  }
}

export function assistedAlert(bill: Bill, reason: string | null): AlertInput {
  return billAlert('PAYMENT_ASSISTED', bill, {
    method: manualMethod(bill),
    hasPixCode: String(bill.pixCode !== null),
    reason: reason ?? '',
  })
}

const INVOICE_ALERTS: Partial<Record<InvoiceStatus, AlertType>> = {
  ISSUED: 'INVOICE_ISSUED',
  REJECTED: 'INVOICE_FAILED',
}

export function invoiceAlert(
  invoice: Invoice,
  clientName: string,
): AlertInput | null {
  const type = INVOICE_ALERTS[invoice.status]
  if (!type) {
    return null
  }
  return {
    tenantId: invoice.tenantId,
    type,
    entityId: invoice.entityId,
    invoiceId: invoice.id,
    data: {
      invoice: invoice.number ? `Nota ${invoice.number}` : 'Nota',
      number: invoice.number ?? '',
      client: clientName,
      amount: formatMoney(invoice.amount),
    },
    dedupeKey: `${type}:${invoice.id}`,
  }
}

const SOURCE_NAMES = { GMAIL: 'e-mail', DDA: 'DDA' }

// The capture was skipped, so there is no bill to point at yet.
export function amountRequiredAlert(
  tenantId: string,
  entityId: string,
  source: keyof typeof SOURCE_NAMES,
  found: { externalId: string; payee: string | null },
): AlertInput {
  return {
    tenantId,
    type: 'BILL_NEEDS_AMOUNT',
    entityId,
    data: {
      payee: found.payee ?? 'Uma conta',
      source: SOURCE_NAMES[source],
      sourceKind: source,
    },
    dedupeKey: `BILL_NEEDS_AMOUNT:${entityId}:${source}:${found.externalId}`,
  }
}

export function cardClosedAlert(
  tenantId: string,
  statement: {
    id: string
    entityId: string
    card: string
    issuer: string
    closing: LocalDate
    due: LocalDate
  },
): AlertInput {
  return {
    tenantId,
    type: 'CARD_BILL_CLOSED',
    entityId: statement.entityId,
    data: {
      statementId: statement.id,
      card: `${statement.issuer} ${statement.card}`,
      closing: formatDay(statement.closing),
      dueDate: formatDay(statement.due),
    },
    dedupeKey: `CARD_BILL_CLOSED:${statement.entityId}:${statement.issuer}:${statement.card}:${statement.closing}`,
  }
}

const ERROR_SUMMARY_LENGTH = 140

// One alert per job and day: a cron that keeps failing does not flood the inbox.
export function jobFailedAlert(
  tenantId: string,
  job: string,
  error: unknown,
  day: LocalDate,
): AlertInput {
  const summary =
    error instanceof Error ? `${error.name}: ${error.message}` : 'Unknown error'
  return {
    tenantId,
    type: 'JOB_FAILED',
    data: { job, error: summary.slice(0, ERROR_SUMMARY_LENGTH) },
    dedupeKey: `JOB_FAILED:${job}:${day}`,
  }
}

export function makeReportJobFailure(deps: {
  alerts?: AlertEmitter
  clock: Clock
}) {
  return async function reportJobFailure(
    tenantId: string,
    job: string,
    error: unknown,
  ): Promise<void> {
    const day = toLocalDate(deps.clock.now())
    await emitAlert(deps.alerts, jobFailedAlert(tenantId, job, error, day))
  }
}

// The hook other use cases call; without an emitter wired it does nothing.
export async function emitAlert(
  alerts: AlertEmitter | undefined,
  input: AlertInput | null,
): Promise<void> {
  if (!alerts || !input) {
    return
  }
  await alerts.emit(input)
}
