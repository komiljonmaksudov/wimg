package com.wimg.app.ui.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Sync
import androidx.compose.material.icons.outlined.Undo
import androidx.compose.material.icons.outlined.UnfoldMore
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.wimg.app.i18n.L
import com.wimg.app.ui.theme.StatusBarState
import com.wimg.app.ui.theme.Wimg
import com.wimg.app.ui.theme.WimgDimens
import com.wimg.app.ui.theme.WimgMotion
import com.wimg.app.ui.theme.WimgShape
import com.wimg.app.ui.theme.WimgType
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.Locale
import kotlin.math.abs

// ---------------------------------------------------------------------------
// Amounts: 1.234,56 €, minus is U+2212, income gets an explicit +, cents smaller.
// ---------------------------------------------------------------------------

const val MINUS = "−"

/** Splits an amount in euros into ("−1.234", ",56 €"). */
fun amountParts(euros: Double, showPlus: Boolean = true): Pair<String, String> {
    val cents = Math.round(abs(euros) * 100)
    val whole = String.format(Locale.GERMANY, "%,d", cents / 100)
    val sign = when {
        cents == 0L -> ""
        euros < 0 -> MINUS
        showPlus -> "+"
        else -> ""
    }
    return sign + whole to String.format(Locale.GERMANY, ",%02d €", cents % 100)
}

/** Plain-text amount for places that can't style cents (titles, accessibility). */
fun amountText(euros: Double, showPlus: Boolean = true): String =
    amountParts(euros, showPlus).let { it.first + it.second }

@Composable
fun Amount(
    euros: Double,
    style: TextStyle,
    centsStyle: TextStyle,
    color: Color,
    modifier: Modifier = Modifier,
    showPlus: Boolean = true,
) {
    val (whole, cents) = amountParts(euros, showPlus)
    Text(
        buildAnnotatedString {
            append(whole)
            withStyle(SpanStyle(fontSize = centsStyle.fontSize, letterSpacing = centsStyle.letterSpacing)) { append(cents) }
        },
        style = style,
        color = color,
        maxLines = 1,
        modifier = modifier,
    )
}

// ---------------------------------------------------------------------------
// Press feedback: scale 0.97 on press-down, 120 ms EaseOut.
// ---------------------------------------------------------------------------

@Composable
fun Modifier.pressable(enabled: Boolean = true, role: Role = Role.Button, label: String? = null, onClick: () -> Unit): Modifier {
    val source = remember { MutableInteractionSource() }
    val pressed by source.collectIsPressedAsState()
    val s by animateFloatAsState(if (pressed) WimgMotion.PRESS_SCALE else 1f, WimgMotion.press(), label = "press")
    return this
        .scale(s)
        .clickable(interactionSource = source, indication = null, enabled = enabled, role = role, onClickLabel = label, onClick = onClick)
}

// ---------------------------------------------------------------------------
// Band + sheet: the one number that matters on dark, the list on light.
// ---------------------------------------------------------------------------

/**
 * A screen in the redesign: dark band at the top (under the status bar), light
 * sheet with 20 dp top corners below it. Marks the status bar as "over band" so
 * its icons turn light while this screen is shown.
 */
@Composable
fun BandScreen(
    band: @Composable ColumnScope.() -> Unit,
    modifier: Modifier = Modifier,
    sheet: @Composable ColumnScope.() -> Unit,
) {
    DisposableEffect(Unit) {
        StatusBarState.enter()
        onDispose { StatusBarState.leave() }
    }
    val c = Wimg.colors
    Column(modifier.fillMaxSize().background(c.band)) {
        Column(
            Modifier.fillMaxWidth().statusBarsPadding().padding(start = 20.dp, end = 20.dp, top = 16.dp, bottom = 22.dp),
            content = band,
        )
        Column(
            Modifier.fillMaxSize().clip(WimgShape.sheetTop).background(c.sheet),
            content = sheet,
        )
    }
}

