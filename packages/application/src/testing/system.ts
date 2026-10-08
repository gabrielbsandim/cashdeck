import { type Clock, type IdGenerator } from '@/ports/system'

export class FixedClock implements Clock {
  constructor(private current: Date) {}

  now(): Date {
    return new Date(this.current)
  }

  set(next: Date): void {
    this.current = next
  }
}

export class SequentialIdGenerator implements IdGenerator {
  private counter = 0

  constructor(private readonly prefix = 'id') {}

  next(): string {
    this.counter += 1
    return `${this.prefix}_${this.counter}`
  }
}
