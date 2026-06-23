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
    /// JSON-RPC response body. Empty slice → it was a notification (caller
    /// replies 202 with no body).
    body: []u8,
    /// `{"type":"changes","rows":[...]}` to broadcast to this key's WebSocket
    /// listeners, or null when the request made no writes.
    broadcast: ?[]u8 = null,
};

const PROTOCOL_VERSION = "2025-03-26";

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
pub fn handleRpc(gpa: std.mem.Allocator, store: *Store, key: []const u8, body: []const u8) !RpcResult {
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

    if (std.mem.eql(u8, method, "initialize")) {
        return .{ .body = try result(gpa, id_json, "{\"protocolVersion\":\"" ++ PROTOCOL_VERSION ++
            "\",\"capabilities\":{\"tools\":{}},\"serverInfo\":{\"name\":\"wimg\",\"version\":\"0.3.0\"}}") };
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
        return handleToolCall(gpa, store, key, id_json, obj.get("params"));
    }

    return errorResponse(gpa, id_json, -32601, "Method not found");
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
    // TODO(phase-2): port stripPII() over description-like columns before return.
    return toolText(gpa, id_json, res);
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

test "isReadOnlySql" {
    try std.testing.expect(isReadOnlySql("SELECT * FROM transactions"));
    try std.testing.expect(isReadOnlySql("  with x as (select 1) select * from x"));
    try std.testing.expect(!isReadOnlySql("DELETE FROM transactions"));
    try std.testing.expect(!isReadOnlySql("UPDATE transactions SET category=1"));
}
