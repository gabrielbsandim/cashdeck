import { type ReceiptCopy } from '@cashdeck/application'
import { localeFromAcceptLanguage, messagesFor } from '@cashdeck/i18n'

export function receiptCopy(request: Request): ReceiptCopy {
  const locale = localeFromAcceptLanguage(
    request.headers.get('accept-language'),
  )
  return { locale, ...messagesFor(locale) }
}
