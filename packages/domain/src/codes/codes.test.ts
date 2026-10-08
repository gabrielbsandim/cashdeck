import { describe, expect, it } from 'vitest'
import { mod10, mod11Arrecadacao, mod11Boleto } from '@/codes/check-digits'
import { decodeBoleto, dueDateFromFactor } from '@/codes/boleto'
import { decodeArrecadacao } from '@/codes/arrecadacao'
import { crc16, encodeBrCode, parseBrCode, parseTlv } from '@/codes/br-code'
import { decodePaymentCode } from '@/codes/payment-code'
import { Money } from '@/money/money'
import { ValidationError } from '@/shared/domain-error'

const BOLETO_BARCODE = '00199160500000123450000002800012345678901217'
const BOLETO_LINE = '00190000090280001234256789012178916050000012345'
const TAX_BARCODE = '85600000001500003282026102000000000000123000'
const TAX_LINE = '856000000013500003282026610200000004000001230002'
const MOD11_BARCODE = '83820000000999000552026102000000000000456000'
const MOD11_LINE = '838200000002999000552026610200000000000004560000'
const REFERENCE_VALUE_BARCODE = '81780000000100000552026102000000000000456000'
const BCB_SAMPLE =
  '00020126580014br.gov.bcb.pix0136123e4567-e12b-12d1-a456-4266554400005204000053039865802BR5913Fulano de Tal6008BRASILIA62070503***63041D3D'

describe('check digits', () => {
  it('computes modulo 10', () => {
    expect(mod10('1')).toBe(8)
    expect(mod10('9')).toBe(1)
    expect(mod10('0')).toBe(0)
  })

  it('computes the boleto modulo 11 with 1 for 0, 10 and 11', () => {
    expect(mod11Boleto('1')).toBe(9)
    expect(mod11Boleto('14')).toBe(1)
    expect(mod11Boleto('6')).toBe(1)
  })

  it('computes the arrecadacao modulo 11', () => {
    expect(mod11Arrecadacao('1')).toBe(9)
    expect(mod11Arrecadacao('14')).toBe(0)
    expect(mod11Arrecadacao('6')).toBe(0)
    expect(mod11Arrecadacao('5')).toBe(1)
  })
})

describe('decodeBoleto', () => {
  it('decodes a barcode and builds its digitable line', () => {
    const boleto = decodeBoleto(BOLETO_BARCODE, '2026-10-08')
    expect(boleto.digitableLine).toBe(BOLETO_LINE)
    expect(boleto.bankCode).toBe('001')
    expect(boleto.amount).toEqual(Money.of(12345))
    expect(boleto.dueDate).toBe('2026-10-20')
  })

  it('decodes a digitable line back to the barcode', () => {
    expect(decodeBoleto(BOLETO_LINE, '2026-10-08').barcode).toBe(BOLETO_BARCODE)
  })

  it('returns no amount and no due date when they are zero', () => {
    const body = '0019' + '0000' + '0000000000' + '0000002800012345678901217'
    const barcode = body.slice(0, 4) + mod11Boleto(body) + body.slice(4)
    const boleto = decodeBoleto(barcode, '2026-10-08')
    expect(boleto.amount).toBeNull()
    expect(boleto.dueDate).toBeNull()
  })

  it('rejects wrong check digits', () => {
    expect(() =>
      decodeBoleto(BOLETO_BARCODE.replace(/^00199/, '00198'), '2026-10-08'),
    ).toThrow('barcode check digit')
    expect(() =>
      decodeBoleto(
        BOLETO_LINE.slice(0, 9) + '0' + BOLETO_LINE.slice(10),
        '2026-10-08',
      ),
    ).toThrow('digitable line check digit')
  })
})

describe('dueDateFromFactor', () => {
  it('picks the cycle closest to the reference date', () => {
    expect(dueDateFromFactor(1000, '2000-07-01')).toBe('2000-07-03')
    expect(dueDateFromFactor(1000, '2025-03-01')).toBe('2025-02-22')
    expect(dueDateFromFactor(9999, '2025-02-01')).toBe('2025-02-21')
  })
})

describe('decodeArrecadacao', () => {
  it('decodes a modulo 10 government guide', () => {
    const guide = decodeArrecadacao(TAX_BARCODE)
    expect(guide.segment).toBe('GOVERNMENT')
    expect(guide.isTaxGuide).toBe(true)
    expect(guide.amount).toEqual(Money.of(15000))
    expect(guide.digitableLine).toBe(TAX_LINE)
    expect(decodeArrecadacao(TAX_LINE).barcode).toBe(TAX_BARCODE)
  })

  it('decodes a modulo 11 utility bill', () => {
    const bill = decodeArrecadacao(MOD11_LINE)
    expect(bill.barcode).toBe(MOD11_BARCODE)
    expect(bill.segment).toBe('ENERGY_AND_GAS')
    expect(bill.isTaxGuide).toBe(false)
    expect(bill.amount).toEqual(Money.of(9990))
  })

  it('has no amount when the value is a reference', () => {
    expect(decodeArrecadacao(REFERENCE_VALUE_BARCODE).amount).toBeNull()
  })

  it('rejects invalid codes', () => {
    expect(() => decodeArrecadacao('855' + TAX_BARCODE.slice(3))).toThrow(
      'Unknown value indicator',
    )
    expect(() =>
      decodeArrecadacao(TAX_BARCODE.replace(/^8560/, '8561')),
    ).toThrow('Barcode check digit')
    expect(() =>
      decodeArrecadacao(TAX_LINE.slice(0, 11) + '9' + TAX_LINE.slice(12)),
    ).toThrow('Digitable line check digit')
    const body = '886' + TAX_BARCODE.slice(4)
    const unknownSegment = body.slice(0, 3) + mod10(body) + body.slice(3)
    expect(() => decodeArrecadacao(unknownSegment)).toThrow('Unknown segment')
  })
})

