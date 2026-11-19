import Foundation
import WimgI18n

struct RecurringPattern: Codable, Identifiable, Equatable {
    let id: String
    let merchant: String
    let amount: Double
    let interval: String
    let category: Int
    let last_seen: String
    let next_due: String?
    let active: Int
    let prev_amount: Double?
    let price_change: Double?
    /// Name the user gave it (edit sheet); nil = the detected merchant.
    var name: String? = nil
    /// "Nicht wiederkehrend": listed only under Ausgeblendet.
    var hidden: Int? = nil
    /// What detection found, before a fixed amount.
    var detected_amount: Double? = nil
    /// 1 when the user set a fixed amount.
    var fixed: Int? = nil

    var displayName: String { name ?? merchant }
    var isHidden: Bool { (hidden ?? 0) != 0 }
    var isActive: Bool { active != 0 }
    var hasPriceChange: Bool { price_change != nil && abs(price_change!) > 0 }
    var isPriceUp: Bool { (price_change ?? 0) > 0 }

    static func intervalLabel(_ interval: String) -> String {
        switch interval {
        case "weekly": #L("Wöchentlich")
        case "monthly": #L("Monatlich")
        case "quarterly": #L("Vierteljährlich")
        case "annual": #L("Jährlich")
        default: interval
        }
    }

    static var isEnglish: Bool {
        UserDefaults.standard.string(forKey: "wimg_locale") == "en"
    }

    private static var displayLocale: Locale {
        Locale(identifier: isEnglish ? "en_US" : "de_DE")
    }

    // Note: we don't use `String(localized: "\(days)T überfällig")` because
    // string interpolation produces a runtime key (e.g. "5T überfällig") that
    // doesn't exist in the .xcstrings catalog (only the static key
    // "T überfällig" does). Branch on `isEnglish` manually so the dynamic
    // values get the right surrounding text in each language.
    var nextDueFormatted: String? {
        guard let next_due else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: next_due) else { return nil }

        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: date)).day ?? 0
        let isEng = Self.isEnglish

        if days < 0 {
            return isEng ? "\(abs(days))d overdue" : "\(abs(days))T überfällig"
        }
        if days == 0 { return isEng ? "Today" : "Heute" }
        if days == 1 { return isEng ? "Tomorrow" : "Morgen" }
        if days <= 7 {
            return isEng ? "In \(days) days" : "In \(days) Tagen"
        }

        let display = DateFormatter()
        display.dateFormat = isEng ? "MMM d" : "d. MMM"
        display.locale = Self.displayLocale
        return display.string(from: date)
    }

    var lastSeenFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: last_seen) else { return last_seen }
        let display = DateFormatter()
        display.dateFormat = Self.isEnglish ? "MMM d" : "d. MMM"
        display.locale = Self.displayLocale
        return display.string(from: date)
    }
}
