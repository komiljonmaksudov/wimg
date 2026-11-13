package com.wimg.app.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.AccountBalance
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Sync
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.wimg.app.R
import com.wimg.app.i18n.L
import com.wimg.app.ui.components.BandScreen
import com.wimg.app.ui.components.StepBand
import com.wimg.app.ui.components.pressable
import com.wimg.app.ui.theme.StatusBarState
import com.wimg.app.ui.theme.Wimg
import com.wimg.app.ui.theme.WimgDimens
import com.wimg.app.ui.theme.WimgMotion
import com.wimg.app.ui.theme.WimgShape
import com.wimg.app.ui.theme.WimgType

/**
 * First start: welcome, then where the transactions come from. Finishes with the
 * route to open next: "fints", "import", "settings/sync/link" or "dashboard".
 */
@Composable
fun OnboardingScreen(onComplete: (String) -> Unit) {
    var page by remember { mutableIntStateOf(0) }
    BackHandler(enabled = page == 1) { page = 0 }
    AnimatedContent(
        targetState = page,
        transitionSpec = { fadeIn(tween(200, easing = WimgMotion.EaseOut)) togetherWith fadeOut(tween(120)) },
        label = "onboarding",
    ) { p ->
        if (p == 0) Welcome(onStart = { page = 1 }, onHaveWimg = { onComplete("settings/sync/link") })
        else SourceChoice(onBack = { page = 0 }, onPick = onComplete)
    }
}

@Composable
private fun Welcome(onStart: () -> Unit, onHaveWimg: () -> Unit) {
    val c = Wimg.colors
    // Dark screen: light status bar icons.
    DisposableEffect(Unit) { StatusBarState.enter(); onDispose { StatusBarState.leave() } }
    Box(Modifier.fillMaxSize().background(c.band)) {
        Column(
            Modifier.fillMaxSize().statusBarsPadding().verticalScroll(rememberScrollState())
                .padding(start = 24.dp, end = 24.dp, top = 56.dp, bottom = 140.dp),
        ) {
            AppIcon(Modifier.size(76.dp))
            Text(
                L("Deine Finanzen.") + "\n" + L("Auf deinem Gerät."),
                style = WimgType.title.copy(fontSize = WimgType.title.fontSize * 1.45f, lineHeight = WimgType.title.fontSize * 1.6f),
                color = Color.White, modifier = Modifier.padding(top = 36.dp),
            )
            Text(L("Sieh, wohin dein Geld geht. Ohne Konto, ohne Cloud-Zwang."), style = WimgType.body.copy(fontSize = WimgType.body.fontSize * 1.1f), color = c.bandSub, modifier = Modifier.padding(top = 14.dp))
            Spacer(Modifier.height(36.dp))
            Feature(Icons.Outlined.Lock, L("Bleibt auf deinem Gerät"), L("Kein Konto nötig. Deine Daten gehören dir."))
            Feature(Icons.Outlined.AccountBalance, L("Direkt von deiner Bank"), L("Umsätze per FinTS abrufen, ohne Dienst dazwischen. Oder eine CSV-Datei importieren."))
            Feature(Icons.Outlined.Sync, L("Sync zwischen deinen Geräten"), L("Ende-zu-Ende-verschlüsselt, mit einem Schlüssel statt Passwort."))
        }
        OnboardingBar(Modifier.align(Alignment.BottomCenter)) {
            BarButton(L("Ich habe schon wimg"), primary = false, modifier = Modifier.weight(1f), onClick = onHaveWimg)
            BarButton(L("Los geht’s"), primary = true, modifier = Modifier.weight(1f), onClick = onStart)
        }
    }
}

/** The adaptive icon's two layers, cropped to the visible 72/108 like a launcher does. */
@Composable
private fun AppIcon(modifier: Modifier) {
    Box(modifier.shadow(12.dp, RoundedCornerShape(22.dp)).clip(RoundedCornerShape(22.dp))) {
        listOf(R.mipmap.ic_launcher_background, R.mipmap.ic_launcher_foreground).forEach { res ->
            Image(
                painterResource(res), contentDescription = null, contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize().graphicsLayer { scaleX = 1.5f; scaleY = 1.5f },
            )
        }
    }
}

@Composable
private fun Feature(icon: ImageVector, title: String, desc: String) {
    val c = Wimg.colors
    Row(Modifier.padding(bottom = 22.dp)) {
        Box(Modifier.size(44.dp).clip(WimgShape.iconTile).background(Color.White.copy(alpha = 0.07f)), contentAlignment = Alignment.Center) {
            Icon(icon, contentDescription = null, tint = Color(0xFF9DB8DA), modifier = Modifier.size(21.dp))
        }
        Spacer(Modifier.width(16.dp))
        Column {
            Text(title, style = WimgType.rowTitle.copy(fontWeight = FontWeight.Bold, fontSize = WimgType.rowTitle.fontSize * 1.07f), color = Color.White)
            Text(desc, style = WimgType.body, color = c.bandSub, modifier = Modifier.padding(top = 2.dp))
        }
    }
}

