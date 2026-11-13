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
}
