import {
  type Bill,
  BILL_ACTION_ALERTS,
  recipientKeys,
  transitionBill,
} from '@cashdeck/domain'
import { type BillDetailView } from '@/dtos/bill'
import { NotFoundError } from '@/errors/errors'
import { type Deps } from '@/use-cases/deps'

export const AUTO_DEBIT_COLLECTION = 'auto-debit'

type AutoDebitEntry = { entityId: string; key: string }

const entryId = (entityId: string, key: string) => `${entityId}|${key}`

const idsOf = (bill: Bill) =>
  recipientKeys(bill).map(key => entryId(bill.entityId, key))

export type AutoDebitCheck = (bill: Bill) => boolean

// The bank debits these payees by itself, so the app never pays their bills
// and only waits for the debit to show in the statement.
export async function loadAutoDebit(
  deps: Pick<Deps, 'documents'>,
  tenantId: string,
): Promise<AutoDebitCheck> {
  const entries = await deps.documents.list<AutoDebitEntry>(
    tenantId,
    AUTO_DEBIT_COLLECTION,
  )
  const flagged = new Set(
    entries.map(entry => entryId(entry.entityId, entry.key)),
  )
  return bill => idsOf(bill).some(id => flagged.has(id))
}

export function makeSetAutoDebit(
  deps: Pick<
    Deps,
    'bills' | 'alertStore' | 'documents' | 'audit' | 'clock' | 'ids'
  >,
  getBill: (tenantId: string, billId: string) => Promise<BillDetailView>,
) {
  async function store(bill: Bill, tenantId: string, enabled: boolean) {
    for (const key of recipientKeys(bill)) {
      const id = entryId(bill.entityId, key)
      if (enabled) {
        await deps.documents.put<AutoDebitEntry>(
          tenantId,
          AUTO_DEBIT_COLLECTION,
          id,
          { entityId: bill.entityId, key },
        )
        continue
      }
      await deps.documents.delete(tenantId, AUTO_DEBIT_COLLECTION, id)
    }
  }

  return async function setAutoDebit(
    tenantId: string,
    billId: string,
    enabled: boolean,
  ): Promise<BillDetailView> {
    const bill = await deps.bills.findById(tenantId, billId)
    if (!bill) {
      throw new NotFoundError('Bill')
    }
    await store(bill, tenantId, enabled)
    if (enabled && bill.status === 'NEEDS_CONFIRMATION') {
      await deps.bills.save(transitionBill(bill, 'OPEN'))
    }
    if (enabled) {
      await deps.alertStore.markBillRead(
        tenantId,
        bill.id,
        BILL_ACTION_ALERTS,
        deps.clock.now(),
      )
    }
    await deps.audit.record({
      id: deps.ids.next(),
      tenantId,
      actor: 'USER',
      action: 'bill.auto_debit_set',
      subjectId: bill.id,
      rail: null,
      result: enabled ? 'ENABLED' : 'DISABLED',
      details: { recipients: recipientKeys(bill) },
      at: deps.clock.now(),
    })
    return getBill(tenantId, billId)
  }
}
