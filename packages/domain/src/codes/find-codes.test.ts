import { describe, expect, it } from 'vitest'
import { encodeBrCode } from '@/codes/br-code'
import {
  findBrCodes,
  findPaymentCodes,
  validBarcode,
  validBrCode,
} from '@/codes/find-codes'
import { Money } from '@/money/money'

const TODAY = '2026-10-08'
const BOLETO_LINE = '00190000090280001234256789012178916050000012345'
const BOLETO_PRINTED = '00190.00009 02800.012342 56789.012178 9 16050000012345'
const STATIC = encodeBrCode({
  key: 'person@example.com',
  merchantName: 'Example Store',
  merchantCity: 'Sao Paulo',
  amount: Money.of(12345),
})
// A txid that carries "6304" plus four hex digits used to cut the code short.
const TRICKY = encodeBrCode({
  key: 'person@example.com',
  merchantName: 'Example Store',
  merchantCity: 'Sao Paulo',
  txid: 'AB6304BEEF99',
})

describe('validBarcode', () => {
  it('keeps the digits of a valid barcode or digitable line', () => {
    expect(validBarcode(BOLETO_PRINTED, TODAY)).toBe(BOLETO_LINE)
  })

  it('drops a wrong check digit, a Pix code and garbage', () => {
    expect(validBarcode(BOLETO_LINE.replace(/5$/, '6'), TODAY)).toBeNull()
    expect(validBarcode(STATIC, TODAY)).toBeNull()
    expect(validBarcode('', TODAY)).toBeNull()
  })
})

describe('validBrCode', () => {
  it('returns the trimmed payload of a valid code', () => {
    expect(validBrCode(` ${STATIC} `)).toBe(STATIC)
  })

  it('drops a code whose checksum fails', () => {
    expect(validBrCode(STATIC.slice(0, -1) + 'X')).toBeNull()
  })
})

describe('findBrCodes', () => {
  it('finds a code whose payload contains 6304 and four hex digits', () => {
    expect(TRICKY).toContain('6304BEEF')
    expect(findBrCodes(`Pague com Pix: ${TRICKY} obrigado`)).toEqual([TRICKY])
  })

  it('joins a code broken across lines', () => {
    const broken = `${TRICKY.slice(0, 40)}\r\n${TRICKY.slice(40)}`
    expect(findBrCodes(broken)).toEqual([TRICKY])
  })

  it('lists every valid code, the longest first, once', () => {
    expect(findBrCodes(`${STATIC} and ${TRICKY} and ${STATIC}`)).toEqual([
      STATIC,
      TRICKY,
    ])
  })

  it('ignores a misread code and non printable text', () => {
    expect(findBrCodes(STATIC.slice(0, -1) + '0')).toEqual([])
    expect(
      findBrCodes(`${STATIC.slice(0, 30)}\u0000${STATIC.slice(30)}`),
    ).toEqual([])
    expect(findBrCodes('no codes here')).toEqual([])
  })
})

describe('findPaymentCodes', () => {
  it('finds the barcode and the Pix code of a bolepix', () => {
    expect(
      findPaymentCodes(`Linha: ${BOLETO_PRINTED}\nPix: ${STATIC}`, TODAY),
    ).toEqual({ barcode: BOLETO_LINE, pixCode: STATIC })
  })

  it('answers nulls when nothing validates', () => {
    expect(findPaymentCodes('Total 123,45', TODAY)).toEqual({
      barcode: null,
      pixCode: null,
    })
  })
})
