package com.wimg.app.widget

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.LocalSize
import androidx.compose.ui.unit.DpSize
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.updateAll
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.wimg.app.MainActivity
import com.wimg.app.R
import com.wimg.app.i18n.__t
import com.wimg.app.ui.theme.LocaleState
import com.wimg.app.ui.theme.categoryColors
import java.text.DateFormatSymbols
import java.text.NumberFormat
import java.util.Locale

// Board 13: one dark medium widget for the month, two light small ones.

private val Dark = Color(0xFF1D1C1A)
private val DarkSub = Color(0xFFA8A49C)
private val Neg = Color(0xFFFF9A85)
private val Pos = Color(0xFF86DDA6)
private val Light = Color(0xFFFAF9F6)
private val LightText = Color(0xFF1A1A1A)
private val LightSub = Color(0xFF6B6A66)

suspend fun updateAllWidgets(context: Context) {
    MonthWidget().updateAll(context)
    FixedCostsWidget().updateAll(context)
    TodayWidget().updateAll(context)
}

/** Widgets run without Compose state: seed the locale the app uses. */
private fun t(context: Context, key: String): String {
    val stored = LocaleState.stored(context)
    if (LocaleState.locale != stored) LocaleState.locale = stored
    return __t(key)
}

private fun locale() = if (LocaleState.locale == "en") Locale.ENGLISH else Locale.GERMANY

/**
 * "−1.396,66 €", or "•••• €" when amounts are hidden. German grouping in every
 * language, like the app ("414.45 €" in the widget next to "2.726,02 €" in the app).
 * [cents] false: whole euros, for the narrow widget.
 */
private fun money(v: Double, masked: Boolean, plus: Boolean = false, cents: Boolean = true): String {
    if (masked) return "•••• €"
    val digits = if (cents) 2 else 0
    val f = NumberFormat.getNumberInstance(Locale.GERMANY).apply { minimumFractionDigits = digits; maximumFractionDigits = digits }
    val sign = when { v < -0.004 -> "−"; plus && v > 0.004 -> "+"; else -> "" }
    return "$sign${f.format(kotlin.math.abs(v))} €"
}

private fun shortDate(iso: String?): String {
    if (iso == null || iso.length < 10) return ""
    val m = iso.substring(5, 7).toIntOrNull() ?: return iso
    val d = iso.substring(8, 10).toIntOrNull() ?: return iso
    return "$d. ${DateFormatSymbols(locale()).shortMonths[m - 1].trimEnd('.')}."
}

private fun open(context: Context, route: String?) = actionStartActivity(
    Intent(context, MainActivity::class.java).apply {
        flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        if (route != null) putExtra(MainActivity.EXTRA_ROUTE, route)
    },
)

private fun style(color: Color, size: TextUnit, bold: Boolean = false) =
    TextStyle(color = ColorProvider(color), fontSize = size, fontWeight = if (bold) FontWeight.Bold else FontWeight.Normal)

/** The category bar as a bitmap: Glance has no proportional weights. */
private fun categoryBar(parts: List<Pair<Int, Double>>): Bitmap {
    val w = 900; val h = 18; val gap = 6f
    val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bmp)
    val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    val total = parts.sumOf { it.second }
    if (total <= 0) {
        paint.color = 0x33FFFFFF
        canvas.drawRoundRect(RectF(0f, 0f, w.toFloat(), h.toFloat()), h / 2f, h / 2f, paint)
        return bmp
    }
    val usable = w - gap * (parts.size - 1)
    var x = 0f
    parts.forEach { (id, amount) ->
        val seg = (amount / total * usable).toFloat().coerceAtLeast(h.toFloat())
        paint.color = (categoryColors[id]?.second ?: 0xFF8A857C).toInt()
        canvas.drawRoundRect(RectF(x, 0f, (x + seg).coerceAtMost(w.toFloat()), h.toFloat()), h / 2f, h / 2f, paint)
        x += seg + gap
    }
    return bmp
}

