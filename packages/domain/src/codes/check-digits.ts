function weightedFromRight(
  digits: string,
  weightAt: (position: number) => number,
): number[] {
  return [...digits]
    .reverse()
    .map((char, position) => Number(char) * weightAt(position))
}

export function mod10(digits: string): number {
  const sum = weightedFromRight(digits, position =>
    position % 2 === 0 ? 2 : 1,
  )
    .map(product => (product > 9 ? product - 9 : product))
    .reduce((total, value) => total + value, 0)
  return (10 - (sum % 10)) % 10
}

function mod11Sum(digits: string): number {
  return weightedFromRight(digits, position => (position % 8) + 2).reduce(
    (total, value) => total + value,
    0,
  )
}

export function mod11Boleto(digits: string): number {
  const dv = 11 - (mod11Sum(digits) % 11)
  return dv === 0 || dv >= 10 ? 1 : dv
}

export function mod11Arrecadacao(digits: string): number {
  const rest = mod11Sum(digits) % 11
  return rest < 2 ? 0 : 11 - rest
}
