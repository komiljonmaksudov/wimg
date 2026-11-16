package com.wimg.app.ui.theme

import android.app.Activity
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.Easing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat
import com.wimg.app.R

// Design tokens for the wimg redesign. The rules behind them are in
// ~/Desktop/wimg-redesign/handoff/DESIGN-SYSTEM.md. A colour that shows up in
// the design exports but not here gets a named token here, never a raw hex in
// a screen.

@Immutable
data class WimgPalette(
    val band: Color,
    val bandSub: Color,
    val bandNeg: Color,
    val bandPos: Color,
    val sheet: Color,
    val card: Color,
    val text: Color,
    val text2: Color,
    val text3: Color,
    val line: Color,
    val neutralTint: Color,
    val ink: Color,
    val inkText: Color,
    val accent: Color,
    val onAccent: Color,
    val accentSoft: Color,
    val accentLight: Color,
    val pos: Color,
    val danger: Color,
    val dangerBg: Color,
    val warn: Color,
    val warnBg: Color,
    val sync: Color,
    val syncBg: Color,
    val trackOff: Color,
    val neuBg: Color,
    val neuFg: Color,
    val catVersicherung: Color,
    val catLebensmittel: Color,
    val catNebenkosten: Color,
    val catShopping: Color,
    val catSonstigesBar: Color,
    val isDark: Boolean,
)

val LightWimgPalette = WimgPalette(
    band = Color(0xFF1D1C1A), bandSub = Color(0xFFA8A49C), bandNeg = Color(0xFFFF9A85), bandPos = Color(0xFF86DDA6),
    sheet = Color(0xFFFAF9F6), card = Color(0xFFFFFFFF),
    text = Color(0xFF1A1A1A), text2 = Color(0xFF6B6A66), text3 = Color(0xFFB5B2AC), line = Color(0xFFECE8E1),
    neutralTint = Color(0xFFF1EDE5), ink = Color(0xFF1A1A1A), inkText = Color(0xFFFFFFFF),
    accent = Color(0xFF4A6D96), onAccent = Color(0xFFFFFFFF), accentSoft = Color(0xFFE4ECF5), accentLight = Color(0xFF8FB0D3),
    pos = Color(0xFF1B7A43), danger = Color(0xFFB3261E), dangerBg = Color(0xFFFCE8E6),
    warn = Color(0xFF9A5B00), warnBg = Color(0xFFFFF1D6), sync = Color(0xFFE8710A), syncBg = Color(0xFFFDEBDC),
    trackOff = Color(0xFFE3E5E9), neuBg = Color(0xFFECE6FF), neuFg = Color(0xFF5236C9),
    catVersicherung = Color(0xFF3B6FD8), catLebensmittel = Color(0xFF2E9E6A), catNebenkosten = Color(0xFF8A63D2),
    catShopping = Color(0xFFD9822B), catSonstigesBar = Color(0xFFC9C4BB),
    isDark = false,
)

val DarkWimgPalette = WimgPalette(
    band = Color(0xFF1E1E21), bandSub = Color(0xFF9A9BA0), bandNeg = Color(0xFFFF9A85), bandPos = Color(0xFF86DDA6),
    sheet = Color(0xFF111114), card = Color(0xFF1C1C1E),
    text = Color(0xFFF2F2F3), text2 = Color(0xFF9A9BA0), text3 = Color(0xFF4A4A50), line = Color(0x14FFFFFF),
    neutralTint = Color(0xFF26262A), ink = Color(0xFFF2F2F3), inkText = Color(0xFF111114),
    accent = Color(0xFF6F93BC), onAccent = Color(0xFFFFFFFF), accentSoft = Color(0x298FB0D3), accentLight = Color(0xFF8FB0D3),
    pos = Color(0xFF6FD39A), danger = Color(0xFFFF8A80), dangerBg = Color(0x1FFF8A80),
    warn = Color(0xFFF5B54A), warnBg = Color(0x1FF5B54A), sync = Color(0xFFFF9A3C), syncBg = Color(0x24FF9A3C),
    trackOff = Color(0xFF3A3B41), neuBg = Color(0x2EB9A8FF), neuFg = Color(0xFFCFC2FF),
    catVersicherung = Color(0xFF7FA6F5), catLebensmittel = Color(0xFF5CC992), catNebenkosten = Color(0xFFB39AF0),
    catShopping = Color(0xFFF2A65E), catSonstigesBar = Color(0xFF5A5A60),
    isDark = true,
)

/**
 * Category colours from the design export (light, dark), keyed by the libwimg
 * category id. Sonstiges/unkategorisiert use text2 for the label and their own
 * bar colour (catSonstigesBar).
 */
