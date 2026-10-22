//! MCP (Model Context Protocol) over Streamable HTTP — the native port of
//! `../wimg-sync/src/mcp-tools.ts` + `mcp-session.ts`.
//!
//! Two tools, matching the Worker after its Code-Mode refactor:
//!   query(sql)                          — read-only SQL over the live SQLite
//!   set_category(transaction_id, cat)   — the only write
//!
//! libwimg is a singleton (one global DB + one fixed-buffer arena), so MCP
//! requests are serialized by `lib_lock`. Per request we load the caller's
//! decrypted rows into libwimg's in-memory SQLite, run the tool, and (for
//! writes) re-encrypt the changed rows back into our own Store so they persist
//! and fan out over WebSocket.
//!
//! Dual-era transport: a request carrying modern per-request `_meta`
//! (`io.modelcontextprotocol/protocolVersion`) is served under MCP 2026-07-28 —
//! no handshake, no session, `server/discover`, mirrored-header validation,
//! `resultType` + cache hints. Anything else gets the 2025-03-26 behavior the
//! Worker had (initialize → tools/list → tools/call), which is what Claude
//! Desktop via `mcp-remote` still speaks.
//!
//! Natively we share libwimg's address space, so strings are passed by
//! (ptr, len) directly — no `wimg_alloc` bounce needed. Every libwimg call that
//! returns a length-prefixed buffer allocates from libwimg's arena, which
//! `wimg_free` resets wholesale; so we copy each result out immediately.

const std = @import("std");
const store_mod = @import("store.zig");
const Store = store_mod.Store;
const Row = store_mod.Row;

// --- libwimg C ABI (resolved at link time) ---
extern fn wimg_init(path: [*:0]const u8) i32;
extern fn wimg_close() void;
extern fn wimg_free(ptr: [*]const u8, len: u32) void;
extern fn wimg_get_categories() ?[*]const u8;
extern fn wimg_query(sql: [*]const u8, sql_len: u32) ?[*]const u8;
extern fn wimg_set_category(id: [*]const u8, id_len: u32, category: u8) i32;
extern fn wimg_get_changes(since_ts: i64) ?[*]const u8;
extern fn wimg_apply_changes(data: [*]const u8, len: u32) i32;
extern fn wimg_derive_key(sync_key: [*]const u8, sync_key_len: u32) ?[*]const u8;
extern fn wimg_encrypt_field(pt: [*]const u8, pt_len: u32, key: [*]const u8, nonce: [*]const u8) ?[*]const u8;
extern fn wimg_decrypt_field(ct: [*]const u8, ct_len: u32, key: [*]const u8) ?[*]const u8;

// libc CSPRNG for the encryption nonce (macOS + glibc ≥ 2.36 / BSD).
extern fn arc4random_buf(buf: [*]u8, len: usize) void;

/// libwimg's global DB + arena are process-wide singletons, so all MCP work is
/// serialized on this lock.
var lib_spin: SpinLock = .{};

const SpinLock = struct {
    locked: std.atomic.Value(bool) = .init(false),
    fn lock(self: *SpinLock) void {
        while (self.locked.cmpxchgWeak(false, true, .acquire, .monotonic) != null) std.atomic.spinLoopHint();
    }
    fn unlock(self: *SpinLock) void {
        self.locked.store(false, .release);
    }
};

pub const RpcResult = struct {
    /// HTTP status. Modern requests use 400/404 for protocol errors.
    status: std.http.Status = .ok,
    /// False for modern requests: 2026-07-28 has no sessions, so the caller
    /// must not mint or echo `Mcp-Session-Id`.
    session: bool = true,
    /// JSON-RPC response body. Empty slice → it was a notification (caller
    /// replies 202 with no body).
    body: []u8,
    /// `{"type":"changes","rows":[...]}` to broadcast to this key's WebSocket
    /// listeners, or null when the request made no writes.
    broadcast: ?[]u8 = null,
};

/// Legacy (initialize-handshake) revision the Worker spoke.
const PROTOCOL_VERSION = "2025-03-26";
/// Modern stateless revision.
const MODERN_VERSION = "2026-07-28";
const SUPPORTED_VERSIONS_JSON = "[\"" ++ MODERN_VERSION ++ "\",\"2025-11-25\",\"2025-06-18\",\"" ++ PROTOCOL_VERSION ++ "\"]";
const SERVER_INFO_JSON = "{\"name\":\"wimg\",\"version\":\"0.3.0\"}";
/// Tool list and discovery never vary per user, so shared caches may keep them.
const CACHE_HINTS_JSON = "\"ttlMs\":3600000,\"cacheScope\":\"public\"";
const INSTRUCTIONS = "wimg personal finance (amounts in integer cents, negative = expense). " ++
    "Read anything with query (read-only SQL; its description lists the tables and category ids). " ++
    "set_category is the only write.";

/// The MCP request headers the HTTP layer captured (empty when absent).
pub const Headers = struct {
    protocol_version: []const u8 = "",
    method: []const u8 = "",
    name: []const u8 = "",
};

// --- length-prefixed helpers ---

fn lenOf(ptr: [*]const u8) usize {
    return @as(usize, ptr[0]) | (@as(usize, ptr[1]) << 8) | (@as(usize, ptr[2]) << 16) | (@as(usize, ptr[3]) << 24);
}

/// Copy a libwimg length-prefixed result into `gpa` memory, then reset the arena.
fn dupResult(gpa: std.mem.Allocator, ptr: ?[*]const u8) !?[]u8 {
    const p = ptr orelse return null;
    const out = try gpa.dupe(u8, p[4 .. 4 + lenOf(p)]);
    wimg_free(p, 0);
    return out;
}

// --- public entry point ---

