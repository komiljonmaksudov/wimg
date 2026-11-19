import Foundation

struct Account: Codable, Identifiable {
    let id: String
    let name: String
    let bank: String
    let color: String
    // Closing balance from the latest FinTS statement (cents). 0 = unknown
    // (e.g. CSV-only accounts that never carried a statement balance).
    let balanceCents: Int
    let balanceDate: String
    /// "Ausgeblendet": left out of "Alle Konten" lists and sums, still fetched and searchable.
    let hidden: Int

    var isHidden: Bool { hidden != 0 }

    enum CodingKeys: String, CodingKey {
        case id, name, bank, color, hidden
        case balanceCents = "balance_cents"
        case balanceDate = "balance_date"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        bank = try c.decodeIfPresent(String.self, forKey: .bank) ?? ""
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? "#4361ee"
        balanceCents = try c.decodeIfPresent(Int.self, forKey: .balanceCents) ?? 0
        balanceDate = try c.decodeIfPresent(String.self, forKey: .balanceDate) ?? ""
        hidden = try c.decodeIfPresent(Int.self, forKey: .hidden) ?? 0
    }

    /// Statement closing balance in major units (e.g. EUR), or nil if unknown.
    var balance: Double? {
        balanceDate.isEmpty ? nil : Double(balanceCents) / 100
    }
}
