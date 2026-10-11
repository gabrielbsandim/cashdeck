import { describe, expect, it } from 'vitest'
import {
  byRecentUse,
  contactName,
  createPixContact,
  mentionedHandles,
  parseHandle,
  parsePixKey,
  type PixContact,
  rankContacts,
  recordPixPaid,
  searchText,
  suggestHandle,
} from '@/contacts/pix-contact'
import { ValidationError } from '@/shared/domain-error'

const NOW = new Date('2026-10-11T12:00:00Z')

function contact(overrides: Partial<PixContact> = {}): PixContact {
  return {
    ...createPixContact({
      id: 'c1',
      tenantId: 't1',
      name: 'Ana Souza',
      handle: 'ana',
      key: { type: 'EMAIL', value: 'ana@example.com' },
      now: NOW,
    }),
    ...overrides,
  }
}

describe('parsePixKey', () => {
  it.each([
    ['529.982.247-25', 'CPF', '52998224725'],
    ['11.222.333/0001-81', 'CNPJ', '11222333000181'],
    ['Ana@Example.com', 'EMAIL', 'ana@example.com'],
    ['+55 11 98765-4321', 'PHONE', '+5511987654321'],
    ['(11) 98765-4321', 'PHONE', '+5511987654321'],
    ['5511987654321', 'PHONE', '+5511987654321'],
    [
      '123E4567-E89B-12D3-A456-426614174000',
      'EVP',
      '123e4567-e89b-12d3-a456-426614174000',
    ],
  ])('reads %s as a %s key', (raw, type, value) => {
    expect(parsePixKey(raw)).toEqual({ type, value })
  })

  it('validates against the type the user chose', () => {
    expect(parsePixKey('11987654321', 'PHONE').value).toBe('+5511987654321')
    expect(() => parsePixKey('52998224725', 'CNPJ')).toThrow('not a valid CNPJ')
  })

  it('rejects what is no key at all', () => {
    expect(() => parsePixKey('hello')).toThrow(ValidationError)
    expect(() => parsePixKey('+1 555 0100')).toThrow('not a Pix key')
  })
})

describe('handles', () => {
  it('reads a handle with or without the at sign', () => {
    expect(parseHandle(' @Ana.Souza ')).toBe('ana.souza')
    expect(() => parseHandle('@a')).toThrow(ValidationError)
    expect(() => parseHandle('ana souza')).toThrow(ValidationError)
  })

  it('suggests the first name, then the full name, then a number', () => {
    expect(suggestHandle('João da Silva', new Set())).toBe('joao')
    expect(suggestHandle('João da Silva', new Set(['joao']))).toBe('joao.silva')
    expect(
      suggestHandle('João da Silva', new Set(['joao', 'joao.silva', 'joao2'])),
    ).toBe('joao3')
    expect(suggestHandle('Ana', new Set(['ana']))).toBe('ana2')
    expect(suggestHandle('X', new Set())).toBe('x0')
    expect(suggestHandle('!!!', new Set())).toBe('contato')
  })

  it('finds the mentions in a message', () => {
    expect(
      mentionedHandles('Manda 50 pro @Ana e @joao.silva. Valeu @ana, a@b.com'),
    ).toEqual(['ana', 'joao.silva'])
    expect(mentionedHandles('sem menção')).toEqual([])
  })
})

describe('contacts', () => {
  it('keeps a clean name', () => {
    expect(contactName('  Ana   Souza ')).toBe('Ana Souza')
    expect(() => contactName(' ')).toThrow(ValidationError)
    expect(() => contactName('a'.repeat(81))).toThrow(ValidationError)
  })

  it('counts each Pix paid to a contact', () => {
    const later = new Date('2026-10-12T12:00:00Z')
    expect(recordPixPaid(contact(), later)).toMatchObject({
      timesPaid: 1,
      lastPaidAt: later,
      updatedAt: later,
    })
  })

  it('folds accents and case for search', () => {
    expect(searchText('  JOÃO   Ávila ')).toBe('joao avila')
  })
})

describe('rankContacts', () => {
  const ana = contact()
  const joana = contact({
    id: 'c2',
    name: 'Joana Lima',
    handle: 'joana',
    lastPaidAt: NOW,
  })
  const joao = contact({ id: 'c3', name: 'João Pedro Alves', handle: 'jp' })
  const all = [ana, joana, joao]

  it('lists everyone, paid most recently first, for an empty query', () => {
    expect(rankContacts(all, ' @ ').map(c => c.id)).toEqual(['c2', 'c1', 'c3'])
  })

  it.each([
    ['@ana', ['c1', 'c2']],
    ['jo', ['c2', 'c3']],
    ['joao', ['c3']],
    ['joão alves', ['c3']],
    ['pedro', ['c3']],
    ['souza', ['c1']],
    ['oana', ['c2']],
    ['ana@example.com', ['c2', 'c1', 'c3']],
    ['zé', []],
  ])('ranks %s', (query, ids) => {
    expect(rankContacts(all, query).map(c => c.id)).toEqual(ids)
  })

  it('puts the exact name above a prefix', () => {
    const exact = contact({ id: 'c4', name: 'Jo', handle: 'jojo' })
    expect(rankContacts([joana, exact], 'jo').map(c => c.id)).toEqual([
      'c4',
      'c2',
    ])
  })

  it('breaks ties by name', () => {
    expect(byRecentUse(joao, ana)).toBeGreaterThan(0)
  })
})
