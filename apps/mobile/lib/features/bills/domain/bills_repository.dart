import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/bills/domain/bill.dart';

abstract interface class BillsRepository {
  Future<Result<List<Bill>>> list();

  Future<Result<Bill>> get(String id);

  /// The user paid it outside the app, from step 3.
  Future<Result<Bill>> markPaid(String id);

  /// The in-app confirmation a capped payment waits for before step 1.
  Future<Result<Bill>> confirmPayment(String id);
}
