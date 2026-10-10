import { type LocalDate } from '@cashdeck/domain'

export type CertificateFile = { fileName: string; bytes: Uint8Array }

export type CertificateFacts = {
  fingerprint: string
  // Null when the format hides it (a PKCS#12 file without its password).
  validUntil: LocalDate | null
}

export interface CertificateInspector {
  inspect(file: CertificateFile): CertificateFacts
}

export type ArchiveEntry = { name: string; content: string | Uint8Array }

export interface ArchiveWriter {
  zip(entries: readonly ArchiveEntry[]): Uint8Array
}

export type AuthorizedMailbox = { address: string; refreshToken: string }

export interface MailboxAuthorizer {
  readonly provider: string
  authorizationUrl(state: string): string
  exchange(code: string): Promise<AuthorizedMailbox>
}

export type PdfRow = readonly [label: string, value: string]

export interface PdfWriter {
  render(title: string, rows: readonly PdfRow[]): Uint8Array
}

// Passwords to try on a protected PDF, such as prefixes of the owner's tax id.
export type DocumentFile = {
  mimeType: string
  bytes: Uint8Array
  passwords?: readonly string[]
}

export interface DocumentTextReader {
  // Null when the file has no text layer the reader understands (a photo).
  read(file: DocumentFile): Promise<string | null>
}