/// Handle one JSON-RPC request body. Caller holds nothing; this serializes on
/// the libwimg lock internally. Returned slices are owned by `gpa`.
pub fn handleRpc(gpa: std.mem.Allocator, store: *Store, key: []const u8, body: []const u8, headers: Headers) !RpcResult {
    const parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch
        return errorResponse(gpa, null, -32700, "Parse error");
    defer parsed.deinit();
    if (parsed.value != .object) return errorResponse(gpa, null, -32600, "Invalid request");
    const obj = parsed.value.object;

    const method = switch (obj.get("method") orelse return errorResponse(gpa, null, -32600, "Missing method")) {
        .string => |s| s,
        else => return errorResponse(gpa, null, -32600, "Invalid method"),
    };

    // Echo the request id verbatim (number, string, or null). Absent → notification.
    const id_json: ?[]u8 = if (obj.get("id")) |v|
        try std.json.Stringify.valueAlloc(gpa, v, .{})
    else
        null;
    defer if (id_json) |id| gpa.free(id);

    const params = obj.get("params");
    if (modernVersion(params)) |version| {
        return handleModern(gpa, store, key, id_json, method, params, version, headers);
    }

    if (std.mem.eql(u8, method, "initialize")) {
        return .{ .body = try result(gpa, id_json, "{\"protocolVersion\":\"" ++ PROTOCOL_VERSION ++
            "\",\"capabilities\":{\"tools\":{}},\"serverInfo\":" ++ SERVER_INFO_JSON ++ "}") };
    }
    if (std.mem.startsWith(u8, method, "notifications/")) {
        return .{ .body = "" }; // notification — no response
    }
    if (std.mem.eql(u8, method, "ping")) {
        return .{ .body = try result(gpa, id_json, "{}") };
    }
    if (std.mem.eql(u8, method, "tools/list")) {
        return .{ .body = try result(gpa, id_json, TOOLS_LIST) };
    }
    if (std.mem.eql(u8, method, "tools/call")) {
        return handleToolCall(gpa, store, key, id_json, params);
    }

    return errorResponse(gpa, id_json, -32601, "Method not found");
}

/// `params._meta["io.modelcontextprotocol/protocolVersion"]`, present only on
/// modern (2026-07-28+) requests.
fn modernVersion(params: ?std.json.Value) ?[]const u8 {
    const p = params orelse return null;
    if (p != .object) return null;
    const meta = p.object.get("_meta") orelse return null;
    if (meta != .object) return null;
    return switch (meta.object.get("io.modelcontextprotocol/protocolVersion") orelse return null) {
        .string => |v| v,
        else => null,
    };
}

/// Serve one stateless 2026-07-28 request.
fn handleModern(
    gpa: std.mem.Allocator,
    store: *Store,
    key: []const u8,
    id_json: ?[]u8,
    method: []const u8,
    params: ?std.json.Value,
    version: []const u8,
    headers: Headers,
) !RpcResult {
    if (!std.mem.eql(u8, version, MODERN_VERSION)) {
        var data: std.ArrayList(u8) = .empty;
        defer data.deinit(gpa);
        try data.appendSlice(gpa, "{\"supported\":" ++ SUPPORTED_VERSIONS_JSON ++ ",\"requested\":");
        try appendJsonString(gpa, &data, version);
        try data.append(gpa, '}');
        return modernError(gpa, id_json, .bad_request, -32022, "Unsupported protocol version", data.items);
    }

    // Mirrored headers must be present and match the body, so a gateway that
    // routes on headers can't be steered apart from what we execute.
    if (!std.mem.eql(u8, headers.protocol_version, version))
        return modernError(gpa, id_json, .bad_request, -32020, "Header mismatch: MCP-Protocol-Version", null);
    if (!std.mem.eql(u8, headers.method, method))
        return modernError(gpa, id_json, .bad_request, -32020, "Header mismatch: Mcp-Method", null);
    if (std.mem.eql(u8, method, "tools/call")) {
        const body_name = if (params) |p| (if (p == .object) strField(p.object, "name") else null) else null;
        var name_buf: [256]u8 = undefined;
        const header_name = decodeHeaderValue(headers.name, &name_buf) orelse
            return modernError(gpa, id_json, .bad_request, -32020, "Header mismatch: Mcp-Name malformed", null);
        if (body_name == null or !std.mem.eql(u8, header_name, body_name.?))
            return modernError(gpa, id_json, .bad_request, -32020, "Header mismatch: Mcp-Name", null);
    }

    if (std.mem.eql(u8, method, "server/discover")) {
        return .{ .session = false, .body = try modernResult(gpa, id_json, "{\"supportedVersions\":" ++ SUPPORTED_VERSIONS_JSON ++
            ",\"capabilities\":{\"tools\":{}},\"instructions\":\"" ++ INSTRUCTIONS ++ "\"," ++ CACHE_HINTS_JSON ++ "}") };
    }
    if (std.mem.eql(u8, method, "tools/list")) {
        // TOOLS_LIST is `{"tools":[...]}` — splice the cache hints in before its closing brace.
        const with_hints = TOOLS_LIST[0 .. TOOLS_LIST.len - 1] ++ "," ++ CACHE_HINTS_JSON ++ "}";
        return .{ .session = false, .body = try modernResult(gpa, id_json, with_hints) };
    }
    if (std.mem.eql(u8, method, "tools/call")) {
        return modernize(gpa, try handleToolCall(gpa, store, key, id_json, params));
    }
    // initialize, ping and the rest don't exist in 2026-07-28.
    return modernError(gpa, id_json, .not_found, -32601, "Method not found", null);
}

