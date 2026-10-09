import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/bills/domain/bill.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:equatable/equatable.dart';

/// One page of bills, open ones before settled ones.
final class BillPage extends Equatable {
  const new({required this.bills, this.nextCursor});

  final List<Bill> bills;

  /// Opaque; null on the last page.
  final String? nextCursor;

  @override
  List<Object?> get props => [bills, nextCursor];
}

abstract interface class BillsRepository {
  /// [owner] null lists both entities; [cursor] comes from the last page.
  Future<Result<BillPage>> list({EntityKind? owner, String? cursor});

  Future<Result<Bill>> get(String id);

  /// The user paid it outside the app, from step 3.
  Future<Result<Bill>> markPaid(String id);

  /// Runs the ladder; [confirmed] is true only after the user confirmed in
  /// the app, which is what a capped or new payee payment waits for.
  Future<Result<Bill>> pay(String id, {required bool confirmed});
}
