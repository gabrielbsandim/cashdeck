import {
  type DocumentFile,
  type DocumentTextReader,
} from '@cashdeck/application'
import { extractTextItems, getDocumentProxy } from 'unpdf'

const PDF = 'application/pdf'

// One text item per line keeps a code wrapped over two lines whole, since the
// code finders drop line breaks. A scanned or broken PDF yields null.
export class PdfTextReader implements DocumentTextReader {
  async read(file: DocumentFile): Promise<string | null> {
    if (file.mimeType !== PDF) {
      return null
    }
    for (const password of [undefined, ...(file.passwords ?? [])]) {
      const text = await textOf(file.bytes, password)
      if (text !== null) {
        return text
      }
    }
    return null
  }
}

async function textOf(
  bytes: Uint8Array,
  password: string | undefined,
): Promise<string | null> {
  try {
    const pdf = await getDocumentProxy(new Uint8Array(bytes), {
      verbosity: 0,
      password,
    })
    const { items } = await extractTextItems(pdf)
    return items
      .flat()
      .map(item => item.str)
      .join('\n')
  } catch {
    return null
  }
}
