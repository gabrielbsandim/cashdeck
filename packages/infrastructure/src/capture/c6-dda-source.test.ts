import { describe, expect, it } from 'vitest'
import { C6DdaBillSource } from '@/capture/c6-dda-source'
import { BankClients } from '@/rails/bank-client'
import { C6_HOSTS } from '@/rails/c6-client'
import {
  BOLETO_LINE,
  credentials,
  ENTITY,
  STATIC_PIX,
  TENANT,
} from '@/testing/provider-fixtures'
import { ScriptedTransport } from '@/testing/scripted-transport'

const API = `${C6_HOSTS.production}/v1/schedule_payments`
const TOKEN = `${C6_HOSTS.production}/v1/auth/`

function source(items: unknown[]) {
  const scripted = new ScriptedTransport()
    .on('POST', TOKEN, { json: { access_token: 'tok' } })
    .on('GET', `${API}/query`, { json: { items } })
  return new C6DdaBillSource({
    credentials: credentials({
      C6_CLIENT_ID: 'c',
      C6_CLIENT_SECRET: 's',
      C6_CERT: 'cert',
      C6_KEY: 'key',
    }),
    clients: new BankClients(() => scripted.transport),
    now: () => new Date('2026-10-08T12:00:00Z'),
  })
}

describe('C6DdaBillSource Pix codes', () => {
  it('maps a Pix code from any of the candidate fields when it validates', async () => {
    const bills = await source([
      { amount: 123.45, content: BOLETO_LINE, pix_qr_code: STATIC_PIX },
      { amount: 123.45, content: BOLETO_LINE, emv: ` ${STATIC_PIX} ` },
      { amount: 123.45, content: BOLETO_LINE, qr_code: `${STATIC_PIX}X` },
      { amount: 123.45, content: BOLETO_LINE, pix_code: 42 },
    ]).fetch(TENANT, ENTITY)
    expect(bills.map(bill => bill.pixCode)).toEqual([
      STATIC_PIX,
      STATIC_PIX,
      null,
      null,
    ])
  })
})
