import { type PdfRow, type PdfWriter } from '@cashdeck/application'

const PAGE_WIDTH = 595
const PAGE_HEIGHT = 842
const MARGIN = 56
const LINE = 18

// Helvetica in WinAnsi covers Latin-1; anything outside it prints as '?'.
function latin1(text: string): string {
  return [...text]
    .map(char => (char.charCodeAt(0) <= 0xff ? char : '?'))
    .join('')
    .replace(/[\\()]/g, match => `\\${match}`)
}

function textAt(size: number, y: number, text: string) {
  return `BT /F1 ${size} Tf ${MARGIN} ${y} Td (${latin1(text)}) Tj ET`
}

export class SimplePdfWriter implements PdfWriter {
  render(title: string, rows: readonly PdfRow[]): Uint8Array {
    const top = PAGE_HEIGHT - MARGIN
    const content = [
      textAt(16, top, title),
      ...rows.map(([label, value], index) =>
        textAt(11, top - 2 * LINE - index * LINE, `${label}: ${value}`),
      ),
    ].join('\n')
    const objects = [
      '<< /Type /Catalog /Pages 2 0 R >>',
      '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
      `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${PAGE_WIDTH} ${PAGE_HEIGHT}] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>`,
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>',
      `<< /Length ${Buffer.byteLength(content, 'latin1')} >>\nstream\n${content}\nendstream`,
    ]
    let body = '%PDF-1.4\n'
    const offsets: number[] = []
    objects.forEach((object, index) => {
      offsets.push(Buffer.byteLength(body, 'latin1'))
      body += `${index + 1} 0 obj\n${object}\nendobj\n`
    })
    const xref = Buffer.byteLength(body, 'latin1')
    body += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`
    body += offsets
      .map(offset => `${String(offset).padStart(10, '0')} 00000 n \n`)
      .join('')
    body += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`
    return new Uint8Array(Buffer.from(body, 'latin1'))
  }
}
