import { ValidationError } from '@/shared/domain-error'

export type CurrencyCode = string

const CURRENCY_PATTERN = /^[A-Z]{3}$/

export class Money {
  private constructor(
    readonly cents: number,
    readonly currency: CurrencyCode,
  ) {}

  static of(cents: number, currency: CurrencyCode = 'BRL'): Money {
    if (!Number.isSafeInteger(cents)) {
      throw new ValidationError('Money must be an integer amount of cents.')
    }
    if (!CURRENCY_PATTERN.test(currency)) {
      throw new ValidationError('Currency must be an ISO 4217 code.')
    }
    return new Money(cents, currency)
  }

  static zero(currency: CurrencyCode = 'BRL'): Money {
    return Money.of(0, currency)
  }

  static fromDecimal(value: string, currency: CurrencyCode = 'BRL'): Money {
    const match = /^(-)?(\d+)(?:\.(\d{1,2}))?$/.exec(value.trim())
    if (!match) {
      throw new ValidationError(`"${value}" is not a decimal amount.`)
    }
    const [, sign, whole, fraction = ''] = match
    const cents = Number(whole) * 100 + Number(fraction.padEnd(2, '0'))
    return Money.of(sign ? -cents : cents, currency)
  }

  add(other: Money): Money {
    this.assertSameCurrency(other)
    return Money.of(this.cents + other.cents, this.currency)
  }

  subtract(other: Money): Money {
    this.assertSameCurrency(other)
    return Money.of(this.cents - other.cents, this.currency)
  }

  negate(): Money {
    return Money.of(-this.cents, this.currency)
  }

  isZero(): boolean {
    return this.cents === 0
  }

  isNegative(): boolean {
    return this.cents < 0
  }

  isPositive(): boolean {
    return this.cents > 0
  }

  compare(other: Money): -1 | 0 | 1 {
    this.assertSameCurrency(other)
    return Math.sign(this.cents - other.cents) as -1 | 0 | 1
  }

  equals(other: Money): boolean {
    return this.currency === other.currency && this.cents === other.cents
  }

  toDecimal(): string {
    const sign = this.cents < 0 ? '-' : ''
    const absolute = Math.abs(this.cents)
    const fraction = String(absolute % 100).padStart(2, '0')
    return `${sign}${Math.floor(absolute / 100)}.${fraction}`
  }

  toJSON(): { cents: number; currency: CurrencyCode } {
    return { cents: this.cents, currency: this.currency }
  }

  private assertSameCurrency(other: Money): void {
    if (other.currency !== this.currency) {
      throw new ValidationError(
        `Cannot combine ${this.currency} with ${other.currency}.`,
      )
    }
  }
}
