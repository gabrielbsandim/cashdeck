import {
  type PdfDocument,
  type PdfSection,
  type PdfWriter,
} from '@cashdeck/application'

const PAGE_WIDTH = 595
const PAGE_HEIGHT = 842
const MARGIN = 56
const BAND = 112
const VALUE_X = 200
// Helvetica averages about half its size per character; a little more keeps
// digits and capitals inside the margin.
const VALUE_CHARS = Math.floor((PAGE_WIDTH - MARGIN - VALUE_X) / (11 * 0.56))

type Rgb = readonly [number, number, number]

const BRAND: Rgb = [0.196, 0.388, 0.765]
const INK: Rgb = [0.11, 0.13, 0.17]
const MUTED: Rgb = [0.42, 0.45, 0.5]
const RULE: Rgb = [0.88, 0.9, 0.93]
const ON_BRAND: Rgb = [1, 1, 1]
const ON_BRAND_SOFT: Rgb = [0.85, 0.9, 1]

const rgb = (color: Rgb) => color.map(part => part.toFixed(3)).join(' ')

// Helvetica in WinAnsi covers Latin-1; anything outside it prints as '?'.
// Intl puts thin spaces in times and amounts, so those become plain ones.
function latin1(text: string): string {
  return [...text.replace(/[\u2000-\u200a\u202f]/g, ' ')]
    .map(char => (char.charCodeAt(0) <= 0xff ? char : '?'))
    .join('')
    .replace(/[\\()]/g, match => `\\${match}`)
}

type Font = 'F1' | 'F2'

const text =
  (font: Font, size: number, color: Rgb, x: number, y: number) =>
  (value: string) =>
    `BT /${font} ${size} Tf ${rgb(color)} rg ${x} ${y} Td (${latin1(value)}) Tj ET`

const rule = (y: number) =>
  `${rgb(RULE)} RG 0.8 w ${MARGIN} ${y} m ${PAGE_WIDTH - MARGIN} ${y} l S`

// Breaks at spaces, and inside a word longer than a line, such as a code.
export function wrap(value: string, width = VALUE_CHARS): string[] {
  const lines: string[] = []
  let line = ''
  for (const word of value.split(' ').flatMap(chunksOf(width))) {
    const joined = line ? `${line} ${word}` : word
    if (joined.length <= width) {
      line = joined
      continue
    }
    lines.push(line)
    line = word
  }
  return [...lines, line].filter(Boolean)
}

const chunksOf = (width: number) => (word: string) =>
  word.match(new RegExp(`.{1,${width}}`, 'g')) ?? []

function sectionOps(section: PdfSection, top: number) {
  const ops = [
    text('F2', 12, BRAND, MARGIN, top)(section.heading),
    rule(top - 9),
  ]
  let y = top - 30
  for (const [label, value] of section.rows) {
    ops.push(text('F1', 10, MUTED, MARGIN, y)(label))
    for (const line of wrap(value)) {
      ops.push(text('F1', 11, INK, VALUE_X, y)(line))
      y -= 15
    }
    y -= 7
  }
  return { ops, bottom: y - 16 }
}

function contentOf(document: PdfDocument) {
  const top = PAGE_HEIGHT - BAND
  const ops = [
    `${rgb(BRAND)} rg 0 ${top} ${PAGE_WIDTH} ${BAND} re f`,
    text('F2', 22, ON_BRAND, MARGIN, PAGE_HEIGHT - 54)('Cashdeck'),
    text('F1', 12, ON_BRAND_SOFT, MARGIN, PAGE_HEIGHT - 80)(document.title),
    text('F2', 30, INK, MARGIN, top - 58)(document.amount),
    text('F1', 11, MUTED, MARGIN, top - 80)(document.caption),
  ]
  let y = top - 130
  for (const section of document.sections) {
    const drawn = sectionOps(section, y)
    ops.push(...drawn.ops)
    y = drawn.bottom
  }
  ops.push(
    rule(MARGIN + 18),
    text('F1', 9, MUTED, MARGIN, MARGIN)(document.footer),
  )
  return ops.join('\n')
}

export class SimplePdfWriter implements PdfWriter {
  render(document: PdfDocument): Uint8Array {
    const content = contentOf(document)
    const font = (name: string) =>
      `<< /Type /Font /Subtype /Type1 /BaseFont /${name} /Encoding /WinAnsiEncoding >>`
    const objects = [
      '<< /Type /Catalog /Pages 2 0 R >>',
      '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
      `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${PAGE_WIDTH} ${PAGE_HEIGHT}] /Resources << /Font << /F1 4 0 R /F2 6 0 R >> >> /Contents 5 0 R >>`,
      font('Helvetica'),
      `<< /Length ${Buffer.byteLength(content, 'latin1')} >>\nstream\n${content}\nendstream`,
      font('Helvetica-Bold'),
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
