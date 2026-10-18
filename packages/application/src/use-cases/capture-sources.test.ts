import { describe, expect, it } from 'vitest'
import { type BillSource, type CapturedBill } from '@/ports/providers'
import { Money } from '@cashdeck/domain'
import { account, fullDeps, transaction } from '@/testing/deps.test-helpers'
import { InMemoryEntityRepository } from '@/testing/repositories'
import {
  BOLETO_LINE,
  company,
  NOW,
  PIX_NO_AMOUNT,
  personal,
  TAX_BARCODE,
  TENANT,
} from '@/testing/scenario.test-helpers'
import { loadBillLines } from '@/use-cases/bill-lines'
import {
  DDA_COLLECTION,
  MAILBOX_COLLECTION,
  makeCaptureSources,
} from '@/use-cases/capture-sources'

const found = (overrides: Partial<CapturedBill>): CapturedBill => ({
  externalId: 'm1',
  paymentCode: null,
  payee: 'Utility',
  amountCents: null,
  dueDate: null,
  kind: null,
  ...overrides,
})

function source(
  kind: 'GMAIL' | 'DDA',
  bills: CapturedBill[] | Error,
): BillSource {
  return {
    source: kind,
    fetch: async () => {
      if (bills instanceof Error) {
        throw bills
      }
      return bills
    },
  }
}

const GMAIL_BILLS = [
  found({ paymentCode: BOLETO_LINE }),
  found({
    externalId: 'm2',
    pixCode: PIX_NO_AMOUNT,
    amountCents: 900,
    dueDate: '2026-10-30',
  }),
  found({ externalId: 'm3' }),
  found({ externalId: 'm4', paymentCode: 'not a code', payee: null }),
]

