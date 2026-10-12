import {
  type CategoryRule,
  directionOf,
  learnableCounterparty,
  normalizeDescription,
  type RuleSubject,
} from '@/categories/category'

export type MerchantPattern = Pick<CategoryRule, 'pattern' | 'counterparty'>

function runsOf(words: readonly string[]): string[] {
  const runs: string[] = []
  for (let size = words.length; size > 0; size -= 1) {
    for (let start = 0; start + size <= words.length; start += 1) {
      runs.push(words.slice(start, start + size).join(' '))
    }
  }
  return runs
}

// The longest run of words every description shares, so a rule built from it
// matches each of them.
export function commonWords(descriptions: readonly string[]): string {
  const [first = '', ...rest] = descriptions.map(normalizeDescription)
  const words = first.split(' ').filter(word => word !== '')
  const shared = runsOf(words).find(run =>
    rest.every(text => ` ${text} `.includes(` ${run} `)),
  )
  return shared ?? ''
}

// Words first; a group without shared words still has one rule when every
// member names the same payee document.
export function sharedPattern(
  subjects: readonly RuleSubject[],
): MerchantPattern | null {
  const pattern = commonWords(subjects.map(subject => subject.description))
  if (pattern !== '') {
    return { pattern, counterparty: null }
  }
  const documents = new Set(
    subjects.map(subject => learnableCounterparty(subject.counterparty)),
  )
  const [document = null] = documents
  if (documents.size !== 1 || document === null) {
    return null
  }
  return { pattern: '', counterparty: document }
}

// Transactions a single rule would label together: same direction and same
// description words, or the same payee when the words say nothing.
export function reviewKey(subject: RuleSubject & { id: string }): string {
  const direction = directionOf(subject)
  const words = normalizeDescription(subject.description)
  if (words !== '') {
    return `${direction}:${words}`
  }
  const document = learnableCounterparty(subject.counterparty)
  return document ? `${direction}#${document}` : `${direction}@${subject.id}`
}
