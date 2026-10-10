package io.cashdeck.app.notifications

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** The Dart side's view of the listener: its state and its settings. */
class CardNotificationChannel(private val context: Context) : MethodChannel.MethodCallHandler {
    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, NAME).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val store = CardNotificationStore(context)
        when (call.method) {
            "status" -> result.success(status(store))
            "openAccessSettings" -> {
                context.startActivity(
                    Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
                result.success(null)
            }
            "configure" -> {
                store.configure(
                    enabled = call.argument<Boolean>("enabled") ?: false,
                    packages = call.argument<List<String>>("packages").orEmpty().toSet(),
                    accountId = call.argument<String>("accountId"),
                    baseUrl = call.argument<String>("baseUrl"),
                    token = call.argument<String>("token"),
                )
                if (store.enabled) {
                    CardNotificationListener.readActiveNotifications()
                    CardNotificationUploader.schedule(context)
                }
                result.success(status(store))
            }
            else -> result.notImplemented()
        }
    }

    private fun status(store: CardNotificationStore): Map<String, Any?> = mapOf(
        "access" to hasAccess(),
        "enabled" to store.enabled,
        "packages" to store.packages.toList(),
        "accountId" to store.accountId,
        "pending" to store.queue().length(),
        "apps" to store.seenApps().map { (pkg, label) -> mapOf("package" to pkg, "label" to label) },
    )

    private fun hasAccess(): Boolean {
        val enabled = Settings.Secure.getString(
            context.contentResolver,
            "enabled_notification_listeners",
        ).orEmpty()
        val self = ComponentName(context, CardNotificationListener::class.java)
        return enabled.split(':').any { ComponentName.unflattenFromString(it) == self }
    }

    companion object {
        const val NAME = "io.cashdeck.app/card_notifications"
    }
}
