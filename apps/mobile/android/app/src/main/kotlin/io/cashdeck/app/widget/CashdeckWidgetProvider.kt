package io.cashdeck.app.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import io.cashdeck.app.MainActivity
import io.cashdeck.app.R
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Draws what the app last saved: the amount free to spend today, the next bill and the open card
 * bill. Keys mirror `WidgetKeys` in `features/home_widget/domain/widget_snapshot.dart`.
 */
class CashdeckWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, render(context, widgetData))
        }
    }

    private fun render(context: Context, data: SharedPreferences): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.cashdeck_widget)
        val hidden = data.getBoolean(HIDDEN, false)
        val masked = context.getString(R.string.widget_masked)
        fun amount(key: String): String? = if (hidden) masked else data.getString(key, null)

        views.setTextViewText(R.id.widget_updated, updatedLine(context, data))
        renderSafe(context, views, data, amount(SAFE_AMOUNT))
        renderBill(context, views, data, amount(BILL_AMOUNT))
        renderCard(context, views, data, amount(CARD_AMOUNT))

        views.setOnClickPendingIntent(R.id.widget_root, open(context, "home"))
        views.setOnClickPendingIntent(R.id.widget_safe, open(context, "home"))
        views.setOnClickPendingIntent(R.id.widget_bill, open(context, "bills"))
        views.setOnClickPendingIntent(R.id.widget_card, open(context, "cards"))
        return views
    }

    private fun updatedLine(context: Context, data: SharedPreferences): String {
        val time = data.getString(UPDATED_TIME, null)
        val on = data.getString(UPDATED_ON, null)
        if (time == null || on == null) return context.getString(R.string.widget_open_app)
        if (on == today()) return context.getString(R.string.widget_updated_at, time)
        return context.getString(R.string.widget_updated_on, dayMonth(on), time)
    }

    private fun renderSafe(
        context: Context,
        views: RemoteViews,
        data: SharedPreferences,
        amount: String?,
    ) {
        views.setTextViewText(R.id.widget_safe_amount, amount ?: context.getString(R.string.widget_unknown))
        val until = data.getString(SAFE_UNTIL, null)
        val caption = when {
            until == null -> ""
            data.getBoolean(SAFE_SHORT, false) -> context.getString(R.string.widget_safe_short, until)
            else -> context.getString(R.string.widget_safe_per_day, until)
        }
        views.setTextViewText(R.id.widget_safe_caption, caption)
    }

    private fun renderBill(
        context: Context,
        views: RemoteViews,
        data: SharedPreferences,
        amount: String?,
    ) {
        val payee = data.getString(BILL_PAYEE, null)
        val due = data.getString(BILL_DUE, "").orEmpty()
        val overdue = data.getBoolean(BILL_OVERDUE, false)
        val (value, caption) = when {
            payee == null -> context.getString(R.string.widget_unknown) to ""
            payee.isEmpty() -> context.getString(R.string.widget_no_bill) to ""
            overdue -> amount.orEmpty() to context.getString(R.string.widget_bill_overdue, payee, due)
            else -> amount.orEmpty() to context.getString(R.string.widget_bill_due, payee, due)
        }
        views.setTextViewText(R.id.widget_bill_amount, value)
        views.setTextViewText(R.id.widget_bill_caption, caption)
        views.setTextColor(
            R.id.widget_bill_caption,
            context.getColor(if (overdue) R.color.widget_overdue else R.color.widget_on_surface_variant),
        )
    }

    private fun renderCard(
        context: Context,
        views: RemoteViews,
        data: SharedPreferences,
        amount: String?,
    ) {
        val stored = data.getString(CARD_AMOUNT, null)
        val due = data.getString(CARD_DUE, "").orEmpty()
        val (value, caption) = when {
            stored == null -> context.getString(R.string.widget_unknown) to ""
            stored.isEmpty() -> context.getString(R.string.widget_no_card) to ""
            due.isEmpty() -> amount.orEmpty() to ""
            else -> amount.orEmpty() to context.getString(R.string.widget_card_due, due)
        }
        views.setTextViewText(R.id.widget_card_amount, value)
        views.setTextViewText(R.id.widget_card_caption, caption)
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
        const val BILL_PAYEE = "bill_payee"
        const val BILL_AMOUNT = "bill_amount"
        const val BILL_DUE = "bill_due"
        const val BILL_OVERDUE = "bill_overdue"
        const val CARD_AMOUNT = "card_amount"
        const val CARD_DUE = "card_due"
    }
}
