import { type Deps } from '@/use-cases/deps'

// The adapters' CredentialResolver reads `NAME@entityId`, then `NAME`, then the
// environment; the vault context of a sealed credential is its secret name.
export function credentialName(name: string, entityId: string): string {
  return `${name}@${entityId}`
}

export async function putCredential(
  deps: Pick<Deps, 'secrets' | 'vault'>,
  tenantId: string,
  name: string,
  value: string,
): Promise<void> {
  await deps.secrets.put(tenantId, name, await deps.vault.seal(value, name))
}
