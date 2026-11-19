import Foundation

/// One bank login (as Android's BankConnection): bank, user, TAN medium, last fetch.
struct BankConnection: Codable, Identifiable, Hashable {
    let id: String
    var blz: String
    var kennung: String
    /// Bank name from the catalogue.
    var name: String
    var tanMedium: String?
    var lastFetchAt: Double = 0
    var lastFetchNew: Int = 0
}

/// Several bank logins. The one shown in Banken is "active": its data sits in
/// the Keychain slots the FinTS flow has always used (fints_blz, fints_kennung,
/// fints_pin, fints_tan_medium), so that flow didn't change. Each login's PIN
/// is also kept under its own Keychain entry (fints_pin_<id>) so switching and
/// the background refresh can use every login.
enum BankConnections {
    private static let listKey = "wimg_fints_connections"
    private static let activeKey = "wimg_fints_active"

    static func pinKey(_ id: String) -> String { "fints_pin_\(id)" }

    /// All logins. A login from before this list (only the Keychain slots) becomes the first entry.
    static func all() -> [BankConnection] {
        if let data = UserDefaults.standard.data(forKey: listKey),
           let list = try? JSONDecoder().decode([BankConnection].self, from: data) {
            return list
        }
        guard let blz = KeychainService.get(KeychainService.fintsBLZ),
              let user = KeychainService.get(KeychainService.fintsKennung) else { return [] }
        let c = BankConnection(id: UUID().uuidString.lowercased(), blz: blz, kennung: user, name: blz,
                               tanMedium: KeychainService.get(KeychainService.fintsTanMedium))
        if let pin = KeychainService.get(KeychainService.fintsPIN) { KeychainService.set(pinKey(c.id), value: pin) }
        save([c])
        UserDefaults.standard.set(c.id, forKey: activeKey)
        return [c]
    }

    private static func save(_ list: [BankConnection]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(list), forKey: listKey)
    }

    static var activeId: String? { UserDefaults.standard.string(forKey: activeKey) }
    static var active: BankConnection? { let a = all(); return a.first { $0.id == activeId } ?? a.first }

    static func hasPIN(_ c: BankConnection) -> Bool { KeychainService.get(pinKey(c.id)) != nil }
    static var anyWithPIN: Bool { all().contains(where: hasPIN) }

    /// Puts a login into the Keychain slots and makes it the one shown.
    static func activate(_ id: String) {
        guard let c = all().first(where: { $0.id == id }) else { return }
        KeychainService.set(KeychainService.fintsBLZ, value: c.blz)
        KeychainService.set(KeychainService.fintsKennung, value: c.kennung)
        if let pin = KeychainService.get(pinKey(c.id)) { KeychainService.set(KeychainService.fintsPIN, value: pin) }
        else { KeychainService.delete(KeychainService.fintsPIN) }
        if let m = c.tanMedium { KeychainService.set(KeychainService.fintsTanMedium, value: m) }
        else { KeychainService.delete(KeychainService.fintsTanMedium) }
        UserDefaults.standard.set(id, forKey: activeKey)
    }

    /// After a sign-in or a change in the slots: the login with this bank and
    /// user is updated (or added) from the slots and becomes the active one.
    static func storeActiveSlots(name: String) {
        guard let blz = KeychainService.get(KeychainService.fintsBLZ),
              let user = KeychainService.get(KeychainService.fintsKennung) else { return }
        var list = all()
        var c = list.first { $0.blz == blz && $0.kennung == user }
            ?? BankConnection(id: UUID().uuidString.lowercased(), blz: blz, kennung: user, name: name)
        c.name = name.isEmpty ? c.name : name
        c.tanMedium = KeychainService.get(KeychainService.fintsTanMedium)
        if let pin = KeychainService.get(KeychainService.fintsPIN) { KeychainService.set(pinKey(c.id), value: pin) }
        else { KeychainService.delete(pinKey(c.id)) }
        list.removeAll { $0.id == c.id }
        list.append(c)
        save(list)
        UserDefaults.standard.set(c.id, forKey: activeKey)
    }

    static func recordFetch(_ id: String?, new: Int) {
        guard let id = id ?? activeId else { return }
        var list = all()
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        list[i].lastFetchAt = Date().timeIntervalSince1970
        list[i].lastFetchNew = new
        save(list)
    }

    /// Removes a login and its PIN; another one becomes active.
    static func remove(_ id: String) {
        var list = all()
        list.removeAll { $0.id == id }
        KeychainService.delete(pinKey(id))
        save(list)
        if activeId == id {
            if let next = list.first { activate(next.id) }
            else {
                for k in [KeychainService.fintsBLZ, KeychainService.fintsKennung, KeychainService.fintsPIN, KeychainService.fintsTanMedium] {
                    KeychainService.delete(k)
                }
                UserDefaults.standard.removeObject(forKey: activeKey)
            }
        }
    }
}
