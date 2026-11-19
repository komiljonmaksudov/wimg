import Foundation
import UIKit

/// URLSession-based sync client with real-time WebSocket support + E2E encryption.
actor SyncService {
    static let shared = SyncService()

    private let baseURL = WimgConfig.syncBaseURL
    private let tsDefault = WimgConfig.udSyncLastTS

    private var wsTask: URLSessionWebSocketTask?
    private var reconnectDelay: TimeInterval = 1.0
    private var isClosed = false
    private var pingTimer: Task<Void, Never>?

    /// Cached encryption key (derived from sync key via HKDF-SHA256).
    private var encryptionKey: Data?

    /// Echo suppression: ignore WS changes for 2s after our own push.
    private var suppressUntil: Date = .distantPast

    // MARK: - Sync Key (Keychain)

    var syncKey: String? {
        KeychainService.get(KeychainService.syncKey)
    }

    var lastSyncTimestamp: Int {
        UserDefaults.standard.integer(forKey: tsDefault)
    }

    var isEnabled: Bool { syncKey != nil }

    nonisolated func setSyncKey(_ key: String) {
        KeychainService.set(KeychainService.syncKey, value: key)
        UserDefaults.standard.removeObject(forKey: SyncService.removedKey)
    }

    nonisolated func clearSyncKey() {
        KeychainService.delete(KeychainService.syncKey)
        UserDefaults.standard.removeObject(forKey: tsDefault)
    }

    private nonisolated func setLastSync(_ ts: Int) {
        UserDefaults.standard.set(ts, forKey: tsDefault)
    }

    /// Derive and cache encryption key from the current sync key.
    private func getEncryptionKey() -> Data? {
        if let cached = encryptionKey { return cached }
        guard let key = syncKey,
              let derived = LibWimg.deriveEncryptionKey(syncKey: key) else { return nil }
        encryptionKey = derived
        return derived
    }

    /// Migrate sync key from UserDefaults to Keychain (one-time).
    nonisolated func migrateIfNeeded() {
        KeychainService.migrateFromUserDefaults(
            udKey: WimgConfig.udSyncKey,
            account: KeychainService.syncKey
        )
    }

    // MARK: - HTTP Push/Pull

    func push() async throws -> Int {
        guard let key = syncKey else { throw SyncError.noKey }

        let changes = LibWimg.getChanges(sinceMs: lastSyncTimestamp)
        if changes.isEmpty { return 0 }

        // Encrypt rows before sending
        let wireRows = encryptRows(changes)
        let payload = WirePayload(rows: wireRows)
        let body = try JSONEncoder().encode(payload)

        var request = URLRequest(url: URL(string: "\(baseURL)/sync/\(key)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SyncError.pushFailed(String(data: data, encoding: .utf8) ?? "")
        }

        struct MergeResult: Decodable { let merged: Int }
        let result = try JSONDecoder().decode(MergeResult.self, from: data)

        // Suppress echo for 2 seconds
        suppressUntil = Date().addingTimeInterval(2)

        // Also broadcast via WebSocket for real-time delivery
        pushChangesViaWS(wireRows)

        return result.merged
    }

    func pull() async throws -> Int {
        guard let key = syncKey else { throw SyncError.noKey }

        let since = lastSyncTimestamp
        let url = URL(string: "\(baseURL)/sync/\(key)?since=\(since)")!

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SyncError.pullFailed(String(data: data, encoding: .utf8) ?? "")
        }

        let wirePayload = try JSONDecoder().decode(WirePayload.self, from: data)
        if wirePayload.rows.isEmpty { return 0 }

        // Decrypt rows from server
        let plainRows = decryptRows(wirePayload.rows)
        if plainRows.isEmpty { return 0 }

        let applied = try LibWimg.applyChanges(plainRows)
        setLastSync(Int(Date().timeIntervalSince1970 * 1000))
        return applied
    }

    func syncFull() async throws -> (pushed: Int, pulled: Int) {
        // Another device removed this one (or replaced the key): stop, keep the data.
        if !touchDevice() {
            leaveRemoved()
            return (0, 0)
        }
        let pushed = try await push()
        let pulled = try await pull()
        // A pull can bring this device's own removal mark.
        if !touchDevice() {
            leaveRemoved()
            return (pushed, pulled)
        }
        setLastSync(Int(Date().timeIntervalSince1970 * 1000))
        UserDefaults.standard.set(Int(Date().timeIntervalSince1970 * 1000), forKey: Self.lastSyncAtKey)
        return (pushed, pulled)
    }

    // MARK: - Key check before linking (board 21)

    enum Probe: Equatable { case found(Int), noMatch, offline }

    /// Reads what the server holds under `key` without saving the key, and
    /// checks that the key can open it. Nothing is ever pushed under a wrong key.
    func probe(_ key: String) async -> Probe {
        guard let url = URL(string: "\(baseURL)/sync/\(key)?since=0") else { return .noMatch }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return .offline }
            let rows = try JSONDecoder().decode(WirePayload.self, from: data).rows
            guard !rows.isEmpty, let derived = LibWimg.deriveEncryptionKey(syncKey: key) else { return .noMatch }
            // A few rows are enough to tell whether the key opens them.
            let readable = rows.prefix(5).filter { row in
                if case .encrypted(let ct) = row.data { return LibWimg.decryptField(ciphertext: ct, key: derived) != nil }
                return false
            }.count
            return readable > 0 ? .found(rows.count) : .noMatch
        } catch {
            return .offline
        }
    }

    /// A key as typed: 32 hex characters, any case, with or without dashes;
    /// o→0 and i/l→1 (they look alike). Nil when it can't be a key.
    nonisolated static func normalizeKey(_ raw: String) -> String? {
        let hex = String(raw.lowercased().filter { $0.isLetter || $0.isNumber }.map { ch -> Character in
            switch ch { case "o": "0"; case "i", "l": "1"; default: ch }
        })
        guard hex.count == 32, hex.allSatisfy({ "0123456789abcdef".contains($0) }) else { return nil }
        let a = Array(hex)
        return [String(a[0..<8]), String(a[8..<12]), String(a[12..<16]), String(a[16..<20]), String(a[20...])].joined(separator: "-")
    }

    // MARK: - Devices (board 21)

    static let deviceIdKey = "wimg_device_id"
    static let removedKey = "wimg_sync_removed"
    static let lastSyncAtKey = "wimg_sync_last_at"

    /// This device's id in the device list (random, only inside the E2E data).
    nonisolated static var deviceId: String {
        if let id = UserDefaults.standard.string(forKey: deviceIdKey) { return id }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: deviceIdKey)
        return id
    }

    /// iOS gives apps only the model name ("iPhone"), not the user's device name.
    nonisolated static var deviceName: String { UIDevice.current.model }

    nonisolated static var deviceKind: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "tablet" : "phone"
    }

    /// Set when another device removed this one or the key was replaced.
    nonisolated static var wasRemoved: Bool { UserDefaults.standard.bool(forKey: removedKey) }

    /// Unix ms of the last full sync, 0 if never.
    nonisolated static var lastSyncAt: Int { UserDefaults.standard.integer(forKey: lastSyncAtKey) }

    /// Marks this device as still linked. False: another device removed it.
    private func touchDevice() -> Bool {
        (try? LibWimg.touchDevice(id: Self.deviceId, name: Self.deviceName, kind: Self.deviceKind)) ?? true
    }

    private func leaveRemoved() {
        disconnectWebSocket()
        clearSyncKey()
        UserDefaults.standard.set(true, forKey: Self.removedKey)
    }

    /// "Neuen Schlüssel erstellen": the other devices are marked removed, the
    /// server copy under the old key is deleted, only the removal marks are
    /// written back there (so the others learn they are out), and everything is
    /// pushed again under a fresh key. False: nothing changed, the old key stays.
    func replaceKey() async -> Bool {
        guard let old = syncKey else { return false }
        do {
            let me = Self.deviceId
            for d in LibWimg.getDevices() where d.id != me { try? LibWimg.removeDevice(id: d.id) }
            _ = try await push()
            var del = URLRequest(url: URL(string: "\(baseURL)/sync/\(old)")!)
            del.httpMethod = "DELETE"
            let (_, resp) = try await URLSession.shared.data(for: del)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return false }
            let marks = encryptRows(LibWimg.getChanges(sinceMs: 0).filter { $0.table == "sync_devices" })
            if !marks.isEmpty {
                var post = URLRequest(url: URL(string: "\(baseURL)/sync/\(old)")!)
                post.httpMethod = "POST"
                post.setValue("application/json", forHTTPHeaderField: "Content-Type")
                post.httpBody = try JSONEncoder().encode(WirePayload(rows: marks))
                _ = try await URLSession.shared.data(for: post)
            }
            disconnectWebSocket()
            setSyncKey(UUID().uuidString.lowercased())
            encryptionKey = nil
            setLastSync(0)
            _ = try await push()
            UserDefaults.standard.set(Int(Date().timeIntervalSince1970 * 1000), forKey: Self.lastSyncAtKey)
            connectWebSocket()
            return true
        } catch {
            return false
        }
    }

    // MARK: - E2E Encryption

    /// Encrypt plaintext SyncRows for network transmission.
    private func encryptRows(_ rows: [LibWimg.SyncRow]) -> [WireRow] {
        guard let key = getEncryptionKey() else {
            // No encryption key — send plaintext (shouldn't happen)
            return rows.map { WireRow(table: $0.table, id: $0.id, data: .object($0.data), updated_at: $0.updated_at) }
        }

        return rows.map { row in
            guard let dataJSON = try? JSONEncoder().encode(row.data),
                  let plaintext = String(data: dataJSON, encoding: .utf8),
                  let encrypted = LibWimg.encryptField(plaintext: plaintext, key: key)
            else {
                return WireRow(table: row.table, id: row.id, data: .object(row.data), updated_at: row.updated_at)
            }
            return WireRow(table: row.table, id: row.id, data: .encrypted(encrypted), updated_at: row.updated_at)
        }
    }

    /// Decrypt wire-format rows to plaintext SyncRows for local DB.
    private func decryptRows(_ rows: [WireRow]) -> [LibWimg.SyncRow] {
        let key = getEncryptionKey()

        return rows.compactMap { row in
            switch row.data {
            case .encrypted(let ciphertext):
                guard let key,
                      let plaintext = LibWimg.decryptField(ciphertext: ciphertext, key: key),
                      let jsonData = plaintext.data(using: .utf8),
                      let dict = try? JSONDecoder().decode([String: AnyCodable].self, from: jsonData)
                else { return nil }
                return LibWimg.SyncRow(table: row.table, id: row.id, data: dict, updated_at: row.updated_at)

            case .object(let dict):
                // Plaintext (migration path — old data before encryption)
                return LibWimg.SyncRow(table: row.table, id: row.id, data: dict, updated_at: row.updated_at)
            }
        }
    }

    // MARK: - WebSocket

    func connectWebSocket() {
        guard let key = syncKey else { return }
        isClosed = false
        encryptionKey = nil // Re-derive on next use
        doConnect(key: key)
    }

    func disconnectWebSocket() {
        isClosed = true
        pingTimer?.cancel()
        pingTimer = nil
        wsTask?.cancel(with: .normalClosure, reason: nil)
        wsTask = nil
        encryptionKey = nil
    }

    private func doConnect(key: String) {
        guard !isClosed else { return }

        let wsURL = baseURL
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
        guard let url = URL(string: "\(wsURL)/ws/\(key)") else { return }

        let session = URLSession(configuration: .default)
        wsTask = session.webSocketTask(with: url)
        wsTask?.resume()

        reconnectDelay = 1.0
        receiveLoop(key: key)
    }

    private func receiveLoop(key: String) {
        wsTask?.receive { [weak self] result in
            guard let self else { return }

            Task {
                await self.handleReceiveResult(result, key: key)
            }
        }
    }

    private func handleReceiveResult(_ result: Result<URLSessionWebSocketTask.Message, Error>, key: String) {
        switch result {
        case .success(let message):
            switch message {
            case .string(let text):
                handleMessage(text)
            case .data(let data):
                if let text = String(data: data, encoding: .utf8) {
                    handleMessage(text)
                }
            @unknown default:
                break
            }
            receiveLoop(key: key)

        case .failure:
            guard !isClosed else { return }
            // Reconnect with exponential backoff
            let delay = reconnectDelay
            reconnectDelay = min(reconnectDelay * 2, 30.0)

            Task {
                try? await Task.sleep(for: .seconds(delay))
                doConnect(key: key)
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let msg = try? JSONDecoder().decode(WireMessage.self, from: data) else {
            return
        }

        switch msg.type {
        case "changes":
            guard let wireRows = msg.rows, !wireRows.isEmpty else { return }

            // Echo suppression: ignore own changes echoed back
            if Date() < suppressUntil { return }

            // Decrypt and apply
            let plainRows = decryptRows(wireRows)
            guard !plainRows.isEmpty else { return }
            _ = try? LibWimg.applyChanges(plainRows)

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .wimgDataChanged, object: nil)
            }

        case "ping":
            let pong = #"{"type":"pong"}"#
            wsTask?.send(.string(pong)) { _ in }

        case "push_ack":
            break

        default:
            break
        }
    }

    private func pushChangesViaWS(_ wireRows: [WireRow]) {
        guard let wsTask, wsTask.state == .running else { return }

        struct WSPush: Encodable {
            let type = "push"
            let rows: [WireRow]
        }

        guard let data = try? JSONEncoder().encode(WSPush(rows: wireRows)),
              let text = String(data: data, encoding: .utf8) else { return }

        wsTask.send(.string(text)) { error in
            if let error {
                print("[wimg-sync] WS push failed: \(error)")
            }
        }
    }
}

// MARK: - Wire Format (encrypted sync payload)

/// Row data that can be either encrypted (String) or plaintext (dict).
private enum RowData: Codable {
    case object([String: AnyCodable])
    case encrypted(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .encrypted(str)
        } else {
            self = .object(try container.decode([String: AnyCodable].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let dict): try container.encode(dict)
        case .encrypted(let str): try container.encode(str)
        }
    }
}

/// Wire-format row: data may be encrypted string or plaintext dict.
private struct WireRow: Codable {
    let table: String
    let id: String
    let data: RowData
    let updated_at: Int
}

private struct WirePayload: Codable {
    let rows: [WireRow]
}

private struct WireMessage: Decodable {
    let type: String
    let rows: [WireRow]?
    let merged: Int?
}

// MARK: - Errors

enum SyncError: LocalizedError {
    case noKey
    case pushFailed(String)
    case pullFailed(String)

    var errorDescription: String? {
        switch self {
        case .noKey: "Kein Sync-Schlüssel konfiguriert"
        case .pushFailed(let msg): "Push fehlgeschlagen: \(msg)"
        case .pullFailed(let msg): "Pull fehlgeschlagen: \(msg)"
        }
    }
}