class MonthWidget : GlanceAppWidget() {
    // Resizable down to 2×2: below ~220 dp a compact layout (the full one cut
    // every number off: "+414.4…", "−1,781.…").
    override val sizeMode = SizeMode.Responsive(setOf(DpSize(150.dp, 150.dp), DpSize(250.dp, 110.dp)))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val d = WidgetData.load(context)
        val masked = WidgetData.masked(context)
        val bar = categoryBar(d.categories.take(8))
        val monthName = DateFormatSymbols(locale()).months[(if (d.month in 1..12) d.month else java.util.Calendar.getInstance().get(java.util.Calendar.MONTH) + 1) - 1]
        val stand = if (d.hasData) {
            val c = java.util.Calendar.getInstance().apply { timeInMillis = d.updatedAt }
            t(context, "Stand %s · %s").format(
                shortDate("%04d-%02d-%02d".format(c.get(1), c.get(2) + 1, c.get(5))),
                "%02d:%02d".format(c.get(java.util.Calendar.HOUR_OF_DAY), c.get(java.util.Calendar.MINUTE)),
            )
        } else ""
        provideContent {
            val narrow = LocalSize.current.width < 220.dp
            Column(
                GlanceModifier.fillMaxSize().cornerRadius(24.dp).background(Dark).padding(if (narrow) 14.dp else 18.dp).clickable(open(context, null)),
            ) {
                Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
                    val headline = when (d.mode) {
                        "salary" -> t(context, "Bis zum Gehalt verfügbar")
                        "day" -> t(context, "Bis zum %d. verfügbar").format(d.startDay)
                        else -> t(context, "Verfügbar im %s").format(monthName)
                    }
                    Text(headline, style = style(DarkSub, if (narrow) 12.sp else 13.sp), maxLines = 2, modifier = GlanceModifier.defaultWeight())
                    Image(ImageProvider(R.mipmap.ic_launcher_round), contentDescription = null, modifier = GlanceModifier.size(22.dp))
                }
                if (!d.hasData) {
                    Spacer(GlanceModifier.defaultWeight())
                    Text(t(context, "Öffne wimg einmal, dann steht hier dein Monat."), style = style(DarkSub, 13.sp))
                    return@Column
                }
                Text(
                    money(d.available, masked, plus = true, cents = !narrow),
                    style = style(if (masked) androidx.compose.ui.graphics.Color.White else if (d.available < 0) Neg else Pos, if (narrow) 24.sp else 30.sp, bold = true),
                    maxLines = 1,
                )
                if (d.overdueDay > 0) {
                    // Salary late: no minus alarm, just the note (board 26/06).
                    Text(t(context, "Gehalt erwartet am %d., noch nicht da").format(d.overdueDay), style = style(Neg, 13.sp), maxLines = 1)
                }
                Spacer(GlanceModifier.defaultWeight())
                Image(ImageProvider(bar), contentDescription = null, contentScale = androidx.glance.layout.ContentScale.FillBounds, modifier = GlanceModifier.fillMaxWidth().height(6.dp))
                Spacer(GlanceModifier.height(if (narrow) 8.dp else 10.dp))
                if (narrow) {
                    // One pair only; "Stand" doesn't fit. Calendar months have no
                    // "per day left" (their perDay is spending per day): Expenses.
                    if (d.mode != "calendar") {
                        Text(t(context, "%s pro Tag").format(money(d.perDay.coerceAtLeast(0.0), masked, cents = false)), style = style(androidx.compose.ui.graphics.Color.White, 14.sp, bold = true), maxLines = 1)
                        Text(if (d.daysLeft == 1) t(context, "noch 1 Tag") else t(context, "noch %d Tage").format(d.daysLeft), style = style(DarkSub, 12.sp), maxLines = 1)
                    } else {
                        Text(t(context, "Ausgaben"), style = style(DarkSub, 12.sp), maxLines = 1)
                        Text(money(-d.expenses, masked, cents = false), style = style(androidx.compose.ui.graphics.Color.White, 14.sp, bold = true), maxLines = 1)
                    }
                    return@Column
                }
                if (d.mode != "calendar") Row(GlanceModifier.fillMaxWidth()) {
                    Column(GlanceModifier.defaultWeight()) {
                        Text(t(context, "Ausgaben"), style = style(DarkSub, 12.sp))
                        Text(money(-d.expenses, masked), style = style(androidx.compose.ui.graphics.Color.White, 15.sp, bold = true), maxLines = 1)
                    }
                    Column(GlanceModifier.defaultWeight()) {
                        Text(if (d.daysLeft == 1) t(context, "noch 1 Tag") else t(context, "noch %d Tage").format(d.daysLeft), style = style(DarkSub, 12.sp))
                        Text(t(context, "%s pro Tag").format(money(d.perDay.coerceAtLeast(0.0), masked)), style = style(androidx.compose.ui.graphics.Color.White, 15.sp, bold = true), maxLines = 1)
                    }
                } else Row(GlanceModifier.fillMaxWidth()) {
                    Column(GlanceModifier.defaultWeight()) {
                        Text(t(context, "Ausgaben"), style = style(DarkSub, 12.sp))
                        Text(money(-d.expenses, masked), style = style(androidx.compose.ui.graphics.Color.White, 15.sp, bold = true), maxLines = 1)
                    }
                    Column(GlanceModifier.defaultWeight()) {
                        Text(t(context, "Ausgaben/Tag"), style = style(DarkSub, 12.sp))
                        Text(money(d.perDay, masked), style = style(androidx.compose.ui.graphics.Color.White, 15.sp, bold = true), maxLines = 1)
                    }
                }
                Spacer(GlanceModifier.height(8.dp))
                Text(stand, style = style(DarkSub, 11.sp))
            }
        }
    }
}

