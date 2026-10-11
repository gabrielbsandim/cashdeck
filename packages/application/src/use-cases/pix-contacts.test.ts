import { describe, expect, it } from 'vitest'
import { ValidationError } from '@cashdeck/domain'
import { ConflictError, NotFoundError } from '@/errors/errors'
import { fullDeps } from '@/testing/deps.test-helpers'
import { NOW, TENANT } from '@/testing/scenario.test-helpers'
import { makePixContacts } from '@/use-cases/pix-contacts'

function setup() {
  const deps = fullDeps()
  return { deps, contacts: makePixContacts(deps) }
}

describe('pix contacts', () => {
  it('saves a contact with a handle from its first name', async () => {
    const { contacts } = setup()
    const created = await contacts.create(TENANT, {
      name: ' João  Silva ',
      pixKey: '529.982.247-25',
    })
    expect(created).toEqual({
      id: created.id,
      name: 'João Silva',
      handle: 'joao',
      pixKey: '52998224725',
      pixKeyType: 'CPF',
      timesPaid: 0,
      lastPaidAt: null,
      createdAt: NOW.toISOString(),
    })
    const twin = await contacts.create(TENANT, {
      name: 'João Pereira',
      pixKey: 'joao@example.com',
    })
    expect(twin.handle).toBe('joao.pereira')
  })

  it('refuses a taken handle or key', async () => {
    const { contacts } = setup()
    await contacts.create(TENANT, {
      name: 'Ana',
      pixKey: 'ana@example.com',
      handle: '@ana',
    })
    await expect(
      contacts.create(TENANT, {
        name: 'Ana Lima',
        pixKey: 'lima@example.com',
        handle: 'ana',
      }),
    ).rejects.toThrow(ConflictError)
    await expect(
      contacts.create(TENANT, { name: 'Outra', pixKey: 'ANA@example.com' }),
    ).rejects.toThrow('already saved as Ana')
    await expect(
      contacts.create(TENANT, { name: 'Bia', pixKey: 'nope' }),
    ).rejects.toThrow(ValidationError)
  })

  it('searches, edits and removes contacts', async () => {
    const { deps, contacts } = setup()
    const ana = await contacts.create(TENANT, {
      name: 'Ana Souza',
      pixKey: 'ana@example.com',
    })
    const bia = await contacts.create(TENANT, {
      name: 'Bia Lima',
      pixKey: '+55 11 98765-4321',
    })
    expect((await contacts.list(TENANT)).map(c => c.handle)).toEqual([
      'ana',
      'bia',
    ])
    expect((await contacts.list(TENANT, 'lima')).map(c => c.id)).toEqual([
      bia.id,
    ])

    const renamed = await contacts.update(TENANT, ana.id, {
      name: 'Ana Souza Lima',
      handle: 'aninha',
    })
    expect(renamed).toMatchObject({
      name: 'Ana Souza Lima',
      handle: 'aninha',
      pixKey: 'ana@example.com',
    })
    const rekeyed = await contacts.update(TENANT, ana.id, {
      pixKey: '11987654320',
      pixKeyType: 'PHONE',
    })
    expect(rekeyed).toMatchObject({
      pixKey: '+5511987654320',
      pixKeyType: 'PHONE',
    })
    const retyped = await contacts.update(TENANT, ana.id, {
      pixKey: '52998224725',
    })
    expect(retyped.pixKeyType).toBe('CPF')
    await expect(
      contacts.update(TENANT, ana.id, { pixKeyType: 'CNPJ' }),
    ).rejects.toThrow(ValidationError)
    await expect(
      contacts.update(TENANT, ana.id, { handle: 'bia' }),
    ).rejects.toThrow(ConflictError)
    await expect(contacts.update(TENANT, 'missing', {})).rejects.toThrow(
      NotFoundError,
    )

    expect(await contacts.remove(TENANT, ana.id)).toEqual({ id: ana.id })
    expect(await deps.pixContacts.findById(TENANT, ana.id)).toBeNull()
    await expect(contacts.remove(TENANT, ana.id)).rejects.toThrow(NotFoundError)
    await deps.pixContacts.delete('other-tenant', bia.id)
    expect(await deps.pixContacts.findById('other-tenant', bia.id)).toBeNull()
    expect(await deps.pixContacts.findById(TENANT, bia.id)).not.toBeNull()
  })

  it('pays a saved key as the contact it belongs to', async () => {
    const { deps, contacts } = setup()
    const ana = await contacts.create(TENANT, {
      name: 'Ana',
      pixKey: 'ana@example.com',
    })
    const byKey = await contacts.resolve(TENANT, {
      name: 'Aninha',
      pixKey: 'Ana@Example.com',
    })
    expect(byKey).toMatchObject({ isNew: false, contact: { id: ana.id } })
    const fresh = await contacts.resolve(TENANT, {
      name: 'Bia',
      pixKey: 'bia@example.com',
      pixKeyType: 'EMAIL',
    })
    expect(fresh).toMatchObject({ isNew: true, contact: { handle: 'bia' } })
    expect(await deps.pixContacts.list(TENANT)).toHaveLength(1)

    const paid = await contacts.recordPaid(TENANT, {
      name: 'Bia',
      pixKey: 'bia@example.com',
    })
    expect(paid).toMatchObject({ timesPaid: 1, lastPaidAt: NOW })
    const again = await contacts.recordPaid(TENANT, { contactId: paid.id })
    expect(again.timesPaid).toBe(2)
    await expect(
      contacts.resolve(TENANT, { contactId: 'missing' }),
    ).rejects.toThrow(NotFoundError)
  })
})