internal val categoryColors: Map<Int, Pair<Long, Long>> = mapOf(
    1 to (0xFF2E9E6A to 0xFF5CC992),   // Lebensmittel
    2 to (0xFFC2410C to 0xFFF07F5A),   // Essen gehen
    3 to (0xFF0E7490 to 0xFF4FC3D9),   // Transport
    4 to (0xFF8B5E3C to 0xFFC9A27E),   // Wohnen
    5 to (0xFF8A63D2 to 0xFFB39AF0),   // Nebenkosten
    6 to (0xFFBE185D to 0xFFF078B0),   // Unterhaltung
    7 to (0xFFD9822B to 0xFFF2A65E),   // Shopping
    8 to (0xFFD14343 to 0xFFF07272),   // Gesundheit
    9 to (0xFF3B6FD8 to 0xFF7FA6F5),   // Versicherung
    10 to (0xFF1B7A43 to 0xFF6FD39A),  // Einkommen
    11 to (0xFF64748B to 0xFF94A3B8),  // Umbuchung
    12 to (0xFF7C8B2E to 0xFFB5C25A),  // Bargeld
    13 to (0xFF4F46E5 to 0xFF8B8CF5),  // Abonnements
    14 to (0xFF0284C7 to 0xFF5BC0F0),  // Reisen
    15 to (0xFFA16207 to 0xFFD9A54A),  // Bildung
)

/** Foreground colour of a category (icons, dots); Sonstiges falls back to text2. */
fun WimgPalette.category(id: Int): Color =
    categoryColors[id]?.let { Color(if (isDark) it.second else it.first) } ?: text2

/** Bar/segment colour of a category; Sonstiges gets its own neutral bar. */
fun WimgPalette.categoryBar(id: Int): Color =
    categoryColors[id]?.let { Color(if (isDark) it.second else it.first) } ?: catSonstigesBar

// Static weights cut from the Google Fonts variable files (fontTools instancer).
// One file per weight: Android otherwise falls back to the variable font's
// default instance (Manrope's is ExtraLight) and fakes bold on top.
val Manrope = FontFamily(
    Font(R.font.manrope_medium, FontWeight.Medium),
    Font(R.font.manrope_semibold, FontWeight.SemiBold),
    Font(R.font.manrope_bold, FontWeight.Bold),
    Font(R.font.manrope_extrabold, FontWeight.ExtraBold),
)
val Inter = FontFamily(
    Font(R.font.inter_regular, FontWeight.Normal),
    Font(R.font.inter_medium, FontWeight.Medium),
    Font(R.font.inter_semibold, FontWeight.SemiBold),
    Font(R.font.inter_bold, FontWeight.Bold),
)
val JetBrainsMono = FontFamily(
    Font(R.font.jetbrainsmono_regular, FontWeight.Normal),
    Font(R.font.jetbrainsmono_medium, FontWeight.Medium),
)

private const val TABULAR = "tnum"

object WimgType {
    // Single big numbers use proportional figures; tabular only where amounts stack in a column.
    val amountHero = TextStyle(fontFamily = Manrope, fontWeight = FontWeight.ExtraBold, fontSize = 38.sp, lineHeight = 46.sp, letterSpacing = (-1).sp)
    val amountHeroCents = amountHero.copy(fontSize = 21.sp, letterSpacing = (-0.3).sp)
    val amountLarge = TextStyle(fontFamily = Manrope, fontWeight = FontWeight.ExtraBold, fontSize = 24.sp, lineHeight = 30.sp, letterSpacing = (-0.4).sp)
    val amountStat = TextStyle(fontFamily = Manrope, fontWeight = FontWeight.Bold, fontSize = 15.sp, lineHeight = 20.sp, letterSpacing = (-0.2).sp)
    val title = TextStyle(fontFamily = Manrope, fontWeight = FontWeight.ExtraBold, fontSize = 24.sp, lineHeight = 30.sp, letterSpacing = (-0.4).sp)
    val sheetTitle = TextStyle(fontFamily = Manrope, fontWeight = FontWeight.ExtraBold, fontSize = 21.sp, lineHeight = 28.sp)
    val section = TextStyle(fontFamily = Manrope, fontWeight = FontWeight.ExtraBold, fontSize = 18.sp, lineHeight = 24.sp)
    val rowTitle = TextStyle(fontFamily = Inter, fontWeight = FontWeight.SemiBold, fontSize = 15.sp, lineHeight = 21.sp)
    val amountRow = TextStyle(fontFamily = Manrope, fontWeight = FontWeight.Bold, fontSize = 16.sp, lineHeight = 22.sp, fontFeatureSettings = TABULAR)
    val amountRowCents = amountRow.copy(fontSize = 11.sp)
    val button = TextStyle(fontFamily = Manrope, fontWeight = FontWeight.Bold, fontSize = 15.sp, lineHeight = 20.sp)
    val chip = TextStyle(fontFamily = Manrope, fontWeight = FontWeight.Bold, fontSize = 14.sp, lineHeight = 18.sp)
    val body = TextStyle(fontFamily = Inter, fontWeight = FontWeight.Normal, fontSize = 15.sp, lineHeight = 22.sp)
    val desc = TextStyle(fontFamily = Inter, fontWeight = FontWeight.Normal, fontSize = 13.sp, lineHeight = 18.sp)
    val label = TextStyle(fontFamily = Inter, fontWeight = FontWeight.Bold, fontSize = 13.sp, lineHeight = 18.sp)
    val caption = TextStyle(fontFamily = Inter, fontWeight = FontWeight.Medium, fontSize = 12.sp, lineHeight = 16.sp)
    val bandOver = TextStyle(fontFamily = Inter, fontWeight = FontWeight.Medium, fontSize = 13.sp, lineHeight = 18.sp)
    val mono = TextStyle(fontFamily = JetBrainsMono, fontWeight = FontWeight.Medium, fontSize = 13.sp, lineHeight = 19.sp)
}

