import Foundation
import Security

/// Swift wrapper over libwimg C ABI. Mirrors wimg-web/src/lib/wasm.ts.
/// Pattern: call C function -> get pointer to length-prefixed JSON -> decode -> free pointer.
final class LibWimg {
    private init() {}

    private static var isInitialized = false
    /// Set during data reset to prevent concurrent C ABI calls while DB is being destroyed/recreated.
    static var isResetting = false

    /// libwimg uses a process-wide fixed-buffer allocator; `wimg_free` resets the entire arena.
    /// Any concurrent FFI call can invalidate pointers returned to another thread — serialize access.
    private static let abiLock = NSRecursiveLock()

    private static func withWimgAbi<R>(_ body: () throws -> R) rethrows -> R {
        abiLock.lock()
        defer { abiLock.unlock() }
        return try body()
    }

    // MARK: - Lifecycle

    static func initialize() throws {
        try withWimgAbi {
            let dbPath = LibWimg.dbPath()
            try dbPath.withCString { cPath in
                let rc = wimg_init(cPath)
                if rc != 0 {
                    throw WimgError.initFailed(lastError())
                }
            }
            isInitialized = true

            // Set HTTP callback for FinTS (uses URLSession for native TLS)
            wimg_set_http_callback { url, urlLen, body, bodyLen, outBuf, outBufLen in
            guard let url, let body, let outBuf else {
                print("[FinTS HTTP] callback received nil pointers")
                return -1
            }

            let urlStr = String(bytes: UnsafeBufferPointer(start: url, count: Int(urlLen)), encoding: .utf8) ?? ""
            let bodyData = Data(bytes: body, count: Int(bodyLen))

            guard let requestUrl = URL(string: urlStr) else {
                print("[FinTS HTTP] invalid URL: \(urlStr)")
                return -1
            }

            // Never log bodies: requests carry the PIN, responses carry statements.
            print("[FinTS HTTP] POST \(urlStr) (\(bodyData.count) bytes)")

            var request = URLRequest(url: requestUrl)
            request.httpMethod = "POST"
            request.httpBody = bodyData
            request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 30

            // Synchronous request on a dedicated queue (FinTS calls are blocking from Zig)
            let semaphore = DispatchSemaphore(value: 0)
            var responseData: Data?
            var responseError: Error?

            let session = URLSession(configuration: .ephemeral)
            session.dataTask(with: request) { data, response, error in
                responseData = data
                responseError = error
                if let httpResponse = response as? HTTPURLResponse {
                    print("[FinTS HTTP] response: \(httpResponse.statusCode), \(data?.count ?? 0) bytes")
                }
                semaphore.signal()
            }.resume()

            let waitResult = semaphore.wait(timeout: .now() + 35)
            if waitResult == .timedOut {
                print("[FinTS HTTP] request timed out after 35s")
                session.invalidateAndCancel()
                return -1
            }

            if let error = responseError {
                print("[FinTS HTTP] error: \(error.localizedDescription)")
                return -1
            }
            guard let data = responseData else {
                print("[FinTS HTTP] no response data")
                return -1
            }
            guard data.count <= outBufLen else {
                print("[FinTS HTTP] response too large: \(data.count) > \(outBufLen)")
                return -1
            }

            data.copyBytes(to: outBuf, count: data.count)
            return Int32(data.count)
        }
        }
    }

    static func close() {
        withWimgAbi {
            wimg_close()
            isInitialized = false
        }
    }

    // MARK: - Parse & Import

