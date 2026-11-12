package com.wimg.app.ui.navigation

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.background
import com.wimg.app.ui.theme.Wimg
import com.wimg.app.ui.components.BarState
import com.wimg.app.ui.components.BarAction
import com.wimg.app.ui.components.BarBack
import androidx.compose.ui.graphics.Brush
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.List
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.outlined.AccountBalance
import androidx.compose.material.icons.outlined.BarChart
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.FileUpload
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.wimg.app.i18n.L
import com.wimg.app.ui.components.AccountPicker
import com.wimg.app.ui.components.BarChip
import com.wimg.app.ui.components.BarClearance
import com.wimg.app.ui.components.BarIcon
import com.wimg.app.ui.components.BarIcons
import com.wimg.app.ui.components.FloatingBar
import com.wimg.app.ui.components.Place
import com.wimg.app.ui.components.PlaceMenu
import com.wimg.app.ui.screens.*
import com.wimg.app.ui.theme.WimgDimens
import com.wimg.app.ui.theme.WimgMotion

private const val ONBOARDING_KEY = "wimg_onboarding_done"

/** Routes already rebuilt in the redesign (band + sheet, content under the bar). */
private val REDESIGNED = setOf("dashboard", "transactions", "tx/{id}", "recurring")

/** Everything the place chip can switch to, in menu order. */
val PLACES = listOf(
    Place("dashboard", "Übersicht", Icons.Outlined.Home),
    Place("transactions", "Umsätze", Icons.AutoMirrored.Outlined.List),
    Place("recurring", "Wiederkehrend", Icons.Outlined.Refresh),
    Place("analysis", "Analyse", Icons.Outlined.BarChart),
    Place("review", "Rückblick", Icons.Outlined.CalendarMonth),
    Place("fints", "Bankverbindung", Icons.Outlined.AccountBalance, gapBefore = true),
    Place("import", "Import", Icons.Outlined.FileUpload),
    Place("settings", "Einstellungen", Icons.Outlined.Settings),
    Place("about", "Über wimg", Icons.Outlined.Info),
)

