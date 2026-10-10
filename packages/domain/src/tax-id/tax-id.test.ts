import { describe, expect, it } from 'vitest'
import { findTaxIds, TaxId } from '@/tax-id/tax-id'
import { ValidationError } from '@/shared/domain-error'

describe('TaxId', () => {
  it('parses and formats a CPF', () => {
    const id = TaxId.parse('529.982.247-25')
    expect(id.kind).toBe('CPF')
    expect(id.value).toBe('52998224725')
    expect(id.format()).toBe('529.982.247-25')
    expect(String(id)).toBe('52998224725')
  })

  it('parses and formats a numeric CNPJ', () => {
    const id = TaxId.parse('11.222.333/0001-81')
    expect(id.kind).toBe('CNPJ')
    expect(id.format()).toBe('11.222.333/0001-81')
  })

  it('handles check digits that wrap to zero', () => {
    expect(TaxId.parse('100.000.001-08').kind).toBe('CPF')
    expect(TaxId.parse('11.222.333/0005-05').kind).toBe('CNPJ')
  })

  it('parses an alphanumeric CNPJ', () => {
    const id = TaxId.parse('12.abc.345/01de-35')
    expect(id.kind).toBe('CNPJ')
    expect(id.value).toBe('12ABC34501DE35')
    expect(id.format()).toBe('12.ABC.345/01DE-35')
  })

  it('rejects wrong check digits and repeated digits', () => {
    for (const raw of [
      '529.982.247-24',
      '529.982.247-15',
      '111.111.111-11',
      '11.222.333/0001-80',
      '11.222.333/0001-71',
      '00000000000000',
      '12345',
    ]) {
      expect(() => TaxId.parse(raw)).toThrow(ValidationError)
    }
  })

  it('compares by value', () => {
    expect(
      TaxId.parse('52998224725').equals(TaxId.parse('529.982.247-25')),
    ).toBe(true)
  })
})

describe('findTaxIds', () => {
  it('finds the printed CNPJ and CPF and skips digit runs', () => {
    const text = [
      'Contribuinte: 11.222.333/0001-81',
      'CPF 52998224725 e de novo 529.982.247-25',
      'Errado: 11.222.333/0001-80',
      'Codigo 85890000005500000641111222333000181202610200',
    ].join('\n')
    expect(findTaxIds(text)).toEqual(['11222333000181', '52998224725'])
    expect(findTaxIds('sem documento')).toEqual([])
  })
})
