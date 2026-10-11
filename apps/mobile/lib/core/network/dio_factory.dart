import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/session/server_credentials.dart';
import 'package:dio/dio.dart';

BaseOptions apiBaseOptions(AppConfig config, [ServerCredentials? session]) =>
    BaseOptions(
      baseUrl: session?.baseUrl ?? config.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      contentType: Headers.jsonContentType,
      headers: {
        'X-Client': 'mobile',
        if (session != null) 'Authorization': 'Bearer ${session.token}',
      },
    );

/// Why a request never left the phone: the safe mode refuses writes.
final class SafeModeRefusal {
  const new();
}

/// Signs every request with the session token; a 401 means the token was
/// revoked on the server, so [onUnauthorized] signs the device out. While
/// [refuseWrites] answers true only reads go out.
Dio createApiDio(
  AppConfig config, {
  ServerCredentials? session,
  void Function()? onUnauthorized,
  bool Function()? refuseWrites,
}) {
  final dio = Dio(apiBaseOptions(config, session));
  if (refuseWrites != null) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.method.toUpperCase() == 'GET' || !refuseWrites()) {
            handler.next(options);
            return;
          }
          handler.reject(
            DioException(
              requestOptions: options,
              error: const SafeModeRefusal(),
            ),
          );
        },
      ),
    );
  }
  if (onUnauthorized == null) return dio;
  dio.interceptors.add(
    InterceptorsWrapper(
      onError: (error, handler) {
        if (error.response?.statusCode == 401) onUnauthorized();
        handler.next(error);
      },
    ),
  );
  return dio;
}
