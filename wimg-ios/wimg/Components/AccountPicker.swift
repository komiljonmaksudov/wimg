import SwiftUI
import WimgI18n

struct AccountPicker: View {
    @Binding var selectedAccount: String?
    let accounts: [Account]
    var onAccountsChanged: (() -> Void)?

    @State private var showAddSheet = false
    @State private var editingAccount: Account?
    @State private var accountToDelete: Account?

    private var label: String {
        if let id = selectedAccount,
           let acct = accounts.first(where: { $0.id == id }) {
            return acct.name
        }
        return "Alle Konten"
    }

    var body: some View {
        Menu {
            Button {
                selectedAccount = nil
            } label: {
                if selectedAccount == nil {
                    Label(#L("Alle Konten"), systemImage: "checkmark")
                } else {
                    Text(#L("Alle Konten"))
                }
            }

            if !accounts.isEmpty {
                Divider()

                ForEach(accounts) { acct in
                    Menu {
                        Button {
                            selectedAccount = acct.id
                        } label: {
                            Label(#L("Auswählen"), systemImage: selectedAccount == acct.id ? "checkmark.circle.fill" : "circle")
                        }

                        Button {
                            editingAccount = acct
                        } label: {
                            Label(#L("Bearbeiten"), systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            accountToDelete = acct
                        } label: {
                            Label(#L("Löschen"), systemImage: "trash")
                        }
                    } label: {
                        if selectedAccount == acct.id {
                            Label(acct.name, systemImage: "checkmark")
                        } else {
                            Text(acct.name)
                        }
                    }
                }
            }

            Divider()

            Button {
                showAddSheet = true
            } label: {
                Label(#L("Konto hinzufügen"), systemImage: "plus")
            }
        } label: {
            HStack(spacing: 6) {
                if let id = selectedAccount,
                   let acct = accounts.first(where: { $0.id == id }) {
                    Circle()
                        .fill(Color(hex: acct.color) ?? .gray)
                        .frame(width: 8, height: 8)
                }
                Text(label)
                    .font(WimgFont.font(.inter, .bold, 15, relativeTo: .subheadline))
                Image(systemName: "chevron.down")
                    .font(.caption2.bold())
            }
            .foregroundStyle(WimgTheme.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(WimgTheme.cardBg)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
        }
        .sheet(isPresented: $showAddSheet) {
            AccountFormSheet(mode: .add) {
                onAccountsChanged?()
            }
        }
        .sheet(item: $editingAccount) { acct in
            AccountFormSheet(mode: .edit(acct)) {
                onAccountsChanged?()
            }
        }
        .alert(#L("Konto löschen?"), isPresented: Binding(
            get: { accountToDelete != nil },
            set: { if !$0 { accountToDelete = nil } }
        )) {
            Button(#L("Abbrechen"), role: .cancel) {
                accountToDelete = nil
            }
            Button(#L("Löschen"), role: .destructive) {
                if let acct = accountToDelete {
                    if selectedAccount == acct.id {
                        selectedAccount = nil
                    }
                    try? LibWimg.deleteAccount(id: acct.id)
                    onAccountsChanged?()
                    NotificationCenter.default.post(name: .wimgDataChanged, object: nil)
                }
                accountToDelete = nil
            }
        } message: {
            if let acct = accountToDelete {
                Text(#L("\u{201E}\(acct.name)\u{201C} wird entfernt. Transaktionen bleiben erhalten."))
            }
        }
    }
}

// MARK: - Account Form Sheet (Add / Edit)

struct AccountFormSheet: View {
    enum Mode: Identifiable {
        case add
        case edit(Account)

        var id: String {
            switch self {
            case .add: "add"
            case .edit(let a): a.id
            }
        }
    }

    let mode: Mode
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedColor = "#1A1A1A"
    @State private var showDeleteConfirm = false

    private let presetColors = [
        "#1A1A1A", "#f5a623", "#6c5ce7", "#2dc653",
        "#ff6b6b", "#45b7d1", "#fd79a8", "#e17055",
    ]

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var editAccount: Account? {
        if case .edit(let a) = mode { return a }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(#L("Name")) {
                    TextField("z.B. Bargeld, Haushalt...", text: $name)
                        .font(WimgFont.font(.inter, .regular, 17, relativeTo: .body))
                }

                Section(#L("Farbe")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
                        ForEach(presetColors, id: \.self) { color in
                            Circle()
                                .fill(Color(hex: color) ?? .gray)
                                .frame(width: 32, height: 32)
                                .overlay {
                                    if color == selectedColor {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                    }
                                }
                                .onTapGesture { selectedColor = color }
                        }
                    }
                    .padding(.vertical, 4)
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            HStack {
                                Spacer()
                                Label(#L("Konto löschen"), systemImage: "trash")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Konto bearbeiten" : "Konto hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(#L("Abbrechen")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Sichern" : "Erstellen") {
                        save()
                    }
                    .fontWeight(.bold)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert(#L("Konto löschen?"), isPresented: $showDeleteConfirm) {
                Button(#L("Abbrechen"), role: .cancel) {}
                Button(#L("Löschen"), role: .destructive) {
                    if let acct = editAccount {
                        try? LibWimg.deleteAccount(id: acct.id)
                        onDone()
                        NotificationCenter.default.post(name: .wimgDataChanged, object: nil)
                        dismiss()
                    }
                }
            } message: {
                if let acct = editAccount {
                    Text(#L("\u{201E}\(acct.name)\u{201C} wird entfernt. Transaktionen bleiben erhalten."))
                }
            }
            .onAppear {
                if let acct = editAccount {
                    name = acct.name
                    selectedColor = acct.color
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let acct = editAccount {
            try? LibWimg.updateAccount(id: acct.id, name: trimmed, color: selectedColor)
        } else {
            let id = trimmed.lowercased()
                .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            try? LibWimg.addAccount(id: id, name: trimmed, color: selectedColor)
        }

        onDone()
        NotificationCenter.default.post(name: .wimgDataChanged, object: nil)
        dismiss()
    }
}

// MARK: - Color hex extension

extension Color {
    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return nil }
        self.init(
            red: Double((val >> 16) & 0xFF) / 255,
            green: Double((val >> 8) & 0xFF) / 255,
            blue: Double(val & 0xFF) / 255
        )
    }
}
