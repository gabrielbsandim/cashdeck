import {
  type AlertType,
  type Bill,
  type LocalDate,
  type Money,
  type RailId,
} from '@cashdeck/domain'
import { type AlertEmitter, type AlertInput } from '@/ports/alerts'
import { type Invoice, type InvoiceStatus } from '@/ports/records'

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

const due = (d: AlertData) => `${d.payee} · ${d.amount}`

// Push and inbox text, in pt-BR: the server speaks the default locale.
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
    body: `Faltam ${d.shortfall} na reserva para as contas de ${d.dueDate}.`,
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
    data: { payee: found.payee ?? 'Uma conta', source: SOURCE_NAMES[source] },
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
