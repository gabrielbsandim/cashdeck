export function isNeonConnectionString(connectionString: string): boolean {
  let hostname = ''

  try {
    hostname = new URL(connectionString).hostname
  } catch {
    // Not a URL, so not a Neon host either; Prisma reports the string itself.
  }

  return hostname.toLowerCase().endsWith('.neon.tech')
}
