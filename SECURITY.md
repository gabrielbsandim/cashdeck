# Security

Please report vulnerabilities privately through GitHub security advisories on
this repository rather than in a public issue.

Cashdeck handles bank credentials and can move money, so the design keeps a few
rules:

- Provider tokens, client certificates and the NFS-e certificate are sealed
  with envelope encryption (`EnvelopeSecretVault`, AES-256-GCM). The master key
  lives only in the environment (`CASHDECK_MASTER_KEY`).
- Automatic payments respect per-rail daily caps, ask for confirmation on a new
  payee or above a threshold, and stop entirely under the kill switch.
- Every payment attempt writes an audit event with rail, idempotency key and
  result.
- Error reporting is off unless `SENTRY_DSN` is set; no telemetry is sent by
  default.
