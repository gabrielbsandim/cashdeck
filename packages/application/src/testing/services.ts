import { ValidationError } from '@cashdeck/domain'
import {
  type ArchiveEntry,
  type ArchiveWriter,
  type AuthorizedMailbox,
  type CertificateFacts,
  type CertificateFile,
  type CertificateInspector,
  type DocumentFile,
  type DocumentTextReader,
  type MailboxAuthorizer,
  type PdfRow,
  type PdfWriter,
} from '@/ports/services'

export class FakeCertificateInspector implements CertificateInspector {
  constructor(private readonly validUntil: string | null = '2027-03-02') {}

  inspect(file: CertificateFile): CertificateFacts {
    if (file.bytes.length === 0) {
      throw new ValidationError('The certificate file is empty.')
    }
    const isPem =
      file.fileName.endsWith('.crt') || file.fileName.endsWith('.pem')
    return {
      fingerprint: `fp-${file.bytes.length}`,
      validUntil: isPem ? this.validUntil : null,
    }
  }
}

export class FakeArchiveWriter implements ArchiveWriter {
  readonly archives: ArchiveEntry[][] = []

  zip(entries: readonly ArchiveEntry[]): Uint8Array {
    this.archives.push([...entries])
    return new TextEncoder().encode(entries.map(entry => entry.name).join('\n'))
  }
}

export class FakeMailboxAuthorizer implements MailboxAuthorizer {
  readonly provider = 'GMAIL'

  constructor(
    private readonly mailbox: AuthorizedMailbox = {
      address: 'person@example.com',
      refreshToken: 'refresh-token',
    },
  ) {}

  authorizationUrl(state: string): string {
    return `https://accounts.example.com/consent?state=${encodeURIComponent(state)}`
  }

  async exchange(code: string): Promise<AuthorizedMailbox> {
    if (code !== 'good-code') {
      throw new ValidationError('The authorization code was refused.')
    }
    return this.mailbox
  }
}

export class FakePdfWriter implements PdfWriter {
  render(title: string, rows: readonly PdfRow[]): Uint8Array {
    const lines = rows.map(([label, value]) => `${label}: ${value}`)
    return new TextEncoder().encode([title, ...lines].join('\n'))
  }
}

export class FakeDocumentTextReader implements DocumentTextReader {
  readonly reads: DocumentFile[] = []

  constructor(private readonly text: string | null = null) {}

  async read(file: DocumentFile): Promise<string | null> {
    this.reads.push(file)
    return this.text
  }
}
