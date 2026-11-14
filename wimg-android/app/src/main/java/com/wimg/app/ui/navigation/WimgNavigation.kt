package com.wimg.app.ui.navigation

import androidx.compose.foundation.layout.imePadding
import com.wimg.app.ui.screens.loadRecurring
import com.wimg.app.ui.screens.REC_KEY
import com.wimg.app.ui.screens.loadTx
import com.wimg.app.ui.screens.txKey
import com.wimg.app.ui.components.Changes
import com.wimg.app.ui.components.ScreenCache
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.EnterTransition
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
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.AccountBalance
import androidx.compose.material.icons.outlined.BarChart
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.FileUpload
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material3.Text
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.LaunchedEffect
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

private val PLACE_ROUTES by lazy { PLACES.map { it.route }.toSet() }

private fun isPlaceSwitch(from: androidx.navigation.NavBackStackEntry, to: androidx.navigation.NavBackStackEntry) =
    from.destination.route in PLACE_ROUTES && to.destination.route in PLACE_ROUTES

private const val ONBOARDING_KEY = "wimg_onboarding_done"

/** Routes already rebuilt in the redesign (band + sheet, content under the bar). */
private val REDESIGNED = setOf("dashboard", "transactions", "tx/{id}", "recurring", "rec/{id}", "settings", "settings/lock", "settings/data", "settings/rules", "settings/accounts", "settings/notifications", "settings/period", "settings/appearance", "manual", "settings/sync", "settings/sync/key", "settings/sync/link", "settings/sync/linked", "fints", "fints/add", "fints/{id}?quick={quick}", "import", "dev/bar", "about", "about/news", "about/faq", "about/privacy", "about/licenses", "review")

/** Everything the place chip can switch to, in menu order. */
val PLACES = listOf(
    Place("dashboard", "Übersicht", Icons.Outlined.Home),
    Place("transactions", "Umsätze", Icons.AutoMirrored.Outlined.List),
    Place("recurring", "Wiederkehrend", Icons.Outlined.Refresh),
    Place("review", "Rückblick", Icons.Outlined.CalendarMonth),
    Place("fints", "Banken", Icons.Outlined.AccountBalance, gapBefore = true),
    Place("import", "Import", Icons.Outlined.FileUpload),
    Place("settings", "Einstellungen", Icons.Outlined.Settings),
    Place("about", "Über wimg", Icons.Outlined.Info),
)

