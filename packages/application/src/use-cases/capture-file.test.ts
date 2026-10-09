import { describe, expect, it, vi } from 'vitest'
import { encodeBrCode, Money, ValidationError } from '@cashdeck/domain'
import { ProviderNotConfiguredError } from '@/errors/errors'
import { base64, fullDeps } from '@/testing/deps.test-helpers'
import {
  BOLETO_BARCODE,
  BOLETO_LINE,
  PIX_NO_AMOUNT,
  TENANT,
} from '@/testing/scenario.test-helpers'
import { FakeDocumentTextReader } from '@/testing/services'
import { makeCaptureFile } from '@/use-cases/capture-file'

const PIX_OF_BOLETO = encodeBrCode({
  key: '11222333000181',
  merchantName: 'Fornecedor Exemplo',
  merchantCity: 'SAO PAULO',
  amount: Money.of(12345),
  txid: 'FAT6304BEEF01',
})

const upload = {
  entity: 'PF' as const,
  fileName: 'bill.pdf',
  mimeType: 'application/pdf',
  base64: base64('pdf'),
}

const reading = (overrides: Record<string, unknown> = {}) => ({
  paymentCode: BOLETO_LINE,
  pixCode: '',
  payee: 'Supplier',
  amount: 0,
  dueDate: '',
  ...overrides,
})

function setup(...replies: unknown[]) {
  return withText(null, ...replies)
}

function withText(text: string | null, ...replies: unknown[]) {
  const documentText = new FakeDocumentTextReader(text)
  const deps = fullDeps({ documentText })
  for (const reply of replies) {
    deps.llm.enqueueObject(reply)
  }
  return { deps, documentText, captureFile: makeCaptureFile(deps) }
}

describe('capture from a shared file', () => {
  it('reads the code, captures the bill and keeps the file', async () => {
    const { deps, captureFile } = setup(reading(), reading())
    const result = await captureFile(TENANT, upload)
    expect(result.duplicate).toBe(false)
    expect(result.bill).toMatchObject({ source: 'SHARE', payee: 'Supplier' })
    const files = await deps.attachments.list(TENANT, result.bill.id)
    expect(files.map(file => [file.fileName, file.size])).toEqual([
      ['bill.pdf', 3],
    ])
    expect(deps.llm.calls[0]?.messages[0]?.attachments).toEqual([
      { mimeType: 'application/pdf', dataBase64: upload.base64 },
    ])
    const again = await captureFile(TENANT, upload)
    expect(again.duplicate).toBe(true)
    expect(await deps.attachments.list(TENANT, result.bill.id)).toHaveLength(1)
  })

  it('takes a Pix code with the amount and due date it printed', async () => {
    const { captureFile } = setup(
      reading({
        paymentCode: ' ',
        pixCode: PIX_NO_AMOUNT,
        amount: 123.45,
        dueDate: '2026-10-20',
      }),
    )
    const { bill } = await captureFile(TENANT, upload)
    expect(bill).toMatchObject({ kind: 'PIX_QR', dueDate: '2026-10-20' })
    expect(bill.amount.cents).toBe(12345)
  })

  it('refuses an unreadable file or one without a code', async () => {
    await expect(setup({}).captureFile(TENANT, upload)).rejects.toThrow(
      'The file could not be read.',
    )
    await expect(
      setup(reading({ paymentCode: '' })).captureFile(TENANT, upload),
    ).rejects.toThrow(ValidationError)
  })

  it('drops a mistyped Pix code and keeps the barcode bill', async () => {
    const { captureFile } = setup(
      reading({ pixCode: PIX_NO_AMOUNT.slice(0, -1) + 'X' }),
    )
    const { bill } = await captureFile(TENANT, upload)
    expect(bill).toMatchObject({ kind: 'BOLETO', pixCode: null })
  })

  it('keeps the barcode when the Pix amount disagrees', async () => {
    const pix = encodeBrCode({
      key: 'k@example.com',
      merchantName: 'Other',
      merchantCity: 'City',
      amount: Money.of(1),
    })
    const { captureFile } = setup(reading({ pixCode: pix }))
    const { bill } = await captureFile(TENANT, upload)
    expect(bill).toMatchObject({ code: BOLETO_BARCODE, pixCode: null })
  })

  it('prefers the codes in the text layer over the model reading', async () => {
    const { captureFile, documentText } = withText(
      `Linha digitavel ${BOLETO_LINE}\nPix copia e cola:\n${PIX_OF_BOLETO}`,
      reading({ paymentCode: '123', pixCode: PIX_OF_BOLETO.slice(0, 120) }),
    )
    const { bill } = await captureFile(TENANT, upload)
    expect(bill).toMatchObject({
      code: BOLETO_BARCODE,
      pixCode: PIX_OF_BOLETO,
      payee: 'Supplier',
    })
    expect(documentText.reads[0]?.mimeType).toBe('application/pdf')
  })

  it('captures from the text layer when the model fails or says nothing', async () => {
    const failing = withText(BOLETO_LINE)
    vi.spyOn(failing.deps.llm, 'chat').mockRejectedValueOnce(
      new ProviderNotConfiguredError('AI'),
    )
    const { bill } = await failing.captureFile(TENANT, upload)
    expect(bill).toMatchObject({ code: BOLETO_BARCODE, payee: null })

    const silent = withText(`Pix: ${PIX_NO_AMOUNT}`, {})
    await expect(silent.captureFile(TENANT, upload)).rejects.toMatchObject({
      code: 'AMOUNT_REQUIRED',
    })
  })

  it('surfaces a model failure when the text layer has no code', async () => {
    const { deps, captureFile } = setup()
    vi.spyOn(deps.llm, 'chat').mockRejectedValueOnce(
      new ProviderNotConfiguredError('AI'),
    )
    await expect(captureFile(TENANT, upload)).rejects.toThrow(
      ProviderNotConfiguredError,
    )
  })

  it('takes the amount and due date the client sends after AMOUNT_REQUIRED', async () => {
    const { captureFile } = setup(
      reading({
        paymentCode: '',
        pixCode: PIX_NO_AMOUNT,
        dueDate: '20/10/2026',
      }),
      reading({ paymentCode: '', pixCode: PIX_NO_AMOUNT, amount: 9 }),
    )
    await expect(captureFile(TENANT, upload)).rejects.toMatchObject({
      code: 'AMOUNT_REQUIRED',
    })
    const { bill } = await captureFile(TENANT, {
      ...upload,
      amountCents: 4500,
      dueDate: '2026-10-21',
    })
    expect(bill).toMatchObject({ dueDate: '2026-10-21' })
    expect(bill.amount.cents).toBe(4500)
  })
})
