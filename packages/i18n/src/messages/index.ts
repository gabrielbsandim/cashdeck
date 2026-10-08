import { type Locale } from '../locales'
import { en } from './en'
import { ptBR } from './pt-BR'
import { type Messages } from './types'

export type { Messages }

export const MESSAGES: Record<Locale, Messages> = { 'pt-BR': ptBR, en }

export function messagesFor(locale: Locale): Messages {
  return MESSAGES[locale]
}
