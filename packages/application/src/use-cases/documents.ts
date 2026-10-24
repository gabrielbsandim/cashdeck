import { type BillKind, ValidationError } from '@cashdeck/domain'
import { money, type MoneyView } from '@/dtos/common'
import { type TransferView } from '@/dtos/finance'
import { type PdfRow } from '@/ports/services'
import { type TransferKind } from '@/ports/records'
import { type Deps } from '@/use-cases/deps'
import { makeGetTransfer } from '@/use-cases/finance'
import { makeReceipts } from '@/use-cases/receipts'
import { required } from '@/use-cases/shared'

export type RenderedFile = { fileName: string; bytes: Uint8Array }

// The words a receipt prints, in the reader's language.
export type ReceiptCopy = {
  readonly locale: string
  readonly billKind: Readonly<Record<BillKind, string>>
  readonly receipt: {
    readonly payment: string
    readonly transfer: string
    readonly paidOn: string
    readonly madeOn: string
    readonly to: string
    readonly from: string
    readonly details: string
    readonly name: string
    readonly key: string
    readonly code: string
    readonly kind: string
    readonly dueDate: string
    readonly paidBy: string
    readonly manual: string
    readonly transaction: string
    readonly account: string
    readonly reference: string
    readonly footer: string
    readonly transferKind: Readonly<Record<TransferKind, string>>
  }
}

type DocumentDeps = Pick<
  Deps,
  | 'bills'
  | 'payments'
  | 'entities'
  | 'attachments'
  | 'accounts'
  | 'transfers'
  | 'pdfs'
  | 'clock'
  | 'ids'
>

// Receipts read in Brazil, whatever the server's clock.
const TIME_ZONE = 'America/Sao_Paulo'

const amountText = (copy: ReceiptCopy, value: MoneyView) =>
  new Intl.NumberFormat(copy.locale, {
    style: 'currency',
    currency: value.currency,
  }).format(value.cents / 100)

const momentText = (copy: ReceiptCopy, at: Date) =>
  new Intl.DateTimeFormat(copy.locale, {
    timeZone: TIME_ZONE,
    dateStyle: 'short',
    timeStyle: 'short',
  }).format(at)

const dayText = (copy: ReceiptCopy, day: string) =>
  new Intl.DateTimeFormat(copy.locale, {
    timeZone: 'UTC',
    dateStyle: 'short',
  }).format(new Date(`${day}T12:00:00Z`))

// ASAAS reads Asaas and INTER_EMPRESAS reads Inter Empresas.
const railName = (rail: string) =>
  rail
    .toLowerCase()
    .split('_')
    .map(word => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ')

const filled = (rows: readonly PdfRow[]) => rows.filter(([, value]) => value)

export function makeDocuments(deps: DocumentDeps) {
  const receipts = makeReceipts(deps)
  const getTransfer = makeGetTransfer(deps)

  const footerOf = (copy: ReceiptCopy) =>
    `${copy.receipt.footer} ${momentText(copy, deps.clock.now())}`

  async function receiptPdf(
    tenantId: string,
    billId: string,
    copy: ReceiptCopy,
  ): Promise<RenderedFile> {
    const bill = required(await deps.bills.findById(tenantId, billId), 'Bill')
    if (bill.status !== 'PAID') {
      throw new ValidationError('The bill is not paid yet.')
    }
    const { proof } = await receipts.receipt(tenantId, billId)
    const words = copy.receipt
    const paidAt = new Date(proof?.paidAt ?? (bill.paidAt as Date))
    const bytes = deps.pdfs.render({
      title: words.payment,
      amount: amountText(copy, proof?.amount ?? money(bill.amount)),
      caption: `${words.paidOn} ${momentText(copy, paidAt)}`,
      sections: [
        {
          heading: words.to,
          rows: filled([
            [words.name, bill.payee ?? ''],
            [
              bill.kind === 'PIX_KEY' ? words.key : words.code,
              bill.kind === 'PIX_QR' ? '' : (bill.code ?? ''),
            ],
          ]),
        },
        {
          heading: words.from,
          rows: filled([
            [words.name, proof?.payer ?? ''],
            [words.paidBy, proof ? railName(proof.rail) : words.manual],
          ]),
        },
        {
          heading: words.details,
          rows: filled([
            [words.kind, copy.billKind[bill.kind]],
            [words.dueDate, dayText(copy, bill.dueDate)],
            [
              words.transaction,
              (proof?.transactionId ?? '').replace(/^\w+:/, ''),
            ],
          ]),
        },
      ],
      footer: footerOf(copy),
    })
    return { fileName: `receipt-${bill.id}.pdf`, bytes }
  }

  const partyRows = (copy: ReceiptCopy, party: TransferView['from']) => [
    [copy.receipt.name, party.holder] as const,
    [copy.receipt.account, party.account] as const,
  ]

  async function transferPdf(
    tenantId: string,
    id: string,
    copy: ReceiptCopy,
  ): Promise<RenderedFile> {
    const transfer = await getTransfer(tenantId, id)
    const words = copy.receipt
    const bytes = deps.pdfs.render({
      title: words.transfer,
      amount: amountText(copy, transfer.amount),
      caption: `${words.madeOn} ${momentText(copy, new Date(transfer.at))}`,
      sections: [
        { heading: words.from, rows: partyRows(copy, transfer.from) },
        { heading: words.to, rows: partyRows(copy, transfer.to) },
        {
          heading: words.details,
          rows: filled([
            [words.kind, words.transferKind[transfer.kind]],
            [words.paidBy, transfer.rail],
            [words.reference, transfer.document ?? ''],
          ]),
        },
      ],
      footer: footerOf(copy),
    })
    return { fileName: `transfer-${transfer.id}.pdf`, bytes }
  }

  return { receiptPdf, transferPdf }
}
