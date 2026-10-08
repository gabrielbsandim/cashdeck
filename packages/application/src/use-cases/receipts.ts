import { type z } from 'zod'
import { money, type uploadSchema } from '@/dtos/common'
import { type AttachmentView, type ReceiptView } from '@/dtos/receipts'
import { NotFoundError } from '@/errors/errors'
import { type AttachmentMeta } from '@/ports/records'
import { type Deps } from '@/use-cases/deps'
import { decodeUpload, required, requireEntityById } from '@/use-cases/shared'

type ReceiptDeps = Pick<
  Deps,
  'bills' | 'payments' | 'entities' | 'attachments' | 'clock' | 'ids'
>

const toAttachmentView = (meta: AttachmentMeta): AttachmentView => ({
  id: meta.id,
  fileName: meta.fileName,
  mimeType: meta.mimeType,
  bytes: meta.size,
})

export function makeReceipts(deps: ReceiptDeps) {
  async function findBill(tenantId: string, billId: string) {
    return required(await deps.bills.findById(tenantId, billId), 'Bill')
  }

  async function receipt(
    tenantId: string,
    billId: string,
  ): Promise<ReceiptView> {
    const bill = await findBill(tenantId, billId)
    const entity = await requireEntityById(
      deps.entities,
      tenantId,
      bill.entityId,
    )
    const attempts = await deps.payments.listAttempts(tenantId, bill.id)
    const paid = attempts.find(attempt => attempt.outcome === 'PAID')
    const attachments = await deps.attachments.list(tenantId, bill.id)
    return {
      billId: bill.id,
      proof: paid
        ? {
            rail: paid.rail,
            amount: money(paid.amount),
            paidAt: (bill.paidAt ?? paid.at).toISOString(),
            payer: entity.name,
            receiver: bill.payee ?? '',
            transactionId: paid.externalId,
            authentication: null,
          }
        : null,
      attachments: attachments.map(toAttachmentView),
    }
  }

  async function addAttachment(
    tenantId: string,
    billId: string,
    upload: z.infer<typeof uploadSchema>,
  ): Promise<AttachmentView> {
    const bill = await findBill(tenantId, billId)
    const bytes = decodeUpload(upload.base64)
    const attachment = {
      id: deps.ids.next(),
      tenantId,
      billId: bill.id,
      fileName: upload.fileName,
      mimeType: upload.mimeType,
      size: bytes.length,
      createdAt: deps.clock.now(),
      bytes,
    }
    await deps.attachments.save(attachment)
    return toAttachmentView(attachment)
  }

  async function attachment(tenantId: string, billId: string, id: string) {
    const found = await deps.attachments.find(tenantId, id)
    if (found?.billId !== billId) {
      throw new NotFoundError('Attachment')
    }
    return found
  }

  return { receipt, addAttachment, attachment }
}
