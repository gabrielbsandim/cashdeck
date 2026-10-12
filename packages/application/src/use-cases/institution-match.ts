import { type Institution } from '@/ports/records'

// Connectors that mirror accounts of other banks, so the bank behind each
// account has to be read from the account itself.
const AGGREGATORS = new Set(['meupluggy'])

const NOISE = new Set([
  'banco',
  'bank',
  'sa',
  's',
  'a',
  'de',
  'do',
  'da',
  'instituicao',
  'pagamento',
  'pagamentos',
  'ltda',
  'me',
  'financeira',
  'credito',
  'conta',
  'digital',
  'open',
  'finance',
  'empresas',
  'pf',
  'pj',
])

const MIN_KEY_LENGTH = 2

const wordsOf = (name: string): string[] =>
  name
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter(word => word !== '' && !NOISE.has(word))

export function institutionKey(name: string): string {
  return wordsOf(name).join('')
}

// An account named after the brand alone, "XP" for "XP Banking", is the
// weakest match: it only counts when no connector name fits better.
function startsTheName(accountName: string, connectorName: string): boolean {
  const account = wordsOf(accountName)
  const connector = wordsOf(connectorName)
  return (
    account.length > 0 && account.every((word, at) => connector[at] === word)
  )
}

export function isAggregator(name: string): boolean {
  return AGGREGATORS.has(institutionKey(name))
}

type Named = { name: string }

function score(accountName: string, connector: Named): number {
  const accountKey = institutionKey(accountName)
  const key = institutionKey(connector.name)
  if (key.length < MIN_KEY_LENGTH || isAggregator(connector.name)) {
    return 0
  }
  if (key === accountKey) {
    return 2 * key.length
  }
  if (accountKey.startsWith(key)) {
    return key.length
  }
  return startsTheName(accountName, connector.name) ? accountKey.length / 2 : 0
}

// The connector whose name the account name carries, preferring an exact
// name and then the longest one, so "C6 BANK" picks C6 Bank over C6.
export function matchConnector<T extends Named>(
  accountName: string,
  connectors: readonly T[],
): T | null {
  let best: T | null = null
  let bestScore = 0
  for (const connector of connectors) {
    const current = score(accountName, connector)
    if (current <= bestScore) {
      continue
    }
    best = connector
    bestScore = current
  }
  return best
}

// The app link of the institution a rail is named after, among the ones the
// tenant configured a link for.
export function appLinkFor(
  railName: string,
  institutions: readonly Institution[],
): string | null {
  const linked = institutions.filter(institution => institution.appLink)
  return matchConnector(railName, linked)?.appLink ?? null
}
