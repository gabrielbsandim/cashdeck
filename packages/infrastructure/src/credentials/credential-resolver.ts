import {
  ProviderNotConfiguredError,
  type SecretStore,
  type SecretVault,
} from '@cashdeck/application'

export type CredentialScope = { tenantId?: string; entityId?: string }

export interface Credentials {
  get(name: string, scope?: CredentialScope): Promise<string | null>
}

export type CredentialResolverOptions = {
  env: Record<string, string | undefined>
  tenantId: string
  secrets?: SecretStore
  vault?: SecretVault
}

// A credential uploaded in the app is sealed under `NAME@entityId` (or `NAME`
// for the whole tenant) with the secret name as the vault context.
export function credentialSecretName(name: string, entityId?: string): string {
  return entityId ? `${name}@${entityId}` : name
}

export class CredentialResolver implements Credentials {
  constructor(private readonly options: CredentialResolverOptions) {}

  async get(name: string, scope: CredentialScope = {}): Promise<string | null> {
    const sealed = await this.sealed(name, scope)
    if (sealed !== null) {
      return sealed
    }
    return this.options.env[name]?.trim() || null
  }

  private async sealed(
    name: string,
    scope: CredentialScope,
  ): Promise<string | null> {
    const { secrets, vault } = this.options
    if (!secrets || !vault) {
      return null
    }
    const tenantId = scope.tenantId ?? this.options.tenantId
    const names = scope.entityId
      ? [credentialSecretName(name, scope.entityId), name]
      : [name]
    for (const secretName of names) {
      const value = await secrets.get(tenantId, secretName)
      if (value !== null) {
        return vault.open(value, secretName)
      }
    }
    return null
  }
}

export async function requireCredentials<K extends string>(
  credentials: Credentials,
  provider: string,
  names: readonly K[],
  scope: CredentialScope = {},
): Promise<Record<K, string>> {
  const values = await Promise.all(
    names.map(name => credentials.get(name, scope)),
  )
  if (values.some(value => value === null)) {
    throw new ProviderNotConfiguredError(provider)
  }
  return Object.fromEntries(
    names.map((name, index) => [name, values[index]]),
  ) as Record<K, string>
}

export async function optionalCredential(
  credentials: Credentials,
  name: string,
  fallback: string,
  scope: CredentialScope = {},
): Promise<string> {
  return (await credentials.get(name, scope)) ?? fallback
}
