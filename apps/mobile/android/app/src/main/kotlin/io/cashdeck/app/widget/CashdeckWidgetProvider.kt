package io.cashdeck.app.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import io.cashdeck.app.MainActivity
import io.cashdeck.app.R
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Draws what the app or the background refresh last saved: the amount free to spend today, the
 * next bill and the open card bill, in the layout its [WidgetSize] fits. Keys mirror `WidgetKeys` in
 * `features/home_widget/domain/widget_snapshot.dart`.
 */
class CashdeckWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, views(context, appWidgetManager, id, widgetData))
        }
        // A widget added before the refresh existed never saw onEnabled.
        WidgetRefreshWorker.schedule(context)
    }

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        WidgetRefreshWorker.schedule(context)
        WidgetRefreshWorker.refreshNow(context)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        WidgetRefreshWorker.cancel(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        val restarted = intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == Intent.ACTION_MY_PACKAGE_REPLACED
        if (!restarted || !WidgetRefreshWorker.hasWidget(context)) return
        WidgetRefreshWorker.schedule(context)
        WidgetRefreshWorker.refreshNow(context)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        val data = HomeWidgetPlugin.getData(context)
        appWidgetManager.updateAppWidget(appWidgetId, views(context, appWidgetManager, appWidgetId, data))
    }

    /** From Android 12 the launcher picks the layout per size itself, resizing included. */
    private fun views(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        data: SharedPreferences,
    ): RemoteViews {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val sized = WidgetSize.values().associate { SizeF(it.width, it.height) to render(context, data, it) }
            return RemoteViews(sized)
        }
        return render(context, data, WidgetSize.fitting(manager.getAppWidgetOptions(id)))
    }

    private fun render(context: Context, data: SharedPreferences, size: WidgetSize): RemoteViews {
        val views = RemoteViews(context.packageName, size.layout)
        val hidden = data.getBoolean(HIDDEN, false)
        val masked = context.getString(R.string.widget_masked)
        fun amount(key: String): String? = if (hidden) masked else data.getString(key, null)

        val updated = updatedLine(context, data)
        views.setTextViewText(R.id.widget_updated, updated.orEmpty())
        renderSafe(context, views, data, size, amount(SAFE_AMOUNT), amount(SAFE_TOTAL), opened = updated != null)
        views.setOnClickPendingIntent(android.R.id.background, open(context, "home"))
        views.setOnClickPendingIntent(R.id.widget_safe, open(context, "home"))
        if (!size.tiles) return views

        renderBill(context, views, data, size, amount(BILL_AMOUNT))
        renderCard(context, views, data, size, amount(CARD_AMOUNT))
        views.setOnClickPendingIntent(R.id.widget_bill, open(context, "bills"))
        views.setOnClickPendingIntent(R.id.widget_card, open(context, "cards"))
        return views
    }

    /** Null until something was saved, or after the session ended. */
    private fun updatedLine(context: Context, data: SharedPreferences): String? {
        val time = data.getString(UPDATED_TIME, null)
        val on = data.getString(UPDATED_ON, null)
        if (time == null || on == null) return null
        if (on == today()) return context.getString(R.string.widget_updated_at, time)
        return context.getString(R.string.widget_updated_on, dayMonth(on), time)
    }

    private fun renderSafe(
        context: Context,
        views: RemoteViews,
        data: SharedPreferences,
        size: WidgetSize,
        amount: String?,
        total: String?,
        opened: Boolean,
    ) {
        val short = data.getBoolean(SAFE_SHORT, false)
        val until = data.getString(SAFE_UNTIL, null)
        val caption = when {
            !opened -> context.getString(R.string.widget_open_app)
            until == null -> ""
            short -> context.getString(R.string.widget_safe_short, until)
            else -> context.getString(R.string.widget_safe_per_day, until)
        }
        views.setTextViewText(R.id.widget_safe_amount, amount ?: context.getString(R.string.widget_unknown))
        views.setTextViewText(R.id.widget_safe_caption, caption)
        views.textColor(context, R.id.widget_safe_amount, if (short) R.color.widget_overdue else size.amountColor)
        if (!size.hero) return

        val background = if (short) R.drawable.widget_hero_short_background else R.drawable.widget_hero_background
        views.setInt(R.id.widget_safe, "setBackgroundResource", background)
        val days = (data.all[SAFE_DAYS] as? Number)?.toInt()
        val month = monthLine(context, total, days).takeIf { opened && !short }
        views.setTextViewText(R.id.widget_safe_month, month.orEmpty())
        views.setViewVisibility(R.id.widget_safe_month, if (month == null) View.GONE else View.VISIBLE)
    }

    private fun monthLine(context: Context, total: String?, days: Int?): String? {
        if (total == null || days == null) return null
        val left = context.resources.getQuantityString(R.plurals.widget_days_left, days, days)
        return context.getString(R.string.widget_safe_month, total, left)
    }

    private fun renderBill(
        context: Context,
        views: RemoteViews,
        data: SharedPreferences,
        size: WidgetSize,
        amount: String?,
    ) {
        val payee = data.getString(BILL_PAYEE, null)
        val due = data.getString(BILL_DUE, "").orEmpty()
        val overdue = data.getBoolean(BILL_OVERDUE, false)
        val (value, caption) = when {
            payee == null -> context.getString(R.string.widget_unknown) to ""
            payee.isEmpty() -> context.getString(R.string.widget_no_bill) to ""
            !size.hero && overdue -> amount.orEmpty() to context.getString(R.string.widget_overdue_on, due)
            !size.hero -> amount.orEmpty() to context.getString(R.string.widget_due_on, due)
            overdue -> amount.orEmpty() to context.getString(R.string.widget_bill_overdue, payee, due)
            else -> amount.orEmpty() to context.getString(R.string.widget_bill_due, payee, due)
        }
        views.setTextViewText(R.id.widget_bill_amount, value)
        views.setTextViewText(R.id.widget_bill_caption, caption)
        views.textColor(
            context,
            R.id.widget_bill_caption,
            if (overdue) R.color.widget_overdue else R.color.widget_on_surface_variant,
        )
    }

    private fun renderCard(
        context: Context,
        views: RemoteViews,
        data: SharedPreferences,
        size: WidgetSize,
        amount: String?,
    ) {
        val stored = data.getString(CARD_AMOUNT, null)
        val due = data.getString(CARD_DUE, "").orEmpty()
        val (value, caption) = when {
            stored == null -> context.getString(R.string.widget_unknown) to ""
            stored.isEmpty() -> context.getString(R.string.widget_no_card) to ""
            due.isEmpty() -> amount.orEmpty() to ""
            else -> amount.orEmpty() to context.getString(R.string.widget_due_on, due)
        }
        views.setTextViewText(R.id.widget_card_amount, value)
        views.setTextViewText(R.id.widget_card_caption, caption)
    }

    /** A color resource resolves on the launcher from Android 12, so a theme switch recolors it. */
    private fun RemoteViews.textColor(context: Context, id: Int, color: Int) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            setColorStateList(id, "setTextColor", color)
            return
        }
        setTextColor(id, context.getColor(color))
    }

    private fun open(context: Context, path: String) =
        HomeWidgetLaunchIntent.getActivity(
            context,
            MainActivity::class.java,
            Uri.parse("cashdeck://widget/$path"),
        )

    private fun today(): String = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())

    private fun dayMonth(iso: String): String =
        if (iso.length < 10) iso else "${iso.substring(8, 10)}/${iso.substring(5, 7)}"

    private companion object {
        const val HIDDEN = "hidden"
        const val UPDATED_TIME = "updated_time"
        const val UPDATED_ON = "updated_on"
        const val SAFE_AMOUNT = "safe_amount"
        const val SAFE_UNTIL = "safe_until"
        const val SAFE_SHORT = "safe_short"
        const val SAFE_TOTAL = "safe_total"
        const val SAFE_DAYS = "safe_days"
        const val BILL_PAYEE = "bill_payee"
        const val BILL_AMOUNT = "bill_amount"
        const val BILL_DUE = "bill_due"
        const val BILL_OVERDUE = "bill_overdue"
        const val CARD_AMOUNT = "card_amount"
        const val CARD_DUE = "card_due"
    }
}

/** Smallest first; dimensions in dp, as the launcher reports them. */
private enum class WidgetSize(
    val layout: Int,
    val width: Float,
    val height: Float,
    val tiles: Boolean,
    val hero: Boolean,
    val amountColor: Int,
) {
    SMALL(R.layout.cashdeck_widget_small, 110f, 110f, false, false, R.color.widget_on_surface),
    COMPACT(R.layout.cashdeck_widget, 250f, 110f, true, false, R.color.widget_on_surface),
    FULL(R.layout.cashdeck_widget_full, 250f, 190f, true, true, R.color.widget_on_hero),
    ;

    companion object {
        /** Portrait: the narrow width and the tall height. An unknown size keeps the 4x2. */
        fun fitting(options: Bundle): WidgetSize {
            val width = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
            val height = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT)
            if (width == 0 || height == 0) return COMPACT
            return values().lastOrNull { width >= it.width && height >= it.height } ?: SMALL
        }
    }
}
