package io.cashdeck.app.notifications

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.TimeUnit

/** Sends the queued notifications to the server, retrying while offline. */
class CardNotificationUploader(context: Context, params: WorkerParameters) :
    Worker(context, params) {
    override fun doWork(): Result {
        val store = CardNotificationStore(applicationContext)
        val accountId = store.accountId
        val baseUrl = store.baseUrl
        val token = store.token
        if (!store.enabled || accountId == null || baseUrl == null || token == null) {
            return Result.success()
        }
        while (true) {
            val queue = store.queue()
            if (queue.length() == 0) return Result.success()
            val batch = JSONArray()
            for (index in 0 until minOf(queue.length(), BATCH)) batch.put(queue.get(index))
            val status = try {
                post(baseUrl, token, JSONObject().put("accountId", accountId).put("notifications", batch))
            } catch (_: IOException) {
                return Result.retry()
            }
            when {
                status == HttpURLConnection.HTTP_UNAUTHORIZED -> {
                    store.forgetToken()
                    return Result.failure()
                }
                status >= HttpURLConnection.HTTP_INTERNAL_ERROR || status == TOO_MANY -> return Result.retry()
                // A 2xx is stored, any other 4xx can never be: either way it leaves the queue.
                else -> store.drop(ids(batch))
            }
        }
    }

    private fun ids(batch: JSONArray): Set<String> =
        (0 until batch.length()).map { batch.getJSONObject(it).getString("id") }.toSet()

    private fun post(baseUrl: String, token: String, body: JSONObject): Int {
        val connection = URL("$baseUrl$PATH").openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.connectTimeout = TIMEOUT_MS
            connection.readTimeout = TIMEOUT_MS
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("Authorization", "Bearer $token")
            connection.setRequestProperty("X-Client", "mobile-notifications")
            connection.outputStream.use { it.write(body.toString().toByteArray()) }
            return connection.responseCode
        } finally {
            connection.disconnect()
        }
    }

    companion object {
        private const val WORK = "card-notifications-upload"
        private const val PATH = "/api/v1/card-notifications"
        private const val BATCH = 50
        private const val TOO_MANY = 429
        private const val TIMEOUT_MS = 30_000

        fun schedule(context: Context) {
            val request = OneTimeWorkRequestBuilder<CardNotificationUploader>()
                .setConstraints(
                    Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build(),
                )
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 1, TimeUnit.MINUTES)
                .build()
            WorkManager.getInstance(context)
                .enqueueUniqueWork(WORK, ExistingWorkPolicy.APPEND_OR_REPLACE, request)
        }
    }
}
