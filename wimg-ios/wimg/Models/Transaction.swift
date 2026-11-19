import Foundation

struct Transaction: Codable, Identifiable {
    let id: String
    let date: String
    let description: String
    let amount: Double
    let currency: String
    let category: Int
    let account: String?
    let excluded: Int?
    /// Row title: the description without its booking type (libwimg booking.zig).
    var title: String? = nil
    /// Booking type ("Lastschrift", "Karte", …) or "" when the bank sent none.
    var kind: String? = nil
    /// Entered by hand (Umsatz von Hand): can be edited and deleted.
    var manual: Bool? = nil

    var displayTitle: String { (title?.isEmpty == false ? title : nil) ?? description }
    var isManual: Bool { manual ?? false }
    var isExpense: Bool { amount < 0 }
    var isIncome: Bool { amount > 0 }
    var isExcluded: Bool { (excluded ?? 0) != 0 }

    var parsedDate: Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: date)
    }
}

struct ImportResult: Codable {
    let total_rows: Int
    let imported: Int
    let skipped_duplicates: Int
    let errors: Int
    let format: String
    let categorized: Int
}

struct ParseResult: Codable {
    let format: String
    let total_rows: Int
    let transactions: [Transaction]
    /// Statement files: the bank's account they go to, and what is already here.
    var account: String? = nil
    var duplicates: Int? = nil
}
