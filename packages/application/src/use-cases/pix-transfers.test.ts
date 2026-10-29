import { describe, expect, it } from 'vitest'
import { sendPixSchema } from '@/dtos/pix-contacts'
import { type Actor } from '@/ports/repositories'
import { fullDeps } from '@/testing/deps.test-helpers'
import { FakePaymentRail, FakeRecipientDirectory } from '@/testing/providers'
import { TENANT } from '@/testing/scenario.test-helpers'
import { makePixTransfers } from '@/use-cases/pix-transfers'

const USER: Actor = { kind: 'USER', id: null, requestId: null }

const OWNER = {
  name: 'Ana Exemplo',
  taxId: '***.456.789-**',
  bank: 'Banco Exemplo',
}

function setup() {
  const deps = fullDeps({
    rails: [new FakePaymentRail('ASAAS')],
    recipientDirectory: new FakeRecipientDirectory({
      'ana@example.com': OWNER,
      'down@example.com': new Error('directory down'),
    }),
  })
  return { deps, transfers: makePixTransfers(deps) }
}

describe('pix transfers', () => {
  it('names who a key pays before sending, from the payer entity', async () => {
    const { deps, transfers } = setup()
    const fresh = await transfers.preview(TENANT, {
      name: 'Ana',
      pixKey: 'ana@example.com',
      entity: 'PJ',
    })
    expect(fresh).toEqual({
      contact: {
        id: null,
        name: 'Ana',
        handle: 'ana',
        pixKey: 'ana@example.com',
        pixKeyType: 'EMAIL',
        isNew: true,
      },
      recipient: { ...OWNER, verified: true },
    })
    expect(deps.recipientDirectory.lookups[0]?.scope).toEqual({
      tenantId: TENANT,
      entityId: 'pj',
    })
    const saved = await deps.pixContacts.list(TENANT)
    expect(saved).toEqual([])
    const down = await transfers.preview(TENANT, {
      name: 'Bia',
      pixKey: 'down@example.com',
      entity: 'PF',
    })
    expect(down.recipient).toEqual({
      name: 'Bia',
      taxId: null,
      bank: null,
      verified: false,
    })
  })

  it('pays now, saves the contact and pays it again by id', async () => {
    const { deps, transfers } = setup()
    const first = await transfers.send(
      TENANT,
      sendPixSchema.parse({
        name: 'Ana',
        pixKey: 'ana@example.com',
        amountCents: 2050,
        entity: 'PF',
      }),
      USER,
    )
    expect(first.run.bill).toMatchObject({
      entityId: 'pf',
      kind: 'PIX_KEY',
      source: 'MANUAL',
      payee: 'Ana',
      code: 'ana@example.com',
      status: 'PAID',
    })
    const known = await transfers.preview(TENANT, {
      contactId: first.contactId,
      entity: 'PF',
    })
    expect(known.contact).toMatchObject({ id: first.contactId, isNew: false })
    const again = await transfers.send(
      TENANT,
      sendPixSchema.parse({
        contactId: first.contactId,
        amountCents: 100,
        entity: 'PF',
      }),
      USER,
      'CHAT',
    )
    expect(again.contactId).toBe(first.contactId)
    expect(again.run.bill.source).toBe('CHAT')
    expect((await deps.pixContacts.list(TENANT))[0]?.timesPaid).toBe(2)
  })

  it('needs a contact or a name and a key', () => {
    expect(() =>
      sendPixSchema.parse({ name: 'Ana', amountCents: 1, entity: 'PF' }),
    ).toThrow('Choose a contact, or give a name and a Pix key.')
  })
})