/// Rewrap a legacy tool reply for 2026-07-28: a `result` gains `resultType` +
/// serverInfo `_meta`; JSON-RPC errors pass through. The tool code builds
/// replies in one place for both eras, so converting here keeps it unchanged.
fn modernize(gpa: std.mem.Allocator, legacy: RpcResult) !RpcResult {
    var r = legacy;
    r.session = false;
    const parsed = try std.json.parseFromSlice(std.json.Value, gpa, legacy.body, .{});
    defer parsed.deinit();
    const res = parsed.value.object.get("result") orelse return r;
    const id_json = try std.json.Stringify.valueAlloc(gpa, parsed.value.object.get("id") orelse .null, .{});
    defer gpa.free(id_json);
    const res_json = try std.json.Stringify.valueAlloc(gpa, res, .{});
    defer gpa.free(res_json);
    r.body = try modernResult(gpa, id_json, res_json);
    gpa.free(legacy.body);
    return r;
}

/// Decode an `Mcp-Name` value: plain ASCII, or the `=?base64?…?=` sentinel.
fn decodeHeaderValue(value: []const u8, buf: []u8) ?[]const u8 {
    const prefix = "=?base64?";
    const suffix = "?=";
    if (!(std.mem.startsWith(u8, value, prefix) and std.mem.endsWith(u8, value, suffix) and value.len >= prefix.len + suffix.len))
        return value;
    const enc = value[prefix.len .. value.len - suffix.len];
    const n = std.base64.standard.Decoder.calcSizeForSlice(enc) catch return null;
    if (n > buf.len) return null;
    std.base64.standard.Decoder.decode(buf[0..n], enc) catch return null;
    return buf[0..n];
}

fn handleToolCall(gpa: std.mem.Allocator, store: *Store, key: []const u8, id_json: ?[]u8, params: ?std.json.Value) !RpcResult {
    const p = (params orelse return errorResponse(gpa, id_json, -32602, "Missing params"));
    if (p != .object) return errorResponse(gpa, id_json, -32602, "Invalid params");
    const name = switch (p.object.get("name") orelse return errorResponse(gpa, id_json, -32602, "Missing tool name")) {
        .string => |s| s,
        else => return errorResponse(gpa, id_json, -32602, "Invalid tool name"),
    };
    const args = p.object.get("arguments") orelse std.json.Value{ .null = {} };

    lib_spin.lock();
    defer lib_spin.unlock();

    // Fresh in-memory DB loaded with this key's decrypted rows.
    if (wimg_init(":memory:") != 0) return errorResponse(gpa, id_json, -32603, "wimg_init failed");
    defer wimg_close();

    var enc_key: [32]u8 = undefined;
    loadKeyData(gpa, store, key, &enc_key) catch
        return errorResponse(gpa, id_json, -32603, "Failed to load data");

    if (std.mem.eql(u8, name, "query")) {
        return toolQuery(gpa, id_json, args);
    } else if (std.mem.eql(u8, name, "set_category")) {
        return toolSetCategory(gpa, store, key, id_json, args, &enc_key);
    }
    return errorResponse(gpa, id_json, -32602, "Unknown tool");
}

// --- data loading (decrypt our Store rows → libwimg) ---

fn loadKeyData(gpa: std.mem.Allocator, store: *Store, key: []const u8, enc_key_out: *[32]u8) !void {
    // Derive the 32-byte encryption key from the sync key.
    const key_buf = (try dupResult(gpa, wimg_derive_key(key.ptr, @intCast(key.len)))) orelse return error.KeyDerivation;
    defer gpa.free(key_buf);
    if (key_buf.len != 32) return error.KeyDerivation;
    @memcpy(enc_key_out, key_buf[0..32]);

    // Pull all stored rows for this key (encrypted), then decrypt each `data`.
    var pull: std.ArrayList(u8) = .empty;
    defer pull.deinit(gpa);
    try store.rowsSinceJson(gpa, key, 0, &pull);

    const parsed = try std.json.parseFromSlice(std.json.Value, gpa, pull.items, .{});
    defer parsed.deinit();
    const rows = (parsed.value.object.get("rows") orelse return).array.items;
    if (rows.len == 0) return;

    var apply: std.ArrayList(u8) = .empty;
    defer apply.deinit(gpa);
    try apply.appendSlice(gpa, "{\"rows\":[");
    var wrote = false;
    for (rows) |row| {
        if (row != .object) continue;
        const o = row.object;
        const table = strField(o, "table") orelse continue;
        const id = strField(o, "id") orelse continue;
        const updated_at = intField(o, "updated_at") orelse continue;
        const data_val = o.get("data") orelse continue;

        // Encrypted rows carry `data` as a base64 string; dev rows as an object.
        const plaintext: []u8 = switch (data_val) {
            .string => |ct| (try dupResult(gpa, wimg_decrypt_field(ct.ptr, @intCast(ct.len), enc_key_out))) orelse continue,
            else => try std.json.Stringify.valueAlloc(gpa, data_val, .{}),
        };
        defer gpa.free(plaintext);

        if (wrote) try apply.append(gpa, ',');
        wrote = true;
        try apply.appendSlice(gpa, "{\"table\":");
        try appendJsonString(gpa, &apply, table);
        try apply.appendSlice(gpa, ",\"id\":");
        try appendJsonString(gpa, &apply, id);
        try apply.appendSlice(gpa, ",\"data\":");
        try apply.appendSlice(gpa, plaintext);
        try apply.appendSlice(gpa, ",\"updated_at\":");
        try appendInt(gpa, &apply, updated_at);
        try apply.append(gpa, '}');
    }
    try apply.appendSlice(gpa, "]}");

    if (wimg_apply_changes(apply.items.ptr, @intCast(apply.items.len)) < 0) return error.ApplyFailed;
}

// --- query tool ---

fn toolQuery(gpa: std.mem.Allocator, id_json: ?[]u8, args: std.json.Value) !RpcResult {
    const sql = if (args == .object) strField(args.object, "sql") orelse "" else "";
    if (sql.len == 0) return toolError(gpa, id_json, "query: missing 'sql'");
    if (!isReadOnlySql(sql)) return toolError(gpa, id_json, "query: only SELECT / WITH statements allowed");

    const res = (try dupResult(gpa, wimg_query(sql.ptr, @intCast(sql.len)))) orelse
        return toolError(gpa, id_json, "query: failed (check SQL)");
    defer gpa.free(res);
    const scrubbed = stripResultPii(gpa, res) catch res;
    defer if (scrubbed.ptr != res.ptr) gpa.free(scrubbed);
    return toolText(gpa, id_json, scrubbed);
}