object WimgShape {
    val sheetTop = RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp)
    val group = RoundedCornerShape(16.dp)
    val bar = RoundedCornerShape(20.dp)
    val button = RoundedCornerShape(13.dp)
    val dockAction = RoundedCornerShape(12.dp)
    val iconTile = RoundedCornerShape(12.dp)
    val toggleTrack = RoundedCornerShape(8.dp)
    val toggleKnob = RoundedCornerShape(6.dp)
    val segmentOuter = RoundedCornerShape(10.dp)
    val segmentInner = RoundedCornerShape(8.dp)
    val bottomSheet = RoundedCornerShape(28.dp)
    val badge = RoundedCornerShape(6.dp)
}

object WimgDimens {
    val sheetPadding = 16.dp
    val rowMinHeight = 56.dp
    val rowInsetDivider = 16.dp
    val touchTarget = 44.dp
    val barHeight = 60.dp
    val barHeightCompact = 52.dp
    val barBottomGap = 20.dp
    val barPadding = 8.dp
    val barGap = 4.dp
    val barDockedWidth = 358.dp
    val dockSeam = 3.dp
    val toggleWidth = 48.dp
    val toggleHeight = 26.dp
    val toggleKnob = 20.dp
    val sheetEdgeInset = 8.dp
    /** Space a scrolling list leaves at the bottom so its last row clears the floating bar. */
    val listBottomClearance = 112.dp
}

object WimgMotion {
    val EaseOut: Easing = CubicBezierEasing(0.23f, 1f, 0.32f, 1f)       // enter, exit, docking
    val EaseInOut: Easing = CubicBezierEasing(0.77f, 0f, 0.175f, 1f)    // on-screen shape changes

    const val PRESS_MS = 120
    const val PRESS_SCALE = 0.97f
    const val DOCK_MIN_MS = 150
    const val DOCK_MAX_MS = 270
    const val DOCK_CONTENT_MS = 200
    const val DOCK_CONTENT_DELAY_MS = 40
    val DOCK_CONTENT_RISE = 6.dp
    const val UNDOCK_MS = 180
    const val UNDO_COUNTDOWN_MS = 6_000
    const val BAR_COMPACT_MS = 160
    const val HOLD_TO_DELETE_MS = 2_000
    const val HOLD_RELEASE_MS = 200

    /** Height change of the bar when a row docks: Δh / 500 s, clamped to 150–270 ms. */
    fun dockDurationMs(deltaHeightDp: Float): Int =
        (deltaHeightDp / 500f * 1000f).toInt().coerceIn(DOCK_MIN_MS, DOCK_MAX_MS)

    fun <T> dock(deltaHeightDp: Float) = tween<T>(dockDurationMs(deltaHeightDp), easing = EaseOut)
    fun <T> undock() = tween<T>(UNDOCK_MS, easing = EaseOut)
    fun <T> barCompact() = tween<T>(BAR_COMPACT_MS, easing = EaseOut)
    fun <T> press() = tween<T>(PRESS_MS, easing = EaseOut)
}

val LocalWimgPalette = staticCompositionLocalOf { LightWimgPalette }

object Wimg {
    val colors: WimgPalette @Composable get() = LocalWimgPalette.current
}

/** Global app state — mutate from Settings to trigger recomposition */
object ThemeState {
    var mode by mutableIntStateOf(-1) // -1=system, 1=light, 2=dark
}

