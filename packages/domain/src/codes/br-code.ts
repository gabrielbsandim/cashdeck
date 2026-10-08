import { Money } from '@/money/money'
import { ValidationError } from '@/shared/domain-error'

export type BrCode = {
  readonly type: 'PIX'
  readonly payload: string
  readonly key: string | null
  readonly url: string | null
  readonly description: string | null
  readonly amount: Money | null
  readonly merchantName: string
  readonly merchantCity: string
  readonly txid: string | null
  readonly singleUse: boolean
}

const PIX_GUI = 'br.gov.bcb.pix'

export function crc16(value: string): string {
  let crc = 0xffff
  for (const byte of new TextEncoder().encode(value)) {
    crc ^= byte << 8
    for (let bit = 0; bit < 8; bit += 1) {
      crc = crc & 0x8000 ? ((crc << 1) ^ 0x1021) & 0xffff : (crc << 1) & 0xffff
    }
  }
  return crc.toString(16).toUpperCase().padStart(4, '0')
}

export function parseTlv(value: string): Map<string, string> {
  const fields = new Map<string, string>()
  let position = 0
  while (position < value.length) {
    const id = value.slice(position, position + 2)
    const length = Number(value.slice(position + 2, position + 4))
    const content = value.slice(position + 4, position + 4 + length)
    if (!/^\d{2}$/.test(id) || content.length !== length) {
      throw new ValidationError('Malformed Pix payload.')
    }
    fields.set(id, content)
    position += 4 + length
  }
  return fields
}

function pixAccount(fields: Map<string, string>): Map<string, string> {
  for (let id = 26; id <= 51; id += 1) {
    const raw = fields.get(String(id))
    const account = raw === undefined ? undefined : parseTlv(raw)
    if (account?.get('00')?.toLowerCase() === PIX_GUI) {
      return account
    }
  }
  throw new ValidationError('Payload is not a Pix code.')
}

function required(
  fields: Map<string, string>,
  id: string,
  name: string,
): string {
  const value = fields.get(id)
  if (!value) {
    throw new ValidationError(`Pix payload is missing the ${name}.`)
  }
  return value
}

export function parseBrCode(raw: string): BrCode {
  const payload = raw.trim()
  const expected = crc16(payload.slice(0, -4))
  if (
    payload.slice(-8, -4) !== '6304' ||
    payload.slice(-4).toUpperCase() !== expected
  ) {
    throw new ValidationError('Pix payload checksum does not match.')
  }
  const fields = parseTlv(payload)
  if (fields.get('00') !== '01') {
    throw new ValidationError('Unsupported Pix payload format.')
  }
  const account = pixAccount(fields)
  const key = account.get('01') || null
  const url = account.get('25') || null
  if (key === null && url === null) {
    throw new ValidationError('Pix payload has neither a key nor a location.')
  }
  const amount = fields.get('54')
  const additional = parseTlv(fields.get('62') ?? '')
  const txid = additional.get('05') ?? null
  return {
    type: 'PIX',
    payload,
    key,
    url,
    description: account.get('02') ?? null,
    amount: amount === undefined ? null : Money.fromDecimal(amount),
    merchantName: required(fields, '59', 'merchant name'),
    merchantCity: required(fields, '60', 'merchant city'),
    txid: txid === '***' ? null : txid,
    singleUse: fields.get('01') === '12',
  }
}

export type EncodeBrCodeInput = {
  key: string
  merchantName: string
  merchantCity: string
  amount?: Money
  txid?: string
  description?: string
}

function tlv(id: string, value: string): string {
  return `${id}${String(value.length).padStart(2, '0')}${value}`
}

export function encodeBrCode(input: EncodeBrCodeInput): string {
  const account =
    tlv('00', PIX_GUI) +
    tlv('01', input.key) +
    (input.description ? tlv('02', input.description) : '')
  const body =
    tlv('00', '01') +
    tlv('26', account) +
    tlv('52', '0000') +
    tlv('53', '986') +
    (input.amount ? tlv('54', input.amount.toDecimal()) : '') +
    tlv('58', 'BR') +
    tlv('59', input.merchantName.slice(0, 25)) +
    tlv('60', input.merchantCity.slice(0, 15)) +
    tlv('62', tlv('05', input.txid ?? '***')) +
    '6304'
  return body + crc16(body)
}
