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

// The payee document first, since banks describe one payee in many ways;
// words when the members name no shared document.
export function sharedPattern(
  subjects: readonly RuleSubject[],
): MerchantPattern | null {
  const documents = new Set(
    subjects.map(subject => learnableCounterparty(subject.counterparty)),
  )
  const [document = null] = documents
  if (documents.size === 1 && document !== null) {
    return { pattern: '', counterparty: document }
  }
  const pattern = commonWords(subjects.map(subject => subject.description))
  return pattern === '' ? null : { pattern, counterparty: null }
}

// Transactions a single rule would label together: same direction and same
// payee, or the same description words when no payee document is known.
export function reviewKey(subject: RuleSubject & { id: string }): string {
  const direction = directionOf(subject)
  const document = learnableCounterparty(subject.counterparty)
  if (document) {
    return `${direction}#${document}`
  }
  const words = normalizeDescription(subject.description)
  return words === '' ? `${direction}@${subject.id}` : `${direction}:${words}`
}
