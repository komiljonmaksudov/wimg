import Foundation

struct DemoDataService {
    private static let demoLoadedKey = "wimg_demo_loaded"

    // MARK: - Fixed monthly transactions

    private static let fixedMonthly: [(desc: String, amount: Int?)] = [
        ("GEHALT {MONTH} 2026 MUSTER GMBH", 325_000),
        ("MIETE {MONTH} 2026 HAUSVERWALTUNG MUSTERSTADT", -95_000),
        ("GRUENSTROM AG STROM GAS", nil), // random -9500...-11500
        ("FLIMMERKISTE STREAMING", -1_799),
        ("KLANGWELLE STREAMING", -999),
        ("MUSTER VERSICHERUNG AG", -8_950),
        ("RUNDFUNKBEITRAG", -1_836),
        ("FUNKLINE MOBILFUNK", -3_999),
    ]

    private static let frequent: [(desc: String, min: Int, max: Int, freqMin: Int, freqMax: Int)] = [
        ("SUPERMARKT AM PARK {id}//MUSTERSTADT/DE", -8_500, -1_500, 3, 4),
        ("KORNFELD SUPERMARKT", -4_500, -1_200, 2, 3),
        ("FRISCHE ECKE SUPERMARKT {id}", -5_500, -800, 2, 3),
        ("DROGERIE SONNENSCHEIN", -2_500, -500, 1, 2),
        ("MUSTERSTADT VERKEHRSBETRIEBE", -4_500, -1_500, 1, 2),
    ]

    private static let occasional: [(desc: String, min: Int, max: Int)] = [
        ("PIZZERIA BELLA LUNA", -3_500, -1_200),
        ("KAUFHAUS ZENTRUM", -12_000, -1_500),
        ("DROGERIE AM ECK", -2_000, -500),
        ("APOTHEKE AM MARKT", -3_000, -500),
    ]

    private static let monthNames = [
        "", "JANUAR", "FEBRUAR", "MAERZ", "APRIL", "MAI", "JUNI",
        "JULI", "AUGUST", "SEPTEMBER", "OKTOBER", "NOVEMBER", "DEZEMBER",
    ]

    // MARK: - Public API

    static var isDemoLoaded: Bool {
        UserDefaults.standard.bool(forKey: demoLoadedKey)
    }

    static func clearDemoFlag() {
        UserDefaults.standard.removeObject(forKey: demoLoadedKey)
    }

    static func loadDemoData() {
        let csv = generateDemoCSV()
        guard let data = csv.data(using: .isoLatin1) else { return }

        do {
            let result = try LibWimg.importCSV(data)
            if result.imported > 0 {
                _ = LibWimg.autoCategorize()
                UserDefaults.standard.set(true, forKey: demoLoadedKey)
                NotificationCenter.default.post(name: .wimgDataChanged, object: nil)
            }
        } catch {
            print("[wimg] Demo import failed: \(error)")
        }
    }

    // MARK: - CSV Generation

    static func generateDemoCSV() -> String {
        let calendar = Calendar.current
        let now = Date()
        var rows: [(date: String, desc: String, amount: String, sortKey: Int)] = []

        for offset in 0..<3 {
            guard let monthDate = calendar.date(byAdding: .month, value: -offset, to: now) else { continue }
            let year = calendar.component(.year, from: monthDate)
            let month = calendar.component(.month, from: monthDate)
            let maxDay = calendar.range(of: .day, in: .month, for: monthDate)?.count ?? 28
            let monthName = monthNames[month]

            // Fixed monthly (day 1-5)
            for tx in fixedMonthly {
                let day = Int.random(in: 1...min(5, maxDay))
                let desc = tx.desc.replacingOccurrences(of: "{MONTH}", with: monthName)
                let cents: Int
                if let fixed = tx.amount {
                    cents = fixed
                } else {
                    cents = Int.random(in: -11_500 ... -9_500)
                }
                rows.append((
                    date: formatDate(year: year, month: month, day: day),
                    desc: desc,
                    amount: formatAmount(cents: cents),
                    sortKey: year * 10000 + month * 100 + day
                ))
            }

            // Frequent
            for tx in frequent {
                let count = Int.random(in: tx.freqMin...tx.freqMax)
                for _ in 0..<count {
                    let day = Int.random(in: 1...maxDay)
                    let id = String(Int.random(in: 10000...99999))
                    let desc = tx.desc.replacingOccurrences(of: "{id}", with: id)
                    let cents = Int.random(in: tx.min...tx.max)
                    rows.append((
                        date: formatDate(year: year, month: month, day: day),
                        desc: desc,
                        amount: formatAmount(cents: cents),
                        sortKey: year * 10000 + month * 100 + day
                    ))
                }
            }

            // Occasional (0-2x)
            for tx in occasional {
                let count = Int.random(in: 0...2)
                for _ in 0..<count {
                    let day = Int.random(in: 5...maxDay)
                    let cents = Int.random(in: tx.min...tx.max)
                    rows.append((
                        date: formatDate(year: year, month: month, day: day),
                        desc: tx.desc,
                        amount: formatAmount(cents: cents),
                        sortKey: year * 10000 + month * 100 + day
                    ))
                }
            }
        }

        // Sort descending (Comdirect order)
        rows.sort { $0.sortKey > $1.sortKey }

        let header = "\"Buchungstag\";\"Wertstellung (Valuta)\";\"Vorgang\";\"Buchungstext\";\"Umsatz in EUR\""
        let lines = rows.map { r in
            "\"\(r.date)\";\"\(r.date)\";\"Lastschrift\";\"\(r.desc)\";\"\(r.amount)\""
        }

        return header + "\n" + lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Helpers

    private static func formatDate(year: Int, month: Int, day: Int) -> String {
        String(format: "%02d.%02d.%04d", day, month, year)
    }

    private static func formatAmount(cents: Int) -> String {
        let sign = cents < 0 ? "-" : ""
        let abs = Swift.abs(cents)
        let eur = abs / 100
        let ct = abs % 100

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "de_DE")
        formatter.groupingSeparator = "."
        let eurStr = formatter.string(from: NSNumber(value: eur)) ?? "\(eur)"

        return "\(sign)\(eurStr),\(String(format: "%02d", ct))"
    }
}
