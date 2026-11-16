package com.wimg.app.ui.screens

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider
import com.wimg.app.i18n.L
import com.wimg.app.ui.components.PriceGhost
import com.wimg.app.ui.components.Squirrel
import com.wimg.app.ui.components.SquirrelPose
import com.wimg.app.ui.theme.Wimg
import com.wimg.app.ui.theme.WimgType

/** What the squirrel does on a card of the Rückblick opener. */
internal enum class OpenerFigure { VOLL, RING, SLEEP, CAUGHT }

/**
 * One card of the opener (prototype CARDS). [ring] is the Sparquote (0..1) for
 * the ring card, [stitches] the days without spending, [prices] the caught ghost's tag.
 */
internal class OpenerCard(
    val label: String,
    val head: AnnotatedString,
    val sub: String,
    val figure: OpenerFigure,
    val ring: Float = 0f,
    val stitches: Int = 0,
    val prices: Pair<String, String> = "" to "",
)

private val Out = CubicBezierEasing(0.23f, 1f, 0.32f, 1f)
private val Drawer = CubicBezierEasing(0.32f, 0.72f, 0f, 1f)

/**
 * Rückblick opener: up to four cards before the month's review, tap for the
 * next one, "Überspringen" or back to leave. Only shown when there is something
 * true to say (see [openerCards]).
 */
@Composable
internal fun ReviewOpener(title: String, cards: List<OpenerCard>, onDone: () -> Unit) {
    Dialog(onDismissRequest = onDone, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        val c = Wimg.colors
        val bg = if (c.isDark) Color(0xFF111114) else Color(0xFFF3ECDD)
        // Its own window: reach under the status and navigation bars in the opener's
        // colour (they stayed black above and below the cards otherwise).
        (LocalView.current.parent as? DialogWindowProvider)?.window?.let { w ->
            w.setDimAmount(0f)
            w.setLayout(android.view.ViewGroup.LayoutParams.MATCH_PARENT, android.view.ViewGroup.LayoutParams.MATCH_PARENT)
            w.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(bg.toArgb()))
            w.addFlags(android.view.WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
            @Suppress("DEPRECATION") run {
                w.statusBarColor = android.graphics.Color.TRANSPARENT
                w.navigationBarColor = android.graphics.Color.TRANSPARENT
            }
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) w.isNavigationBarContrastEnforced = false
            // A dialog window keeps clear of the status bar by default (the band of the
            // page behind showed through, black): lay it out over the whole screen.
            // The cards pad themselves away from the bars (windowInsetsPadding).
            w.addFlags(android.view.WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or android.view.WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS)
            w.attributes = w.attributes.apply {
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) layoutInDisplayCutoutMode = android.view.WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) setFitInsetsTypes(0)
            }
            androidx.core.view.WindowCompat.getInsetsController(w, w.decorView).apply {
                isAppearanceLightStatusBars = !c.isDark
                isAppearanceLightNavigationBars = !c.isDark
            }
        }
        val ink = if (c.isDark) Color(0xFFF2F2F3) else Color(0xFF1A1A1A)
        val sub = if (c.isDark) Color(0xFF9A9BA0) else Color(0xFF6B6A66)
        var i by remember { mutableIntStateOf(0) }
        val reduce = remember { android.animation.ValueAnimator.getDurationScale() == 0f }
        // 0..1 over the card's first 700 ms: the card comes in, then the ring fills and the stitches appear.
        val t = remember(i) { Animatable(if (reduce) 1f else 0f) }
        LaunchedEffect(i) { if (!reduce) t.animateTo(1f, tween(700, easing = LinearEasing)) }
        val u = t.value
        val enter = Out.transform((u * 700f / 240f).coerceAtMost(1f))
        val card = cards[i.coerceAtMost(cards.lastIndex)]
        val next = { if (i < cards.lastIndex) i++ else onDone() }

        Column(
            Modifier.fillMaxSize().background(bg)
                .clickable(remember { MutableInteractionSource() }, indication = null, onClickLabel = L("Weiter")) { next() }
                .windowInsetsPadding(WindowInsets.systemBars)
                .padding(start = 22.dp, end = 22.dp, top = 16.dp, bottom = 26.dp),
        ) {
            Row(Modifier.fillMaxWidth().padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                cards.indices.forEach { j ->
                    Box(Modifier.weight(1f).height(3.dp).clip(RoundedCornerShape(2.dp)).background(if (j <= i) ink else ink.copy(alpha = if (c.isDark) 0.16f else 0.14f)))
                }
            }
            Row(Modifier.fillMaxWidth().padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(title, style = WimgType.desc, color = sub, modifier = Modifier.weight(1f))
                Text(L("Überspringen"), style = WimgType.desc, color = sub,
                    modifier = Modifier.clip(RoundedCornerShape(8.dp)).clickable { onDone() }.padding(horizontal = 6.dp, vertical = 4.dp))
            }
            Column(
                Modifier.weight(1f).fillMaxWidth().graphicsLayer { alpha = enter; translationY = (1f - enter) * 16.dp.toPx() },
                verticalArrangement = Arrangement.Center,
            ) {
                Box(Modifier.fillMaxWidth().heightIn(min = 250.dp), contentAlignment = Alignment.Center) {
                    OpenerFigureView(card, u, reduce, ink)
                }
                if (card.stitches > 0) Stitches(card.stitches, if (reduce) 1f else u, ink)
                Text(card.label, style = WimgType.desc, color = sub, modifier = Modifier.padding(top = 22.dp))
                Text(card.head, style = WimgType.title.copy(fontSize = 28.sp, lineHeight = 34.sp), color = ink, modifier = Modifier.padding(top = 6.dp))
                if (card.sub.isNotEmpty()) Text(card.sub, style = WimgType.body.copy(fontSize = 15.sp, lineHeight = 21.sp), color = sub, modifier = Modifier.padding(top = 10.dp))
            }
            Text(L("Tippen für weiter"), style = WimgType.desc, color = sub, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
        }
    }
}