// --- PII scrubbing (ported from mcp-tools.ts stripPII / PII_COLUMNS) ---

/// Column names (case-insensitive) whose string cells get scrubbed.
fn isPiiColumn(name: []const u8) bool {
    const cols = [_][]const u8{ "desc", "description", "raw", "note", "reference", "pattern", "payee", "merchant" };
    for (cols) |c| if (std.ascii.eqlIgnoreCase(name, c)) return true;
    return false;
}

/// Re-run a `{columns,rows,...}` query result, scrubbing PII from string cells
/// of PII columns. Returns the original slice unchanged when there's nothing to do.
fn stripResultPii(gpa: std.mem.Allocator, result_json: []const u8) ![]const u8 {
    const parsed = try std.json.parseFromSlice(std.json.Value, gpa, result_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return result_json;
    const cols_v = parsed.value.object.get("columns") orelse return result_json;
    const rows_v = parsed.value.object.get("rows") orelse return result_json;
    if (cols_v != .array or rows_v != .array) return result_json;

    // Which column indices are PII?
    var pii = std.ArrayList(usize).empty;
    defer pii.deinit(gpa);
    for (cols_v.array.items, 0..) |col, idx| {
        if (col == .string and isPiiColumn(col.string)) try pii.append(gpa, idx);
    }
    if (pii.items.len == 0) return result_json;

    var owned = std.ArrayList([]u8).empty;
    defer {
        for (owned.items) |b| gpa.free(b);
        owned.deinit(gpa);
    }
    for (rows_v.array.items) |row| {
        if (row != .array) continue;
        for (pii.items) |idx| {
            if (idx >= row.array.items.len) continue;
            const cell = row.array.items[idx];
            if (cell != .string) continue;
            const stripped = try stripPii(gpa, cell.string);
            try owned.append(gpa, stripped);
            row.array.items[idx] = .{ .string = stripped };
        }
    }

    return std.json.Stringify.valueAlloc(gpa, parsed.value, .{});
}

fn isWord(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

/// Hand-rolled port of the Worker's stripPII regex chain: scrub IBANs, BICs,
/// card numbers, and `EREF+/MREF+/CRED+/KREF+/IBAN+/ABWA+` reference fields, then
/// collapse whitespace.
fn stripPii(gpa: std.mem.Allocator, input: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(gpa);

    var i: usize = 0;
    while (i < input.len) {
        const boundary = (i == 0) or !isWord(input[i - 1]);

        // EREF+/MREF+/CRED+/KREF+/IBAN+ <non-space>  → "PREFIX+***"
        const refs = [_][]const u8{ "EREF+", "MREF+", "CRED+", "KREF+", "IBAN+" };
        var matched = false;
        if (boundary) {
            for (refs) |pre| {
                if (std.mem.startsWith(u8, input[i..], pre)) {
                    try out.appendSlice(gpa, pre);
                    try out.appendSlice(gpa, "***");
                    i += pre.len;
                    while (i < input.len and input[i] != ' ' and input[i] != '\t') i += 1;
                    matched = true;
                    break;
                }
            }
        }
        if (matched) continue;

        // ABWA+ <until '+'>  → "ABWA+***"
        if (boundary and std.mem.startsWith(u8, input[i..], "ABWA+")) {
            try out.appendSlice(gpa, "ABWA+***");
            i += "ABWA+".len;
            while (i < input.len and input[i] != '+') i += 1;
            continue;
        }

        // BIC+<8-11 alnum>  → "BIC+***"
        if (boundary and std.mem.startsWith(u8, input[i..], "BIC+")) {
            var j = i + "BIC+".len;
            var n: usize = 0;
            while (j < input.len and std.ascii.isAlphanumeric(input[j])) : (j += 1) n += 1;
            if (n >= 8 and n <= 11) {
                try out.appendSlice(gpa, "BIC+***");
                i = j;
                continue;
            }
        }

        // IBAN number (2 letters, 2 digits, 4×4 digit groups, optional trailing).
        if (boundary) {
            if (matchIban(input, i)) |end| {
                try out.appendSlice(gpa, "***");
                i = end;
                continue;
            }
            // Card number (4×4 digit groups).
            if (matchCard(input, i)) |end| {
                try out.appendSlice(gpa, "***");
                i = end;
                continue;
            }
        }

        try out.append(gpa, input[i]);
        i += 1;
    }

    // Collapse runs of spaces/tabs and trim.
    return collapseWhitespace(gpa, try out.toOwnedSlice(gpa));
}

/// `[A-Z]{2}\d{2}` then four mandatory `\s?\d{4}` groups, then optional trailing
/// `\s?\d{0,4}\s?\d{0,2}`. Returns the end index, or null if no match.
fn matchIban(s: []const u8, start: usize) ?usize {
    if (start + 4 > s.len) return null;
    if (!std.ascii.isUpper(s[start]) or !std.ascii.isUpper(s[start + 1])) return null;
    if (!std.ascii.isDigit(s[start + 2]) or !std.ascii.isDigit(s[start + 3])) return null;
    var p = start + 4;
    var g: usize = 0;
    while (g < 4) : (g += 1) {
        if (p < s.len and s[p] == ' ') p += 1;
        var k: usize = 0;
        while (k < 4) : (k += 1) {
            if (p >= s.len or !std.ascii.isDigit(s[p])) return null;
            p += 1;
        }
    }
    p = consumeOptDigits(s, p, 4);
    p = consumeOptDigits(s, p, 2);
    return p;
}

/// Optional single space + up to `max` digits (only consumed if at least one
/// digit follows). Returns the (possibly advanced) index.
fn consumeOptDigits(s: []const u8, start: usize, max: usize) usize {
    var p = start;
    const after_space = if (p < s.len and s[p] == ' ') p + 1 else p;
    if (after_space >= s.len or !std.ascii.isDigit(s[after_space])) return start;
    p = after_space;
    var k: usize = 0;
    while (k < max and p < s.len and std.ascii.isDigit(s[p])) : (k += 1) p += 1;
    return p;
}

/// Four groups of exactly four digits (optional single space between), not
/// followed by another digit.
fn matchCard(s: []const u8, start: usize) ?usize {
    var p = start;
    var g: usize = 0;
    while (g < 4) : (g += 1) {
        if (g > 0 and p < s.len and s[p] == ' ') p += 1;
        var k: usize = 0;
        while (k < 4) : (k += 1) {
            if (p >= s.len or !std.ascii.isDigit(s[p])) return null;
            p += 1;
        }
    }
    if (p < s.len and std.ascii.isDigit(s[p])) return null; // 17th digit → not a card
    return p;
}

/// Collapse runs of spaces/tabs to a single space and trim ends. Frees `in`.
fn collapseWhitespace(gpa: std.mem.Allocator, in: []u8) ![]u8 {
    defer gpa.free(in);
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(gpa);
    var prev_space = false;
    for (in) |c| {
        const is_space = c == ' ' or c == '\t';
        if (is_space) {
            if (!prev_space) try out.append(gpa, ' ');
            prev_space = true;
        } else {
            try out.append(gpa, c);
            prev_space = false;
        }
    }
    const slice = try out.toOwnedSlice(gpa);
    const trimmed = std.mem.trim(u8, slice, " ");
    if (trimmed.len == slice.len) return slice;
    const dup = try gpa.dupe(u8, trimmed);
    gpa.free(slice);
    return dup;
}

// --- set_category tool ---

fn toolSetCategory(gpa: std.mem.Allocator, store: *Store, key: []const u8, id_json: ?[]u8, args: std.json.Value, enc_key: *[32]u8) !RpcResult {
    if (args != .object) return toolError(gpa, id_json, "set_category: missing arguments");
    const txn_id = strField(args.object, "transaction_id") orelse return toolError(gpa, id_json, "set_category: missing 'transaction_id'");
    const cat_name = strField(args.object, "category") orelse return toolError(gpa, id_json, "set_category: missing 'category'");

    const cat_id = (try resolveCategoryId(gpa, cat_name)) orelse
        return toolError(gpa, id_json, "set_category: unknown category");

    if (wimg_set_category(txn_id.ptr, @intCast(txn_id.len), cat_id) != 0)
        return toolError(gpa, id_json, "set_category: failed");

    // Persist + broadcast: pull the changed rows, re-encrypt, merge into Store.
    const broadcast = try writeBackChanges(gpa, store, key, enc_key);

    var msg: std.ArrayList(u8) = .empty;
    defer msg.deinit(gpa);
    try msg.appendSlice(gpa, "{\"success\":true,\"transaction_id\":");
    try appendJsonString(gpa, &msg, txn_id);
    try msg.appendSlice(gpa, ",\"category_id\":");
    try appendInt(gpa, &msg, cat_id);
    try msg.append(gpa, '}');

    var r = try toolText(gpa, id_json, msg.items);
    r.broadcast = broadcast;
    return r;
}

/// Re-encrypt libwimg's pending changes and merge them into our Store. Returns
/// a `{"type":"changes",...}` broadcast payload (or null if nothing changed).
fn writeBackChanges(gpa: std.mem.Allocator, store: *Store, key: []const u8, enc_key: *[32]u8) !?[]u8 {
    const changes = (try dupResult(gpa, wimg_get_changes(0))) orelse return null;
    defer gpa.free(changes);

    const parsed = std.json.parseFromSlice(std.json.Value, gpa, changes, .{}) catch return null;
    defer parsed.deinit();
    const rows = (parsed.value.object.get("rows") orelse return null).array.items;
    if (rows.len == 0) return null;

    var enc_rows = try std.ArrayList(Row).initCapacity(gpa, rows.len);
    defer enc_rows.deinit(gpa);
    var owned = try std.ArrayList([]u8).initCapacity(gpa, rows.len * 2);
    defer {
        for (owned.items) |b| gpa.free(b);
        owned.deinit(gpa);
    }

    for (rows) |row| {
        if (row != .object) continue;
        const o = row.object;
        const table = strField(o, "table") orelse continue;
        const id = strField(o, "id") orelse continue;
        const updated_at = intField(o, "updated_at") orelse continue;
        const data_val = o.get("data") orelse continue;

        const plaintext = try std.json.Stringify.valueAlloc(gpa, data_val, .{});
        defer gpa.free(plaintext);

        var nonce: [24]u8 = undefined;
        arc4random_buf(&nonce, nonce.len);
        const ct = (try dupResult(gpa, wimg_encrypt_field(plaintext.ptr, @intCast(plaintext.len), enc_key, &nonce))) orelse continue;
        // Store `data` as a JSON string value: "<ciphertext>".
        var quoted: std.ArrayList(u8) = .empty;
        try appendJsonString(gpa, &quoted, ct);
        gpa.free(ct);
        const quoted_slice = try quoted.toOwnedSlice(gpa);

        const table_dup = try gpa.dupe(u8, table);
        const id_dup = try gpa.dupe(u8, id);
        try owned.append(gpa, quoted_slice);
        try owned.append(gpa, table_dup);
        try owned.append(gpa, id_dup);
        try enc_rows.append(gpa, .{ .table = table_dup, .id = id_dup, .data = quoted_slice, .updated_at = updated_at });
    }

    if (enc_rows.items.len == 0) return null;
    _ = store.merge(key, enc_rows.items) catch {};

    var bc: std.ArrayList(u8) = .empty;
    errdefer bc.deinit(gpa);
    try bc.appendSlice(gpa, "{\"type\":\"changes\",\"rows\":");
    try store_mod.appendRowsArrayJson(gpa, &bc, enc_rows.items);
    try bc.append(gpa, '}');
    return try bc.toOwnedSlice(gpa);
}

// --- category resolution (ported from mcp-tools.ts) ---

const Alias = struct { k: []const u8, v: []const u8 };
const CATEGORY_ALIASES = [_]Alias{
    .{ .k = "uncategorized", .v = "unkategorisiert" },
    .{ .k = "groceries", .v = "lebensmittel" },
    .{ .k = "food", .v = "lebensmittel" },
    .{ .k = "dining", .v = "essen gehen" },
    .{ .k = "restaurant", .v = "essen gehen" },
    .{ .k = "restaurants", .v = "essen gehen" },
    .{ .k = "eating out", .v = "essen gehen" },
    .{ .k = "transportation", .v = "transport" },
    .{ .k = "housing", .v = "wohnen" },
    .{ .k = "rent", .v = "wohnen" },
    .{ .k = "utilities", .v = "nebenkosten" },
    .{ .k = "bills", .v = "nebenkosten" },
    .{ .k = "entertainment", .v = "unterhaltung" },
    .{ .k = "health", .v = "gesundheit" },
    .{ .k = "healthcare", .v = "gesundheit" },
    .{ .k = "pharmacy", .v = "gesundheit" },
    .{ .k = "insurance", .v = "versicherung" },
    .{ .k = "income", .v = "einkommen" },
    .{ .k = "salary", .v = "einkommen" },
    .{ .k = "gehalt", .v = "einkommen" },
    .{ .k = "transfer", .v = "umbuchung" },
    .{ .k = "transfers", .v = "umbuchung" },
    .{ .k = "cash", .v = "bargeld" },
    .{ .k = "subscriptions", .v = "abonnements" },
    .{ .k = "abos", .v = "abonnements" },
    .{ .k = "subs", .v = "abonnements" },
    .{ .k = "travel", .v = "reisen" },
    .{ .k = "education", .v = "bildung" },
    .{ .k = "other", .v = "sonstiges" },
    .{ .k = "misc", .v = "sonstiges" },
};

/// Resolve an English/German/alias category name to its libwimg id by reading
/// `wimg_get_categories`. Case-insensitive exact → alias → substring match.
fn resolveCategoryId(gpa: std.mem.Allocator, input: []const u8) !?u8 {
    const cats_json = (try dupResult(gpa, wimg_get_categories())) orelse return null;
    defer gpa.free(cats_json);
    const parsed = std.json.parseFromSlice(std.json.Value, gpa, cats_json, .{}) catch return null;
    defer parsed.deinit();
    if (parsed.value != .array) return null;

    var buf: [64]u8 = undefined;
    const target = std.ascii.lowerString(&buf, std.mem.trim(u8, input, " \t"));

    // Resolve through alias table first (target may become a German canonical).
    var canonical: []const u8 = target;
    for (CATEGORY_ALIASES) |a| {
        if (std.mem.eql(u8, a.k, target)) {
            canonical = a.v;
            break;
        }
    }

    // exact match on canonical
    if (matchCategory(gpa, parsed.value.array.items, canonical, true)) |id| return id;
    // substring fallback on the original input
    if (matchCategory(gpa, parsed.value.array.items, target, false)) |id| return id;
    return null;
}

fn matchCategory(gpa: std.mem.Allocator, cats: []std.json.Value, needle: []const u8, exact: bool) ?u8 {
    for (cats) |cat| {
        if (cat != .object) continue;
        const name = strField(cat.object, "name") orelse continue;
        const id = intField(cat.object, "id") orelse continue;
        var buf: [64]u8 = undefined;
        if (name.len > buf.len) continue;
        const lname = std.ascii.lowerString(buf[0..name.len], name);
        const hit = if (exact)
            std.mem.eql(u8, lname, needle)
        else
            (std.mem.indexOf(u8, lname, needle) != null or std.mem.indexOf(u8, needle, lname) != null);
        if (hit) {
            _ = gpa;
            return std.math.cast(u8, id) orelse continue;
        }
    }
    return null;
}

// --- response builders ---

fn result(gpa: std.mem.Allocator, id_json: ?[]u8, result_json: []const u8) ![]u8 {
    const id = id_json orelse "null";
    return std.fmt.allocPrint(gpa, "{{\"jsonrpc\":\"2.0\",\"id\":{s},\"result\":{s}}}", .{ id, result_json });
}

/// 2026-07-28 result: `resultType` and the server's identity in `_meta` are
/// spliced into `result_json`, which must be a non-empty object.
fn modernResult(gpa: std.mem.Allocator, id_json: ?[]const u8, result_json: []const u8) ![]u8 {
    const id = id_json orelse "null";
    return std.fmt.allocPrint(gpa, "{{\"jsonrpc\":\"2.0\",\"id\":{s},\"result\":{{\"resultType\":\"complete\",\"_meta\":{{\"io.modelcontextprotocol/serverInfo\":{s}}},{s}}}", .{ id, SERVER_INFO_JSON, result_json[1..] });
}

fn modernError(gpa: std.mem.Allocator, id_json: ?[]u8, status: std.http.Status, code: i32, message: []const u8, data: ?[]const u8) !RpcResult {
    const id = id_json orelse "null";
    const body = if (data) |d|
        try std.fmt.allocPrint(gpa, "{{\"jsonrpc\":\"2.0\",\"id\":{s},\"error\":{{\"code\":{d},\"message\":\"{s}\",\"data\":{s}}}}}", .{ id, code, message, d })
    else
        try std.fmt.allocPrint(gpa, "{{\"jsonrpc\":\"2.0\",\"id\":{s},\"error\":{{\"code\":{d},\"message\":\"{s}\"}}}}", .{ id, code, message });
    return .{ .body = body, .status = status, .session = false };
}

fn errorResponse(gpa: std.mem.Allocator, id_json: ?[]u8, code: i32, message: []const u8) !RpcResult {
    const id = id_json orelse "null";
    const body = try std.fmt.allocPrint(gpa, "{{\"jsonrpc\":\"2.0\",\"id\":{s},\"error\":{{\"code\":{d},\"message\":\"{s}\"}}}}", .{ id, code, message });
    return .{ .body = body };
}

/// MCP `tools/call` success: `{content:[{type:"text",text:<payload>}]}`.
fn toolText(gpa: std.mem.Allocator, id_json: ?[]u8, payload: []const u8) !RpcResult {
    var content: std.ArrayList(u8) = .empty;
    defer content.deinit(gpa);
    try content.appendSlice(gpa, "{\"content\":[{\"type\":\"text\",\"text\":");
    try appendJsonString(gpa, &content, payload);
    try content.appendSlice(gpa, "}]}");
    return .{ .body = try result(gpa, id_json, content.items) };
}

/// MCP tool failure: result with `isError:true`.
fn toolError(gpa: std.mem.Allocator, id_json: ?[]u8, message: []const u8) !RpcResult {
    var content: std.ArrayList(u8) = .empty;
    defer content.deinit(gpa);
    try content.appendSlice(gpa, "{\"content\":[{\"type\":\"text\",\"text\":");
    try appendJsonString(gpa, &content, message);
    try content.appendSlice(gpa, "}],\"isError\":true}");
    return .{ .body = try result(gpa, id_json, content.items) };
}

// --- small helpers ---

fn strField(o: std.json.ObjectMap, name: []const u8) ?[]const u8 {
    return switch (o.get(name) orelse return null) {
        .string => |s| s,
        else => null,
    };
}

fn intField(o: std.json.ObjectMap, name: []const u8) ?i64 {
    return switch (o.get(name) orelse return null) {
        .integer => |i| i,
        .float => |f| @intFromFloat(f),
        .number_string => |s| std.fmt.parseInt(i64, s, 10) catch null,
        else => null,
    };
}

fn appendInt(gpa: std.mem.Allocator, out: *std.ArrayList(u8), v: i64) !void {
    var buf: [24]u8 = undefined;
    try out.appendSlice(gpa, std.fmt.bufPrint(&buf, "{d}", .{v}) catch unreachable);
}

fn appendJsonString(gpa: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) !void {
    try out.append(gpa, '"');
    for (s) |ch| switch (ch) {
        '"' => try out.appendSlice(gpa, "\\\""),
        '\\' => try out.appendSlice(gpa, "\\\\"),
        '\n' => try out.appendSlice(gpa, "\\n"),
        '\r' => try out.appendSlice(gpa, "\\r"),
        '\t' => try out.appendSlice(gpa, "\\t"),
        0...8, 11, 12, 14...31 => {
            var esc: [6]u8 = undefined;
            try out.appendSlice(gpa, std.fmt.bufPrint(&esc, "\\u{x:0>4}", .{ch}) catch unreachable);
        },
        else => try out.append(gpa, ch),
    };
    try out.append(gpa, '"');
}

/// True for `SELECT ...` / `WITH ...` (after trimming line comments).
fn isReadOnlySql(sql: []const u8) bool {
    const t = std.mem.trim(u8, sql, " \t\r\n");
    return std.ascii.startsWithIgnoreCase(t, "select") or std.ascii.startsWithIgnoreCase(t, "with");
}

const TOOLS_LIST =
    \\{"tools":[
    \\{"name":"query","description":"Run a read-only SQL query (SELECT/WITH only) against the wimg SQLite. Tables: transactions(id,date,description,amount /*cents,signed*/,currency,category /*int*/,account,raw,excluded,updated_at), accounts(id,name,bank,color,balance_cents,balance_date,updated_at), rules(pattern,category,priority,updated_at), snapshots(id,date,net_worth,income,expenses,tx_count,breakdown,updated_at), meta(key,value). Category IDs: 0=Unkategorisiert,1=Lebensmittel,2=Essen gehen,3=Transport,4=Wohnen,5=Nebenkosten,6=Unterhaltung,7=Shopping,8=Gesundheit,9=Versicherung,10=Einkommen,11=Umbuchung,12=Bargeld,13=Abonnements,14=Reisen,15=Bildung,255=Sonstiges. Amounts are integer cents.","inputSchema":{"type":"object","properties":{"sql":{"type":"string","description":"SQL SELECT or WITH statement."}},"required":["sql"]}},
    \\{"name":"set_category","description":"Set the category of one transaction by id. The only write. Category accepts German canonical, English, or alias (e.g. Lebensmittel/Groceries/Food). Also auto-learns a rule for the merchant.","inputSchema":{"type":"object","properties":{"transaction_id":{"type":"string"},"category":{"type":"string"}},"required":["transaction_id","category"]}}
    \\]}
;

test "stripPii scrubs IBAN, card, BIC and reference fields" {
    const gpa = std.testing.allocator;
    const cases = [_]struct { in: []const u8, want: []const u8 }{
        .{ .in = "REWE DE89 3704 0044 0532 0130 00 DANKE", .want = "REWE *** DANKE" },
        .{ .in = "Karte 1234 5678 9012 3456  end", .want = "Karte *** end" },
        .{ .in = "EREF+ABC123XYZ Zahlung", .want = "EREF+*** Zahlung" },
        .{ .in = "BIC+COBADEFFXXX ueberweisung", .want = "BIC+*** ueberweisung" },
        .{ .in = "ABWA+John Doe+more", .want = "ABWA+***+more" },
        .{ .in = "SPOTIFY AB", .want = "SPOTIFY AB" }, // nothing to strip
    };
    for (cases) |c| {
        const got = try stripPii(gpa, c.in);
        defer gpa.free(got);
        try std.testing.expectEqualStrings(c.want, got);
    }
}

fn modernBody(comptime method: []const u8, comptime extra_params: []const u8) []const u8 {
    return "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"" ++ method ++ "\",\"params\":{" ++ extra_params ++
        "\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":\"" ++ MODERN_VERSION ++ "\"}}}";
}

test "modern server/discover and tools/list carry resultType, serverInfo and cache hints" {
    const gpa = std.testing.allocator;
    // Neither method touches the store.
    const discover = try handleRpc(gpa, undefined, "k", modernBody("server/discover", ""), .{ .protocol_version = MODERN_VERSION, .method = "server/discover" });
    defer gpa.free(discover.body);
    try std.testing.expect(!discover.session);
    try std.testing.expectEqual(std.http.Status.ok, discover.status);
    for ([_][]const u8{ "\"id\":7", "\"resultType\":\"complete\"", "\"io.modelcontextprotocol/serverInfo\":{\"name\":\"wimg\"", "\"supportedVersions\":[\"2026-07-28\"", "\"ttlMs\":3600000", "\"cacheScope\":\"public\"" }) |want|
        try std.testing.expect(std.mem.indexOf(u8, discover.body, want) != null);

    const list = try handleRpc(gpa, undefined, "k", modernBody("tools/list", ""), .{ .protocol_version = MODERN_VERSION, .method = "tools/list" });
    defer gpa.free(list.body);
    const parsed = try std.json.parseFromSlice(std.json.Value, gpa, list.body, .{});
    defer parsed.deinit();
    const res = parsed.value.object.get("result").?.object;
    try std.testing.expectEqual(@as(usize, 2), res.get("tools").?.array.items.len);
    try std.testing.expectEqualStrings("public", res.get("cacheScope").?.string);
}

test "modern requests: version, header and method errors" {
    const gpa = std.testing.allocator;
    const Case = struct { body: []const u8, headers: Headers, status: std.http.Status, code: []const u8 };
    const cases = [_]Case{
        // Unknown version → 400 / -32022 listing what we support.
        .{ .body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\",\"params\":{\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":\"2099-01-01\"}}}", .headers = .{ .protocol_version = "2099-01-01", .method = "tools/list" }, .status = .bad_request, .code = "-32022" },
        // Missing / mismatched mirrored headers → -32020.
        .{ .body = modernBody("tools/list", ""), .headers = .{}, .status = .bad_request, .code = "-32020" },
        .{ .body = modernBody("tools/list", ""), .headers = .{ .protocol_version = MODERN_VERSION, .method = "tools/call" }, .status = .bad_request, .code = "-32020" },
        .{ .body = modernBody("tools/call", "\"name\":\"query\","), .headers = .{ .protocol_version = MODERN_VERSION, .method = "tools/call", .name = "set_category" }, .status = .bad_request, .code = "-32020" },
        .{ .body = modernBody("tools/call", "\"name\":\"query\","), .headers = .{ .protocol_version = MODERN_VERSION, .method = "tools/call", .name = "=?base64?!!!?=" }, .status = .bad_request, .code = "-32020" },
        // initialize doesn't exist in 2026-07-28 → 404 / -32601.
        .{ .body = modernBody("initialize", ""), .headers = .{ .protocol_version = MODERN_VERSION, .method = "initialize" }, .status = .not_found, .code = "-32601" },
    };
    for (cases) |c| {
        const r = try handleRpc(gpa, undefined, "k", c.body, c.headers);
        defer gpa.free(r.body);
        try std.testing.expectEqual(c.status, r.status);
        try std.testing.expect(!r.session);
        try std.testing.expect(std.mem.indexOf(u8, r.body, c.code) != null);
    }
}

test "legacy initialize keeps the session flow" {
    const gpa = std.testing.allocator;
    const r = try handleRpc(gpa, undefined, "k", "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}", .{});
    defer gpa.free(r.body);
    try std.testing.expect(r.session);
    try std.testing.expect(std.mem.indexOf(u8, r.body, "\"protocolVersion\":\"2025-03-26\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, r.body, "resultType") == null);
}

test "decodeHeaderValue: plain and base64 sentinel" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("query", decodeHeaderValue("query", &buf).?);
    try std.testing.expectEqualStrings("set_category", decodeHeaderValue("=?base64?c2V0X2NhdGVnb3J5?=", &buf).?);
    try std.testing.expect(decodeHeaderValue("=?base64?!!!?=", &buf) == null);
}

test "modernize rewraps a tool result and passes errors through" {
    const gpa = std.testing.allocator;
    const ok = try modernize(gpa, .{ .body = try gpa.dupe(u8, "{\"jsonrpc\":\"2.0\",\"id\":\"a\\\"b\",\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]}}") });
    defer gpa.free(ok.body);
    try std.testing.expect(!ok.session);
    const parsed = try std.json.parseFromSlice(std.json.Value, gpa, ok.body, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("a\"b", parsed.value.object.get("id").?.string);
    const res = parsed.value.object.get("result").?.object;
    try std.testing.expectEqualStrings("complete", res.get("resultType").?.string);
    try std.testing.expectEqualStrings("hi", res.get("content").?.array.items[0].object.get("text").?.string);

    const err_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32602,\"message\":\"Unknown tool\"}}";
    const err = try modernize(gpa, .{ .body = try gpa.dupe(u8, err_body) });
    defer gpa.free(err.body);
    try std.testing.expectEqualStrings(err_body, err.body);
}

test "isReadOnlySql" {
    try std.testing.expect(isReadOnlySql("SELECT * FROM transactions"));
    try std.testing.expect(isReadOnlySql("  with x as (select 1) select * from x"));
    try std.testing.expect(!isReadOnlySql("DELETE FROM transactions"));
    try std.testing.expect(!isReadOnlySql("UPDATE transactions SET category=1"));
}