describe('Pix BR Code', () => {
  it('matches the CRC of the central bank sample', () => {
    expect(crc16(BCB_SAMPLE.slice(0, -4))).toBe('1D3D')
  })

  it('parses the central bank sample', () => {
    const code = parseBrCode(BCB_SAMPLE)
    expect(code.key).toBe('123e4567-e12b-12d1-a456-426655440000')
    expect(code.merchantName).toBe('Fulano de Tal')
    expect(code.merchantCity).toBe('BRASILIA')
    expect(code.amount).toBeNull()
    expect(code.txid).toBeNull()
    expect(code.url).toBeNull()
    expect(code.description).toBeNull()
    expect(code.singleUse).toBe(false)
  })

  it('round trips an encoded static code', () => {
    const payload = encodeBrCode({
      key: 'person@example.com',
      merchantName: 'Example Person With A Long Name',
      merchantCity: 'Sao Paulo',
      amount: Money.of(4990),
      txid: 'BILL123',
      description: 'Rent',
    })
    const code = parseBrCode(` ${payload} `)
    expect(code.amount).toEqual(Money.of(4990))
    expect(code.txid).toBe('BILL123')
    expect(code.description).toBe('Rent')
    expect(code.merchantName).toHaveLength(25)
  })

  it('encodes a code without the optional fields', () => {
    const code = parseBrCode(
      encodeBrCode({
        key: '+5511999990000',
        merchantName: 'A',
        merchantCity: 'B',
      }),
    )
    expect(code.amount).toBeNull()
    expect(code.description).toBeNull()
    expect(code.txid).toBeNull()
  })

  it('parses a dynamic single use code with a location', () => {
    const account = '0014br.gov.bcb.pix2520pix.example.com/qr/1'
    const body =
      '000201010212' +
      `26${account.length}${account}` +
      '52040000530398654041.005802BR5905Store6004City6304'
    const code = parseBrCode(body + crc16(body))
    expect(code.url).toBe('pix.example.com/qr/1')
    expect(code.key).toBeNull()
    expect(code.singleUse).toBe(true)
    expect(code.amount).toEqual(Money.of(100))
  })

  function sign(body: string): string {
    return body + crc16(body)
  }

  it('rejects invalid payloads', () => {
    expect(() => parseBrCode(BCB_SAMPLE.slice(0, -1) + 'E')).toThrow('checksum')
    expect(() =>
      parseBrCode(BCB_SAMPLE.slice(0, -8) + '6305' + '0000'),
    ).toThrow('checksum')
    expect(() => parseBrCode(sign('000202' + '5802BR6304'))).toThrow(
      'Unsupported Pix payload format',
    )
    expect(() =>
      parseBrCode(sign('000201' + '26080004test5802BR6304')),
    ).toThrow('not a Pix code')
    expect(() =>
      parseBrCode(sign('000201' + '26180014br.gov.bcb.pix6304')),
    ).toThrow('neither a key nor a location')
    expect(() =>
      parseBrCode(
        sign('000201' + '26220014br.gov.bcb.pix0100' + '6004City6304'),
      ),
    ).toThrow('neither a key')
    expect(() =>
      parseBrCode(
        sign('000201' + '26250014br.gov.bcb.pix0103abc' + '6004City6304'),
      ),
    ).toThrow('missing the merchant name')
    expect(() => parseTlv('0005abc')).toThrow(ValidationError)
    expect(() => parseTlv('ab02xx')).toThrow('Malformed')
  })
})

describe('decodePaymentCode', () => {
  it('routes each format to its decoder', () => {
    expect(decodePaymentCode(BCB_SAMPLE, '2026-10-08').type).toBe('PIX')
    expect(decodePaymentCode(BOLETO_LINE, '2026-10-08').type).toBe('BOLETO')
    expect(decodePaymentCode(BOLETO_BARCODE, '2026-10-08').type).toBe('BOLETO')
    expect(
      decodePaymentCode(TAX_LINE.replace(/(\d{12})/g, '$1 '), '2026-10-08')
        .type,
    ).toBe('ARRECADACAO')
    expect(decodePaymentCode(TAX_LINE, '2026-10-08').type).toBe('ARRECADACAO')
    expect(decodePaymentCode(TAX_BARCODE, '2026-10-08').type).toBe(
      'ARRECADACAO',
    )
  })

  it('rejects unknown input', () => {
    expect(() => decodePaymentCode('hello', '2026-10-08')).toThrow(
      'must be a barcode',
    )
    expect(() => decodePaymentCode('123', '2026-10-08')).toThrow(
      'unexpected length',
    )
    expect(() =>
      decodePaymentCode(TAX_LINE.slice(0, 47), '2026-10-08'),
    ).toThrow('unexpected length')
  })
})