private data class Choice(val route: String, val title: String, val desc: String, val recommended: Boolean = false)

@Composable
private fun SourceChoice(onBack: () -> Unit, onPick: (String) -> Unit) {
    val c = Wimg.colors
    val choices = listOf(
        Choice("fints", "Bank verbinden", "Umsätze direkt von der Bank holen, ca. 1.700 deutsche Banken. Mit TAN.", recommended = true),
        Choice("import", "CSV importieren", "Datei von Comdirect, Trade Republic oder Scalable."),
        Choice("dashboard", "Leer starten", "Erstmal umsehen. Daten kannst du später hinzufügen."),
    )
    var selected by remember { mutableIntStateOf(0) }
    Box(Modifier.fillMaxSize()) {
        BandScreen(band = { StepBand(L("Einrichten"), 1, 3, L("Woher kommen deine Umsätze?")) }) {
            Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 140.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                choices.forEachIndexed { i, ch ->
                    val on = selected == i
                    Row(
                        Modifier.fillMaxWidth().pressable(role = androidx.compose.ui.semantics.Role.RadioButton) { selected = i }
                            .clip(WimgShape.group).background(c.card)
                            .border(if (on) 2.dp else 1.dp, if (on) c.ink else c.line, WimgShape.group)
                            .padding(18.dp),
                    ) {
                        Box(Modifier.padding(top = 2.dp).size(24.dp).clip(CircleShape).border(2.dp, if (on) c.ink else c.text3, CircleShape), contentAlignment = Alignment.Center) {
                            if (on) Box(Modifier.size(12.dp).clip(CircleShape).background(c.ink))
                        }
                        Spacer(Modifier.width(16.dp))
                        Column(Modifier.weight(1f)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(L(ch.title), style = WimgType.rowTitle.copy(fontWeight = FontWeight.Bold, fontSize = WimgType.rowTitle.fontSize * 1.1f), color = c.text)
                                if (ch.recommended) {
                                    Text(
                                        L("empfohlen"), style = WimgType.caption, color = c.text2,
                                        modifier = Modifier.padding(start = 10.dp).clip(CircleShape).background(c.neutralTint).padding(horizontal = 10.dp, vertical = 3.dp),
                                    )
                                }
                            }
                            Text(L(ch.desc), style = WimgType.body, color = c.text2, modifier = Modifier.padding(top = 4.dp))
                        }
                    }
                }
                Text(
                    L("Du kannst später jederzeit eine Bank verbinden oder weitere Dateien importieren, über das + in der Leiste."),
                    style = WimgType.desc, color = c.text2, modifier = Modifier.padding(horizontal = 4.dp, vertical = 4.dp),
                )
            }
        }
        OnboardingBar(Modifier.align(Alignment.BottomCenter)) {
            Box(
                Modifier.size(WimgDimens.touchTarget).pressable(label = L("Zurück"), onClick = onBack).clip(WimgShape.button).background(c.neutralTint),
                contentAlignment = Alignment.Center,
            ) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = null, tint = c.text, modifier = Modifier.size(22.dp)) }
            BarButton(L("Weiter"), primary = true, modifier = Modifier.weight(1f)) { onPick(choices[selected].route) }
        }
    }
}

/** Same surface as the floating bar, full width, for screens before the app's bar exists. */
@Composable
private fun OnboardingBar(modifier: Modifier, content: @Composable RowScope.() -> Unit) {
    val c = Wimg.colors
    Row(
        modifier.navigationBarsPadding().padding(start = 16.dp, end = 16.dp, bottom = WimgDimens.barBottomGap).fillMaxWidth()
            .shadow(14.dp, WimgShape.bar).clip(WimgShape.bar).background(c.card).border(1.dp, c.line, WimgShape.bar)
            .padding(WimgDimens.barPadding),
        horizontalArrangement = Arrangement.spacedBy(WimgDimens.barGap),
        verticalAlignment = Alignment.CenterVertically,
        content = content,
    )
}

@Composable
private fun BarButton(label: String, primary: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val c = Wimg.colors
    Box(
        modifier.height(WimgDimens.touchTarget).pressable(onClick = onClick).clip(WimgShape.button)
            .background(if (primary) c.accent else c.card)
            .then(if (primary) Modifier else Modifier.border(1.dp, c.line, WimgShape.button)),
        contentAlignment = Alignment.Center,
    ) { Text(label, style = WimgType.button, color = if (primary) c.onAccent else c.text, maxLines = 1) }
}