object LocaleState {
    var locale by mutableStateOf("de") // "de" or "en"

    /** The stored choice ("de", "en" or "system"), resolved to "de" or "en". */
    fun stored(context: android.content.Context): String =
        when (val s = context.getSharedPreferences("wimg", 0).getString("wimg_locale", "system") ?: "system") {
            "system" -> if (java.util.Locale.getDefault().language == "de") "de" else "en"
            else -> s
        }
}

/**
 * True while a screen with a dark band is shown. A counter, not a flag: during
 * navigation the next screen enters before the previous one leaves, so a plain
 * boolean would end up cleared by the screen that just left.
 */
object StatusBarState {
    private var bands by mutableIntStateOf(0)
    val overBand: Boolean get() = bands > 0
    fun enter() { bands++ }
    fun leave() { bands = (bands - 1).coerceAtLeast(0) }
}

@Composable
fun WimgTheme(content: @Composable () -> Unit) {
    // Read stored theme + locale on first composition
    val context = LocalView.current.context
    LaunchedEffect(Unit) {
        val prefs = context.getSharedPreferences("wimg", 0)
        val storedTheme = prefs.getInt("wimg_theme", -1)
        if (ThemeState.mode != storedTheme) ThemeState.mode = storedTheme
        val storedLocale = LocaleState.stored(context)
        if (LocaleState.locale != storedLocale) LocaleState.locale = storedLocale
    }

    val darkTheme = when (ThemeState.mode) {
        1 -> false
        2 -> true
        else -> isSystemInDarkTheme()
    }
    val c = if (darkTheme) DarkWimgPalette else LightWimgPalette
    val scheme = if (darkTheme) {
        darkColorScheme(
            primary = c.accent, onPrimary = c.onAccent, primaryContainer = c.accentSoft, onPrimaryContainer = c.text,
            background = c.sheet, onBackground = c.text, surface = c.card, onSurface = c.text,
            surfaceVariant = c.neutralTint, onSurfaceVariant = c.text2, outline = c.line, outlineVariant = c.line,
            error = c.danger, errorContainer = c.dangerBg, onErrorContainer = c.danger,
            surfaceContainer = c.card, surfaceContainerLow = c.card, surfaceContainerHigh = c.card,
        )
    } else {
        lightColorScheme(
            primary = c.accent, onPrimary = c.onAccent, primaryContainer = c.accentSoft, onPrimaryContainer = c.text,
            background = c.sheet, onBackground = c.text, surface = c.card, onSurface = c.text,
            surfaceVariant = c.neutralTint, onSurfaceVariant = c.text2, outline = c.line, outlineVariant = c.line,
            error = c.danger, errorContainer = c.dangerBg, onErrorContainer = c.danger,
            surfaceContainer = c.card, surfaceContainerLow = c.card, surfaceContainerHigh = c.card,
        )
    }

    // Screens with a band set light status bar icons themselves (see Band); the
    // default fits the sheet for screens that haven't been redesigned yet.
    val view = LocalView.current
    val overBand = StatusBarState.overBand // read in composition so a change recomposes
    if (!view.isInEditMode) {
        SideEffect {
            // HyperOS recolours dark fills in otherwise light screens (the active
            // black chip came out white). wimg themes itself: opt this view out.
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) view.isForceDarkAllowed = false
            val window = (view.context as Activity).window
            val insets = WindowCompat.getInsetsController(window, view)
            insets.isAppearanceLightStatusBars = !darkTheme && !overBand
            insets.isAppearanceLightNavigationBars = !darkTheme
        }
    }

    CompositionLocalProvider(LocalWimgPalette provides c) {
        MaterialTheme(
            colorScheme = scheme,
            typography = Typography(
                headlineLarge = WimgType.title.copy(fontSize = 30.sp, lineHeight = 36.sp),
                headlineMedium = WimgType.title.copy(fontSize = 26.sp, lineHeight = 32.sp),
                headlineSmall = WimgType.title,
                titleLarge = WimgType.sheetTitle,
                titleMedium = WimgType.section.copy(fontSize = 17.sp),
                titleSmall = WimgType.button,
                bodyLarge = WimgType.body,
                bodyMedium = WimgType.body.copy(fontSize = 14.sp, lineHeight = 20.sp),
                bodySmall = WimgType.desc,
                labelLarge = WimgType.button,
                labelMedium = WimgType.label.copy(fontSize = 12.sp),
                labelSmall = WimgType.caption.copy(fontSize = 11.sp),
            ),
            shapes = Shapes(small = WimgShape.button, medium = WimgShape.group, large = WimgShape.bottomSheet),
            content = content,
        )
    }
}
