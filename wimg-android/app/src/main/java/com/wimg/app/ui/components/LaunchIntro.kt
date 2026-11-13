package com.wimg.app.ui.components

import android.provider.Settings
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import com.wimg.app.R
import com.wimg.app.ui.theme.WimgMotion
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.first

/** Same blue as the system splash (windowSplashScreenBackground), so the hand-over is invisible. */
private val SplashBlue = Color(0xFF4F6F93)

/** Once per process: a cold start shows it, coming back to the app doesn't. */
object LaunchIntroState {
    var done by mutableStateOf(false)
    /** Width of the system splash icon view in px (it holds the pocket inset by 64/288). */
    var splashIconPx by mutableStateOf(0)
}

/**
 * Cold-start intro, after the website's pocket refill. Starts with the empty
 * pocket exactly where the system splash drew it, drops the notes and the card
 * in, the pocket settles, then it fades out over the app (which composes
 * underneath the whole time). ~650 ms, tap to skip, skipped when system
 * animations are off.
 */
@Composable
fun LaunchIntro() {
    if (LaunchIntroState.done) return
    val context = LocalContext.current
    val animationsOff = remember {
        runCatching { Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE) }.getOrDefault(1f) == 0f
    }
    if (animationsOff) { LaunchIntroState.done = true; return }

    val density = androidx.compose.ui.platform.LocalDensity.current
    // Start at the size the splash drew the pocket (160/288 of its icon view).
    val startScale = LaunchIntroState.splashIconPx.let { px ->
        if (px <= 0) 1f else (px * 160f / 288f / with(density) { 160.dp.toPx() }).coerceIn(0.3f, 1f)
    }
    val grow = remember { Animatable(1f) }
    // The splash hands over its icon size a frame after we first compose; take it
    // before the splash goes away (MainActivity removes it a frame later).
    LaunchedEffect(startScale) { if (grow.value == 1f && startScale < 1f) grow.snapTo(startScale) }
    val items = remember { List(4) { Animatable(0f) } } // n20, n10, card, n50: drawn back to front
    val settle = remember { Animatable(1f) }
    val out = remember { Animatable(1f) }
    var skipped by remember { mutableStateOf(false) }

    LaunchedEffect(skipped) {
        if (skipped) {
            out.animateTo(0f, tween(160, easing = WimgMotion.EaseOut))
            LaunchIntroState.done = true
            return@LaunchedEffect
        }
        // Wait (briefly) for the splash size, so the pocket starts exactly there.
        kotlinx.coroutines.withTimeoutOrNull(150) { androidx.compose.runtime.snapshotFlow { LaunchIntroState.splashIconPx }.first { it > 0 } }
        delay(32)
        coroutineScope {
            launch { grow.animateTo(1f, tween(280, easing = WimgMotion.EaseOut)) }
            // Website refill stagger; the front-most note lands last.
            val starts = listOf(100L, 60L, 40L, 0L)
            items.forEachIndexed { i, a ->
                launch {
                    delay(60 + starts[i])
                    a.animateTo(1f, tween(300, easing = WimgMotion.EaseOut))
                }
            }
            launch {
                // The pocket gives a little as the last note lands.
                delay(60 + 100 + 230)
                settle.snapTo(0.97f)
                settle.animateTo(1f, spring(dampingRatio = 0.5f, stiffness = Spring.StiffnessMedium))
            }
            launch {
                delay(60 + 100 + 300 + 90)
                out.animateTo(0f, tween(200, easing = WimgMotion.EaseOut))
            }
        }
        LaunchIntroState.done = true
    }

    Box(
        Modifier
            .fillMaxSize()
            .graphicsLayer { alpha = out.value }
            .background(SplashBlue)
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { skipped = true },
        contentAlignment = Alignment.Center,
    ) {
        // Same size and centre as the system splash icon (splash_pocket.xml).
        Box(Modifier.size(160.dp).graphicsLayer { scaleX = grow.value; scaleY = grow.value }) {
            val res = listOf(R.drawable.launch_n20, R.drawable.launch_n10, R.drawable.launch_card, R.drawable.launch_n50)
            res.forEachIndexed { i, r ->
                val p = items[i].value
                Layer(r, Modifier.graphicsLayer {
                    alpha = (p * 1.8f).coerceAtMost(1f)
                    translationY = -(1f - p) * size.height * 0.22f
                })
            }
            Layer(R.drawable.launch_pocket, Modifier.graphicsLayer {
                scaleY = settle.value
                scaleX = 1f + (1f - settle.value) * 0.3f
                transformOrigin = TransformOrigin(0.5f, 0.3f)
            })
        }
    }
}

@Composable
private fun Layer(res: Int, modifier: Modifier = Modifier) {
    Image(painterResource(res), contentDescription = null, modifier = modifier.fillMaxSize())
}
