import { daysBetween, type LocalDate, localDate } from '@/calendar/local-date'
import { crc16, parseBrCode } from '@/codes/br-code'
import { decodePaymentCode } from '@/codes/payment-code'

export type FoundCodes = { barcode: string | null; pixCode: string | null }

const DIGIT_RUN = /\d[\d.\s-]{42,62}\d/g
const BR_CODE_START = '000201'
const CRC_TAG = '6304'
// EMV QR Code payloads are capped at 512 characters.
const MAX_BR_CODE_LENGTH = 512
const PRINTABLE = /^[\x20-\x7E]*$/

export function validBarcode(raw: string, today: LocalDate): string | null {
  const digits = raw.replace(/\D/g, '')
  // Digits alone can never form a BR Code, so a decoded code is a barcode.
  try {
    decodePaymentCode(digits, today)
    return digits
  } catch {
    return null
  }
}

// The checksum rejects a misread code, so a Pix code is only kept when exact.
export function validBrCode(raw: string): string | null {
  try {
    return parseBrCode(raw).payload
  } catch {
    return null
  }
}

function hasValidCrc(candidate: string): boolean {
  return crc16(candidate.slice(0, -4)) === candidate.slice(-4).toUpperCase()
}

function indexesOf(text: string, needle: string): number[] {
  const found: number[] = []
  for (
    let index = text.indexOf(needle);
    index !== -1;
    index = text.indexOf(needle, index + 1)
  ) {
    found.push(index)
  }
  return found
}

function candidatesFrom(text: string, start: number): string[] {
  const window = text.slice(start, start + MAX_BR_CODE_LENGTH)
  return indexesOf(window, CRC_TAG)
    .map(tag => window.slice(0, tag + CRC_TAG.length + 4))
    .filter(candidate => PRINTABLE.test(candidate))
}

// "6304" plus four hex digits can also appear inside a payload (a txid, a
// URL), so every end is tried and the longest code whose CRC holds wins.
export function findBrCodes(text: string): string[] {
  const flat = text.replace(/\r?\n/g, '')
  const valid = indexesOf(flat, BR_CODE_START)
    .flatMap(start => candidatesFrom(flat, start))
    .filter(hasValidCrc)
    .map(validBrCode)
    .filter((code): code is string => code !== null)
  return [...new Set(valid)].sort((a, b) => b.length - a.length)
}

export function findPaymentCodes(text: string, today: LocalDate): FoundCodes {
  const barcode =
    (text.match(DIGIT_RUN) ?? [])
      .map(run => validBarcode(run, today))
      .find(code => code !== null) ?? null
  return { barcode, pixCode: findBrCodes(text)[0] ?? null }
}

// "Vencimento: 15/10/2026", "conta com vencimento em 15/10": a date printed
// right after the word, the year optional.
const DUE_DATE =
  /venc[a-z]*\D{0,30}?(\d{1,2})[/.-](\d{1,2})(?:[/.-](\d{4}|\d{2}))?/g
const HALF_YEAR = 183

// Without a year the date is the next one, so a December e-mail can say January.
function yearOf(raw: string | undefined, date: LocalDate, today: LocalDate) {
  const year = Number(today.slice(0, 4))
  if (raw !== undefined) {
    return raw.length === 2 ? 2000 + Number(raw) : Number(raw)
  }
  return daysBetween(date, today) > HALF_YEAR ? year + 1 : year
}

function dueDateOf(
  match: RegExpMatchArray,
  today: LocalDate,
): LocalDate | null {
  const day = Number(match[1])
  const month = Number(match[2])
  const sameYear = localDate(Number(today.slice(0, 4)), month, day)
  const year = yearOf(match[3], sameYear, today)
  const date = localDate(year, month, day)
  const exact = `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`
  return date === exact ? date : null
}

export function findDueDate(text: string, today: LocalDate): LocalDate | null {
  const plain = text
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()
  for (const match of plain.matchAll(DUE_DATE)) {
    const date = dueDateOf(match, today)
    if (date) {
      return date
    }
  }
  return null
}
