import 'package:cashdeck/core/push/push_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

PushMessage pushMessageOf(RemoteMessage message) => PushMessage(
  title: message.notification?.title,
  body: message.notification?.body,
  data: {for (final entry in message.data.entries) entry.key: '${entry.value}'},
);

/// FCM through firebase_messaging. Without google-services.json the native
/// initialization throws, and push simply stays off.
final class FirebasePushMessaging implements PushMessaging {
  new({
    Future<void> Function()? initialize,
    FirebaseMessaging Function()? messaging,
    this.onMessage,
    this.onMessageOpenedApp,
  }) : _initialize = initialize ?? _initializeFirebase,
       _messaging = messaging ?? (() => FirebaseMessaging.instance);

  final Future<void> Function() _initialize;
  final FirebaseMessaging Function() _messaging;
  final Stream<RemoteMessage>? onMessage;
  final Stream<RemoteMessage>? onMessageOpenedApp;
  Future<bool>? _started;
  var _ready = false;

  static Future<void> _initializeFirebase() => Firebase.initializeApp();

  @override
  Future<bool> start() => _started ??= _start();

  Future<bool> _start() async {
    try {
      await _initialize();
      await _messaging().requestPermission();
      _ready = true;
    } on Object {
      _ready = false;
    }
    return _ready;
  }

  @override
  Future<String?> token() async {
    if (!await start()) return null;
    try {
      return await _messaging().getToken();
    } on Object {
      return null;
    }
  }

  @override
  Stream<String> tokenRefreshes() {
    if (!_ready) return const Stream.empty();
    return _messaging().onTokenRefresh;
  }

  @override
  Stream<PushMessage> foreground() {
    if (!_ready) return const Stream.empty();
    return (onMessage ?? FirebaseMessaging.onMessage).map(pushMessageOf);
  }

  @override
  Stream<PushMessage> opened() {
    if (!_ready) return const Stream.empty();
    return (onMessageOpenedApp ?? FirebaseMessaging.onMessageOpenedApp).map(
      pushMessageOf,
    );
  }

  @override
  Future<PushMessage?> launchedBy() async {
    if (!await start()) return null;
    final message = await _messaging().getInitialMessage();
    return message == null ? null : pushMessageOf(message);
  }
}
