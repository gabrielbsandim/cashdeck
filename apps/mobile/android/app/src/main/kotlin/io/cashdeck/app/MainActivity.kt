package io.cashdeck.app

import android.os.Bundle
import android.view.WindowManager
import io.cashdeck.app.notifications.CardNotificationChannel
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Keeps balances out of screenshots, screen recordings and the recents preview.
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        CardNotificationChannel(applicationContext).register(flutterEngine.dartExecutor.binaryMessenger)
    }
}
