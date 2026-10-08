import { describe, expect, it } from 'vitest'
import { ValidationError } from '@cashdeck/domain'
import { base64, fullDeps } from '@/testing/deps.test-helpers'
import {
  BOLETO_LINE,
  PIX_NO_AMOUNT,
  TENANT,
} from '@/testing/scenario.test-helpers'
import { makeCaptureFile } from '@/use-cases/capture-file'

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
  const deps = fullDeps()
  for (const reply of replies) {
    deps.llm.enqueueObject(reply)
  }
  return { deps, captureFile: makeCaptureFile(deps) }
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
})
