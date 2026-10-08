import { type ArchiveEntry, type ArchiveWriter } from '@cashdeck/application'

const CRC_TABLE = Array.from({ length: 256 }, (_, index) => {
  let value = index
  for (let bit = 0; bit < 8; bit += 1) {
    value = value & 1 ? 0xedb88320 ^ (value >>> 1) : value >>> 1
  }
  return value >>> 0
})

export function crc32(bytes: Uint8Array): number {
  let crc = 0xffffffff
  for (const byte of bytes) {
    crc = (CRC_TABLE[(crc ^ byte) & 0xff] as number) ^ (crc >>> 8)
  }
  return (crc ^ 0xffffffff) >>> 0
}

const encoder = new TextEncoder()
// 1980-01-01, the earliest DOS date: the archive is reproducible.
const DOS_DATE = 0x21
const UTF8_NAMES = 0x0800

type Header = {
  name: Uint8Array
  data: Uint8Array
  crc: number
  offset: number
}

function localHeader(entry: Header): Uint8Array {
  const header = new DataView(new ArrayBuffer(30))
  header.setUint32(0, 0x04034b50, true)
  header.setUint16(4, 20, true)
  header.setUint16(6, UTF8_NAMES, true)
  header.setUint16(12, DOS_DATE, true)
  header.setUint32(14, entry.crc, true)
  header.setUint32(18, entry.data.length, true)
  header.setUint32(22, entry.data.length, true)
  header.setUint16(26, entry.name.length, true)
  return new Uint8Array(header.buffer)
}

function centralHeader(entry: Header): Uint8Array {
  const header = new DataView(new ArrayBuffer(46))
  header.setUint32(0, 0x02014b50, true)
  header.setUint16(4, 20, true)
  header.setUint16(6, 20, true)
  header.setUint16(8, UTF8_NAMES, true)
  header.setUint16(14, DOS_DATE, true)
  header.setUint32(16, entry.crc, true)
  header.setUint32(20, entry.data.length, true)
  header.setUint32(24, entry.data.length, true)
  header.setUint16(28, entry.name.length, true)
  header.setUint32(42, entry.offset, true)
  return new Uint8Array(header.buffer)
}

function endOfDirectory(
  count: number,
  size: number,
  offset: number,
): Uint8Array {
  const end = new DataView(new ArrayBuffer(22))
  end.setUint32(0, 0x06054b50, true)
  end.setUint16(8, count, true)
  end.setUint16(10, count, true)
  end.setUint32(12, size, true)
  end.setUint32(16, offset, true)
  return new Uint8Array(end.buffer)
}

function concat(parts: readonly Uint8Array[]): Uint8Array {
  const out = new Uint8Array(parts.reduce((sum, part) => sum + part.length, 0))
  let at = 0
  for (const part of parts) {
    out.set(part, at)
    at += part.length
  }
  return out
}

// Stored entries (no compression): CSVs and PDFs are small, and stored ZIPs
// open everywhere.
export class StoredZipWriter implements ArchiveWriter {
  zip(entries: readonly ArchiveEntry[]): Uint8Array {
    const local: Uint8Array[] = []
    const headers: Header[] = []
    let offset = 0
    for (const entry of entries) {
      const data =
        typeof entry.content === 'string'
          ? encoder.encode(entry.content)
          : entry.content
      const header = {
        name: encoder.encode(entry.name),
        data,
        crc: crc32(data),
        offset,
      }
      local.push(localHeader(header), header.name, data)
      offset += 30 + header.name.length + data.length
      headers.push(header)
    }
    const central = concat(
      headers.flatMap(header => [centralHeader(header), header.name]),
    )
    return concat([
      ...local,
      central,
      endOfDirectory(headers.length, central.length, offset),
    ])
  }
}
