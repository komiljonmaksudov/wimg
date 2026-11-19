import SwiftUI
import WimgI18n

struct TransactionCard: View {
    let transaction: Transaction
    var onTap: (() -> Void)?

    private var category: WimgCategory {
        WimgCategory.from(transaction.category)
    }

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 12) {
                // Category icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(category.color.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: category.icon)
                        .font(.system(size: 16))
                        .foregroundStyle(category.color)
                }

                // Description + category
                VStack(alignment: .leading, spacing: 3) {
                    Text(transaction.description)
                        .font(WimgFont.font(.inter, .semibold, 15, relativeTo: .subheadline))
                        .lineLimit(1)
                        .foregroundStyle(WimgTheme.text)

                    Text(L(category.name))
                        .font(.caption)
                        .foregroundStyle(WimgTheme.textSecondary)
                }

                Spacer()

                // Amount
                Text(formatAmount(transaction.amount))
                    .font(WimgFont.font(.inter, .bold, 15, relativeTo: .subheadline))
                    .foregroundStyle(transaction.isIncome ? .green : WimgTheme.text)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }
}

func formatAmount(_ amount: Double) -> String {
    let formatted = String(format: "%.2f", abs(amount))
    let sign = amount < 0 ? "-" : (amount > 0 ? "+" : "")
    return "\(sign)\(formatted) \u{20AC}"
}

func formatAmountShort(_ amount: Double) -> String {
    String(format: "%.2f \u{20AC}", amount)
}
