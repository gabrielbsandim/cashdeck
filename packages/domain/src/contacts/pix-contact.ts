import { ValidationError } from '@/shared/domain-error'
import { TaxId } from '@/tax-id/tax-id'

export const PIX_KEY_TYPES = ['CPF', 'CNPJ', 'EMAIL', 'PHONE', 'EVP'] as const
export type PixKeyType = (typeof PIX_KEY_TYPES)[number]

export type PixKey = { readonly type: PixKeyType; readonly value: string }

export type PixContact = {
  readonly id: string
  readonly tenantId: string
  readonly name: string
  readonly handle: string
  readonly pixKey: string
  readonly pixKeyType: PixKeyType
  readonly timesPaid: number
  readonly lastPaidAt: Date | null
  readonly createdAt: Date
  readonly updatedAt: Date
}

const EVP = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
const HANDLE = /^[a-z0-9][a-z0-9._]{1,29}$/
const MAX_NAME = 80

function taxIdOf(raw: string, kind: 'CPF' | 'CNPJ'): string | null {
  try {
    const id = TaxId.parse(raw)
    return id.kind === kind ? id.value : null
  } catch {
    return null
  }
}

// A Brazilian mobile or landline, with or without the country code.
function phoneOf(raw: string): string | null {
  const digits = raw.replace(/\D/g, '')
  const local = /^\d{10,11}$/.test(digits) ? `55${digits}` : digits
  return /^55\d{10,11}$/.test(local) ? `+${local}` : null
}

const PARSERS: Record<PixKeyType, (raw: string) => string | null> = {
  EVP: raw => (EVP.test(raw.toLowerCase()) ? raw.toLowerCase() : null),
  EMAIL: raw => (EMAIL.test(raw) ? raw.toLowerCase() : null),
  PHONE: phoneOf,
  CPF: raw => taxIdOf(raw, 'CPF'),
  CNPJ: raw => taxIdOf(raw, 'CNPJ'),
}

// Eleven digits read as a CPF only when the check digits agree; otherwise they
// are a phone number without the country code.
const GUESS_ORDER: readonly PixKeyType[] = [
  'EVP',
  'EMAIL',
  'CPF',
  'CNPJ',
  'PHONE',
]

function guessOrder(raw: string): readonly PixKeyType[] {
  return raw.startsWith('+') ? ['PHONE'] : GUESS_ORDER
}

export function parsePixKey(raw: string, type?: PixKeyType): PixKey {
  const trimmed = raw.trim()
  for (const candidate of type ? [type] : guessOrder(trimmed)) {
    const value = PARSERS[candidate](trimmed)
    if (value !== null) {
      return { type: candidate, value }
    }
  }
  throw new ValidationError(
    type ? `This is not a valid ${type} Pix key.` : 'This is not a Pix key.',
  )
}

// Accent, case and spacing blind, so "João" finds "joao" and "JOÃO SILVA".
export function searchText(value: string): string {
  return value
    .normalize('NFD')
    .replace(/\p{M}/gu, '')
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .trim()
}

function slug(value: string): string {
  return searchText(value).replace(/[^a-z0-9]/g, '')
}

export function parseHandle(raw: string): string {
  const handle = raw.trim().replace(/^@/, '').toLowerCase()
  if (!HANDLE.test(handle)) {
    throw new ValidationError(
      'A handle has 2 to 30 letters, digits, dots or underscores.',
    )
  }
  return handle
}

// The first name when free, then the first and last name, then a number.
export function suggestHandle(
  name: string,
  taken: ReadonlySet<string>,
): string {
  const words = searchText(name).split(' ').map(slug).filter(Boolean)
  const first = (words[0] ?? 'contato').slice(0, 24).padEnd(2, '0')
  const last = words.length > 1 ? words.at(-1) : undefined
  // A first name alone collides as soon as a second person shares it.
  const candidates = [...(last ? [`${first}.${last}`.slice(0, 30)] : []), first]
  const free = candidates.find(candidate => !taken.has(candidate))
  if (free) {
    return free
  }
  let index = 2
  while (taken.has(`${first}${index}`)) {
    index += 1
  }
  return `${first}${index}`
}

export function contactName(raw: string): string {
  const name = raw.trim().replace(/\s+/g, ' ')
  if (name.length === 0 || name.length > MAX_NAME) {
    throw new ValidationError(`A contact name has 1 to ${MAX_NAME} characters.`)
  }
  return name
}

function score(contact: PixContact, query: string): number {
  const name = searchText(contact.name)
  const words = name.split(' ')
  const parts = query.split(' ')
  const checks: Array<[number, boolean]> = [
    [100, contact.handle === query],
    [90, name === query],
    [70, contact.handle.startsWith(query)],
    [60, name.startsWith(query)],
    [50, words.some(word => word.startsWith(query))],
    [40, parts.every(part => words.some(word => word.startsWith(part)))],
    [30, name.includes(query)],
    [20, contact.pixKey.toLowerCase() === query],
  ]
  return checks.find(([, hit]) => hit)?.[0] ?? 0
}

// Best match first; ties go to the contact paid most recently.
export function rankContacts(
  contacts: readonly PixContact[],
  query: string,
): PixContact[] {
  const wanted = searchText(query).replace(/^@/, '')
  if (wanted === '') {
    return [...contacts].sort(byRecentUse)
  }
  return contacts
    .map(contact => ({ contact, score: score(contact, wanted) }))
    .filter(item => item.score > 0)
    .sort((a, b) => b.score - a.score || byRecentUse(a.contact, b.contact))
    .map(item => item.contact)
}

export function byRecentUse(a: PixContact, b: PixContact): number {
  const used = (b.lastPaidAt?.getTime() ?? 0) - (a.lastPaidAt?.getTime() ?? 0)
  return used || a.name.localeCompare(b.name, 'pt-BR')
}

export function mentionedHandles(text: string): string[] {
  const found = text.matchAll(/(?<![\w@.])@([a-z0-9][a-z0-9._]{1,29})/gi)
  const handles = [...found]
    .map(match => (match[1] as string).toLowerCase().replace(/[._]+$/, ''))
    .filter(handle => HANDLE.test(handle))
  return [...new Set(handles)]
}

export function createPixContact(input: {
  id: string
  tenantId: string
  name: string
  handle: string
  key: PixKey
  now: Date
}): PixContact {
  return {
    id: input.id,
    tenantId: input.tenantId,
    name: contactName(input.name),
    handle: parseHandle(input.handle),
    pixKey: input.key.value,
    pixKeyType: input.key.type,
    timesPaid: 0,
    lastPaidAt: null,
    createdAt: input.now,
    updatedAt: input.now,
  }
}

export function recordPixPaid(contact: PixContact, at: Date): PixContact {
  return {
    ...contact,
    timesPaid: contact.timesPaid + 1,
    lastPaidAt: at,
    updatedAt: at,
  }
}
