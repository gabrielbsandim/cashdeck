// Zero-width and bidirectional marks hide text from the reader but not from
// the model; control characters other than tab and newline go too.
const HIDDEN: ReadonlyArray<readonly [number, number]> = [
  [0x00, 0x08],
  [0x0b, 0x0c],
  [0x0e, 0x1f],
  [0x7f, 0x7f],
  [0x200b, 0x200f],
  [0x202a, 0x202e],
  [0x2060, 0x2064],
  [0x2066, 0x2069],
  [0xfeff, 0xfeff],
]

const visible = (char: string) => {
  const code = char.codePointAt(0) as number
  return !HIDDEN.some(([from, to]) => code >= from && code <= to)
}

export function sanitize(text: string, maxLength = 4000): string {
  return [...text.normalize('NFKC')]
    .filter(visible)
    .join('')
    .replace(/\n{4,}/g, '\n\n\n')
    .trim()
    .slice(0, maxLength)
}

const RED_FLAGS: ReadonlyArray<readonly [string, RegExp]> = [
  [
    'ignore_instructions',
    /ignore\s+(all\s+|the\s+|any\s+)?(previous|prior|above|earlier)\s+(instructions|messages|rules)/i,
  ],
  [
    'ignore_instructions',
    /ignor[ea]\s+(as\s+|todas\s+as\s+)?(instru[cç][oõ]es|regras)/i,
  ],
  [
    'ignore_instructions',
    /esque[cç]a\s+(as\s+|todas\s+as\s+)?(instru[cç][oõ]es|regras)/i,
  ],
  [
    'system_prompt',
    /system\s+prompt|prompt\s+do\s+sistema|developer\s+message/i,
  ],
  [
    'role_change',
    /\byou\s+are\s+now\b|\bagora\s+voc[eê]\s+[eé](?![a-z])|\bact\s+as\b|\baja\s+como\b/i,
  ],
  [
    'developer_mode',
    /developer\s+mode|modo\s+(desenvolvedor|dev)\b|jailbreak/i,
  ],
  ['scope_change', /\b(tenant_?id|entity_?id|tenant)\b/i],
]

export function redFlags(text: string): string[] {
  const found = RED_FLAGS.filter(([, pattern]) => pattern.test(text)).map(
    ([name]) => name,
  )
  return [...new Set(found)]
}

const TAG = /<\/?\s*user_message\s*>/gi

export function wrapUserContent(text: string): string {
  return `<user_message>\n${text.replace(TAG, '[removed]')}\n</user_message>`
}