@Composable
fun WimgNavigation() {
    val context = LocalContext.current
    val prefs = context.getSharedPreferences("wimg", 0)
    var onboardingDone by remember { mutableStateOf(prefs.getBoolean(ONBOARDING_KEY, false)) }

    if (!onboardingDone) {
        OnboardingScreen(onComplete = {
            prefs.edit().putBoolean(ONBOARDING_KEY, true).apply()
            onboardingDone = true
        })
        return
    }

    val navController = rememberNavController()
    var selectedAccount by remember { mutableStateOf<String?>(null) }
    var menuOpen by remember { mutableStateOf(false) }
    val route = navController.currentBackStackEntryAsState().value?.destination?.route
    val place = PLACES.firstOrNull { it.route == route } ?: PLACES.first()

    val panel = BarState.panel
    // Redesigned screens run their content under the bar (with a fade); the
    // others still stop above it until they're redesigned.
    val underBar = route in REDESIGNED

    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize()) {
            // Account picker only renders when there is more than one account.
            AccountPicker(
                selectedAccount = selectedAccount,
                onAccountChanged = { selectedAccount = it },
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
            )
            Box(Modifier.weight(1f).padding(bottom = if (route == "search" || underBar) 0.dp else BarClearance - 24.dp)) {
                NavHost(navController = navController, startDestination = "dashboard") {
                    composable("search") { SearchScreen(selectedAccount = selectedAccount, navController = navController) }
                    composable("dashboard") { HomeScreen(selectedAccount = selectedAccount, navController = navController) }
                    composable("transactions") { TransactionsScreen(selectedAccount = selectedAccount, navController = navController) }
                    composable("tx/{id}") { entry ->
                        TransactionDetailScreen(id = entry.arguments?.getString("id") ?: "", navController = navController)
                    }
                    composable("more") { MoreScreen(navController = navController) }
                    composable("import") { ImportScreen(navController = navController) }
                    composable("analysis") { AnalysisScreen(selectedAccount = selectedAccount, navController = navController) }
                    composable("recurring") { RecurringScreen() }
                    composable("review") { ReviewScreen(selectedAccount = selectedAccount) }
                    composable("fints") { FinTSScreen() }
                    composable("settings") { SettingsScreen() }
                    composable("about") { AboutScreen() }
                }
            }
        }

        // After the NavHost, so these callbacks are registered last and win over
        // its back handling: back closes the menu or panel before leaving the screen.
        BackHandler(enabled = menuOpen) { menuOpen = false }
        BackHandler(enabled = panel != null && !menuOpen) { BarState.onPanelDismiss() }

        if (underBar) {
            val sheet = Wimg.colors.sheet
            Box(
                Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .height(72.dp)
                    // Light veil only: rows stay readable as they pass under the bar.
                    .background(Brush.verticalGradient(0f to sheet.copy(alpha = 0f), 1f to sheet.copy(alpha = 0.85f))),
            )
        }

        // Scrim behind the place menu or a screen's panel.
        AnimatedVisibility(menuOpen || panel != null, enter = fadeIn(tween(200)), exit = fadeOut(tween(160))) {
            Box(
                Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.36f))
                    .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {
                        if (menuOpen) menuOpen = false else BarState.onPanelDismiss()
                    },
            )
        }

        Column(
            Modifier
                .align(Alignment.BottomCenter)
                .navigationBarsPadding()
                .padding(bottom = WimgDimens.barBottomGap),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            AnimatedVisibility(
                menuOpen,
                enter = fadeIn(tween(200, easing = WimgMotion.EaseOut)) + scaleIn(tween(220, easing = WimgMotion.EaseOut), initialScale = 0.96f, transformOrigin = androidx.compose.ui.graphics.TransformOrigin(0.3f, 1f)),
                exit = fadeOut(tween(150)) + scaleOut(tween(150), targetScale = 0.97f),
            ) {
                PlaceMenu(
                    places = PLACES,
                    current = route,
                    onPick = { p ->
                        menuOpen = false
                        navController.goTo(p.route)
                    },
                    modifier = Modifier.padding(bottom = 10.dp),
                )
            }
            AnimatedVisibility(
                panel != null && !menuOpen,
                enter = fadeIn(tween(200, easing = WimgMotion.EaseOut)) + scaleIn(tween(220, easing = WimgMotion.EaseOut), initialScale = 0.96f, transformOrigin = androidx.compose.ui.graphics.TransformOrigin(0.5f, 1f)),
                exit = fadeOut(tween(150)) + scaleOut(tween(150), targetScale = 0.97f),
            ) {
                // Keep the last panel while it animates out.
                var last by remember { mutableStateOf(panel) }
                if (panel != null) last = panel
                Box(Modifier.padding(bottom = 10.dp)) { last?.invoke() }
            }
            val detailBar = BarState.detail
            if (detailBar != null) {
                FloatingBar(
                    left = {
                        BarBack(detailBar.onBack)
                        BarAction(detailBar.actionLabel, detailBar.actionIcon) { detailBar.onAction() }
                    },
                    right = {
                        detailBar.onMore?.let { more ->
                            BarIcon(androidx.compose.material.icons.Icons.Filled.MoreHoriz, L("Mehr")) { more() }
                        }
                    },
                )
            } else if (route != "search") {
                FloatingBar(
                    left = {
                        BarChip(label = L(place.label), icon = place.icon, unfold = true, active = menuOpen) { BarState.onPanelDismiss(); menuOpen = !menuOpen }
                        BarState.chip?.let { chip ->
                            BarChip(label = chip.label, icon = chip.icon, active = chip.active && !menuOpen, contentDescription = chip.contentDescription) { menuOpen = false; chip.onClick() }
                        }
                    },
                    right = {
                        BarIcon(BarIcons.Search, L("Suche")) { menuOpen = false; navController.navigate("search") }
                        BarIcon(BarIcons.Add, L("Hinzufügen"), accent = true) { menuOpen = false; navController.goTo("import") }
                    },
                )
            }
        }
    }
}

/** Places replace each other instead of stacking up; Übersicht stays the root. */
private fun NavHostController.goTo(route: String) {
    navigate(route) {
        popUpTo("dashboard") { inclusive = route == "dashboard" }
        launchSingleTop = true
    }
}
