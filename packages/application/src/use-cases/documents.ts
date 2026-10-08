import { ValidationError } from '@cashdeck/domain'
import { money, type MoneyView } from '@/dtos/common'
import { type TransferView } from '@/dtos/finance'
import { type Deps } from '@/use-cases/deps'
import { makeGetTransfer } from '@/use-cases/finance'
import { makeReceipts } from '@/use-cases/receipts'
import { required } from '@/use-cases/shared'

export type RenderedFile = { fileName: string; bytes: Uint8Array }

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

const amountText = (value: MoneyView) =>
  `${value.currency} ${(value.cents / 100).toFixed(2)}`

const partyText = (party: TransferView['from']) =>
  `${party.holder} (${party.owner}), ${party.account}`

export function makeDocuments(deps: DocumentDeps) {
  const receipts = makeReceipts(deps)
  const getTransfer = makeGetTransfer(deps)

  // A bill marked paid by hand has no rail proof; the bill itself is the record.
  async function receiptPdf(
    tenantId: string,
    billId: string,
  ): Promise<RenderedFile> {
    const bill = required(await deps.bills.findById(tenantId, billId), 'Bill')
    if (bill.status !== 'PAID') {
      throw new ValidationError('The bill is not paid yet.')
    }
    const { proof } = await receipts.receipt(tenantId, billId)
    const bytes = deps.pdfs.render('Payment receipt', [
      ['Payee', bill.payee ?? bill.kind],
      ['Amount', amountText(proof?.amount ?? money(bill.amount))],
      ['Due date', bill.dueDate],
      ['Paid at', proof?.paidAt ?? (bill.paidAt as Date).toISOString()],
      ['Rail', proof?.rail ?? 'MANUAL'],
      ['Payer', proof?.payer ?? ''],
      ['Transaction', proof?.transactionId ?? ''],
    ])
    return { fileName: `receipt-${bill.id}.pdf`, bytes }
  }

  async function transferPdf(
    tenantId: string,
    id: string,
  ): Promise<RenderedFile> {
    const transfer = await getTransfer(tenantId, id)
    const bytes = deps.pdfs.render('Internal transfer', [
      ['Kind', transfer.kind],
      ['Amount', amountText(transfer.amount)],
      ['Date', transfer.at],
      ['Rail', transfer.rail],
      ['From', partyText(transfer.from)],
      ['To', partyText(transfer.to)],
      ['Reference', transfer.document ?? ''],
    ])
    return { fileName: `transfer-${transfer.id}.pdf`, bytes }
  }

  return { receiptPdf, transferPdf }
}
