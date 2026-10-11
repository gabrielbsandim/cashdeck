import 'package:cashdeck/core/network/guard_request.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/pix_contacts/data/pix_contact_dtos.dart';
import 'package:cashdeck/features/pix_contacts/domain/pix_contact.dart';
import 'package:dio/dio.dart';

final class ApiPixContactsRepository implements PixContactsRepository {
  const new(this._dio);

  final Dio _dio;

  static const path = '/api/v1/pix-contacts';

  String _contact(String id) => '$path/${Uri.encodeComponent(id)}';

  @override
  Future<Result<List<PixContact>>> list({String? search}) =>
      guardRequest(() async {
        final response = await _dio.get<Object?>(
          path,
          queryParameters: {'search': ?search},
        );
        return asJsonMapList(unwrapData(response.data))
            .map(pixContactFromJson)
            .toList();
      });

  @override
  Future<Result<PixContact>> create(PixContactDraft draft) =>
      guardRequest(() async {
        final response = await _dio.post<Object?>(
          path,
          data: pixContactDraftToJson(draft),
        );
        return pixContactFromJson(asJsonMap(unwrapData(response.data)));
      });

  @override
  Future<Result<PixContact>> update(String id, PixContactDraft draft) =>
      guardRequest(() async {
        final response = await _dio.patch<Object?>(
          _contact(id),
          data: pixContactDraftToJson(draft),
        );
        return pixContactFromJson(asJsonMap(unwrapData(response.data)));
      });

  @override
  Future<Result<void>> delete(String id) =>
      guardRequest(() => _dio.delete<Object?>(_contact(id)));
}
