import { describe, expect, it } from 'vitest'
import { Money } from '@cashdeck/domain'
import {
  decodePix,
  normalizePixKey,
  paymentDescription,
  pixKeyType,
  pixPayloadOf,
  staticAmountMismatch,
} from '@/rails/pix'
import { bill, DYNAMIC_PIX, STATIC_PIX } from '@/testing/provider-fixtures'

describe('pix helpers', () => {
  it('prefers the bill pix code, then a PIX_QR code', () => {
    expect(pixPayloadOf(bill({ pixCode: ` ${STATIC_PIX} ` }))).toBe(STATIC_PIX)
    expect(pixPayloadOf(bill({ kind: 'PIX_QR', code: STATIC_PIX }))).toBe(
      STATIC_PIX,
    )
    expect(pixPayloadOf(bill())).toBeNull()
    expect(pixPayloadOf(bill({ pixCode: '  ' }))).toBeNull()
  })

  it('classifies and normalizes pix keys', () => {
    expect(pixKeyType('123e4567-e12b-12d1-a456-426655440000')).toBe('EVP')
    expect(pixKeyType('a@b.co')).toBe('EMAIL')
    expect(pixKeyType('+5511999990000')).toBe('PHONE')
    expect(pixKeyType('529.982.247-25')).toBe('CPF')
    expect(pixKeyType('11.222.333/0001-81')).toBe('CNPJ')
    expect(() => pixKeyType('nope')).toThrow('is not a Pix key')
    expect(normalizePixKey('529.982.247-25')).toBe('52998224725')
    expect(normalizePixKey(' a@b.co ')).toBe('a@b.co')
  })

  it('checks a static amount against the bill and trusts dynamic codes', () => {
    const fixed = decodePix(STATIC_PIX)
    expect(fixed.dynamic).toBe(false)
    expect(staticAmountMismatch(fixed, bill())).toBe(false)
    expect(staticAmountMismatch(fixed, bill({ amount: Money.of(100) }))).toBe(
      true,
    )
    const dynamic = decodePix(DYNAMIC_PIX)
    expect(dynamic.dynamic).toBe(true)
    expect(staticAmountMismatch(dynamic, bill({ amount: Money.of(1) }))).toBe(
      false,
    )
    const open = decodePix(
      '00020126580014br.gov.bcb.pix0136123e4567-e12b-12d1-a456-4266554400005204000053039865802BR5913Fulano de Tal6008BRASILIA62070503***63041D3D',
    )
    expect(staticAmountMismatch(open, bill())).toBe(false)
  })

  it('describes a payment by its payee', () => {
    expect(paymentDescription(bill())).toBe('Energia Exemplo')
    expect(paymentDescription(bill({ payee: null }))).toBe('Cashdeck')
  })
})
