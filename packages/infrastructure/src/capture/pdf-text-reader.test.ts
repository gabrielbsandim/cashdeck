import { describe, expect, it } from 'vitest'
import { findPaymentCodes } from '@cashdeck/domain'
import { PdfTextReader } from '@/capture/pdf-text-reader'
import { BOLETO_LINE, STATIC_PIX, TODAY } from '@/testing/provider-fixtures'

// A one page PDF with one Helvetica text line per entry, like a boleto that
// wraps its Pix copy and paste code.
function pdfWithLines(lines: string[]): Uint8Array {
  const content = lines
    .map(
      (line, index) => `BT /F1 9 Tf 40 ${780 - index * 14} Td (${line}) Tj ET`,
    )
    .join('\n')
  const objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    `<< /Length ${content.length} >>\nstream\n${content}\nendstream`,
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
  body += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`
  return new TextEncoder().encode(body)
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

  it('answers null for a photo or a broken file', async () => {
    const bytes = new TextEncoder().encode('not a pdf')
    expect(await reader.read({ mimeType: 'image/png', bytes })).toBeNull()
    expect(await reader.read({ mimeType: 'application/pdf', bytes })).toBeNull()
  })
})
