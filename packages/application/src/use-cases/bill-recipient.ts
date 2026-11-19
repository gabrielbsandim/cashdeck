import { NotFoundError } from '@/errors/errors'
import { type ChatRecipient } from '@/ports/chat'
import { type RecipientDirectory } from '@/ports/providers'
import { type BillRepository } from '@/ports/repositories'
import { checkedRecipient } from '@/use-cases/pix-transfers'

// The ladder pays a Pix code before a barcode, so the code's receiver is who
// gets the money; a bill without one has nothing to check here.
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
    const payload = bill.pixCode ?? (bill.kind === 'PIX_QR' ? bill.code : null)
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
