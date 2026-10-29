import { type BillSource, createBill, Money } from '@cashdeck/domain'
import {
  type PixPreviewView,
  type PreviewPixInput,
  type SendPixInput,
} from '@/dtos/pix-contacts'
import { type ChatRecipient } from '@/ports/chat'
import { type VerifiedPayee } from '@/ports/providers'
import { type Actor } from '@/ports/repositories'
import { sanitize } from '@/use-cases/chat/hardening'
import { type Deps } from '@/use-cases/deps'
import { withLadderAlerts } from '@/use-cases/ladder-alerts'
import { makePixContacts, recipientFrom } from '@/use-cases/pix-contacts'
import { makeRunPaymentLadder } from '@/use-cases/run-payment-ladder'
import { requireEntity, today } from '@/use-cases/shared'

// A failed lookup never blocks the payment; it only leaves it unverified.
export async function checkedRecipient(
  lookup: () => Promise<VerifiedPayee | null>,
  fallback: string,
): Promise<ChatRecipient> {
  const payee = await lookup().catch(() => null)
  if (!payee) {
    return { name: fallback, taxId: null, bank: null, verified: false }
  }
  return {
    name: sanitize(payee.name, 120),
    taxId: payee.taxId && sanitize(payee.taxId, 20),
    bank: payee.bank && sanitize(payee.bank, 120),
    verified: true,
  }
}

export function makePixTransfers(deps: Deps) {
  const contacts = makePixContacts(deps)
  const runLadder = withLadderAlerts(makeRunPaymentLadder(deps), deps.alerts)

  async function preview(
    tenantId: string,
    input: PreviewPixInput,
  ): Promise<PixPreviewView> {
    const owner = await requireEntity(deps.entities, tenantId, input.entity)
    const { contact, isNew } = await contacts.resolve(
      tenantId,
      recipientFrom(input),
    )
    const key = { type: contact.pixKeyType, value: contact.pixKey }
    const recipient = await checkedRecipient(
      () =>
        deps.recipientDirectory.ownerOfKey(key, {
          tenantId,
          entityId: owner.id,
        }),
      contact.name,
    )
    return {
      contact: {
        id: isNew ? null : contact.id,
        name: contact.name,
        handle: contact.handle,
        pixKey: contact.pixKey,
        pixKeyType: contact.pixKeyType,
        isNew,
      },
      recipient,
    }
  }

  // The Pay tab and a Pix the chat proposed both land here once confirmed.
  async function send(
    tenantId: string,
    input: SendPixInput,
    actor: Actor,
    source: BillSource = 'MANUAL',
  ) {
    const owner = await requireEntity(deps.entities, tenantId, input.entity)
    const contact = await contacts.recordPaid(tenantId, recipientFrom(input))
    const now = deps.clock.now()
    const bill = createBill({
      id: deps.ids.next(),
      tenantId,
      entityId: owner.id,
      kind: 'PIX_KEY',
      source,
      payee: contact.name,
      amount: Money.of(input.amountCents),
      dueDate: today(now),
      code: contact.pixKey,
      createdAt: now,
    })
    await deps.bills.save(bill)
    const run = await runLadder(tenantId, bill.id, { confirmed: true, actor })
    return { run, contactId: contact.id }
  }

  return { preview, send }
}
