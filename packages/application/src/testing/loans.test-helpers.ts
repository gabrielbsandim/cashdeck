import { type fullDeps } from '@/testing/deps.test-helpers'
import { TENANT } from '@/testing/scenario.test-helpers'
import { FakeDocumentTextReader } from '@/testing/services'
import { makeLoans } from '@/use-cases/loans'

// A three installment SAC statement: the first paid on 29/09, then 2.000,00
// owed until 17/10 and 1.000,00 until 17/11.
export const loanStatement = (contract: string, signedOn: string) =>
  [
    `CONTRATO ${contract} Data do contrato ${signedOn} Extrato Financeiro`,
    'DADOS FINANCEIROS 3.000,00 Valor Financiamento TAXAS Efetiva(a.a)',
    'CET(a.a) 12,00% 12,50% Valor Imóvel 9.000,00',
    'Sistema Amortização SAC 1/3 Prazo TR Indexador ENCARGOS',
    '1 17/09/2026 1.100,00 1.000,00 1,001719 30,00 10,00 25,00 20,00 5,00',
    '0,00 1,001719 2.000,00 Paga 29/09/2026 1.125,00 15,00',
    '2 17/10/2026 1.085,00 1.000,00 1,000000 30,00 10,00 25,00 0,00 0,00',
    '0,00 1,000000 1.000,00 A Vencer - 0,00 20,00',
    '3 17/11/2026 1.075,00 1.000,00 1,000000 30,00 10,00 25,00 0,00 0,00',
    '0,00 1,000000 0,00 A Vencer - 0,00 10,00',
  ].join('\n')

// Stores that loan, signed on 10/08/2026, as bradesco-<contract>.
export async function importLoan(
  deps: ReturnType<typeof fullDeps>,
  contract = '1234567',
  entity: 'PF' | 'PJ' = 'PF',
) {
  await makeLoans({
    ...deps,
    documentText: new FakeDocumentTextReader(
      loanStatement(contract, '10/08/2026'),
    ),
  }).importStatement(TENANT, {
    entity,
    fileName: 'extrato.pdf',
    mimeType: 'application/pdf',
    base64: 'JVBERi0xLjQ=',
  })
  return `bradesco-${contract}`
}