@Composable
private fun OpenerFigureView(card: OpenerCard, u: Float, reduce: Boolean, ink: Color) {
    when (card.figure) {
        // Tucks the note away: a small squash as the card lands.
        OpenerFigure.VOLL -> {
            val k = if (reduce) 1f else Drawer.transform((u * 700f / 290f).coerceAtMost(1f))
            Squirrel(SquirrelPose.VOLL, 220.dp, Modifier.graphicsLayer {
                scaleX = 1.03f + (1f - 1.03f) * k; scaleY = 0.95f + (1f - 0.95f) * k
                transformOrigin = TransformOrigin(0.5f, 1f)
            })
        }
        // The ring fills up to the Sparquote.
        OpenerFigure.RING -> {
            val ringColor = if (Wimg.colors.isDark) Color(0xFF8FB0D3) else Color(0xFF4A6D96)
            val f = card.ring * (if (reduce) 1f else Drawer.transform(u))
            Box(Modifier.size(240.dp)) {
                Canvas(Modifier.size(240.dp)) {
                    val w = 12.dp.toPx(); val r = 96.dp.toPx()
                    val tl = Offset(center.x - r, center.y - r); val sz = androidx.compose.ui.geometry.Size(2 * r, 2 * r)
                    drawCircle(ink.copy(alpha = 0.10f), r, center, style = Stroke(w))
                    if (f > 0.001f) drawArc(ringColor, -90f, 360f * f, false, tl, sz, style = Stroke(w, cap = StrokeCap.Round))
                }
                Squirrel(SquirrelPose.NORMAL, 176.dp, Modifier.align(Alignment.Center).offset(y = 4.dp))
            }
        }
        OpenerFigure.SLEEP -> Squirrel(SquirrelPose.SLEEP, 220.dp, z = 1f)
        // The ghost it caught, still holding the new price.
        OpenerFigure.CAUGHT -> Box(Modifier.width(300.dp).height(230.dp)) {
            Squirrel(SquirrelPose.LOOK, 220.dp, Modifier.align(Alignment.CenterEnd))
            PriceGhost(card.prices, 140.dp, Modifier.align(Alignment.CenterStart).offset(y = 30.dp))
        }
    }
}

