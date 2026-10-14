package io.cashdeck.app

import io.cashdeck.app.notifications.CardNotificationChannel
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        CardNotificationChannel(applicationContext).register(flutterEngine.dartExecutor.binaryMessenger)
    }
}
