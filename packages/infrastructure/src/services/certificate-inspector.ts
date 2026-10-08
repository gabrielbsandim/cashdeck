import { createHash, X509Certificate } from 'node:crypto'
import {
  type CertificateFacts,
  type CertificateFile,
  type CertificateInspector,
} from '@cashdeck/application'
import { ValidationError } from '@cashdeck/domain'

const PEM_MARKER = '-----BEGIN CERTIFICATE-----'

// A PKCS#12 bundle needs its password to show the expiry; PEM and DER do not.
export class X509CertificateInspector implements CertificateInspector {
  inspect(file: CertificateFile): CertificateFacts {
    if (file.bytes.length === 0) {
      throw new ValidationError('The certificate file is empty.')
    }
    const fingerprint = createHash('sha256').update(file.bytes).digest('hex')
    const certificate = this.parse(file)
    if (!certificate) {
      return { fingerprint, validUntil: null }
    }
    return {
      fingerprint: certificate.fingerprint256.replaceAll(':', '').toLowerCase(),
      validUntil: new Date(certificate.validTo).toISOString().slice(0, 10),
    }
  }

  private parse(file: CertificateFile): X509Certificate | null {
    const text = new TextDecoder().decode(file.bytes)
    const isPem = text.includes(PEM_MARKER)
    if (/\.(pfx|p12)$/i.test(file.fileName) && !isPem) {
      return null
    }
    try {
      return new X509Certificate(isPem ? text : Buffer.from(file.bytes))
    } catch {
      throw new ValidationError('The certificate file could not be read.')
    }
  }
}
