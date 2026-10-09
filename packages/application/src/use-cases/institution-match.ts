import { type ProviderConnector } from '@/ports/providers'

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

export function institutionKey(name: string): string {
  return name
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter(word => word !== '' && !NOISE.has(word))
    .join('')
}

export function isAggregator(name: string): boolean {
  return AGGREGATORS.has(institutionKey(name))
}

function score(accountKey: string, connector: ProviderConnector): number {
  const key = institutionKey(connector.name)
  if (key.length < MIN_KEY_LENGTH || isAggregator(connector.name)) {
    return 0
  }
  if (key === accountKey) {
    return 2 * key.length
  }
  return accountKey.startsWith(key) ? key.length : 0
}

// The connector whose name the account name carries, preferring an exact
// name and then the longest one, so "C6 BANK" picks C6 Bank over C6.
export function matchConnector(
  accountName: string,
  connectors: readonly ProviderConnector[],
): ProviderConnector | null {
  const accountKey = institutionKey(accountName)
  let best: ProviderConnector | null = null
  let bestScore = 0
  for (const connector of connectors) {
    const current = score(accountKey, connector)
    if (current <= bestScore) {
      continue
    }
    best = connector
    bestScore = current
  }
  return best
}
