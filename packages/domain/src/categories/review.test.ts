import { describe, expect, it } from 'vitest'
import { commonWords, reviewKey, sharedPattern } from '@/categories/review'
import { Money } from '@/money/money'

const subject = (
  description: string,
  counterparty: string | null = null,
  cents = -1000,
) => ({ id: 'tx1', description, counterparty, amount: Money.of(cents) })

describe('category review', () => {
  it('finds the longest run of words every description shares', () => {
    expect(
      commonWords([
        'COMPRA MERCADO SOL UNIDADE CENTRO 01',
        'Mercado Sol Unidade Norte',
        'mercado sol unidade',
      ]),
    ).toBe('mercado sol unidade')
    expect(commonWords(['Padaria Lua', 'Padaria Lua'])).toBe('padaria lua')
    expect(commonWords(['Padaria Lua', 'Posto Azul'])).toBe('')
    expect(commonWords(['PIX ENVIADO'])).toBe('')
    expect(commonWords([])).toBe('')
  })

  it('builds one rule for a group from words or a shared document', () => {
    expect(
      sharedPattern([subject('Loja Exemplo 1'), subject('Loja Exemplo 2')]),
    ).toEqual({ pattern: 'loja exemplo', counterparty: null })
    expect(
      sharedPattern([
        subject('PIX ENVIADO', '11.222.333/0001-81'),
        subject('PIX', '11222333000181'),
      ]),
    ).toEqual({ pattern: '', counterparty: '11222333000181' })
    expect(
      sharedPattern([
        subject('PIX', '11222333000181'),
        subject('PIX', '99888777000161'),
      ]),
    ).toBeNull()
    expect(sharedPattern([subject('PIX')])).toBeNull()
  })

  it('keys a transaction by direction and words, then payee, then itself', () => {
    expect(reviewKey(subject('COMPRA Padaria Lua 22'))).toBe('OUT:padaria lua')
    expect(reviewKey(subject('Padaria Lua', null, 500))).toBe('IN:padaria lua')
    expect(reviewKey(subject('PIX ENVIADO', '11222333000181'))).toBe(
      'OUT#11222333000181',
    )
    expect(reviewKey(subject('PIX ENVIADO'))).toBe('OUT@tx1')
  })
})