@Composable
private fun SmallCard(context: Context, route: String, title: String, value: String, foot: String) {
    Column(
        GlanceModifier.fillMaxSize().cornerRadius(24.dp).background(Light).padding(16.dp).clickable(open(context, route)),
    ) {
        Text(title, style = style(LightSub, 13.sp), maxLines = 1)
        Spacer(GlanceModifier.defaultWeight())
        Text(value, style = style(LightText, 24.sp, bold = true), maxLines = 1)
        Spacer(GlanceModifier.defaultWeight())
        Text(foot, style = style(LightSub, 11.sp), maxLines = 2)
    }
}

class FixedCostsWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val d = WidgetData.load(context)
        val masked = WidgetData.masked(context)
        val foot = when {
            !d.hasData -> t(context, "Öffne wimg einmal.")
            d.nextMerchant != null -> t(context, "nächste: %s · %s").format(d.nextMerchant, shortDate(d.nextDate))
            else -> t(context, "Keine festen Zahlungen erkannt")
        }
        val title = if (d.mode == "salary") t(context, "Bis zum Gehalt offen") else t(context, "Fixkosten offen")
        provideContent { SmallCard(context, "recurring", title, money(d.fixedOpen, masked), foot) }
    }
}

class TodayWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val d = WidgetData.load(context)
        val masked = WidgetData.masked(context)
        val foot = when {
            !d.hasData -> t(context, "Öffne wimg einmal.")
            d.todayCount == 1 -> t(context, "1 Umsatz")
            else -> t(context, "%d Umsätze").format(d.todayCount)
        }
        provideContent { SmallCard(context, "transactions", t(context, "Heute"), money(d.todaySum, masked, plus = true), foot) }
    }
}

class MonthWidgetReceiver : GlanceAppWidgetReceiver() { override val glanceAppWidget = MonthWidget() }
class FixedCostsWidgetReceiver : GlanceAppWidgetReceiver() { override val glanceAppWidget = FixedCostsWidget() }
class TodayWidgetReceiver : GlanceAppWidgetReceiver() { override val glanceAppWidget = TodayWidget() }
