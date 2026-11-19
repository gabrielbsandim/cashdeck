import { type Bill } from '@cashdeck/domain'
import { NotFoundError } from '@/errors/errors'
import { type ChatRecipient } from '@/ports/chat'
import { type RecipientDirectory } from '@/ports/providers'
import { type BillRepository } from '@/ports/repositories'
import { checkedRecipient } from '@/use-cases/pix-transfers'

// Only a Pix QR bill is always paid through its code; a boleto's Pix may fall
// back to the barcode, whose beneficiary the Pix directory does not name.
// The same payload the Pix rails send: a stored pixCode, else the bill code.
function pixPayloadOf(bill: Bill): string | null {
  const extra = bill.pixCode?.trim()
  if (extra) {
    return extra
  }
  return bill.code
}

export function makeBillRecipient(deps: {
  bills: BillRepository
  recipientDirectory: RecipientDirectory
}) {
  return async function billRecipient(
    tenantId: string,
    billId: string,
  ): Promise<ChatRecipient | null> {
    const bill = await deps.bills.findById(tenantId, billId)
    if (!bill) {
      throw new NotFoundError('Bill')
    }
    if (bill.kind !== 'PIX_QR') {
      return null
    }
    const payload = pixPayloadOf(bill)
    if (!payload) {
      return null
    }
    return checkedRecipient(
      () =>
        deps.recipientDirectory.receiverOfCode(payload, {
          tenantId,
          entityId: bill.entityId,
        }),
      bill.payee ?? 'Unknown',
    )
  }
}
