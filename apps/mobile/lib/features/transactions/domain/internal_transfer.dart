import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:equatable/equatable.dart';

enum TransferKind { profitDistribution, proLabore }

final class TransferParty extends Equatable {
  const new({required this.owner, required this.holder, required this.account});

  final EntityKind owner;
  final String holder;
  final String account;

  @override
  List<Object?> get props => [owner, holder, account];
}

/// Money between the company and the person. A profit distribution is
/// neutral on both sides; a pro-labore is the company's expense and the
/// person's income.
final class TransferDetail extends Equatable {
  const new({
    required this.id,
    required this.kind,
    required this.amount,
    required this.at,
    required this.rail,
    required this.from,
    required this.to,
    this.document,
  });

  final String id;
  final TransferKind kind;
  final Money amount;
  final DateTime at;
  final String rail;
  final TransferParty from;
  final TransferParty to;

  /// The file that backs it, such as the distribution minutes.
  final String? document;

  bool get neutral => kind == TransferKind.profitDistribution;

  @override
  List<Object?> get props => [id, kind, amount, at, rail, from, to, document];
}

abstract interface class TransfersRepository {
  Future<Result<TransferDetail>> transfer(String id);
}
