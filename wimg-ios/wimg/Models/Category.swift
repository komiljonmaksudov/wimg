import SwiftUI

enum WimgCategory: Int, CaseIterable, Identifiable {
    case uncategorized = 0
    case groceries = 1
    case dining = 2
    case transport = 3
    case housing = 4
    case utilities = 5
    case entertainment = 6
    case shopping = 7
    case health = 8
    case insurance = 9
    case income = 10
    case transfer = 11
    case cash = 12
    case subscriptions = 13
    case travel = 14
    case education = 15
    case other = 255

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .uncategorized: "Unkategorisiert"
        case .groceries: "Lebensmittel"
        case .dining: "Essen gehen"
        case .transport: "Transport"
        case .housing: "Wohnen"
        case .utilities: "Nebenkosten"
        case .entertainment: "Unterhaltung"
        case .shopping: "Shopping"
        case .health: "Gesundheit"
        case .insurance: "Versicherung"
        case .income: "Einkommen"
        case .transfer: "Umbuchung"
        case .cash: "Bargeld"
        case .subscriptions: "Abonnements"
        case .travel: "Reisen"
        case .education: "Bildung"
        case .other: "Sonstiges"
        }
    }

    var color: Color {
        switch self {
        case .uncategorized: Color(hex: 0xDFE6E9)
        case .groceries: Color(hex: 0x4ECDC4)
        case .dining: Color(hex: 0xFF6B6B)
        case .transport: Color(hex: 0x45B7D1)
        case .housing: Color(hex: 0x96CEB4)
        case .utilities: Color(hex: 0xA8D8EA)
        case .entertainment: Color(hex: 0xDDA0DD)
        case .shopping: Color(hex: 0xF7DC6F)
        case .health: Color(hex: 0xFF9FF3)
        case .insurance: Color(hex: 0xC8D6E5)
        case .income: Color(hex: 0x2DC653)
        case .transfer: Color(hex: 0xB8B8B8)
        case .cash: Color(hex: 0xFFD93D)
        case .subscriptions: Color(hex: 0x6C5CE7)
        case .travel: Color(hex: 0xFD79A8)
        case .education: Color(hex: 0x74B9FF)
        case .other: Color(hex: 0xDFE6E9)
        }
    }

    var icon: String {
        switch self {
        case .uncategorized: "questionmark.circle"
        case .groceries: "cart"
        case .dining: "fork.knife"
        case .transport: "car"
        case .housing: "house"
        case .utilities: "bolt"
        case .entertainment: "tv"
        case .shopping: "bag"
        case .health: "heart"
        case .insurance: "shield"
        case .income: "arrow.down.circle"
        case .transfer: "arrow.left.arrow.right"
        case .cash: "banknote"
        case .subscriptions: "repeat"
        case .travel: "airplane"
        case .education: "book"
        case .other: "ellipsis.circle"
        }
    }

    static func from(_ value: Int) -> WimgCategory {
        WimgCategory(rawValue: value) ?? .uncategorized
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}
