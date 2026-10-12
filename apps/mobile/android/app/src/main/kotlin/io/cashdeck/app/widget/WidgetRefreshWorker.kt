package io.cashdeck.app.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.net.Uri
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import java.util.concurrent.TimeUnit

/**
 * Wakes the Dart refresh (`refreshHomeWidgetInBackground`) through the `home_widget` background
 * callback. Only the Dart side reads the session token; nothing here touches it.
 */
class WidgetRefreshWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        if (!hasWidget(applicationContext)) return Result.success()
        return try {
            HomeWidgetBackgroundIntent.getBroadcast(applicationContext, REFRESH_URI).send()
            Result.success()
        } catch (_: PendingIntent.CanceledException) {
            Result.retry()
        }
    }

    companion object {
        private const val PERIODIC = "home-widget-refresh"
        private const val NOW = "home-widget-refresh-now"
        private const val HOURS = 3L

        /** Mirrors `homeWidgetRefreshUri` in `features/home_widget/home_widget_background.dart`. */
        private val REFRESH_URI: Uri = Uri.parse("cashdeck://widget/refresh")

        private val online = Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()

        /** Every few hours while a widget is on the home screen; WorkManager keeps it across boots. */
        fun schedule(context: Context) {
            val request = PeriodicWorkRequestBuilder<WidgetRefreshWorker>(HOURS, TimeUnit.HOURS)
                .setConstraints(online)
                .build()
            WorkManager.getInstance(context)
                .enqueueUniquePeriodicWork(PERIODIC, ExistingPeriodicWorkPolicy.KEEP, request)
        }

        /** Once, as soon as there is a connection. */
        fun refreshNow(context: Context) {
            val request = OneTimeWorkRequestBuilder<WidgetRefreshWorker>().setConstraints(online).build()
            WorkManager.getInstance(context).enqueueUniqueWork(NOW, ExistingWorkPolicy.REPLACE, request)
        }

        fun cancel(context: Context) {
            WorkManager.getInstance(context).apply {
                cancelUniqueWork(PERIODIC)
                cancelUniqueWork(NOW)
            }
        }

        fun hasWidget(context: Context): Boolean =
            AppWidgetManager.getInstance(context)
                .getAppWidgetIds(ComponentName(context, CashdeckWidgetProvider::class.java))
                .isNotEmpty()
    }
}
