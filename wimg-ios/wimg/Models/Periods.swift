import Foundation

// Shapes returned by the libwimg calls iOS gained for the redesign. Same
// fields as Android's models (Summary.kt, Account.kt).

/// One period: a calendar month, a salary period or a "Fester Tag" month. Dates ISO, `to` inclusive.
struct PeriodInfo: Codable, Hashable {
    let from: String
    let to: String
    let days: Int
    var current: Bool? = nil
    /// Salary that started it (salary mode).
    var salary: Double? = nil
    /// The salary came this many days before it was due.
    var early_days: Int? = nil

    var isCurrent: Bool { current ?? false }
}

struct SalaryInfo: Codable, Hashable {
    let key: String
    var title: String? = nil
    var amount: Double? = nil
    /// Day of the month it usually comes.
    var day: Int? = nil
    var count: Int? = nil
    var confirmed: Bool? = nil
    var last: String? = nil
    var next: String? = nil
    var overdue_days: Int? = nil

    /// Short payer name ("MUSTER GMBH GEHALT"), without the month or reference.
    var name: String { key.isEmpty ? (title ?? "") : key }
}

struct OtherIncome: Codable, Hashable, Identifiable {
    let id: String
    let date: String
    let amount: Double
    var title: String? = nil
    var key: String? = nil
}

struct Payer: Codable, Hashable {
    let key: String
    var title: String? = nil
    var amount: Double? = nil
    var count: Int? = nil
    var last: String? = nil
}

/// What `wimg_get_periods` returns. `mode` is what applies; `chosen` what the user picked.
struct Periods: Codable {
    var mode: String = "calendar"
    var chosen: String = "calendar"
    var day: Int = 1
    var today: String = ""
    var salary: SalaryInfo? = nil
    var periods: [PeriodInfo] = []
    var other_income: [OtherIncome] = []
    var payers: [Payer] = []

    var isSalary: Bool { mode == "salary" }
    var isCalendar: Bool { mode == "calendar" }
    var current: PeriodInfo? { periods.first }

    enum CodingKeys: String, CodingKey {
        case mode, chosen, day, today, salary, periods, other_income, payers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decodeIfPresent(String.self, forKey: .mode) ?? "calendar"
        chosen = try c.decodeIfPresent(String.self, forKey: .chosen) ?? "calendar"
        day = try c.decodeIfPresent(Int.self, forKey: .day) ?? 1
        today = try c.decodeIfPresent(String.self, forKey: .today) ?? ""
        salary = try c.decodeIfPresent(SalaryInfo.self, forKey: .salary)
        periods = try c.decodeIfPresent([PeriodInfo].self, forKey: .periods) ?? []
        other_income = try c.decodeIfPresent([OtherIncome].self, forKey: .other_income) ?? []
        payers = try c.decodeIfPresent([Payer].self, forKey: .payers) ?? []
    }
}

/// A payment that belongs to a recurring pattern.
struct RecurringPayment: Codable, Identifiable, Hashable {
    let id: String
    let date: String
    let amount: Double
    /// Set aside as a one-off: shown crossed out, doesn't count for the pattern.
    var oneoff: Bool? = nil

    var isOneoff: Bool { oneoff ?? false }
}

/// A categorisation rule: a text that, found in a booking, assigns a category.
struct Rule: Codable, Identifiable, Hashable {
    let id: Int64
    let pattern: String
    let category: Int
    /// 1 = learned from a manual change; higher = shipped with wimg.
    let priority: Int

    var isLearned: Bool { priority == 1 }
}

/// A device linked through wimg Sync. `last_seen` in unix ms.
struct SyncDevice: Codable, Identifiable, Hashable {
    let id: String
    var name: String? = nil
    var kind: String? = nil
    var last_seen: Int64? = nil
}
