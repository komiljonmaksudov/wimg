import SwiftUI
import WimgI18n

// The old category editor, still used by Suche until it is redesigned (step 8
// of the iOS catch-up). Umsätze uses CategorySheet.
struct CategoryEditorSheet: View {
    let transaction: Transaction
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    private let expenseCategories: [WimgCategory] = [
        .groceries, .dining, .transport, .housing, .utilities,
        .entertainment, .shopping, .health, .insurance, .subscriptions,
        .travel, .education, .cash, .transfer, .other,
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    transactionHeader
                    categoryList
                }
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .background(WimgTheme.bg)
            .navigationTitle(#L("Kategorie"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(#L("Abbrechen")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var transactionHeader: some View {
        VStack(spacing: 8) {
            Text(transaction.description)
                .font(WimgFont.font(.manrope, .bold, 17, relativeTo: .headline))
                .foregroundStyle(WimgTheme.heroText)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(formatAmount(transaction.amount))
                .font(WimgFont.font(.manrope, .black, 22, relativeTo: .title2))
                .foregroundStyle(transaction.isIncome ? .green : WimgTheme.heroText)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .wimgHero()
        .padding(.horizontal)
    }

    private var categoryList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(#L("Kategorie wählen"))
                .font(WimgFont.font(.inter, .bold, 15, relativeTo: .subheadline))
                .foregroundStyle(WimgTheme.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                if transaction.isIncome {
                    categoryRow(.income)
                    Divider().padding(.leading, 60)
                }
                ForEach(expenseCategories) { cat in
                    categoryRow(cat)
                    if cat.id != expenseCategories.last?.id {
                        Divider().padding(.leading, 60)
                    }
                }
            }
            .wimgCard(radius: WimgTheme.radiusMedium)
            .padding(.horizontal)
        }
    }

    private func categoryRow(_ cat: WimgCategory) -> some View {
        Button {
            try? LibWimg.setCategory(id: transaction.id, category: UInt8(cat.rawValue))
            onDismiss()
            dismiss()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(cat.color.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: cat.icon)
                        .font(.system(size: 16))
                        .foregroundStyle(cat.color)
                }

                Text(L(cat.name))
                    .font(WimgFont.font(.inter, .medium, 15, relativeTo: .subheadline))
                    .foregroundStyle(WimgTheme.text)

                Spacer()

                if transaction.category == cat.rawValue {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(WimgTheme.text)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }
}