/** "Over" line (13, bandSub) + title, for list screens. */
@Composable
fun BandTitle(over: String?, title: String) {
    val c = Wimg.colors
    if (over != null) Text(over, style = WimgType.bandOver, color = c.bandSub)
    Text(title, style = WimgType.title, color = Color.White)
}

/** Sub line under a band amount, with an optional status dot. */
@Composable
fun BandSub(text: String, dot: Color? = null) {
    val c = Wimg.colors
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 4.dp)) {
        if (dot != null) {
            Box(Modifier.size(7.dp).clip(CircleShape).background(dot))
            Spacer(Modifier.width(6.dp))
        }
        Text(text, style = WimgType.desc, color = c.bandSub, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

// ---------------------------------------------------------------------------
// Groups and rows: lists, not cards.
// ---------------------------------------------------------------------------

@Composable
fun GroupLabel(text: String, modifier: Modifier = Modifier) {
    Text(text, style = WimgType.label, color = Wimg.colors.text2, modifier = modifier.padding(start = 4.dp, top = 18.dp, bottom = 8.dp))
}

@Composable
fun WimgGroup(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    val c = Wimg.colors
    Column(
        modifier
            .fillMaxWidth()
            .clip(WimgShape.group)
            .background(c.card)
            .border(1.dp, c.line, WimgShape.group),
        content = content,
    )
}

@Composable
fun RowDivider() {
    HorizontalDivider(Modifier.padding(start = WimgDimens.rowInsetDivider), thickness = 1.dp, color = Wimg.colors.line)
}

/** Square-ish icon tile in rows: 36 dp, 12 dp corners, category colour at 10–13 %. */
@Composable
fun IconTile(icon: ImageVector, tint: Color, modifier: Modifier = Modifier) {
    val bg = tint.copy(alpha = if (Wimg.colors.isDark) 0.13f else 0.10f)
    Box(modifier.size(36.dp).clip(WimgShape.iconTile).background(bg), contentAlignment = Alignment.Center) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(19.dp))
    }
}

