import SwiftUI
import WimgI18n

struct RecurringView: View {
    @State private var patterns: [RecurringPattern] = []
    @State private var detecting = false

    // Derived state — recomputed only when `patterns` changes via .onChange.
    @State private var activePatterns: [RecurringPattern] = []
    @State private var priceAlerts: [RecurringPattern] = []
    @State private var monthlyTotal: Double = 0
    @State private var grouped: [(String, [RecurringPattern])] = []

    /// Recompute derived state from `patterns`. Called via .onChange.
    private func recompute() {
        let active = patterns.filter(\.isActive)
        activePatterns = active
        priceAlerts = active.filter(\.hasPriceChange)
        monthlyTotal = active.filter { $0.interval == "monthly" }.reduce(0) { $0 + abs($1.amount) }

        let order = ["weekly", "monthly", "quarterly", "annual"]
        var groupDict: [String: [RecurringPattern]] = [:]
        for p in active { groupDict[p.interval, default: []].append(p) }
        grouped = order.compactMap { key in
            guard let items = groupDict[key], !items.isEmpty else { return nil }
            return (key, items)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                subscriptionsTab
            }
            .padding(.bottom, 24)
        }
        .background(WimgTheme.bg)
        .navigationTitle(#L("Wiederkehrend"))
        .onAppear { reload() }
        .onChange(of: patterns) { recompute() }
    }

    // MARK: - Subscriptions Tab

    @ViewBuilder
    private var subscriptionsTab: some View {
        // Hero card
        if !activePatterns.isEmpty {
            heroCard
        }

        // Price alerts
        if !priceAlerts.isEmpty {
            priceAlertsSection
        }

        // Section header
        HStack(spacing: 8) {
            Text(#L("Abonnements"))
                .font(.system(.title2, design: .rounded, weight: .black))
                .foregroundStyle(WimgTheme.text)
            InfoTooltip(text: #L("Scannt deine Transaktionen nach wiederkehrenden Mustern (mind. 3 ähnliche Beträge in regelmäßigen Abständen). Erkennt Abos, Mieten und Fixkosten."))
            Spacer()

            Button {
                handleDetect()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .bold))
                    Text(detecting ? #L("Erkennung...") : #L("Erkennen"))
                }
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(WimgTheme.heroText)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(WimgTheme.accent)
                .clipShape(Capsule())
            }
            .disabled(detecting)
        }
        .padding(.horizontal)

        if activePatterns.isEmpty {
            VStack(spacing: 8) {
                Text("🔄")
                    .font(.system(size: 48))
                Text(#L("Keine Muster erkannt"))
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(WimgTheme.text)
                Text(#L("Importiere Transaktionen und tippe auf Erkennen"))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(WimgTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 40)
        } else {
            ForEach(grouped, id: \.0) { interval, items in
                VStack(alignment: .leading, spacing: 12) {
                    Text(RecurringPattern.intervalLabel(interval))
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(WimgTheme.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .padding(.horizontal)

                    ForEach(items) { pattern in
                        patternCard(pattern)
                    }
                }
            }
        }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(.white.opacity(0.25))
                .frame(width: 140, height: 140)
                .blur(radius: 30)
                .offset(x: 40, y: -40)

            VStack(spacing: 12) {
                HStack(spacing: 6) {
                    Text(#L("Monatliche Fixkosten"))
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .textCase(.uppercase)
                        .tracking(1)
                    InfoTooltip(text: #L("Summe aller erkannten monatlichen Abos und Fixkosten. Quartals- und Jahresbeiträge werden nicht eingerechnet."))
                        .foregroundStyle(.white.opacity(0.8))
                }

                Text(formatAmountShort(monthlyTotal))
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .tracking(-1)

                Text(#L("\(activePatterns.count) erkannte Muster"))
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .background(Color.green.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: WimgTheme.radiusXL, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 16, y: 4)
        .padding(.horizontal)
    }

    // MARK: - Price Alerts

    private var priceAlertsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(#L("Preisänderungen"))
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(WimgTheme.text)
                InfoTooltip(text: #L("Wenn ein erkanntes Abo seinen Preis ändert, erscheint hier eine Warnung mit altem und neuem Betrag. So bemerkst du schleichende Preiserhöhungen frühzeitig."))
            }
            .padding(.horizontal)

            ForEach(priceAlerts) { alert in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(alert.isPriceUp ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: alert.isPriceUp ? "arrow.up" : "arrow.down")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(alert.isPriceUp ? .red : .green)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(alert.merchant)
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(WimgTheme.text)
                            .lineLimit(1)
                        Text("\(formatAmountShort(abs(alert.prev_amount ?? 0))) → \(formatAmountShort(abs(alert.amount)))")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(WimgTheme.textSecondary)
                    }

                    Spacer()

                    Text("\(alert.isPriceUp ? "+" : "")\(formatAmountShort(alert.price_change ?? 0))")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(alert.isPriceUp ? .red : .green)
                }
                .padding(16)
                .wimgCard(radius: WimgTheme.radiusSmall)
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Pattern Card

    private func patternCard(_ pattern: RecurringPattern) -> some View {
        let cat = WimgCategory.from(pattern.category)

        return HStack(spacing: 12) {
            // Category icon
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cat.color.opacity(0.15))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: cat.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(cat.color)
                }

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(pattern.merchant)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(WimgTheme.text)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let nextDue = pattern.nextDueFormatted {
                        Text(nextDue)
                            .font(.system(.caption2, design: .rounded, weight: .medium))
                            .foregroundStyle(WimgTheme.textSecondary)
                    }
                    Text(#L("· Zuletzt: \(pattern.lastSeenFormatted)"))
                        .font(.system(.caption2, design: .rounded, weight: .medium))
                        .foregroundStyle(WimgTheme.textSecondary)
                }
            }

            Spacer()

            // Amount
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatAmountShort(abs(pattern.amount)))
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(WimgTheme.text)
                if pattern.hasPriceChange {
                    Text("\(pattern.isPriceUp ? "+" : "")\(formatAmountShort(pattern.price_change ?? 0))")
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(pattern.isPriceUp ? .red : .green)
                }
            }
        }
        .padding(16)
        .wimgCard(radius: WimgTheme.radiusMedium)
        .padding(.horizontal)
    }

    // MARK: - Data

    private func reload() {
        Task.detached {
            let p = LibWimg.getRecurring()
            await MainActor.run { patterns = p }
        }
    }

    private func handleDetect() {
        detecting = true
        Task.detached {
            LibWimg.detectRecurring()
            let p = LibWimg.getRecurring()
            await MainActor.run {
                patterns = p
                detecting = false
            }
        }
    }
}
