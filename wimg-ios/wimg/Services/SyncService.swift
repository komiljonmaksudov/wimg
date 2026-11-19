import Foundation

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
        let pushed = try await push()
        let pulled = try await pull()
        setLastSync(Int(Date().timeIntervalSince1970 * 1000))
        return (pushed, pulled)
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