    static func parseCSV(_ data: Data) throws -> ParseResult {
        try withWimgAbi {
            try ensureInit()
            return try data.withUnsafeBytes { rawBuffer in
                guard let ptr = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    throw WimgError.allocationFailed
                }
                guard let resultPtr = wimg_parse_csv(ptr, UInt32(data.count)) else {
                    throw WimgError.importFailed(lastError())
                }
                defer { wimg_free(resultPtr, 0) }
                return try decodeLengthPrefixed(resultPtr)
            }
        }
    }

    static func importCSV(_ data: Data) throws -> ImportResult {
        try withWimgAbi {
            try ensureInit()
            return try data.withUnsafeBytes { rawBuffer in
                guard let ptr = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    throw WimgError.allocationFailed
                }
                guard let resultPtr = wimg_import_csv(ptr, UInt32(data.count)) else {
                    throw WimgError.importFailed(lastError())
                }
                defer { wimg_free(resultPtr, 0) }
                return try decodeLengthPrefixed(resultPtr)
            }
        }
    }

    // MARK: - Transactions

    static func getTransactions() throws -> [Transaction] {
        try getTransactionsFiltered(account: nil)
    }

    static func getTransactionsFiltered(account: String?) throws -> [Transaction] {
        try withWimgAbi {
            guard isInitialized, !isResetting else { return [] }
            let ptr = withAccountFilter(account) { p, len in
                wimg_get_transactions_filtered(p, len)
            }
            guard let ptr else {
                let err = lastError()
                if err.contains("buffer too small") {
                    throw WimgError.operationFailed("getTransactions", "Zu viele Transaktionen zum Anzeigen. Daten sind gespeichert, aber der Anzeigepuffer ist voll.")
                }
                return []
            }
            defer { wimg_free(ptr, 0) }
            return (try? decodeLengthPrefixed(ptr)) ?? []
        }
    }

    static func setCategory(id: String, category: UInt8) throws {
        try withWimgAbi {
            try ensureInit()
            let idData = Array(id.utf8)
            let rc = idData.withUnsafeBufferPointer { buf in
                wimg_set_category(buf.baseAddress!, UInt32(buf.count), category)
            }
            if rc != 0 {
                throw WimgError.operationFailed("setCategory", lastError())
            }
        }
    }

    static func setExcluded(id: String, excluded: Bool) throws {
        try withWimgAbi {
            try ensureInit()
            let idData = Array(id.utf8)
            let rc = idData.withUnsafeBufferPointer { buf in
                wimg_set_excluded(buf.baseAddress!, UInt32(buf.count), excluded ? 1 : 0)
            }
            if rc != 0 {
                throw WimgError.operationFailed("setExcluded", lastError())
            }
        }
    }

    static func autoCategorize() -> Int {
        withWimgAbi {
            guard isInitialized, !isResetting else { return 0 }
            let result = wimg_auto_categorize()
            return Int(max(result, 0))
        }
    }

    // MARK: - Summaries

    static func getSummary(year: Int, month: Int) -> MonthlySummary {
        getSummaryFiltered(year: year, month: month, account: nil)
    }

    static func getSummaryFiltered(year: Int, month: Int, account: String?) -> MonthlySummary {
        withWimgAbi {
            let empty = MonthlySummary(year: year, month: month, income: 0, expenses: 0, available: 0, tx_count: 0, by_category: [])
            guard isInitialized, !isResetting else { return empty }
            let ptr = withAccountFilter(account) { p, len in
                wimg_get_summary_filtered(UInt32(year), UInt32(month), p, len)
            }
            guard let ptr else { return empty }
            defer { wimg_free(ptr, 0) }
            return (try? decodeLengthPrefixed(ptr)) ?? empty
        }
    }

    // MARK: - Recurring

    static func getRecurring() -> [RecurringPattern] {
        withWimgAbi {
            guard isInitialized, !isResetting else { return [] }
            guard let ptr = wimg_get_recurring() else { return [] }
            defer { wimg_free(ptr, 0) }
            return (try? decodeLengthPrefixed(ptr)) ?? []
        }
    }

    @discardableResult
    static func detectRecurring() -> Int {
        withWimgAbi {
            guard isInitialized, !isResetting else { return 0 }
            let result = wimg_detect_recurring()
            return Int(max(result, 0))
        }
    }

    // MARK: - Accounts

    static func getAccounts() -> [Account] {
        withWimgAbi {
            guard isInitialized, !isResetting else { return [] }
            guard let ptr = wimg_get_accounts() else { return [] }
            defer { wimg_free(ptr, 0) }
            return (try? decodeLengthPrefixed(ptr)) ?? []
        }
    }

    static func addAccount(id: String, name: String, color: String) throws {
        try withWimgAbi {
            try ensureInit()
            let json = """
            {"id":"\(id)","name":"\(name)","bank":"","color":"\(color)"}
            """
            let data = Array(json.utf8)
            let rc = data.withUnsafeBufferPointer { buf in
                wimg_add_account(buf.baseAddress!, UInt32(buf.count))
            }
            if rc != 0 {
                throw WimgError.operationFailed("addAccount", lastError())
            }
        }
    }

    static func updateAccount(id: String, name: String, color: String) throws {
        try withWimgAbi {
            try ensureInit()
            let json = """
            {"id":"\(id)","name":"\(name)","bank":"","color":"\(color)"}
            """
            let data = Array(json.utf8)
            let rc = data.withUnsafeBufferPointer { buf in
                wimg_update_account(buf.baseAddress!, UInt32(buf.count))
            }
            if rc != 0 {
                throw WimgError.operationFailed("updateAccount", lastError())
            }
        }
    }

    static func deleteAccount(id: String) throws {
        try withWimgAbi {
            try ensureInit()
            let idData = Array(id.utf8)
            let rc = idData.withUnsafeBufferPointer { buf in
                wimg_delete_account(buf.baseAddress!, UInt32(buf.count))
            }
            if rc != 0 {
                throw WimgError.operationFailed("deleteAccount", lastError())
            }
        }
    }

    // MARK: - Undo/Redo

    struct UndoResult: Codable {
        let op: String
        let table: String
        let row_id: String
        let column: String?
    }

    static func undo() -> UndoResult? {
        withWimgAbi {
            guard isInitialized, !isResetting else { return nil }
            guard let ptr = wimg_undo() else { return nil }
            defer { wimg_free(ptr, 0) }
            return try? decodeLengthPrefixed(ptr)
        }
    }

    static func redo() -> UndoResult? {
        withWimgAbi {
            guard isInitialized, !isResetting else { return nil }
            guard let ptr = wimg_redo() else { return nil }
            defer { wimg_free(ptr, 0) }
            return try? decodeLengthPrefixed(ptr)
        }
    }

    // MARK: - Sync

    struct SyncRow: Codable {
        let table: String
        let id: String
        let data: [String: AnyCodable]
        let updated_at: Int
    }

    struct SyncPayload: Codable {
        let rows: [SyncRow]
    }

    static func getChanges(sinceMs: Int) -> [SyncRow] {
        withWimgAbi {
            guard isInitialized, !isResetting else { return [] }
            guard let ptr = wimg_get_changes(Int64(sinceMs)) else { return [] }
            defer { wimg_free(ptr, 0) }
            let payload: SyncPayload? = try? decodeLengthPrefixed(ptr)
            return payload?.rows ?? []
        }
    }

    static func applyChanges(_ rows: [SyncRow]) throws -> Int {
        try withWimgAbi {
            try ensureInit()
            let payload = SyncPayload(rows: rows)
            let data = try JSONEncoder().encode(payload)
            let rc = Array(data).withUnsafeBufferPointer { buf in
                wimg_apply_changes(buf.baseAddress!, UInt32(buf.count))
            }
            if rc < 0 {
                throw WimgError.operationFailed("applyChanges", lastError())
            }
            return Int(rc)
        }
    }

    // MARK: - Crypto (E2E encryption for sync)

    /// Derive a 32-byte encryption key from a sync key using HKDF-SHA256.
    static func deriveEncryptionKey(syncKey: String) -> Data? {
        withWimgAbi {
            let keyBytes = Array(syncKey.utf8)
            let ptr = keyBytes.withUnsafeBufferPointer { buf in
                wimg_derive_key(buf.baseAddress!, UInt32(buf.count))
            }
            guard let ptr else { return nil }
            defer { wimg_free(ptr, 0) }
            let len = UInt32(ptr[0]) | (UInt32(ptr[1]) << 8) | (UInt32(ptr[2]) << 16) | (UInt32(ptr[3]) << 24)
            return Data(bytes: ptr.advanced(by: 4), count: Int(len))
        }
    }

    /// Encrypt a plaintext string using XChaCha20-Poly1305. Returns base64-encoded ciphertext.
    static func encryptField(plaintext: String, key: Data) -> String? {
        withWimgAbi {
            let ptBytes = Array(plaintext.utf8)
            var nonce = [UInt8](repeating: 0, count: 24)
            _ = SecRandomCopyBytes(kSecRandomDefault, 24, &nonce)

            let result = ptBytes.withUnsafeBufferPointer { ptBuf in
                key.withUnsafeBytes { keyBuf in
                    nonce.withUnsafeBufferPointer { nonceBuf in
                        wimg_encrypt_field(
                            ptBuf.baseAddress!, UInt32(ptBuf.count),
                            keyBuf.baseAddress!.assumingMemoryBound(to: UInt8.self),
                            nonceBuf.baseAddress!
                        )
                    }
                }
            }
            guard let result else { return nil }
            defer { wimg_free(result, 0) }
            return readLengthPrefixedString(result)
        }
    }

    /// Decrypt a base64-encoded ciphertext using XChaCha20-Poly1305. Returns plaintext string.
    static func decryptField(ciphertext: String, key: Data) -> String? {
        withWimgAbi {
            let ctBytes = Array(ciphertext.utf8)
            let result = ctBytes.withUnsafeBufferPointer { ctBuf in
                key.withUnsafeBytes { keyBuf in
                    wimg_decrypt_field(
                        ctBuf.baseAddress!, UInt32(ctBuf.count),
                        keyBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
                    )
                }
            }
            guard let result else { return nil }
            defer { wimg_free(result, 0) }
            return readLengthPrefixedString(result)
        }
    }

    // MARK: - FinTS (native-only bank connection)

    static func fintsGetBanks() -> [BankInfo] {
        withWimgAbi {
            guard let ptr = wimg_fints_get_banks() else { return [] }
            defer { wimg_free(ptr, 0) }
            return (try? decodeLengthPrefixed(ptr)) ?? []
        }
    }

    /// Runs blocking FinTS work on a thread with a 2 MB stack: the protocol
    /// code overflows the 512 KB stack of GCD threads.
    static func onLargeStack<T>(qos: QualityOfService = .userInitiated, _ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let thread = Thread {
                do { continuation.resume(returning: try work()) } catch { continuation.resume(throwing: error) }
            }
            thread.stackSize = 2 * 1024 * 1024
            thread.qualityOfService = qos
            thread.start()
        }
    }

    /// Sends a JSON request to a FinTS C ABI call. JSONEncoder escapes every
    /// value, so a PIN or TAN with `"` or `\\` can't break the request.
    private static func fintsCall<T: Encodable, R: Decodable>(
        _ name: String, _ payload: T,
        _ fn: (UnsafePointer<UInt8>, UInt32) -> UnsafePointer<UInt8>?
    ) throws -> R {
        try withWimgAbi {
            try ensureInit()
            let data = Array(try JSONEncoder().encode(payload))
            let ptr: UnsafePointer<UInt8>? = data.withUnsafeBufferPointer { buf in
                fn(buf.baseAddress!, UInt32(buf.count))
            }
            guard let ptr else {
                throw WimgError.operationFailed(name, lastError())
            }
            defer { wimg_free(ptr, 0) }
            return try decodeLengthPrefixed(ptr)
        }
    }

    private struct ConnectRequest: Encodable { let blz, user, pin, product: String }
    private struct TanRequest: Encodable { let tan: String }
    private struct FetchRequest: Encodable { let from, to: String }

    static func fintsConnect(blz: String, user: String, pin: String, product: String = "F7C4049477F6136957A46EC28") throws -> FintsStatusResult {
        try fintsCall("fintsConnect", ConnectRequest(blz: blz, user: user, pin: pin, product: product)) { wimg_fints_connect($0, $1) }
    }

    static func fintsSendTan(tan: String) throws -> FintsStatusResult {
        try fintsCall("fintsSendTan", TanRequest(tan: tan)) { wimg_fints_send_tan($0, $1) }
    }

    private struct TanMediumSetRequest: Encodable { let name: String }

    static func fintsGetTanMedia() throws -> FintsTanMediaResult {
        try withWimgAbi {
            try ensureInit()
            guard let ptr = wimg_fints_get_tan_media() else {
                throw WimgError.operationFailed("fintsGetTanMedia", lastError())
            }
            defer { wimg_free(ptr, 0) }
            return try decodeLengthPrefixed(ptr)
        }
    }

    static func fintsSetTanMedium(name: String) throws -> FintsStatusResult {
        try fintsCall("fintsSetTanMedium", TanMediumSetRequest(name: name)) { wimg_fints_set_tan_medium($0, $1) }
    }

    static func fintsFetch(from: String, to: String) throws -> FintsFetchResult {
        try fintsCall("fintsFetch", FetchRequest(from: from, to: to)) { wimg_fints_fetch($0, $1) }
    }

    // MARK: - Snapshots

    static func takeSnapshot(year: Int, month: Int) throws {
        try withWimgAbi {
            try ensureInit()
            let rc = wimg_take_snapshot(UInt32(year), UInt32(month))
            if rc != 0 {
                throw WimgError.operationFailed("takeSnapshot", lastError())
            }
        }
    }

    static func getSnapshots() -> [Snapshot] {
        withWimgAbi {
            guard isInitialized, !isResetting else { return [] }
            guard let ptr = wimg_get_snapshots() else { return [] }
            defer { wimg_free(ptr, 0) }
            return (try? decodeLengthPrefixed(ptr)) ?? []
        }
    }

    // MARK: - Export

    static func exportCsv() -> String? {
        withWimgAbi {
            guard isInitialized, !isResetting else { return nil }
            guard let ptr = wimg_export_csv() else { return nil }
            defer { wimg_free(ptr, 0) }
            return readLengthPrefixedString(ptr)
        }
    }

    static func exportDb() -> String? {
        withWimgAbi {
            guard isInitialized, !isResetting else { return nil }
            guard let ptr = wimg_export_db() else { return nil }
            defer { wimg_free(ptr, 0) }
            return readLengthPrefixedString(ptr)
        }
    }

    // MARK: - Private Helpers

    private static func dbPath() -> String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("wimg.db").path
    }

    private static func ensureInit() throws {
        if !isInitialized || isResetting {
            throw WimgError.notInitialized
        }
    }

    /// Call a C ABI function with an account filter string.
    /// Handles empty strings safely (passes a valid pointer with zero length).
    private static func withAccountFilter<T>(
        _ account: String?,
        _ body: (UnsafePointer<UInt8>, UInt32) -> T
    ) -> T {
        let acctStr = account ?? ""
        if acctStr.isEmpty {
            var zero: UInt8 = 0
            return body(&zero, 0)
        }
        let acctData = Array(acctStr.utf8)
        return acctData.withUnsafeBufferPointer { buf in
            body(buf.baseAddress!, UInt32(buf.count))
        }
    }

    /// Read a length-prefixed raw string (4 bytes LE length + data).
    private static func readLengthPrefixedString(_ ptr: UnsafePointer<UInt8>) -> String? {
        let len = UInt32(ptr[0]) | (UInt32(ptr[1]) << 8) | (UInt32(ptr[2]) << 16) | (UInt32(ptr[3]) << 24)
        var bytes = [UInt8](UnsafeBufferPointer(start: ptr.advanced(by: 4), count: Int(len)))
        // Belt-and-braces: legacy FinTS imports can leave embedded NUL/control
        // bytes or truncated multi-byte sequences in description text. A strict
        // UTF-8 decode would return nil and make the whole export silently fail
        // ("nothing happens"). Swap NULs for spaces and decode leniently so the
        // export always succeeds with the data we have.
        for i in bytes.indices where bytes[i] == 0 { bytes[i] = UInt8(ascii: " ") }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Read a length-prefixed string (4 bytes LE length + data) and decode as JSON.
    private static func decodeLengthPrefixed<T: Decodable>(_ ptr: UnsafePointer<UInt8>) throws -> T {
        let len = UInt32(ptr[0]) | (UInt32(ptr[1]) << 8) | (UInt32(ptr[2]) << 16) | (UInt32(ptr[3]) << 24)
        var data = Data(bytes: ptr.advanced(by: 4), count: Int(len))
        // Defensive: FinTS MT940 :86: fields occasionally carry embedded 0x00
        // bytes that survive into description text. Foundation's JSONDecoder
        // rejects raw NUL inside string literals ("Unescaped control character
        // '0x0'"), so swap them for spaces before decoding. Real fix lives in
        // libwimg's MT940 parser — this is a belt-and-braces guard.
        if data.contains(0) {
            data = Data(data.map { $0 == 0 ? UInt8(ascii: " ") : $0 })
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func lastError() -> String {
        guard let ptr = wimg_get_error() else { return "Unknown error" }
        defer { wimg_free(ptr, 0) }
        let len = UInt32(ptr[0]) | (UInt32(ptr[1]) << 8) | (UInt32(ptr[2]) << 16) | (UInt32(ptr[3]) << 24)
        let data = Data(bytes: ptr.advanced(by: 4), count: Int(len))
        return String(data: data, encoding: .utf8) ?? "Unknown error"
    }
}

enum WimgError: LocalizedError {
    case notInitialized
    case initFailed(String)
    case allocationFailed
    case importFailed(String)
    case operationFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .notInitialized: "Database not initialized"
        case .initFailed(let msg): "Init failed: \(msg)"
        case .allocationFailed: "Memory allocation failed"
        case .importFailed(let msg): "Import failed: \(msg)"
        case .operationFailed(let op, let msg): "\(op) failed: \(msg)"
        }
    }
}
