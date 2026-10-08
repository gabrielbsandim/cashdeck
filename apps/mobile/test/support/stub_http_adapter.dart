import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

typedef StubHandler = StubResponse Function(RequestOptions options);

final class StubResponse {
  const new(this.statusCode, [this.body]);

  final int statusCode;
  final Object? body;
}

final class StubHttpAdapter implements HttpClientAdapter {
  new(this._handler);

  final StubHandler _handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final response = _handler(options);
    return ResponseBody.fromString(
      jsonEncode(response.body),
      response.statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio stubDio(StubHandler handler, {String baseUrl = 'https://api.test'}) {
  return Dio(BaseOptions(baseUrl: baseUrl))
    ..httpClientAdapter = StubHttpAdapter(handler);
}

StubHttpAdapter adapterOf(Dio dio) => dio.httpClientAdapter as StubHttpAdapter;
