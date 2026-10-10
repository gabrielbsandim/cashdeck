import { createHash } from 'node:crypto'
import { describe, expect, it } from 'vitest'
import { findPaymentCodes } from '@cashdeck/domain'
import { PdfTextReader } from '@/capture/pdf-text-reader'
import { BOLETO_LINE, STATIC_PIX, TODAY } from '@/testing/provider-fixtures'

// A one page PDF with one Helvetica text line per entry, like a boleto that
// wraps its Pix copy and paste code.
const PAD = Buffer.from(
  '28bf4e5e4e758a4164004e56fffa01082e2e00b6d0683e802f0ca9fe6453697a',
  'hex',
)
const FILE_ID = Buffer.from('00112233445566778899aabbccddeeff', 'hex')
const PERMISSIONS = -4

function rc4(key: Buffer, data: Buffer): Buffer {
  const box = Array.from({ length: 256 }, (_, index) => index)
  let j = 0
  for (let i = 0; i < 256; i += 1) {
    j = (j + (box[i] ?? 0) + (key[i % key.length] ?? 0)) % 256
    ;[box[i], box[j]] = [box[j] ?? 0, box[i] ?? 0]
  }
  const out = Buffer.alloc(data.length)
  let a = 0
  let b = 0
  for (let index = 0; index < data.length; index += 1) {
    a = (a + 1) % 256
    b = (b + (box[a] ?? 0)) % 256
    ;[box[a], box[b]] = [box[b] ?? 0, box[a] ?? 0]
    const k = box[((box[a] ?? 0) + (box[b] ?? 0)) % 256] ?? 0
    out[index] = (data[index] ?? 0) ^ k
  }
  return out
}

const md5 = (...parts: Buffer[]) =>
  createHash('md5').update(Buffer.concat(parts)).digest()

const padded = (password: string) =>
  Buffer.concat([Buffer.from(password, 'latin1'), PAD]).subarray(0, 32)

// The standard security handler, revision 2 (RC4, 40 bit), as old billing
// systems still write it: enough to prove the reader opens a locked PDF.
function locked(password: string) {
  const owner = rc4(md5(padded(password)).subarray(0, 5), padded(password))
  const permissions = Buffer.alloc(4)
  permissions.writeInt32LE(PERMISSIONS)
  const key = md5(padded(password), owner, permissions, FILE_ID).subarray(0, 5)
  return {
    owner,
    user: rc4(key, PAD),
    stream: (objectNumber: number, data: Buffer) => {
      const id = Buffer.from([objectNumber & 0xff, objectNumber >> 8, 0, 0, 0])
      return rc4(md5(key, id).subarray(0, 10), data)
    },
  }
}

function pdfWithLines(lines: string[], password?: string): Uint8Array {
  const content = lines
    .map(
      (line, index) => `BT /F1 9 Tf 40 ${780 - index * 14} Td (${line}) Tj ET`,
    )
    .join('\n')
  const lock = password === undefined ? null : locked(password)
  const stream = lock
    ? lock.stream(5, Buffer.from(content, 'latin1')).toString('latin1')
    : content
  const objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    `<< /Length ${stream.length} >>\nstream\n${stream}\nendstream`,
    ...(lock
      ? [
          `<< /Filter /Standard /V 1 /R 2 /O <${lock.owner.toString('hex')}> /U <${lock.user.toString('hex')}> /P ${PERMISSIONS} >>`,
        ]
      : []),
  ]
  let body = '%PDF-1.4\n'
  const offsets = objects.map((object, index) => {
    const offset = body.length
    body += `${index + 1} 0 obj\n${object}\nendobj\n`
    return offset
  })
  const xref = body.length
  body += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`
  body += offsets
    .map(offset => `${String(offset).padStart(10, '0')} 00000 n \n`)
    .join('')
  const encrypt = lock
    ? ` /Encrypt 6 0 R /ID [<${FILE_ID.toString('hex')}> <${FILE_ID.toString('hex')}>]`
    : ''
  body += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R${encrypt} >>\nstartxref\n${xref}\n%%EOF\n`
  return Buffer.from(body, 'latin1')
}

describe('PdfTextReader', () => {
  const reader = new PdfTextReader()

  it('reads the codes of a PDF, a wrapped Pix code included', async () => {
    const bytes = pdfWithLines([
      'Linha digitavel',
      BOLETO_LINE,
      'Pix copia e cola',
      STATIC_PIX.slice(0, 60),
      STATIC_PIX.slice(60),
    ])
    const text = await reader.read({ mimeType: 'application/pdf', bytes })
    expect(findPaymentCodes(text ?? '', TODAY)).toEqual({
      barcode: BOLETO_LINE,
      pixCode: STATIC_PIX,
    })
  })

  it('opens a locked PDF with the password that fits', async () => {
    const bytes = pdfWithLines(['Linha digitavel', BOLETO_LINE], '5299')
    expect(await reader.read({ mimeType: 'application/pdf', bytes })).toBeNull()
    expect(
      await reader.read({
        mimeType: 'application/pdf',
        bytes,
        passwords: ['1234'],
      }),
    ).toBeNull()
    const text = await reader.read({
      mimeType: 'application/pdf',
      bytes,
      passwords: ['1234', '5299'],
    })
    expect(findPaymentCodes(text ?? '', TODAY).barcode).toBe(BOLETO_LINE)
  })

  it('answers null for a photo or a broken file', async () => {
    const bytes = new TextEncoder().encode('not a pdf')
    expect(await reader.read({ mimeType: 'image/png', bytes })).toBeNull()
    expect(await reader.read({ mimeType: 'application/pdf', bytes })).toBeNull()
  })
})
