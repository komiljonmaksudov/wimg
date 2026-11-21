import SwiftUI
import UserNotifications
import WimgI18n

@main
struct wimgApp: App {
    @State private var initError: String?
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var lock = BiometricLock.shared

    var body: some Scene {
        WindowGroup {
            ZStack {
                if let error = initError {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.red)
                        Text(#L("Initialisierung fehlgeschlagen"))
                            .font(WimgFont.font(.manrope, .bold, 17, relativeTo: .headline))
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(WimgTheme.textSecondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(WimgTheme.bg)
                } else {
                    ContentView()
                }

                // Order matters: privacy overlay sits above lock so the
                // app-switcher snapshot never reveals even the lock screen.
                if lock.isLocked {
                    LockScreen(lock: lock)
                        .transition(.opacity)
                }
                if lock.showPrivacyOverlay || lock.captured {
                    PrivacyOverlay()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: lock.isLocked)
            .animation(.easeInOut(duration: 0.10), value: lock.showPrivacyOverlay)
        }
        .onChange(of: scenePhase) { _, newPhase in
            lock.handleScenePhase(newPhase)
        }
    }

    init() {
        // App Review recording: start from nothing every run (its own files only).
        if let file = ProcessInfo.processInfo.environment["WIMG_DB_FILE"] {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(at: docs.appendingPathComponent(file + suffix)) }
            UserDefaults.standard.removeObject(forKey: OnboardingKey.completed)
        }
        // Migrate credentials from UserDefaults to Keychain (one-time on update)
        SyncService.shared.migrateIfNeeded()

        // "Systemsprache": resolve the phone's language before the first frame.
        LocaleChoice.apply()

        // Register BGAppRefreshTask handler — must happen here, not later.
        // iOS rejects late registrations.
        BackgroundRefresh.register()
        // Taps on notices open their page (wimg_route).
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared

        // Log main thread hangs > 50ms
        #if DEBUG
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue | CFRunLoopActivity.afterWaiting.rawValue, true, 0) { _, activity in
            struct S { static var ts: CFAbsoluteTime = 0 }
            if activity.rawValue == CFRunLoopActivity.afterWaiting.rawValue {
                S.ts = CFAbsoluteTimeGetCurrent()
            } else if S.ts > 0 {
                let ms = (CFAbsoluteTimeGetCurrent() - S.ts) * 1000
                if ms > 50 { print("⚠️ Main thread blocked \(Int(ms))ms") }
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        #endif

        do {
            try LibWimg.initialize()
        } catch {
            _initError = State(initialValue: error.localizedDescription)
        }
    }
}

struct ContentView: View {
    @State private var selectedAccount: String?
    @State private var accounts: [Account] = []
    @AppStorage(OnboardingKey.completed) private var onboardingCompleted = false
    @AppStorage("wimg_locale") private var currentLocale = "de"
    @State private var popToRoot = UUID()
    private var nav: AppNav { AppNav.shared }
    private var themeManager = ThemeManager.shared

    private var appLocale: Locale {
        Locale(identifier: currentLocale == "en" ? "en" : "de")
    }

    /// Tapping the open tab again goes back to its first page.
    private var tabSelection: Binding<AppTab> {
        Binding {
            nav.tab
        } set: { newTab in
            if newTab == nav.tab {
                popToRoot = UUID()
            }
            nav.tab = newTab
        }
    }

    /// Brief 22, option A: four tabs + search. On iOS 26 the system draws the
    /// search tab as its own round button next to the bar; before, it is a
    /// fifth tab. The Dock sits directly above the bar on every tab.
    var body: some View {
        tabs
            .tint(Wimg.accent)
            .environment(\.locale, appLocale)
        .preferredColorScheme(themeManager.mode.colorScheme)
        .onAppear {
            // Pre-warm keyboard to avoid ~300ms cold-start on first search tap
            let warmup = UITextField()
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first?.addSubview(warmup)
            warmup.becomeFirstResponder()
            warmup.resignFirstResponder()
            warmup.removeFromSuperview()

            Task.detached {
                let accs = LibWimg.getAccounts()
                // Auto-snapshot: take monthly snapshot if we haven't this month
                let now = Date()
                let cal = Calendar.current
                let currentMonth = String(format: "%04d-%02d", cal.component(.year, from: now), cal.component(.month, from: now))
                let lastSnapshot = UserDefaults.standard.string(forKey: "wimg_last_snapshot_month")
                if lastSnapshot != currentMonth {
                    try? LibWimg.takeSnapshot(year: cal.component(.year, from: now), month: cal.component(.month, from: now))
                    UserDefaults.standard.set(currentMonth, forKey: "wimg_last_snapshot_month")
                }
                WidgetDataWriter.writeSummary()
                await Notifier.scheduleMonthEnd()
                await MainActor.run { accounts = accs }
            }
            // Connect real-time sync WebSocket + initial pull
            Task {
                let sync = SyncService.shared
                if await sync.isEnabled {
                    await sync.connectWebSocket()
                    _ = try? await sync.pull()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .wimgDataChanged)) { _ in
            Task.detached {
                let accs = LibWimg.getAccounts()
                WidgetDataWriter.writeSummary()
                await MainActor.run { accounts = accs }
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { !onboardingCompleted },
            set: { if !$0 { onboardingCompleted = true } }
        )) {
            OnboardingView()
        }
    }

    @ViewBuilder
    private var tabs: some View {
        if #available(iOS 18, *) {
            TabView(selection: tabSelection) {
                ForEach(AppTab.main) { tab in
                    Tab(L(tab.title), systemImage: tab.icon, value: tab) { page(tab) }
                }
                Tab(value: AppTab.search, role: .search) { page(.search) }
            }
        } else {
            TabView(selection: tabSelection) {
                ForEach(AppTab.allCases) { tab in
                    page(tab)
                        .tabItem { Label(L(tab.title), systemImage: tab.icon) }
                        .tag(tab)
                }
            }
        }
    }

    @ViewBuilder
    private func page(_ tab: AppTab) -> some View {
        Group {
            switch tab {
            case .overview: HomeView(selectedAccount: $selectedAccount, accounts: $accounts)
            case .transactions: TransactionsView(selectedAccount: $selectedAccount, popToRoot: popToRoot)
            case .recurring: NavigationStack { RecurringView() }
            case .more: MoreView(selectedAccount: $selectedAccount, popToRoot: popToRoot)
            case .search: SearchView(selectedAccount: $selectedAccount, popToRoot: popToRoot)
            }
        }
        .wimgDock()
    }
}

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case overview, transactions, recurring, more, search

    var id: String { rawValue }
    static let main: [AppTab] = [.overview, .transactions, .recurring, .more]

    /// German source string, translated with `L()` at the call site.
    var title: String {
        switch self {
        case .overview: "Übersicht"
        case .transactions: "Umsätze"
        case .recurring: "Wiederkehrend"
        case .more: "Mehr"
        case .search: "Suche"
        }
    }

    var icon: String {
        switch self {
        case .overview: "house"
        case .transactions: "list.bullet"
        case .recurring: "arrow.triangle.2.circlepath"
        case .more: "ellipsis"
        case .search: "magnifyingglass"
        }
    }
}
