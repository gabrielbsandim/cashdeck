import { type Bill, type BillLine, type LocalDate } from '@cashdeck/domain'
import { type CapturedBill } from '@/ports/providers'
import { type Deps } from '@/use-cases/deps'

export const BILL_LINES_COLLECTION = 'bill-lines'

// What a captured bill charges for, kept with the document it came in.
export type StoredBillLines = {
  billId: string
  payee: string | null
  dueDate: LocalDate
  total: number
  lines: BillLine[]
  attachmentId: string | null
}

type BillLinesDeps = Pick<Deps, 'documents' | 'attachments' | 'clock' | 'ids'>

export const loadBillLines = (
  deps: Pick<Deps, 'documents'>,
  tenantId: string,
) => deps.documents.list<StoredBillLines>(tenantId, BILL_LINES_COLLECTION)

async function keepFile(
  deps: BillLinesDeps,
  tenantId: string,
  bill: Bill,
  file: CapturedBill['file'],
): Promise<string | null> {
  if (!file) {
    return null
  }
  const id = deps.ids.next()
  await deps.attachments.save({
    id,
    tenantId,
    billId: bill.id,
    fileName: file.fileName,
    mimeType: file.mimeType,
    size: file.bytes.length,
    createdAt: deps.clock.now(),
    bytes: file.bytes,
  })
  return id
}

// The first read of a bill is kept; a reminder of the same bill adds nothing.
export async function keepBillLines(
  deps: BillLinesDeps,
  tenantId: string,
  bill: Bill,
  found: CapturedBill,
): Promise<void> {
  const lines = found.lines ?? []
  if (lines.length === 0 && !found.file) {
    return
  }
  const kept = await deps.documents.get<StoredBillLines>(
    tenantId,
    BILL_LINES_COLLECTION,
    bill.id,
  )
  if (kept) {
    return
  }
  const stored: StoredBillLines = {
    billId: bill.id,
    payee: bill.payee,
    dueDate: bill.dueDate,
    total: bill.amount.cents,
    lines,
    attachmentId: await keepFile(deps, tenantId, bill, found.file),
  }
  await deps.documents.put(tenantId, BILL_LINES_COLLECTION, bill.id, stored)
}
