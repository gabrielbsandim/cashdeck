import {
  contactName,
  createPixContact,
  parseHandle,
  parsePixKey,
  type PixContact,
  type PixKeyType,
  rankContacts,
  recordPixPaid,
  suggestHandle,
} from '@cashdeck/domain'
import {
  type CreatePixContactInput,
  type PixContactView,
  toPixContactView,
  type UpdatePixContactInput,
} from '@/dtos/pix-contacts'
import { ConflictError } from '@/errors/errors'
import { type PixContactRepository } from '@/ports/records'
import { type Clock, type IdGenerator } from '@/ports/system'
import { required } from '@/use-cases/shared'

type PixContactDeps = {
  pixContacts: PixContactRepository
  clock: Clock
  ids: IdGenerator
}

// Someone to pay: a saved contact, or a name and key saved on the first Pix.
export type PixRecipient =
  | { contactId: string }
  | { name: string; pixKey: string; pixKeyType?: PixKeyType }

export type ResolvedRecipient = { contact: PixContact; isNew: boolean }

function assertFree(all: readonly PixContact[], contact: PixContact) {
  const others = all.filter(other => other.id !== contact.id)
  const sameHandle = others.find(other => other.handle === contact.handle)
  if (sameHandle) {
    throw new ConflictError(`@${contact.handle} is already ${sameHandle.name}.`)
  }
  const sameKey = others.find(other => other.pixKey === contact.pixKey)
  if (sameKey) {
    throw new ConflictError(`This Pix key is already saved as ${sameKey.name}.`)
  }
}

const handlesOf = (all: readonly PixContact[]) =>
  new Set(all.map(contact => contact.handle))

export function makePixContacts(deps: PixContactDeps) {
  async function list(
    tenantId: string,
    search = '',
  ): Promise<PixContactView[]> {
    const all = await deps.pixContacts.list(tenantId)
    return rankContacts(all, search).map(toPixContactView)
  }

  function draft(
    tenantId: string,
    all: readonly PixContact[],
    input: CreatePixContactInput,
  ): PixContact {
    const name = contactName(input.name)
    return createPixContact({
      id: deps.ids.next(),
      tenantId,
      name,
      handle: input.handle ?? suggestHandle(name, handlesOf(all)),
      key: parsePixKey(input.pixKey, input.pixKeyType),
      now: deps.clock.now(),
    })
  }

  async function create(
    tenantId: string,
    input: CreatePixContactInput,
  ): Promise<PixContactView> {
    const all = await deps.pixContacts.list(tenantId)
    const contact = draft(tenantId, all, input)
    assertFree(all, contact)
    await deps.pixContacts.save(contact)
    return toPixContactView(contact)
  }

  async function update(
    tenantId: string,
    id: string,
    input: UpdatePixContactInput,
  ): Promise<PixContactView> {
    const current = required(
      await deps.pixContacts.findById(tenantId, id),
      'Contact',
    )
    const keyChanged =
      input.pixKey !== undefined || input.pixKeyType !== undefined
    const key = keyChanged
      ? parsePixKey(input.pixKey ?? current.pixKey, input.pixKeyType)
      : { type: current.pixKeyType, value: current.pixKey }
    const updated: PixContact = {
      ...current,
      name: input.name === undefined ? current.name : contactName(input.name),
      handle:
        input.handle === undefined ? current.handle : parseHandle(input.handle),
      pixKey: key.value,
      pixKeyType: key.type,
      updatedAt: deps.clock.now(),
    }
    assertFree(await deps.pixContacts.list(tenantId), updated)
    await deps.pixContacts.save(updated)
    return toPixContactView(updated)
  }

  async function remove(tenantId: string, id: string): Promise<{ id: string }> {
    required(await deps.pixContacts.findById(tenantId, id), 'Contact')
    await deps.pixContacts.delete(tenantId, id)
    return { id }
  }

  // A key already saved under another name pays that contact, so one person
  // never ends up as two.
  async function resolve(
    tenantId: string,
    recipient: PixRecipient,
  ): Promise<ResolvedRecipient> {
    if ('contactId' in recipient) {
      const contact = required(
        await deps.pixContacts.findById(tenantId, recipient.contactId),
        'Contact',
      )
      return { contact, isNew: false }
    }
    const all = await deps.pixContacts.list(tenantId)
    const contact = draft(tenantId, all, recipient)
    const known = all.find(other => other.pixKey === contact.pixKey)
    return known ? { contact: known, isNew: false } : { contact, isNew: true }
  }

  async function recordPaid(
    tenantId: string,
    recipient: PixRecipient,
  ): Promise<PixContact> {
    const { contact } = await resolve(tenantId, recipient)
    const paid = recordPixPaid(contact, deps.clock.now())
    await deps.pixContacts.save(paid)
    return paid
  }

  return { list, create, update, remove, resolve, recordPaid }
}
