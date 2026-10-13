import 'package:cashdeck/core/network/guard_request.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/bills/data/bill_dtos.dart';
import 'package:cashdeck/features/bills/domain/bill.dart';
import 'package:cashdeck/features/bills/domain/bills_repository.dart';
import 'package:cashdeck/features/entities/data/entity_directory.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:dio/dio.dart';

final class ApiBillsRepository implements BillsRepository {
  new(this._dio, {this.pageSize = 50}) : _entities = EntityDirectory(_dio);

  final Dio _dio;
  final EntityDirectory _entities;
  final int pageSize;

  static const path = '/api/v1/bills';

  /// The server sorts by due date and filters one status at a time, so the
  /// list walks the statuses that need the user first and settled ones last.
  static const statusOrder = [
    'NEEDS_CONFIRMATION',
    'AWAITING_BANK_APPROVAL',
    'ASSISTED',
    'OPEN',
    'PROCESSING',
    'PAID',
    'CANCELLED',
  ];

  @override
  Future<Result<BillPage>> list({EntityKind? owner, String? cursor}) =>
      guardRequest(() async {
        final entityId = owner == null ? null : await _entities.idOf(owner);
        BillsCursor? position = BillsCursor.parse(cursor);
        // The first page asks every status at once; an answer holding more than
        // the page still needs is asked again so the cursor stays exact.
        final ahead = cursor == null
            ? await Future.wait([
                for (final status in statusOrder)
                  _page(status, pageSize, entityId, null),
              ])
            : const <_StatusPage>[];
        final bills = <Bill>[];
        while (position != null && bills.length < pageSize) {
          final wanted = pageSize - bills.length;
          final page =
              _reusable(ahead, position, wanted) ??
              await _page(
                statusOrder[position.status],
                wanted,
                entityId,
                position.server,
              );
          bills.addAll(page.bills);
          position = position.next(page.nextCursor);
        }
        return BillPage(bills: bills, nextCursor: position?.encode());
      });

  Future<_StatusPage> _page(
    String status,
    int limit,
    String? entityId,
    String? cursor,
  ) async {
    final response = await _dio.get<Object?>(
      path,
      queryParameters: {
        'status': status,
        'limit': limit,
        'entityId': ?entityId,
        'cursor': ?cursor,
      },
    );
    final body = asJsonMap(response.data);
    return (
      bills: readMapList(body, 'data').map(billFromJson).toList(),
      nextCursor: readOptionalString(body, 'nextCursor'),
    );
  }

  /// The prefetched answer, when it is exactly what the walk would ask for.
  _StatusPage? _reusable(
    List<_StatusPage> ahead,
    BillsCursor position,
    int wanted,
  ) {
    if (ahead.isEmpty || position.server != null) return null;
    final page = ahead[position.status];
    final whole = page.nextCursor == null && page.bills.length <= wanted;
    return wanted == pageSize || whole ? page : null;
  }

  @override
  Future<Result<Bill>> get(String id) => guardRequest(() async {
    final response = await _dio.get<Object?>(
      '$path/${Uri.encodeComponent(id)}',
    );
    return billFromJson(asJsonMap(unwrapData(response.data)));
  });

  @override
  Future<Result<Bill>> markPaid(String id) => guardRequest(() async {
    final response = await _dio.post<Object?>(
      '$path/${Uri.encodeComponent(id)}/mark-paid',
      data: const <String, Object?>{},
    );
    return billFromJson(asJsonMap(unwrapData(response.data)));
  });

  @override
  Future<Result<Bill>> markUnpaid(String id) => guardRequest(() async {
    final response = await _dio.post<Object?>(
      '$path/${Uri.encodeComponent(id)}/mark-unpaid',
    );
    return billFromJson(asJsonMap(unwrapData(response.data)));
  });

  @override
  Future<Result<Bill>> pay(String id, {required bool confirmed}) =>
      guardRequest(() async {
        final response = await _dio.post<Object?>(
          '$path/${Uri.encodeComponent(id)}/pay',
          data: {'confirmed': confirmed},
        );
        return billFromJson(asJsonMap(unwrapData(response.data)));
      });

  @override
  Future<Result<Bill>> setAutoDebit(String id, {required bool enabled}) =>
      guardRequest(() async {
        final response = await _dio.put<Object?>(
          '$path/${Uri.encodeComponent(id)}/auto-debit',
          data: {'enabled': enabled},
        );
        return billFromJson(asJsonMap(unwrapData(response.data)));
      });

  @override
  Future<Result<Bill>> reschedule(String id, CalendarDate dueDate) =>
      guardRequest(() async {
        final response = await _dio.put<Object?>(
          '$path/${Uri.encodeComponent(id)}/due-date',
          data: {'dueDate': dueDate.iso},
        );
        return billFromJson(asJsonMap(unwrapData(response.data)));
      });

  @override
  Future<Result<Bill>> reconcile(String id) => guardRequest(() async {
    final response = await _dio.post<Object?>(
      '$path/${Uri.encodeComponent(id)}/reconcile',
    );
    return billFromJson(asJsonMap(unwrapData(response.data)));
  });
}

typedef _StatusPage = ({List<Bill> bills, String? nextCursor});

/// Where the walk over [ApiBillsRepository.statusOrder] stopped: the status
/// index and the server's own cursor inside it. Travels as `index:cursor`.
final class BillsCursor {
  const new(this.status, [this.server]);

  /// The first page starts at the first status; anything unreadable is a
  /// format error.
  factory parse(String? raw) {
    if (raw == null) return const BillsCursor(0);
    final split = raw.indexOf(':');
    final head = split < 0 ? raw : raw.substring(0, split);
    final status = int.tryParse(head) ?? -1;
    if (status < 0 || status >= ApiBillsRepository.statusOrder.length) {
      throw FormatException('Invalid bills cursor', raw);
    }
    return BillsCursor(status, split < 0 ? null : raw.substring(split + 1));
  }

  final int status;
  final String? server;

  /// Null once the last status has no more pages.
  BillsCursor? next(String? serverCursor) {
    if (serverCursor != null) return BillsCursor(status, serverCursor);
    final following = status + 1;
    if (following >= ApiBillsRepository.statusOrder.length) return null;
    return BillsCursor(following);
  }

  String encode() => switch (server) {
    null => '$status',
    final cursor => '$status:$cursor',
  };
}
