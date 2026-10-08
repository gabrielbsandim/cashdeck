export const SUPPORTED_LOCALES = ['pt-BR', 'en'] as const

export type Locale = (typeof SUPPORTED_LOCALES)[number]

export const DEFAULT_LOCALE: Locale = 'pt-BR'

const BASE_LANGUAGE: Record<string, Locale> = { pt: 'pt-BR', en: 'en' }

export function resolveLocale(tag: string | null | undefined): Locale {
  const base = (tag ?? '').trim().toLowerCase().slice(0, 2)
  return BASE_LANGUAGE[base] ?? DEFAULT_LOCALE
}

export function localeFromAcceptLanguage(
  header: string | null | undefined,
): Locale {
  const first = (header ?? '').split(',')[0]?.split(';')[0]
  return resolveLocale(first)
}