describe('capture sources', () => {
  it('connects a mailbox, reads it and disconnects it', async () => {
    const deps = fullDeps({ billSources: [source('GMAIL', GMAIL_BILLS)] })
    const capture = makeCaptureSources(deps)
    const start = await capture.startMailbox(TENANT, 'PF', 'state-1')
    expect(start.url).toContain('state=state-1')
    const mailbox = await capture.completeMailbox(TENANT, 'PF', 'good-code')
    expect(await deps.secrets.get(TENANT, 'GMAIL_REFRESH_TOKEN@pf')).toBe(
      'sealed:GMAIL_REFRESH_TOKEN@pf:refresh-token',
    )
    expect((await capture.completeMailbox(TENANT, 'PF', 'good-code')).id).toBe(
      mailbox.id,
    )
    const read = await capture.readMailbox(TENANT, mailbox.id)
    expect(read.mailboxes).toEqual([
      expect.objectContaining({
        owner: 'PF',
        billsFound: 2,
        emailsScanned: 4,
        lastReadAt: NOW.toISOString(),
      }),
    ])
    const again = await capture.readMailbox(TENANT, mailbox.id)
    expect(again.mailboxes[0]?.billsFound).toBe(2)
    const after = await capture.disconnect(TENANT, mailbox.id)
    expect(after.mailboxes).toEqual([])
    expect(await deps.secrets.get(TENANT, 'GMAIL_REFRESH_TOKEN@pf')).toBeNull()
    await expect(capture.disconnect(TENANT, mailbox.id)).rejects.toThrow(
      'Mailbox',
    )
    await expect(capture.readMailbox(TENANT, mailbox.id)).rejects.toThrow(
      'Mailbox',
    )
  })

  it('settles a bill read after the statement already paid it', async () => {
    const deps = fullDeps({
      billSources: [
        source('GMAIL', [
          found({
            pixCode: PIX_NO_AMOUNT,
            amountCents: 61_140,
            dueDate: '2026-10-08',
          }),
        ]),
      ],
    })
    await deps.accounts.save(account({ id: 'checking', entityId: 'pf' }))
    await deps.transactions.save(
      transaction({
        id: 'paid',
        accountId: 'checking',
        amount: Money.of(-61_140),
        bookedOn: '2026-10-06',
      }),
    )
    const capture = makeCaptureSources(deps)
    const mailbox = await capture.completeMailbox(TENANT, 'PF', 'good-code')
    await capture.readMailbox(TENANT, mailbox.id)
    const [bill] = (await deps.bills.list(TENANT, {}, { limit: 10 })).items
    expect(bill).toMatchObject({ status: 'PAID', paidBy: 'STATEMENT' })
  })

  it('files a company guide from the personal mailbox under the company', async () => {
    const deps = fullDeps({
      billSources: [
        source('GMAIL', [
          found({
            paymentCode: TAX_BARCODE,
            dueDate: '2026-10-20',
            taxIds: [company.taxId.value],
          }),
          found({
            externalId: 'm2',
            paymentCode: BOLETO_LINE,
            taxIds: [company.taxId.value, personal.taxId.value],
          }),
          found({
            externalId: 'm3',
            pixCode: PIX_NO_AMOUNT,
            amountCents: 900,
            dueDate: '2026-10-30',
            taxIds: ['11144477735'],
          }),
        ]),
      ],
    })
    const capture = makeCaptureSources(deps)
    const mailbox = await capture.completeMailbox(TENANT, 'PF', 'good-code')
    await capture.readMailbox(TENANT, mailbox.id)
    const page = { cursor: null, limit: 10 }
    const of = async (entityId: string) =>
      (await deps.bills.list(TENANT, { entityId }, page)).items.map(
        bill => bill.kind,
      )
    expect(await of(company.id)).toEqual(['TAX_BARCODE'])
    expect((await of(personal.id)).sort()).toEqual(['BOLETO', 'PIX_QR'])
  })

  it('flags every e-mailed bill whose sender was not verified', async () => {
    const deps = fullDeps({
      billSources: [
        source('GMAIL', [
          found({ paymentCode: BOLETO_LINE, senderVerified: true }),
          found({ externalId: 'm2', paymentCode: TAX_BARCODE }),
          found({
            externalId: 'm3',
            pixCode: PIX_NO_AMOUNT,
            amountCents: 900,
            senderVerified: false,
          }),
        ]),
      ],
    })
    const capture = makeCaptureSources(deps)
    const mailbox = await capture.completeMailbox(TENANT, 'PF', 'good-code')
    await capture.readMailbox(TENANT, mailbox.id)
    const { items } = await deps.bills.list(TENANT, {}, { limit: 10 })
    const flags = Object.fromEntries(
      items.map(bill => [bill.kind, bill.unverifiedSender]),
    )
    expect(flags).toEqual({ BOLETO: false, TAX_BARCODE: true, PIX_QR: true })
  })

  it('keeps the lines and the document of the first read of each bill', async () => {
    const pdf = {
      fileName: 'boleto.pdf',
      mimeType: 'application/pdf',
      bytes: new Uint8Array([37, 80, 68, 70]),
    }
    const gas = { description: 'Consumo de gás', cents: 13665 }
    const deps = fullDeps({
      billSources: [
        source('GMAIL', [
          found({ paymentCode: BOLETO_LINE, lines: [gas], file: pdf }),
          found({ externalId: 'm2', paymentCode: BOLETO_LINE }),
          found({ externalId: 'm3', paymentCode: BOLETO_LINE, lines: [gas] }),
          found({ externalId: 'm4', paymentCode: TAX_BARCODE, file: pdf }),
          found({
            externalId: 'm5',
            pixCode: PIX_NO_AMOUNT,
            amountCents: 900,
            lines: [gas],
          }),
        ]),
      ],
    })
    const capture = makeCaptureSources(deps)
    const mailbox = await capture.completeMailbox(TENANT, 'PF', 'good-code')
    await capture.readMailbox(TENANT, mailbox.id)

    const kept = await loadBillLines(deps, TENANT)
    const { items } = await deps.bills.list(TENANT, {}, { limit: 10 })
    const kindOf = new Map(items.map(bill => [bill.id, bill.kind]))
    const byKind = Object.fromEntries(
      kept.map(row => [
        kindOf.get(row.billId),
        [row.lines.length, row.attachmentId !== null],
      ]),
    )
    expect(byKind).toEqual({
      BOLETO: [1, true],
      TAX_BARCODE: [0, true],
      PIX_QR: [1, false],
    })
    const boleto = kept.find(row => kindOf.get(row.billId) === 'BOLETO')
    const files = await deps.attachments.list(TENANT, boleto?.billId ?? '')
    expect(files.map(file => [file.fileName, file.size])).toEqual([
      ['boleto.pdf', 4],
    ])
  })

  it('starts the next read window when the previous run started', async () => {
    const windows: Date[] = []
    const owners: Array<string | undefined> = []
    const later = new Date(NOW.getTime() + 300_000)
    const slow: BillSource = {
      source: 'GMAIL',
      fetch: async (_tenant, _entity, since, owner) => {
        windows.push(since)
        owners.push(owner?.taxId)
        deps.clock.set(later)
        return []
      },
    }
    const deps = fullDeps({ billSources: [slow] })
    const capture = makeCaptureSources(deps)
    const mailbox = await capture.completeMailbox(TENANT, 'PF', 'good-code')
    const read = await capture.readMailbox(TENANT, mailbox.id)
    expect(read.mailboxes[0]?.lastReadAt).toBe(NOW.toISOString())
    await capture.readMailbox(TENANT, mailbox.id)
    expect(windows[1]).toEqual(NOW)
    const person = await deps.entities.findById(TENANT, 'pf')
    expect(person?.taxId.value).toMatch(/^\d{11}$/)
    expect(owners).toEqual([person?.taxId.value, person?.taxId.value])
  })

  it('replaces the previous mailbox of an entity', async () => {
    const deps = fullDeps()
    const capture = makeCaptureSources(deps)
    await deps.documents.put(TENANT, MAILBOX_COLLECTION, 'old', {
      id: 'old',
      entityId: 'pf',
      address: 'old@example.com',
      provider: 'GMAIL',
      lastReadAt: null,
      billsFound: 0,
      emailsScanned: 0,
    })
    await capture.completeMailbox(TENANT, 'PF', 'good-code')
    const view = await capture.sources(TENANT)
    expect(view.mailboxes.map(m => m.address)).toEqual(['person@example.com'])
  })

  it('shows the company DDA by default and toggles it', async () => {
    const deps = fullDeps({
      billSources: [source('DDA', [found({ paymentCode: BOLETO_LINE })])],
    })
    const capture = makeCaptureSources(deps)
    expect((await capture.sources(TENANT)).dda).toEqual([
      {
        owner: 'PJ',
        bank: 'C6 Empresas',
        lastBatchAt: null,
        boletos: 0,
        enabled: false,
      },
    ])
    expect((await capture.captureAll(TENANT)).created).toBe(0)
    const on = await capture.setDda(TENANT, 'PJ', true)
    expect(on.dda[0]?.enabled).toBe(true)
    const run = await capture.captureAll(TENANT)
    expect(run).toEqual({ created: 1, failures: [] })
    expect((await capture.sources(TENANT)).dda[0]).toMatchObject({
      boletos: 1,
      lastBatchAt: NOW.toISOString(),
    })
    expect(
      (await capture.setDda(TENANT, 'PF', true)).dda.map(row => row.bank),
    ).toEqual(['C6 Empresas', 'Polp Super DDA'])
  })

  it('collects failures from every source and a missing adapter', async () => {
    const deps = fullDeps({
      billSources: [source('GMAIL', new Error('token revoked'))],
    })
    const capture = makeCaptureSources(deps)
    const mailbox = await capture.completeMailbox(TENANT, 'PJ', 'good-code')
    await capture.setDda(TENANT, 'PJ', true)
    const run = await capture.captureAll(TENANT)
    expect(run.failures).toEqual([
      { source: mailbox.id, reason: 'Error: token revoked' },
      { source: 'dda:pj', reason: expect.stringContaining('DDA') as string },
    ])
    await expect(capture.readMailbox(TENANT, mailbox.id)).rejects.toThrow(
      'token revoked',
    )
  })

  it('labels rows of unknown entities and skips the default without a company', async () => {
    const deps = {
      ...fullDeps(),
      entities: new InMemoryEntityRepository([personal]),
    }
    await deps.documents.put(TENANT, MAILBOX_COLLECTION, 'm', {
      id: 'm',
      entityId: 'ghost',
      address: 'a@example.com',
      provider: 'GMAIL',
      lastReadAt: null,
      billsFound: 0,
      emailsScanned: 0,
    })
    await deps.documents.put(TENANT, DDA_COLLECTION, 'ghost', {
      entityId: 'ghost',
      bank: 'Bank',
      lastBatchAt: null,
      boletos: 0,
      enabled: false,
    })
    const view = await makeCaptureSources(deps).sources(TENANT)
    expect(view.mailboxes[0]?.owner).toBe('PF')
    expect(view.dda).toEqual([
      expect.objectContaining({ owner: 'PJ', bank: 'Bank' }),
    ])
  })
})
