export function onlyDigits(value: string): string {
  return value.replace(/\D/g, '')
}

export function digitAt(value: string, index: number): number {
  return Number(value.charAt(index))
}
