import 'package:equatable/equatable.dart';

/// An amount in integer cents of an ISO 4217 currency, as the API sends it.
final class Money extends Equatable implements Comparable<Money> {
  const new(this.cents, {this.currency = brl});

  factory brlFromReais(num reais) => Money((reais * 100).round());

  static const brl = 'BRL';

  final int cents;
  final String currency;

  bool get isNegative => cents < 0;

  bool get isForeign => currency != brl;

  Money get abs => Money(cents.abs(), currency: currency);

  Money operator +(Money other) {
    if (other.currency != currency) {
      throw ArgumentError.value(other.currency, 'currency', 'Mixed currencies');
    }
    return Money(cents + other.cents, currency: currency);
  }

  Money operator -(Money other) => this + -other;

  Money operator -() => Money(-cents, currency: currency);

  @override
  int compareTo(Money other) => cents.compareTo(other.cents);

  @override
  List<Object?> get props => [cents, currency];
}