/** One cross stitch per day without spending, appearing one after another. */
@Composable
private fun Stitches(n: Int, u: Float, ink: Color) {
    val shown = (u.coerceIn(0f, 1f) * 1.1f * n + 0.0001f).toInt().coerceAtMost(n)
    Canvas(Modifier.fillMaxWidth().padding(top = 14.dp).height(28.dp)) {
        val y = size.height / 2
        drawLine(ink.copy(alpha = 0.10f), Offset(6.dp.toPx(), y), Offset(size.width - 6.dp.toPx(), y), 10.dp.toPx(), StrokeCap.Round)
        val left = 18.dp.toPx(); val right = size.width - 18.dp.toPx()
        val step = if (n > 1) minOf(24.dp.toPx(), (right - left) / (n - 1)) else 0f
        val a = minOf(5.dp.toPx(), step * 0.4f).coerceAtLeast(2.dp.toPx())
        val orange = Color(0xFFE08A2E)
        for (j in 0 until shown) {
            val x = left + j * step
            drawLine(orange, Offset(x - a, y - a), Offset(x + a, y + a), 3.dp.toPx(), StrokeCap.Round)
            drawLine(orange, Offset(x - a, y + a), Offset(x + a, y - a), 3.dp.toPx(), StrokeCap.Round)
        }
    }
}

/**
 * The opener's cards, only the ones that are true for this period. Empty when
 * nothing was left over (no opener then): the first card is the one that matters.
 */
@Composable
internal fun openerCards(d: ReviewData, label: String, prevLabel: String?, salaryMode: Boolean): List<OpenerCard> {
    val s = d.summary ?: return emptyList()
    val income = s.income
    val net = income - kotlin.math.abs(s.expenses)
    if (income <= 0.0 || net <= 0.0) return emptyList()
    val rate = (net / income * 100).toInt()
    val green = if (Wimg.colors.isDark) Color(0xFF6FD39A) else Color(0xFF2E9E62)
    fun withAmount(template: String, amount: String) = androidx.compose.ui.text.buildAnnotatedString {
        val parts = template.split("%s", limit = 2)
        append(parts[0])
        pushStyle(androidx.compose.ui.text.SpanStyle(color = green)); append(amount); pop()
        append(parts.getOrElse(1) { "" })
    }
    fun eur(v: Double) = com.wimg.app.ui.components.amountText(v, showPlus = false)
    return buildList {
        add(OpenerCard(label,
            withAmount(if (salaryMode) L("Vom Gehalt sind %s übrig geblieben.") else L("Von den Einnahmen sind %s übrig geblieben."), eur(net)),
            L("Sparquote %d %%.", rate), OpenerFigure.VOLL))
        val p = d.previous
        val prevRate = if (p != null && p.income > 0) ((p.income - kotlin.math.abs(p.expenses)) / p.income * 100).toInt() else null
        if (prevRate != null && rate > prevRate) add(OpenerCard(L("Sparquote"),
            AnnotatedString(if (prevLabel != null) L("Sparquote %d %%, höher als im %s.", rate, prevLabel) else L("Sparquote %d %%, höher als im Zeitraum davor.", rate)),
            if (prevLabel != null) L("%s: %d %%.", prevLabel, prevRate) else L("Davor: %d %%.", prevRate),
            OpenerFigure.RING, ring = (rate / 100f).coerceIn(0f, 1f)))
        if (d.noSpend >= 3) add(OpenerCard(L("Ruhige Tage"),
            AnnotatedString(L("%d Tage ohne Ausgaben.", d.noSpend)),
            d.prevNoSpend?.takeIf { d.noSpend > it }?.let { prev ->
                if (prevLabel != null) L("%d mehr als im %s.", d.noSpend - prev, prevLabel) else L("%d mehr als im Zeitraum davor.", d.noSpend - prev)
            } ?: "",
            OpenerFigure.SLEEP, stitches = d.noSpend))
        d.priceRise?.let { r ->
            add(OpenerCard(L("Abo erwischt"),
                AnnotatedString(L("Abo erwischt: %s +%s.", r.name, eur(r.new - r.old))),
                L("Jetzt %s statt %s.", eur(r.new), eur(r.old)),
                OpenerFigure.CAUGHT, prices = eur(r.old) to eur(r.new)))
        }
    }
}
