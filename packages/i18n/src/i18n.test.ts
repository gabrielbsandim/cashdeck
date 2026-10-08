import { describe, expect, it } from 'vitest'
import {
  DEFAULT_LOCALE,
  localeFromAcceptLanguage,
  resolveLocale,
  SUPPORTED_LOCALES,
} from './locales'
import { MESSAGES, messagesFor } from './messages'

function keys(value: object, prefix = ''): string[] {
  return Object.entries(value).flatMap(([key, child]) =>
    typeof child === 'string'
      ? [`${prefix}${key}`]
      : keys(child, `${prefix}${key}.`),
  )
}

describe('locales', () => {
  it('resolves tags to a supported locale', () => {
    expect(resolveLocale('pt-PT')).toBe('pt-BR')
    expect(resolveLocale('EN_us')).toBe('en')
    expect(resolveLocale('fr')).toBe(DEFAULT_LOCALE)
    expect(resolveLocale(undefined)).toBe(DEFAULT_LOCALE)
    expect(localeFromAcceptLanguage('en-US,en;q=0.9')).toBe('en')
    expect(localeFromAcceptLanguage(null)).toBe('pt-BR')
  })
})

describe('messages', () => {
  it('has the same keys in every locale', () => {
    const reference = keys(MESSAGES[DEFAULT_LOCALE])
    for (const locale of SUPPORTED_LOCALES) {
      expect(keys(messagesFor(locale))).toEqual(reference)
    }
  })
})
