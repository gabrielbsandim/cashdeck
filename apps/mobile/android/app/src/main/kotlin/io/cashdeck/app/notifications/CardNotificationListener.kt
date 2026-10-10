package io.cashdeck.app.notifications

import android.app.Notification
import android.content.pm.PackageManager
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONObject
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Queues what the picked card apps notify and leaves the sending to
 * [CardNotificationUploader]. Every other app is only remembered by name.
 */
class CardNotificationListener : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val notification = sbn.notification ?: return
        if (sbn.packageName == packageName) return
        if (notification.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        if (sbn.isOngoing) return
        val store = CardNotificationStore(applicationContext)
        store.rememberApp(sbn.packageName, labelOf(sbn.packageName))
        if (!store.enabled || sbn.packageName !in store.packages) return
        val extras = notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val text = (
            extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
                ?: extras.getCharSequence(Notification.EXTRA_TEXT)
            )?.toString().orEmpty()
        if (title.isBlank() && text.isBlank()) return
        val content = "${sbn.packageName}|$title|$text"
        if (!store.isFresh(sha256(content), System.currentTimeMillis())) return
        store.enqueue(
            JSONObject()
                .put("id", sha256("$content|${sbn.postTime}").take(ID_LENGTH))
                .put("app", labelOf(sbn.packageName))
                .put("title", title.take(MAX_TITLE))
                .put("text", text.take(MAX_TEXT))
                .put("postedAt", isoInstant(sbn.postTime)),
        )
        CardNotificationUploader.schedule(applicationContext)
    }

    private fun labelOf(packageName: String): String = try {
        val info = packageManager.getApplicationInfo(packageName, 0)
        packageManager.getApplicationLabel(info).toString()
    } catch (_: PackageManager.NameNotFoundException) {
        packageName
    }

    companion object {
        private const val ID_LENGTH = 40
        private const val MAX_TITLE = 500
        private const val MAX_TEXT = 2000

        fun sha256(value: String): String =
            MessageDigest.getInstance("SHA-256")
                .digest(value.toByteArray())
                .joinToString("") { "%02x".format(it) }

        fun isoInstant(millis: Long): String =
            SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
                .apply { timeZone = TimeZone.getTimeZone("UTC") }
                .format(Date(millis))
    }
}