@Composable
fun WimgRow(
    title: String,
    modifier: Modifier = Modifier,
    desc: String? = null,
    leading: (@Composable () -> Unit)? = null,
    trailing: (@Composable RowScope.() -> Unit)? = null,
    chevron: Boolean = false,
    onClick: (() -> Unit)? = null,
) {
    val c = Wimg.colors
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = if (desc != null) 60.dp else WimgDimens.rowMinHeight)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (leading != null) {
            leading()
            Spacer(Modifier.width(12.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(title, style = WimgType.rowTitle, color = c.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (desc != null) Text(desc, style = WimgType.desc, color = c.text2, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
        if (trailing != null) {
            Spacer(Modifier.width(12.dp))
            trailing()
        }
        if (chevron) {
            Spacer(Modifier.width(6.dp))
            Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = null, tint = c.text3, modifier = Modifier.size(20.dp))
        }
    }
}

// ---------------------------------------------------------------------------
// Toggle: soft rectangle, accent when on.
// ---------------------------------------------------------------------------

@Composable
fun WimgToggle(checked: Boolean, onCheckedChange: (Boolean) -> Unit, modifier: Modifier = Modifier, label: String? = null) {
    val c = Wimg.colors
    val x by animateFloatAsState(if (checked) 1f else 0f, tween(180, easing = WimgMotion.EaseInOut), label = "toggle")
    val track = if (checked) c.accent else c.trackOff
    Box(
        modifier
            .size(WimgDimens.toggleWidth, WimgDimens.toggleHeight)
            .clip(WimgShape.toggleTrack)
            .background(track)
            .clickable(role = Role.Switch, onClickLabel = label) { onCheckedChange(!checked) }
            .padding(3.dp),
    ) {
        Box(
            Modifier
                .padding(start = (22 * x).dp)
                .size(WimgDimens.toggleKnob)
                .shadow(1.dp, WimgShape.toggleKnob)
                .clip(WimgShape.toggleKnob)
                .background(Color.White),
        )
    }
}

// ---------------------------------------------------------------------------
// Quiet line: icon + one sentence in text2 instead of a dialog.
// ---------------------------------------------------------------------------

@Composable
fun QuietLine(text: String, modifier: Modifier = Modifier, icon: ImageVector = Icons.Outlined.Info, color: Color = Wimg.colors.text2) {
    Row(modifier.fillMaxWidth().padding(horizontal = 6.dp, vertical = 10.dp)) {
        Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(17.dp).padding(top = 1.dp))
        Spacer(Modifier.width(8.dp))
        Text(text, style = WimgType.desc.copy(lineHeight = WimgType.desc.lineHeight), color = color)
    }
}

// ---------------------------------------------------------------------------
// Dock: status rows that sit on top of the floating bar. One at a time; newest wins.
// ---------------------------------------------------------------------------

enum class DockKind { Sync, Error, Undo, Prompt, Info }

data class DockRow(
    val kind: DockKind,
    val title: String,
    val sub: String? = null,
    val action: String? = null,
    val onAction: (() -> Unit)? = null,
    /** 0..1 for a running fetch/transfer; null when the seam isn't a progress bar. */
    val progress: Float? = null,
    /** Auto-dismiss after this many ms (undo uses the 6 s countdown seam). */
    val timeoutMs: Int? = null,
    val id: Long = System.nanoTime(),
)

object Dock {
    var row by mutableStateOf<DockRow?>(null)
        private set

    fun show(r: DockRow) { row = r }
    fun dismiss(id: Long? = null) { if (id == null || row?.id == id) row = null }

    fun undo(title: String, sub: String? = null, onUndo: () -> Unit) =
        show(DockRow(DockKind.Undo, title, sub, action = "Rückgängig", onAction = onUndo, timeoutMs = WimgMotion.UNDO_COUNTDOWN_MS))

    fun info(title: String, sub: String? = null) =
        show(DockRow(DockKind.Info, title, sub, timeoutMs = 4_000))

    fun error(title: String, sub: String? = null, action: String? = null, onAction: (() -> Unit)? = null) =
        show(DockRow(DockKind.Error, title, sub, action, onAction))
}

@Composable
private fun DockedRowContent(r: DockRow) {
    val c = Wimg.colors
    val (circleBg, circleFg, icon) = when (r.kind) {
        DockKind.Sync -> Triple(c.syncBg, c.sync, Icons.Outlined.Sync)
        DockKind.Error -> Triple(c.dangerBg, c.danger, Icons.Outlined.ErrorOutline)
        DockKind.Undo -> Triple(c.neutralTint, c.text, Icons.Outlined.Undo)
        DockKind.Prompt -> Triple(c.accentSoft, c.accent, Icons.Outlined.Info)
        DockKind.Info -> Triple(c.neutralTint, c.pos, Icons.Outlined.Check)
    }
    // Countdown or progress along the seam.
    val seam = remember(r.id) { Animatable(if (r.kind == DockKind.Undo) 1f else 0f) }
    LaunchedEffect(r.id) {
        if (r.timeoutMs != null) {
            // The seam is only the picture of the countdown; the timeout runs on
            // the clock. With "remove animations" on, animations finish at once,
            // and an undo row tied to one would vanish before anyone could tap it.
            if (r.kind == DockKind.Undo) launch { seam.animateTo(0f, tween(r.timeoutMs, easing = LinearEasing)) }
            delay(r.timeoutMs.toLong())
            Dock.dismiss(r.id)
        }
    }
    LaunchedEffect(r.progress) { r.progress?.let { seam.animateTo(it, tween(400, easing = LinearEasing)) } }
    val seamColor = when (r.kind) {
        DockKind.Sync -> c.sync
        DockKind.Error -> c.danger
        DockKind.Undo -> c.ink
        else -> Color.Transparent
    }
    val seamFraction = when {
        r.kind == DockKind.Error -> 1f
        r.kind == DockKind.Undo || r.progress != null -> seam.value
        else -> 0f
    }

    Column {
        Box(Modifier.fillMaxWidth().padding(top = 6.dp), contentAlignment = Alignment.Center) {
            Box(Modifier.size(32.dp, 4.dp).clip(CircleShape).background(c.line))
        }
        Row(
            Modifier.fillMaxWidth().padding(start = 12.dp, end = 10.dp, top = 6.dp, bottom = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(Modifier.size(36.dp).clip(CircleShape).background(circleBg), contentAlignment = Alignment.Center) {
                Icon(icon, contentDescription = null, tint = circleFg, modifier = Modifier.size(19.dp))
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(r.title, style = WimgType.chip, color = c.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (r.sub != null) Text(r.sub, style = WimgType.caption, color = c.text2, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            if (r.action != null && r.onAction != null) {
                Spacer(Modifier.width(8.dp))
                Box(
                    Modifier
                        .height(40.dp)
                        .clip(WimgShape.dockAction)
                        .background(c.ink)
                        .pressable { r.onAction.invoke(); Dock.dismiss(r.id) }
                        .padding(horizontal = 14.dp),
                    contentAlignment = Alignment.Center,
                ) { Text(L(r.action), style = WimgType.chip, color = c.inkText) }
            }
        }
        Box(Modifier.fillMaxWidth().height(WimgDimens.dockSeam).background(c.line)) {
            Box(Modifier.fillMaxHeight().fillMaxWidth(seamFraction).background(seamColor))
        }
    }
}

// ---------------------------------------------------------------------------
// Floating bar: where you are on the left, what you can do on the right.
// ---------------------------------------------------------------------------

data class Place(val route: String, val label: String, val icon: ImageVector, val gapBefore: Boolean = false)

@Composable
fun BarChip(
    label: String,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    unfold: Boolean = false,
    active: Boolean = false,
    contentDescription: String? = null,
    onClick: () -> Unit,
) {
    val c = Wimg.colors
    Row(
        modifier
            .height(WimgDimens.touchTarget)
            .clip(WimgShape.button)
            .background(if (active) c.ink else c.neutralTint)
            .pressable(label = contentDescription, onClick = onClick)
            .then(if (contentDescription != null) Modifier.semantics { this.contentDescription = contentDescription } else Modifier)
            .padding(horizontal = if (label.isEmpty()) 16.dp else 13.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(7.dp),
    ) {
        val fg = if (active) c.inkText else c.text
        if (icon != null) Icon(icon, contentDescription = null, tint = fg, modifier = Modifier.size(if (label.isEmpty()) 20.dp else 18.dp))
        if (label.isNotEmpty()) Text(label, style = WimgType.chip, color = fg, maxLines = 1)
        if (unfold) Icon(Icons.Outlined.UnfoldMore, contentDescription = null, tint = if (active) c.inkText else c.text2, modifier = Modifier.size(15.dp))
    }
}

@Composable
fun BarIcon(icon: ImageVector, label: String, modifier: Modifier = Modifier, accent: Boolean = false, onClick: () -> Unit) {
    val c = Wimg.colors
    Box(
        modifier
            .size(WimgDimens.touchTarget)
            .clip(WimgShape.button)
            .background(if (accent) c.accent else Color.Transparent)
            .pressable(label = label, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = label, tint = if (accent) c.onAccent else c.text, modifier = Modifier.size(21.dp))
    }
}

/**
 * The floating bar with its docked row. Content-width, 20 dp above the bottom
 * edge; a docked row sits on top of it on the same surface, and the bar widens
 * to 358 dp while one is shown.
 */
@Composable
fun FloatingBar(
    modifier: Modifier = Modifier,
    /** Separator between "where" and "what"; off when there is nothing on the right. */
    divider: Boolean = true,
    left: @Composable RowScope.() -> Unit,
    right: @Composable RowScope.() -> Unit,
) {
    val c = Wimg.colors
    val docked = Dock.row
    Column(
        modifier
            .then(if (docked != null) Modifier.width(WimgDimens.barDockedWidth) else Modifier.width(IntrinsicSize.Max))
            .widthIn(max = WimgDimens.barDockedWidth)
            .shadow(14.dp, WimgShape.bar, ambientColor = Color.Black.copy(alpha = 0.18f), spotColor = Color.Black.copy(alpha = 0.18f))
            .clip(WimgShape.bar)
            .background(c.card)
            .border(1.dp, c.line, WimgShape.bar)
            .animateContentSize(WimgMotion.dock(80f)),
    ) {
        AnimatedVisibility(
            visible = docked != null,
            enter = fadeIn(tween(WimgMotion.DOCK_CONTENT_MS, WimgMotion.DOCK_CONTENT_DELAY_MS, WimgMotion.EaseOut)) +
                slideInVertically(tween(WimgMotion.DOCK_CONTENT_MS, WimgMotion.DOCK_CONTENT_DELAY_MS, WimgMotion.EaseOut)) { it / 8 },
            exit = fadeOut(WimgMotion.undock()) + slideOutVertically(WimgMotion.undock()) { it / 8 },
        ) {
            // Keep showing the last row while it animates out.
            var last by remember { mutableStateOf(docked) }
            if (docked != null) last = docked
            last?.let { DockedRowContent(it) }
        }
        Row(
            Modifier.height(WimgDimens.barHeight).padding(WimgDimens.barPadding),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(WimgDimens.barGap),
        ) {
            left()
            if (divider) Box(Modifier.padding(horizontal = 4.dp).size(1.dp, 24.dp).background(c.line))
            Spacer(Modifier.weight(1f, fill = docked != null))
            right()
        }
    }
}

/** The place switcher that opens from the bar's place chip. */
@Composable
fun PlaceMenu(places: List<Place>, current: String?, onPick: (Place) -> Unit, modifier: Modifier = Modifier) {
    val c = Wimg.colors
    Column(
        modifier
            .width(300.dp)
            .shadow(18.dp, WimgShape.bar, ambientColor = Color.Black.copy(alpha = 0.2f), spotColor = Color.Black.copy(alpha = 0.2f))
            .clip(WimgShape.bar)
            .background(c.card)
            .border(1.dp, c.line, WimgShape.bar)
            .padding(8.dp),
    ) {
        places.forEach { p ->
            if (p.gapBefore) {
                Box(Modifier.padding(horizontal = 12.dp, vertical = 6.dp).fillMaxWidth().height(1.dp).background(c.line))
            }
            val selected = p.route == current
            Row(
                Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(12.dp))
                    .background(if (selected) c.neutralTint else Color.Transparent)
                    .clickable { onPick(p) }
                    .padding(horizontal = 12.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(p.icon, contentDescription = null, tint = c.text, modifier = Modifier.size(20.dp))
                Spacer(Modifier.width(12.dp))
                Text(L(p.label), style = WimgType.button.copy(fontWeight = if (selected) WimgType.button.fontWeight else androidx.compose.ui.text.font.FontWeight.SemiBold), color = c.text, modifier = Modifier.weight(1f))
                if (selected) Icon(Icons.Outlined.Check, contentDescription = null, tint = c.accent, modifier = Modifier.size(18.dp))
            }
        }
    }
}

/** Detail-screen bar: [←] [main action] [⋯]. */
@Composable
fun BackChip(label: String, onClick: () -> Unit) {
    BarChip(label = L(label), icon = Icons.AutoMirrored.Outlined.ArrowBack, onClick = onClick)
}

// Re-exported so screens don't need the icon imports for the common bar actions.
object BarIcons {
    val Search = Icons.Outlined.Search
    val Add = Icons.Outlined.Add
}

/** Space a list leaves at its end so the last row clears the floating bar. */
val BarClearance: Dp = WimgDimens.listBottomClearance

// ---------------------------------------------------------------------------
// Per-screen bar contributions: a period/filter chip next to the place chip, and
// a panel that opens above the bar (month picker, filters). Set from a screen
// with BarContribution(...); cleared when the screen leaves.
// ---------------------------------------------------------------------------

data class BarChipSpec(
    val label: String,
    val active: Boolean,
    val onClick: () -> Unit,
    val icon: ImageVector? = null,
    /** Spoken label for an icon-only chip. */
    val contentDescription: String? = null,
)

/** Detail screens replace the place bar with [←] [main action] [⋯]. */
data class DetailBarSpec(
    val onBack: () -> Unit,
    /** No main action: the back button carries [backLabel] ("← Wiederkehrend"). */
    val actionLabel: String?,
    val actionIcon: ImageVector?,
    val onAction: () -> Unit,
    val backLabel: String? = null,
    val onMore: (() -> Unit)? = null,
    val moreActive: Boolean = false,
)

object BarState {
    var detail by mutableStateOf<DetailBarSpec?>(null)
    var chip by mutableStateOf<BarChipSpec?>(null)
    /** Panel shown above the bar with a scrim; tapping the scrim calls [onPanelDismiss]. */
    var panel by mutableStateOf<(@Composable () -> Unit)?>(null)
    var onPanelDismiss by mutableStateOf<() -> Unit>({})
}

@Composable
fun BarContribution(
    chip: BarChipSpec?,
    panel: (@Composable () -> Unit)?,
    onPanelDismiss: () -> Unit,
    detail: DetailBarSpec? = null,
) {
    androidx.compose.runtime.SideEffect {
        BarState.detail = detail
        BarState.chip = chip
        BarState.panel = panel
        BarState.onPanelDismiss = onPanelDismiss
    }
    DisposableEffect(Unit) {
        onDispose {
            BarState.detail = null
            BarState.chip = null
            BarState.panel = null
            BarState.onPanelDismiss = {}
        }
    }
}

/** Card that floats above the bar for pickers and filters (24 dp corners). */
@Composable
fun BarPanel(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    val c = Wimg.colors
    Column(
        modifier
            .padding(horizontal = 16.dp)
            .fillMaxWidth()
            .widthIn(max = 420.dp)
            .shadow(18.dp, RoundedCornerShape(24.dp), ambientColor = Color.Black.copy(alpha = 0.18f), spotColor = Color.Black.copy(alpha = 0.18f))
            .clip(RoundedCornerShape(24.dp))
            .background(c.card)
            .border(1.dp, c.line, RoundedCornerShape(24.dp))
            .padding(start = 16.dp, end = 16.dp, top = 18.dp, bottom = 16.dp),
        content = content,
    )
}

/** Wide accent button in a detail bar ("Kategorie wählen"). */
@Composable
fun BarAction(label: String, icon: ImageVector?, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val c = Wimg.colors
    Row(
        modifier
            .height(WimgDimens.touchTarget)
            .clip(WimgShape.button)
            .background(c.accent)
            .pressable(onClick = onClick)
            .padding(horizontal = 18.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
    ) {
        if (icon != null) Icon(icon, contentDescription = null, tint = c.onAccent, modifier = Modifier.size(19.dp))
        Text(label, style = WimgType.button, color = c.onAccent, maxLines = 1)
    }
}

/** Square back button for detail bars. */
@Composable
fun BarBack(onClick: () -> Unit) {
    val c = Wimg.colors
    Box(
        Modifier.size(WimgDimens.touchTarget).clip(WimgShape.button).background(c.neutralTint).pressable(label = L("Zurück"), onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = L("Zurück"), tint = c.text, modifier = Modifier.size(21.dp))
    }
}
