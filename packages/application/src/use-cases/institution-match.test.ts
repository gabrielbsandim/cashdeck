import { describe, expect, it } from 'vitest'
import { type ProviderConnector } from '@/ports/providers'
import {
  institutionKey,
  isAggregator,
  matchConnector,
} from '@/use-cases/institution-match'

const connector = (id: number, name: string): ProviderConnector => ({
  id,
  name,
  imageUrl: `https://logo.example/${id}.svg`,
  primaryColor: null,
})

const CONNECTORS = [
  connector(1, 'MeuPluggy'),
  connector(2, 'Banco Exemplo'),
  connector(3, 'Exemplo'),
  connector(4, 'Exemplo Pay'),
  connector(5, 'Banco do Norte'),
  connector(6, 'S.A.'),
]

describe('institution match', () => {
  it('keys a name without accents, case and legal noise', () => {
    expect(institutionKey('Banco Exemplo S.A.')).toBe('exemplo')
    expect(institutionKey('ÉXEMPLO PAY INSTITUIÇÃO DE PAGAMENTO')).toBe(
      'exemplopay',
    )
    expect(institutionKey('Banco do Norte')).toBe('norte')
  })

  it('tells an aggregator connector apart', () => {
    expect(isAggregator('MeuPluggy')).toBe(true)
    expect(isAggregator('Meu Pluggy')).toBe(true)
    expect(isAggregator('Banco Exemplo')).toBe(false)
  })

  it('prefers an exact name, then the longest prefix', () => {
    expect(matchConnector('BANCO EXEMPLO', CONNECTORS)?.id).toBe(2)
    expect(matchConnector('EXEMPLO PAY S.A.', CONNECTORS)?.id).toBe(4)
    expect(matchConnector('Exemplo Cartões', CONNECTORS)?.id).toBe(2)
    expect(matchConnector('BANCO DO NORTE', CONNECTORS)?.id).toBe(5)
  })

  it('never matches the aggregator, an empty key or an unknown name', () => {
    expect(matchConnector('MeuPluggy', CONNECTORS)).toBeNull()
    expect(matchConnector('PRODUTO SEM BANCO', CONNECTORS)).toBeNull()
    expect(matchConnector('S.A.', [connector(6, 'S.A.')])).toBeNull()
  })
})