@Composable
fun WimgNavigation() {
    val context = LocalContext.current
    val prefs = context.getSharedPreferences("wimg", 0)
    var onboardingDone by remember { mutableStateOf(prefs.getBoolean(ONBOARDING_KEY, false)) }

    // Where the first start said to go next ("fints", "import", …).
    var afterOnboarding by remember { mutableStateOf<String?>(null) }
    if (!onboardingDone) {
        OnboardingScreen(onComplete = { next ->
            prefs.edit().putBoolean(ONBOARDING_KEY, true).apply()
            afterOnboarding = next.takeIf { it != "dashboard" }
            onboardingDone = true
        })
        return
    }

    val navController = rememberNavController()
    LaunchedEffect(com.wimg.app.ui.components.NavRequest.route) {
        val req = com.wimg.app.ui.components.NavRequest
        req.route?.let { r ->
            if (req.onTop) navController.navigate(r) else navController.navigate(r) { popUpTo("dashboard") }
            req.route = null; req.onTop = false
        }
    }
    LaunchedEffect(afterOnboarding) {
        afterOnboarding?.let { navController.navigate(it); afterOnboarding = null }
    }
    var selectedAccount by remember { mutableStateOf<String?>(null) }
    // Load the other places in the background, so their first visit isn't empty.
    LaunchedEffect(Changes.version, selectedAccount) {
        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
            runCatching {
                ScreenCache.put(txKey(selectedAccount), loadTx(selectedAccount))
                ScreenCache.put(REC_KEY, loadRecurring())
                val now = java.util.Calendar.getInstance()
                val y = now.get(java.util.Calendar.YEAR); val m = now.get(java.util.Calendar.MONTH) + 1
                ScreenCache.put(com.wimg.app.ui.screens.reviewKey(y, m, selectedAccount), com.wimg.app.ui.screens.loadReview(y, m, selectedAccount))
                // Gehaltsmonat / Fester Tag: Übersicht and Rückblick show the current
                // period, cached under its own key; fill those too, so neither
                // page opens empty.
                com.wimg.app.ui.components.PeriodState.reload()
                val ps = com.wimg.app.ui.components.PeriodState.data
                if (ps != null && !ps.isCalendar) {
                    val cur = ps.periods.firstOrNull()
                    if (cur != null) {
                        val prev = ps.periods.getOrNull(1)
                        ScreenCache.put(com.wimg.app.ui.screens.homePeriodKey(cur.from, selectedAccount), com.wimg.app.ui.screens.loadHomeRange(cur, prev, selectedAccount))
                        ScreenCache.put(com.wimg.app.ui.screens.reviewPeriodKey(cur.from, selectedAccount), com.wimg.app.ui.screens.loadReviewRange(cur, prev, selectedAccount, ps.isSalary))
                    }
                }
            }
        }
    }
    var menuOpen by remember { mutableStateOf(false) }
    // "+" without a page-specific action: Bank verbinden / CSV / von Hand (board 12/07).
    var addOpen by remember { mutableStateOf(false) }
    val entry = navController.currentBackStackEntryAsState().value
    val route = entry?.destination?.route
    if (com.wimg.app.FrameWatch.route != route) { com.wimg.app.FrameWatch.route = route; com.wimg.app.FrameWatch.changedAt = System.nanoTime() }
    // Set before the NavHost composes, not a frame later (see BarContribution).
    if (BarState.currentOwner != entry?.id) BarState.currentOwner = entry?.id
    // Named after the page whose bar is shown: page, name and chips change in one frame.
    val shownRoute = BarState.current.route ?: route
    val place = PLACES.firstOrNull { it.route == shownRoute } ?: PLACES.first()
    // Picking a place closes the menu at once: the page change is the feedback.
    var menuInstant by remember { mutableStateOf(false) }

    val panel = BarState.panel
    // Redesigned screens run their content under the bar (with a fade); the
    // others still stop above it until they're redesigned.
    val underBar = route in REDESIGNED

    // Edge to edge: the system no longer resizes for the keyboard, so the app does.
    // Pages and the floating bar end above it (TAN, PIN, search fields stay visible).
    Box(Modifier.fillMaxSize().imePadding()) {
        Column(Modifier.fillMaxSize()) {
            Box(Modifier.weight(1f).padding(bottom = if (route?.startsWith("search") == true || underBar) 0.dp else BarClearance - 24.dp)) {
                // Switching places happens dozens of times a day: instant, like tabs.
                // Only going into or out of a detail page gets a short fade.
                NavHost(
                    navController = navController, startDestination = "dashboard",
                    enterTransition = { if (isPlaceSwitch(initialState, targetState)) EnterTransition.None else fadeIn(tween(150, easing = WimgMotion.EaseOut)) },
                    exitTransition = { if (isPlaceSwitch(initialState, targetState)) ExitTransition.None else fadeOut(tween(100, easing = WimgMotion.EaseOut)) },
                    popEnterTransition = { if (isPlaceSwitch(initialState, targetState)) EnterTransition.None else fadeIn(tween(150, easing = WimgMotion.EaseOut)) },
                    popExitTransition = { if (isPlaceSwitch(initialState, targetState)) ExitTransition.None else fadeOut(tween(100, easing = WimgMotion.EaseOut)) },
                ) {
                    composable(
                        "search?q={q}",
                        arguments = listOf(androidx.navigation.navArgument("q") { defaultValue = "" }),
                    ) { entry ->
                        SearchScreen(selectedAccount = selectedAccount, navController = navController, initialQuery = entry.arguments?.getString("q").orEmpty())
                    }
                    composable("dashboard") { HomeScreen(selectedAccount = selectedAccount, navController = navController, onSelectAccount = { selectedAccount = it }) }
                    composable("transactions") { TransactionsScreen(selectedAccount = selectedAccount, navController = navController, onSelectAccount = { selectedAccount = it }) }
                    composable("rec/{id}") { entry ->
                        RecurringDetailScreen(id = entry.arguments?.getString("id") ?: "", navController = navController)
                    }
                    composable("tx/{id}") { entry ->
                        TransactionDetailScreen(id = entry.arguments?.getString("id") ?: "", navController = navController)
                    }
                    composable("import") { ImportScreen(navController = navController) }
                    composable("recurring") { RecurringScreen(navController = navController) }
                    composable("review") { ReviewScreen(selectedAccount = selectedAccount, navController = navController) }
                    composable("fints") { BanksScreen(navController) }
                    composable("fints/add") { FinTSScreen(navController) }
                    composable(
                        "fints/{id}?quick={quick}",
                        arguments = listOf(
                            androidx.navigation.navArgument("id") { type = androidx.navigation.NavType.StringType },
                            androidx.navigation.navArgument("quick") { type = androidx.navigation.NavType.StringType; nullable = true; defaultValue = null },
                        ),
                    ) { entry ->
                        FinTSScreen(navController, entry.arguments?.getString("id"), quickOnOpen = entry.arguments?.getString("quick") == "1")
                    }
                    composable("settings") { SettingsScreen(navController = navController) }
                    composable("settings/lock") { SettingsLockScreen(navController) }
                    composable("settings/data") { SettingsDataScreen(navController) }
                    composable("settings/rules") { SettingsRulesScreen(navController) }
                    composable("settings/accounts") { SettingsAccountsScreen(navController) }
                    composable("settings/notifications") { SettingsNotificationsScreen(navController) }
                    composable("settings/period") { SettingsPeriodScreen(navController) }
                    composable("settings/appearance") { SettingsAppearanceScreen(navController) }
                    composable("manual") { ManualEntryScreen(navController) }
                    composable("settings/sync") { SettingsSyncScreen(navController) }
                    composable("settings/sync/key") { SettingsSyncKeyScreen(navController) }
                    composable("settings/sync/link") { SettingsSyncLinkScreen(navController) }
                    composable("settings/sync/linked") { SettingsSyncLinkedScreen(navController) }
                    composable("dev/bar") { BarPlaygroundScreen(navController) }
                    composable("about") { AboutScreen(navController) }
                    composable("about/news") { AboutNewsScreen(navController) }
                    composable("about/faq") { AboutFaqScreen(navController) }
                    composable("about/privacy") { AboutPrivacyScreen(navController) }
                    composable("about/licenses") { AboutLicensesScreen(navController) }
                }
            }
        }

        // After the NavHost, so these callbacks are registered last and win over
        // its back handling: back closes the menu or panel before leaving the screen.
        BackHandler(enabled = menuOpen) { menuOpen = false }
        BackHandler(enabled = addOpen) { addOpen = false }
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
        AnimatedVisibility(menuOpen || addOpen || panel != null, enter = fadeIn(tween(200)), exit = if (menuInstant) ExitTransition.None else fadeOut(tween(160))) {
            Box(
                Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.36f))
                    .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {
                        if (menuOpen) menuOpen = false else if (addOpen) addOpen = false else BarState.onPanelDismiss()
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
            // Menu and panel share one spot above the bar: when one replaces the
            // other, the outgoing one fades on top instead of pushing the new one up.
            Box(contentAlignment = Alignment.BottomCenter) {
                androidx.compose.animation.AnimatedVisibility(
                    menuOpen,
                    enter = fadeIn(tween(200, easing = WimgMotion.EaseOut)) + scaleIn(tween(220, easing = WimgMotion.EaseOut), initialScale = 0.96f, transformOrigin = androidx.compose.ui.graphics.TransformOrigin(0.3f, 1f)),
                    exit = if (menuInstant) ExitTransition.None else fadeOut(tween(90)) + scaleOut(tween(90), targetScale = 0.98f),
                ) {
                    PlaceMenu(
                        places = PLACES,
                        current = route,
                        onPick = { p ->
                            menuInstant = true
                            menuOpen = false
                            navController.goTo(p.route)
                        },
                        modifier = Modifier.padding(bottom = 10.dp),
                    )
                }
                androidx.compose.animation.AnimatedVisibility(
                    addOpen,
                    enter = fadeIn(tween(200, easing = WimgMotion.EaseOut)) + scaleIn(tween(220, easing = WimgMotion.EaseOut), initialScale = 0.96f, transformOrigin = androidx.compose.ui.graphics.TransformOrigin(0.9f, 1f)),
                    exit = fadeOut(tween(120)) + scaleOut(tween(120), targetScale = 0.98f),
                ) {
                    AddMenu(Modifier.padding(bottom = 10.dp)) { r -> addOpen = false; navController.navigate(r) }
                }
                androidx.compose.animation.AnimatedVisibility(
                    panel != null && !menuOpen && !addOpen,
                    enter = fadeIn(tween(200, easing = WimgMotion.EaseOut)) + scaleIn(tween(220, easing = WimgMotion.EaseOut), initialScale = 0.96f, transformOrigin = androidx.compose.ui.graphics.TransformOrigin(0.5f, 1f)),
                    exit = fadeOut(tween(150)) + scaleOut(tween(150), targetScale = 0.97f),
                ) {
                    // Keep the last panel while it animates out.
                    var last by remember { mutableStateOf(panel) }
                    if (panel != null) last = panel
                    Box(Modifier.padding(bottom = 10.dp)) { last?.invoke() }
                }
            }
            val detailBar = BarState.detail
            val searchBar = BarState.current.search
            run {
                // One FloatingBar call site for every kind of bar, search included, so
                // it is never torn down and rebuilt: the kind only changes its
                // contentKey, the surface glides to the new width and the content
                // crossfades (place bar ⇄ search bar morph instead of swapping).
                val kind = when {
                    searchBar != null -> "search"
                    detailBar == null -> "place"
                    detailBar.actionLabel != null -> "action"
                    else -> "back"
                }
                // Search is reachable from every page, except inside a flow that a
                // detour would break (bank setup mid-TAN, CSV import).
                val searchHere = detailBar == null || (route?.startsWith("fints") != true && route != "import" && route != "manual")
                FloatingBar(
                    divider = searchBar == null && (detailBar == null || detailBar.onMore != null || searchHere || detailBar.extraIcon != null),
                    fill = searchBar != null || detailBar?.actionLabel != null,
                    full = searchBar != null,
                    contentKey = kind,
                    left = {
                        when {
                            searchBar != null -> searchBar(this)
                            detailBar == null -> {
                                // Read here, after the NavHost composed, so it names the page shown.
                                val shown = PLACES.firstOrNull { it.route == (BarState.current.route ?: route) } ?: PLACES.first()
                                BarChip(label = L(shown.label), icon = shown.icon, unfold = true, active = menuOpen) { BarState.onPanelDismiss(); menuInstant = false; menuOpen = !menuOpen }
                                BarState.chip?.let { chip ->
                                    BarChip(label = chip.label, icon = chip.icon, modifier = Modifier.weight(1f, fill = false), active = chip.active && !menuOpen, contentDescription = chip.contentDescription, ring = chip.ring) { menuOpen = false; chip.onClick() }
                                }
                            }
                            detailBar.actionLabel != null -> {
                                BarBack(detailBar.onBack)
                                BarAction(detailBar.actionLabel, detailBar.actionIcon, Modifier.weight(1f), busy = detailBar.actionBusy, danger = detailBar.actionDanger) { detailBar.onAction() }
                            }
                            else -> BarChip(
                                label = detailBar.backLabel ?: L("Zurück"),
                                icon = androidx.compose.material.icons.Icons.AutoMirrored.Outlined.ArrowBack,
                            ) { detailBar.onBack() }
                        }
                    },
                    right = {
                        if (searchBar != null) Unit
                        else if (detailBar == null) {
                            BarIcon(BarIcons.Search, L("Suche")) { menuOpen = false; navController.navigate("search") }
                            val add = BarState.current.onAdd
                            if (addOpen) BarIcon(androidx.compose.material.icons.Icons.Outlined.Close, L("Schließen"), accent = true) { addOpen = false }
                            else BarIcon(BarIcons.Add, BarState.current.addLabel ?: L("Hinzufügen"), accent = true) {
                                menuOpen = false; BarState.onPanelDismiss()
                                if (add != null) add() else addOpen = true
                            }
                        } else {
                            detailBar.extraIcon?.let { ic -> BarIcon(ic, detailBar.extraLabel ?: "") { detailBar.onExtra?.invoke() } }
                            if (searchHere && detailBar.extraIcon == null) BarIcon(BarIcons.Search, L("Suche")) { navController.navigate("search") }
                            detailBar.onMore?.let { more ->
                                BarIcon(androidx.compose.material.icons.Icons.Filled.MoreHoriz, L("Mehr")) { more() }
                            }
                        }
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

/** "Hinzufügen" above the bar (board 12/07): the three ways data gets into wimg. */
@Composable
private fun AddMenu(modifier: Modifier = Modifier, onPick: (String) -> Unit) {
    val c = Wimg.colors
    com.wimg.app.ui.components.BarPanel(modifier) {
        Text(L("Hinzufügen"), style = com.wimg.app.ui.theme.WimgType.sheetTitle, color = c.text, modifier = Modifier.padding(start = 4.dp, bottom = 6.dp))
        listOf(
            Triple("fints", Icons.Outlined.AccountBalance, L("Bank verbinden") to L("Umsätze per FinTS abrufen")),
            Triple("import", Icons.Outlined.FileUpload, L("CSV importieren") to L("Comdirect, Trade Republic, Scalable")),
            Triple("manual", androidx.compose.material.icons.Icons.Outlined.Edit, L("Umsatz von Hand") to L("Z. B. Bargeld")),
        ).forEach { (route, icon, text) ->
            com.wimg.app.ui.components.WimgRow(text.first, desc = text.second, onClick = { onPick(route) }, leading = {
                androidx.compose.foundation.layout.Box(
                    Modifier.size(44.dp).clip(com.wimg.app.ui.theme.WimgShape.iconTile).background(c.neutralTint),
                    contentAlignment = Alignment.Center,
                ) { androidx.compose.material3.Icon(icon, contentDescription = null, tint = c.text, modifier = Modifier.size(22.dp)) }
            })
        }
    }
}
