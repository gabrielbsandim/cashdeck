package io.cashdeck.app.notifications

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

/** What the listener and the uploader share, in app-private preferences. */
class CardNotificationStore(context: Context) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences(NAME, Context.MODE_PRIVATE)

    val enabled: Boolean get() = prefs.getBoolean(KEY_ENABLED, false)
    val packages: Set<String> get() = prefs.getStringSet(KEY_PACKAGES, emptySet()) ?: emptySet()
    val accountId: String? get() = prefs.getString(KEY_ACCOUNT, null)
    val baseUrl: String? get() = prefs.getString(KEY_URL, null)
    val token: String? get() = prefs.getString(KEY_TOKEN, null)

    fun configure(
        enabled: Boolean,
        packages: Set<String>,
        accountId: String?,
        baseUrl: String?,
        token: String?,
    ) {
        prefs.edit()
            .putBoolean(KEY_ENABLED, enabled && accountId != null && token != null)
            .putStringSet(KEY_PACKAGES, packages)
            .putString(KEY_ACCOUNT, accountId)
            .putString(KEY_URL, baseUrl)
            .putString(KEY_TOKEN, if (enabled) token else null)
            .apply()
        if (!enabled) clearQueue()
    }

    // A revoked token stops forwarding until the app signs in again.
    fun forgetToken() {
        prefs.edit().putBoolean(KEY_ENABLED, false).remove(KEY_TOKEN).apply()
    }

    fun seenApps(): Map<String, String> {
        val json = JSONObject(prefs.getString(KEY_SEEN, "{}") ?: "{}")
        return json.keys().asSequence().associateWith { json.getString(it) }
    }

    @Synchronized
    fun rememberApp(packageName: String, label: String) {
        val json = JSONObject(prefs.getString(KEY_SEEN, "{}") ?: "{}")
        if (json.optString(packageName) == label) return
        json.remove(packageName)
        if (json.length() >= MAX_SEEN) json.remove(json.keys().next())
        json.put(packageName, label)
        prefs.edit().putString(KEY_SEEN, json.toString()).apply()
    }

    /** False when the same text from the same app arrived moments ago. */
    @Synchronized
    fun isFresh(fingerprint: String, now: Long): Boolean {
        val json = JSONObject(prefs.getString(KEY_RECENT, "{}") ?: "{}")
        val kept = JSONObject()
        json.keys().forEach { key ->
            val at = json.getLong(key)
            if (now - at < REPEAT_WINDOW_MS) kept.put(key, at)
        }
        val fresh = !kept.has(fingerprint)
        kept.put(fingerprint, now)
        prefs.edit().putString(KEY_RECENT, kept.toString()).apply()
        return fresh
    }

    @Synchronized
    fun enqueue(item: JSONObject) {
        val queue = queue()
        queue.put(item)
        while (queue.length() > MAX_QUEUE) queue.remove(0)
        prefs.edit().putString(KEY_QUEUE, queue.toString()).apply()
    }

    @Synchronized
    fun queue(): JSONArray = JSONArray(prefs.getString(KEY_QUEUE, "[]") ?: "[]")

    @Synchronized
    fun drop(ids: Set<String>) {
        val queue = queue()
        val kept = JSONArray()
        for (index in 0 until queue.length()) {
            val item = queue.getJSONObject(index)
            if (item.getString("id") !in ids) kept.put(item)
        }
        prefs.edit().putString(KEY_QUEUE, kept.toString()).apply()
    }

    private fun clearQueue() {
        prefs.edit().remove(KEY_QUEUE).remove(KEY_RECENT).apply()
    }

    companion object {
        private const val NAME = "card_notifications"
        private const val KEY_ENABLED = "enabled"
        private const val KEY_PACKAGES = "packages"
        private const val KEY_ACCOUNT = "account_id"
        private const val KEY_URL = "base_url"
        private const val KEY_TOKEN = "token"
        private const val KEY_SEEN = "seen_apps"
        private const val KEY_RECENT = "recent"
        private const val KEY_QUEUE = "queue"
        private const val MAX_SEEN = 30
        private const val MAX_QUEUE = 200
        private const val REPEAT_WINDOW_MS = 10 * 60 * 1000L
    }
}
