const std = @import("std");
const dbg = @import("dbg.zig");
const builtin = @import("builtin");
const config = @import("config");
const types = @import("types.zig");
const db_mod = @import("db.zig");
const parser = @import("parser.zig");
const categories = @import("categories.zig");
const summary = @import("summary.zig");
const crypto = @import("crypto.zig");
const recurring = @import("recurring.zig");

const Db = db_mod.Db;
const Transaction = types.Transaction;
const ImportResult = types.ImportResult;

const is_wasm = builtin.cpu.arch == .wasm32;

// FinTS modules — native only (WASM can't do HTTPS)
const fints_mod = if (!is_wasm) @import("fints.zig") else struct {};
const fints_http_mod = if (!is_wasm) @import("fints_http.zig") else struct {};
const mt940_mod = if (!is_wasm) @import("mt940.zig") else struct {};
const camt_mod = if (!is_wasm) @import("camt.zig") else struct {};
const banks_mod = if (!is_wasm) @import("banks.zig") else struct {};

// --- JS interop: imported logging function (WASM only) ---
extern fn js_console_log(ptr: [*]const u8, len: u32) void;

// --- Error reporting ---
var error_buf: [512]u8 = undefined;
var error_len: u32 = 0;

fn setError(comptime fmt: []const u8, args: anytype) void {
    const slice = std.fmt.bufPrint(&error_buf, fmt, args) catch {
        const msg = "error: format failed";
        @memcpy(error_buf[0..msg.len], msg);
        error_len = msg.len;
        return;
    };
    error_len = @intCast(slice.len);
    if (is_wasm) {
        js_console_log(&error_buf, error_len);
    }
}

fn log(comptime fmt: []const u8, args: anytype) void {
    var buf: [512]u8 = undefined;
    const slice = std.fmt.bufPrint(&buf, fmt, args) catch return;
    if (is_wasm) {
        js_console_log(&buf, @intCast(slice.len));
    }
}

/// Log a SQLite error with the actual error message from sqlite3_errmsg.
/// Sets the error buffer AND logs to console so failures are always visible.
fn sqliteError(comptime context: []const u8, handle: anytype) void {
    const sqlite_c = @import("sqlite_c.zig");
    const h: *sqlite_c.sqlite3 = switch (@TypeOf(handle)) {
        *sqlite_c.sqlite3 => handle,
        *db_mod.Db => handle.handle,
        else => {
            setError(context, .{});
            return;
        },
    };
    if (sqlite_c.sqlite3_errmsg(h)) |msg| {
        setError(context ++ ": {s}", .{msg});
    } else {
        setError(context, .{});
    }
}

// --- WASM memory management ---
// compact=true (MCP/CF Workers): 16 MB. normal (web browser): 64 MB.
const wasm_buf_size = if (config.compact) 16 * 1024 * 1024 else 64 * 1024 * 1024;
var wasm_buf: [wasm_buf_size]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&wasm_buf);

// Global database instance
var global_db: ?Db = null;

// --- C ABI Exports ---

/// Get the last error message. Returns pointer to error string.
/// First 4 bytes = u32 length, then the string data.
export fn wimg_get_error() ?[*]const u8 {
    if (error_len == 0) return null;

    const out = fba.allocator().alloc(u8, error_len + 4) catch return null;
    const len_bytes: [4]u8 = @bitCast(error_len);
    out[0] = len_bytes[0];
    out[1] = len_bytes[1];
    out[2] = len_bytes[2];
    out[3] = len_bytes[3];
    @memcpy(out[4 .. 4 + error_len], error_buf[0..error_len]);
    return out.ptr;
}

/// Build identifier for verifying the correct WASM is loaded.
const WASM_BUILD_ID = "v7-bpe-scores";

/// Get the build ID string (length-prefixed).
export fn wimg_build_id() ?[*]const u8 {
    return makeLengthPrefixed(WASM_BUILD_ID);
}

/// Initialize the database. Returns 0 on success, -1 on error.
export fn wimg_init(path: [*:0]const u8) i32 {
    log("wimg_init: build=" ++ WASM_BUILD_ID, .{});

    if (global_db != null) {
        global_db.?.close();
    }

    global_db = Db.init(path) catch |err| {
        setError("wimg_init: db.init failed: {s}", .{@errorName(err)});
        return -1;
    };

    log("wimg_init: database initialized successfully", .{});
    return 0;
}

/// Import a CSV file. Auto-detects format. Returns a pointer to a JSON string
/// with the import result, or null on error.
export fn wimg_import_csv(data: [*]const u8, len: u32) ?[*]const u8 {
    log("wimg_import_csv: len={d}", .{len});

    var database = global_db orelse {
        setError("wimg_import_csv: database not initialized", .{});
        return null;
    };

    const csv_data = data[0..len];

    // Batch-parse CSV into transactions (10K buffer reused per batch)
    const max_txns = 10000;
    const txn_buf = fba.allocator().alloc(Transaction, max_txns) catch {
        setError("wimg_import_csv: failed to allocate transaction buffer", .{});
        return null;
    };
    defer fba.allocator().free(txn_buf);

    var cursor = parser.ParseCursor{};
    var result = ImportResult{
        .total_rows = 0,
        .imported = 0,
        .skipped_duplicates = 0,
        .errors = 0,
    };
    var categorized: u32 = 0;
    var account_created = false;

    while (cursor.byte_offset < csv_data.len) {
        var batch_result: ImportResult = undefined;
        parser.parseCsvBatch(csv_data, &cursor, txn_buf, &batch_result);

        if (batch_result.imported == 0 and batch_result.total_rows == 0) break;

        // Insert batch into DB
        var batch_imported: u32 = 0;
        var batch_duplicates: u32 = 0;
        var batch_insert_errors: u32 = 0;

        for (txn_buf[0..batch_result.imported]) |*txn| {
            const inserted = database.insertTransaction(txn) catch {
                batch_insert_errors += 1;
                if (result.errors + batch_insert_errors <= 3) {
                    sqliteError("wimg_import_csv: insert failed", database.handle);
                }
                continue;
            };
            if (inserted) {
                batch_imported += 1;
            } else {
                batch_duplicates += 1;
            }
        }

        // Auto-categorize this batch
        for (txn_buf[0..batch_result.imported]) |*txn| {
            if (txn.category != .uncategorized) continue;
            const matched = categories.matchRules(database.handle, txn.descriptionSlice());
            if (matched != .uncategorized) {
                database.setCategoryById(&txn.id, matched) catch continue;
                categorized += 1;
            }
        }

        // Accumulate totals
        result.total_rows += batch_result.total_rows;
        result.imported += batch_imported;
        result.skipped_duplicates += batch_duplicates;
        result.errors += batch_result.errors + batch_insert_errors;
    }

    const format = cursor.format;

    // Auto-create account entry for this bank format (once)
    if (!account_created) {
        const account_info = accountInfoForFormat(format);
        database.ensureAccount(account_info.id, account_info.name, account_info.color) catch {};
        account_created = true;
    }

    log("wimg_import_csv: format={s}, {d} imported, {d} duplicates, {d} errors, {d} auto-categorized", .{
        format.name(), result.imported, result.skipped_duplicates, result.errors, categorized,
    });

    // Serialize result to JSON (with format and categorized count)
    var json_buf: [512]u8 = undefined;
    const json_len = formatImportResultEx(&json_buf, &result, format, categorized) orelse {
        setError("wimg_import_csv: failed to format result JSON", .{});
        return null;
    };

    return makeLengthPrefixed(json_buf[0..json_len]);
}

/// Parse CSV without importing into the database (preview only).
/// Returns a length-prefixed JSON string with format, total_rows, and transactions array.
export fn wimg_parse_csv(data: [*]const u8, len: u32) ?[*]const u8 {
    log("wimg_parse_csv: len={d}", .{len});

    const csv_data = data[0..len];

    const max_txns = 2000;
    const txn_buf = fba.allocator().alloc(Transaction, max_txns) catch {
        setError("wimg_parse_csv: failed to allocate transaction buffer", .{});
        return null;
    };
    defer fba.allocator().free(txn_buf);

    var result: ImportResult = undefined;
    const format = parser.parseCsv(csv_data, txn_buf, &result);

    log("wimg_parse_csv: format={s}, parsed {d} rows, {d} transactions", .{
        format.name(), result.total_rows, result.imported,
    });

    // Apply rule-based categorization (preview includes predicted categories)
    if (global_db) |database| {
        for (txn_buf[0..result.imported]) |*txn| {
            if (txn.category != .uncategorized) continue;
            const matched = categories.matchRules(database.handle, txn.descriptionSlice());
            if (matched != .uncategorized) {
                txn.category = matched;
            }
        }
    }

    // Serialize to JSON using manual building (same pattern as db.zig)
    const buf_size: usize = 1024 * 1024; // 1 MB
    const buf = fba.allocator().alloc(u8, buf_size + 4) catch {
        setError("wimg_parse_csv: failed to allocate output buffer", .{});
        return null;
    };

    var pos: usize = 4; // skip length prefix
    const out = buf[4..];

    // Header: {"format":"...","total_rows":N,"transactions":[
    const hdr = std.fmt.bufPrint(out, "{{\"format\":\"{s}\",\"total_rows\":{d},\"transactions\":[", .{
        format.name(), result.total_rows,
    }) catch {
        setError("wimg_parse_csv: failed to format header", .{});
        fba.allocator().free(buf);
        return null;
    };
    pos += hdr.len;

    // Write each transaction using db.zig helpers
    for (txn_buf[0..result.imported], 0..) |*txn, i| {
        const s = buf[pos .. buf_size + 4];
        const written = formatPreviewTransaction(
            s,
            i == 0,
            &txn.id,
            txn.date.year,
            txn.date.month,
            txn.date.day,
            txn.descriptionSlice(),
            txn.amount_cents,
            &txn.currency,
            @backingInt(txn.category),
            txn.accountSlice(),
        ) orelse {
            setError("wimg_parse_csv: buffer overflow at transaction {d}", .{i});
            fba.allocator().free(buf);
            return null;
        };
        pos += written;
    }

    // Close: ]}
    if (pos + 2 > buf_size + 4) {
        fba.allocator().free(buf);
        return null;
    }
    buf[pos] = ']';
    buf[pos + 1] = '}';
    pos += 2;

    const json_len = pos - 4;
    const len_bytes: [4]u8 = @bitCast(@as(u32, @intCast(json_len)));
    buf[0] = len_bytes[0];
    buf[1] = len_bytes[1];
    buf[2] = len_bytes[2];
    buf[3] = len_bytes[3];

    return buf.ptr;
}

/// Format a single transaction as JSON for the preview response.
/// Reuses db.zig helpers for amount formatting and JSON escaping.
fn formatPreviewTransaction(
    buf: []u8,
    first: bool,
    id: *const [32]u8,
    year: u16,
    month: u8,
    day: u8,
    desc: []const u8,
    amount_cents: i64,
    currency: *const [3]u8,
    category: u8,
    account: []const u8,
) ?usize {
    var pos: usize = 0;

    if (!first) {
        if (pos >= buf.len) return null;
        buf[pos] = ',';
        pos += 1;
    }

    // {"id":"
    const p1 = "{\"id\":\"";
    if (pos + p1.len + 32 > buf.len) return null;
    @memcpy(buf[pos .. pos + p1.len], p1);
    pos += p1.len;
    @memcpy(buf[pos .. pos + 32], id);
    pos += 32;

    // ","date":"YYYY-MM-DD"
    const p2 = "\",\"date\":\"";
    if (pos + p2.len + 10 > buf.len) return null;
    @memcpy(buf[pos .. pos + p2.len], p2);
    pos += p2.len;
    // Manual date formatting
    buf[pos] = '0' + @as(u8, @intCast(year / 1000));
    buf[pos + 1] = '0' + @as(u8, @intCast((year / 100) % 10));
    buf[pos + 2] = '0' + @as(u8, @intCast((year / 10) % 10));
    buf[pos + 3] = '0' + @as(u8, @intCast(year % 10));
    buf[pos + 4] = '-';
    buf[pos + 5] = '0' + month / 10;
    buf[pos + 6] = '0' + month % 10;
    buf[pos + 7] = '-';
    buf[pos + 8] = '0' + day / 10;
    buf[pos + 9] = '0' + day % 10;
    pos += 10;

    // ","description":"
    const p3 = "\",\"description\":\"";
    if (pos + p3.len > buf.len) return null;
    @memcpy(buf[pos .. pos + p3.len], p3);
    pos += p3.len;
    pos += db_mod.jsonEscapeString(buf[pos..], desc) orelse return null;

    // ","amount":
    const p4 = "\",\"amount\":";
    if (pos + p4.len > buf.len) return null;
    @memcpy(buf[pos .. pos + p4.len], p4);
    pos += p4.len;
    pos += db_mod.formatAmount(buf[pos..], amount_cents) orelse return null;

    // ,"currency":"EUR"
    const p5 = ",\"currency\":\"";
    if (pos + p5.len + 3 > buf.len) return null;
    @memcpy(buf[pos .. pos + p5.len], p5);
    pos += p5.len;
    @memcpy(buf[pos .. pos + 3], currency);
    pos += 3;

    // ","category":N
    const p6 = "\",\"category\":";
    if (pos + p6.len > buf.len) return null;
    @memcpy(buf[pos .. pos + p6.len], p6);
    pos += p6.len;
    pos += db_mod.formatInt(buf[pos..], category) orelse return null;

    // ,"account":"..."
    const p7 = ",\"account\":\"";
    if (pos + p7.len > buf.len) return null;
    @memcpy(buf[pos .. pos + p7.len], p7);
    pos += p7.len;
    pos += db_mod.jsonEscapeString(buf[pos..], account) orelse return null;

    const p8 = "\"}";
    if (pos + p8.len > buf.len) return null;
    @memcpy(buf[pos .. pos + p8.len], p8);
    pos += p8.len;

    return pos;
}

/// Re-run auto-categorization on all uncategorized transactions.
/// Returns number of newly categorized transactions, or -1 on error.
export fn wimg_auto_categorize() i32 {
    var database = global_db orelse {
        setError("wimg_auto_categorize: database not initialized", .{});
        return -1;
    };

    const sql =
        \\SELECT id, description FROM transactions WHERE category = 0;
    ;

    var stmt: ?*@import("sqlite_c.zig").sqlite3_stmt = null;
    const c = @import("sqlite_c.zig");
    const rc = c.sqlite3_prepare_v2(database.handle, sql, -1, &stmt, null);
    if (rc != c.SQLITE_OK or stmt == null) {
        sqliteError("wimg_auto_categorize: prepare failed", database.handle);
        return -1;
    }
    defer _ = c.sqlite3_finalize(stmt.?);

    const s = stmt.?;
    var count: i32 = 0;

    while (c.sqlite3_step(s) == c.SQLITE_ROW) {
        const id_ptr = c.sqlite3_column_text(s, 0) orelse continue;
        const desc_ptr = c.sqlite3_column_text(s, 1) orelse continue;
        const desc_len: usize = @intCast(c.sqlite3_column_bytes(s, 1));

        const matched = categories.matchRules(database.handle, desc_ptr[0..desc_len]);
        if (matched != .uncategorized) {
            const id_slice: *const [32]u8 = @ptrCast(id_ptr);
            database.setCategoryById(id_slice, matched) catch continue;
            count += 1;
        }
    }

    return count;
}

/// Get all transactions as a JSON array.
export fn wimg_get_transactions() ?[*]const u8 {
    var database = global_db orelse {
        setError("wimg_get_transactions: database not initialized", .{});
        return null;
    };

    const buf_size: usize = 8 * 1024 * 1024; // 8 MB
    const buf = fba.allocator().alloc(u8, buf_size + 4) catch {
        setError("wimg_get_transactions: failed to allocate buffer", .{});
        return null;
    };

    const json_len = database.getTransactionsJson(buf.ptr + 4, buf_size) catch |err| {
        setError("wimg_get_transactions: query failed: {s}", .{@errorName(err)});
        fba.allocator().free(buf);
        return null;
    } orelse {
        setError("wimg_get_transactions: buffer too small (4MB exceeded)", .{});
        fba.allocator().free(buf);
        return null;
    };

    const len_bytes: [4]u8 = @bitCast(@as(u32, @intCast(json_len)));
    buf[0] = len_bytes[0];
    buf[1] = len_bytes[1];
    buf[2] = len_bytes[2];
    buf[3] = len_bytes[3];

    return buf.ptr;
}

/// Set the category for a transaction.
export fn wimg_set_category(id: [*]const u8, id_len: u32, category: u8) i32 {
    var database = global_db orelse {
        setError("wimg_set_category: database not initialized", .{});
        return -1;
    };
    database.setCategory(id, id_len, category) catch |err| {
        setError("wimg_set_category: failed: {s}", .{@errorName(err)});
        return -1;
    };
    return 0;
}

/// Set the excluded flag for a transaction.
export fn wimg_set_excluded(id: [*]const u8, id_len: u32, excluded: u8) i32 {
    var database = global_db orelse {
        setError("wimg_set_excluded: database not initialized", .{});
        return -1;
    };
    database.setExcluded(id, id_len, excluded) catch |err| {
        setError("wimg_set_excluded: failed: {s}", .{@errorName(err)});
        return -1;
    };
    return 0;
}

/// Get monthly summary as JSON.
/// year and month are passed as integers.
export fn wimg_get_summary(year: u32, month: u32) ?[*]const u8 {
    const database = global_db orelse {
        setError("wimg_get_summary: database not initialized", .{});
        return null;
    };

    const buf_size: usize = 8 * 1024; // 8 KB should be plenty
    const buf = fba.allocator().alloc(u8, buf_size + 4) catch {
        setError("wimg_get_summary: failed to allocate buffer", .{});
        return null;
    };

    const json_len = summary.getSummaryJson(
        database.handle,
        @intCast(year),
        @intCast(month),
        buf.ptr + 4,
        buf_size,
    ) orelse {
        sqliteError("wimg_get_summary: failed", database.handle);
        fba.allocator().free(buf);
        return null;
    };

    const len_bytes: [4]u8 = @bitCast(@as(u32, @intCast(json_len)));
    buf[0] = len_bytes[0];
    buf[1] = len_bytes[1];
    buf[2] = len_bytes[2];
    buf[3] = len_bytes[3];

    return buf.ptr;
}

// --- Debts ---

/// Get all debts as JSON array.
export fn wimg_get_debts() ?[*]const u8 {
    var database = global_db orelse {
        setError("wimg_get_debts: database not initialized", .{});
        return null;
    };

    const buf_size: usize = 32 * 1024; // 32 KB
    const buf = fba.allocator().alloc(u8, buf_size + 4) catch {
        setError("wimg_get_debts: failed to allocate buffer", .{});
        return null;
    };

    const json_len = database.getDebtsJson(buf.ptr + 4, buf_size) catch |err| {
        setError("wimg_get_debts: query failed: {s}", .{@errorName(err)});
        fba.allocator().free(buf);
        return null;
    } orelse {
        setError("wimg_get_debts: buffer too small", .{});
        fba.allocator().free(buf);
        return null;
    };

    const len_bytes: [4]u8 = @bitCast(@as(u32, @intCast(json_len)));
    buf[0] = len_bytes[0];
    buf[1] = len_bytes[1];
    buf[2] = len_bytes[2];
    buf[3] = len_bytes[3];

    return buf.ptr;
}

/// Add a debt. JSON input: {"id":"...","name":"...","total":1234.56,"monthly":100.00}
export fn wimg_add_debt(data: [*]const u8, len: u32) i32 {
    var database = global_db orelse {
        setError("wimg_add_debt: database not initialized", .{});
        return -1;
    };

    // Simple JSON parsing: find id, name, total, monthly fields
    const json = data[0..len];

    const id = jsonExtractString(json, "\"id\"") orelse {
        setError("wimg_add_debt: missing id field", .{});
        return -1;
    };
    const name_val = jsonExtractString(json, "\"name\"") orelse {
        setError("wimg_add_debt: missing name field", .{});
        return -1;
    };
    const total = jsonExtractNumber(json, "\"total\"") orelse {
        setError("wimg_add_debt: missing total field", .{});
        return -1;
    };
    const monthly = jsonExtractNumber(json, "\"monthly\"") orelse 0;

    database.insertDebt(
        id.ptr,
        @intCast(id.len),
        name_val.ptr,
        @intCast(name_val.len),
        total,
        monthly,
    ) catch |err| {
        setError("wimg_add_debt: insert failed: {s}", .{@errorName(err)});
        return -1;
    };

    return 0;
}

/// Mark a debt as partially paid.
export fn wimg_mark_debt_paid(id: [*]const u8, id_len: u32, amount_cents: i64) i32 {
    var database = global_db orelse {
        setError("wimg_mark_debt_paid: database not initialized", .{});
        return -1;
    };

    database.markDebtPaid(id, id_len, amount_cents) catch |err| {
        setError("wimg_mark_debt_paid: failed: {s}", .{@errorName(err)});
        return -1;
    };

    return 0;
}

/// Delete a debt.
export fn wimg_delete_debt(id: [*]const u8, id_len: u32) i32 {
    var database = global_db orelse {
        setError("wimg_delete_debt: database not initialized", .{});
        return -1;
    };

    database.deleteDebt(id, id_len) catch |err| {
        setError("wimg_delete_debt: failed: {s}", .{@errorName(err)});
        return -1;
    };

    return 0;
}

// --- Savings Goals ---

export fn wimg_get_goals() ?[*]const u8 {
    var database = global_db orelse {
        setError("wimg_get_goals: database not initialized", .{});
        return null;
    };

    const buf_size: usize = 32 * 1024; // 32 KB
    const buf = fba.allocator().alloc(u8, buf_size + 4) catch {
        setError("wimg_get_goals: failed to allocate buffer", .{});
        return null;
    };

    const json_len = database.getGoalsJson(buf.ptr + 4, buf_size) catch |err| {
        setError("wimg_get_goals: query failed: {s}", .{@errorName(err)});
        fba.allocator().free(buf);
        return null;
    } orelse {
        setError("wimg_get_goals: buffer too small", .{});
        fba.allocator().free(buf);
        return null;
    };

    const len_bytes: [4]u8 = @bitCast(@as(u32, @intCast(json_len)));
    buf[0] = len_bytes[0];
    buf[1] = len_bytes[1];
    buf[2] = len_bytes[2];
    buf[3] = len_bytes[3];

    return buf.ptr;
}

/// Add a savings goal. JSON input: {"id":"...","name":"...","icon":"...","target":1234,"deadline":"2026-12-31"}
export fn wimg_add_goal(data: [*]const u8, len: u32) i32 {
    var database = global_db orelse {
        setError("wimg_add_goal: database not initialized", .{});
        return -1;
    };

    const json = data[0..len];

    const id = jsonExtractString(json, "\"id\"") orelse {
        setError("wimg_add_goal: missing id field", .{});
        return -1;
    };
    const name_val = jsonExtractString(json, "\"name\"") orelse {
        setError("wimg_add_goal: missing name field", .{});
        return -1;
    };
    const icon_val = jsonExtractString(json, "\"icon\"") orelse "🎯";
    const target = jsonExtractNumber(json, "\"target\"") orelse {
        setError("wimg_add_goal: missing target field", .{});
        return -1;
    };
    const deadline_val = jsonExtractString(json, "\"deadline\"");

    database.insertGoal(
        id.ptr,
        @intCast(id.len),
        name_val.ptr,
        @intCast(name_val.len),
        icon_val.ptr,
        @intCast(icon_val.len),
        target,
        if (deadline_val) |dl| dl.ptr else null,
        if (deadline_val) |dl| @intCast(dl.len) else 0,
    ) catch |err| {
        setError("wimg_add_goal: insert failed: {s}", .{@errorName(err)});
        return -1;
    };

    return 0;
}

/// Contribute to a savings goal.
export fn wimg_contribute_goal(id: [*]const u8, id_len: u32, amount_cents: i64) i32 {
    var database = global_db orelse {
        setError("wimg_contribute_goal: database not initialized", .{});
        return -1;
    };

    database.contributeGoal(id, id_len, amount_cents) catch |err| {
        setError("wimg_contribute_goal: failed: {s}", .{@errorName(err)});
        return -1;
    };

    return 0;
}

/// Delete a savings goal.
export fn wimg_delete_goal(id: [*]const u8, id_len: u32) i32 {
    var database = global_db orelse {
        setError("wimg_delete_goal: database not initialized", .{});
        return -1;
    };

    database.deleteGoal(id, id_len) catch |err| {
        setError("wimg_delete_goal: failed: {s}", .{@errorName(err)});
        return -1;
    };

    return 0;
}

/// Undo the last action. Returns pointer to length-prefixed JSON, or null if nothing to undo.
export fn wimg_undo() ?[*]const u8 {
    var database = global_db orelse {
        setError("wimg_undo: database not initialized", .{});
        return null;
    };

    const buf_size: usize = 1024;
    const buf = fba.allocator().alloc(u8, buf_size + 4) catch {
        setError("wimg_undo: failed to allocate buffer", .{});
        return null;
    };

    const json_len = database.undo(buf.ptr + 4, buf_size) catch |err| {
        setError("wimg_undo: failed: {s}", .{@errorName(err)});
        fba.allocator().free(buf);
        return null;
    } orelse {
        fba.allocator().free(buf);
        return null;
    };

    const len_bytes: [4]u8 = @bitCast(@as(u32, @intCast(json_len)));
    buf[0] = len_bytes[0];
    buf[1] = len_bytes[1];
    buf[2] = len_bytes[2];
    buf[3] = len_bytes[3];

    return buf.ptr;
}

/// Redo the last undone action. Returns pointer to length-prefixed JSON, or null if nothing to redo.
export fn wimg_redo() ?[*]const u8 {
    var database = global_db orelse {
        setError("wimg_redo: database not initialized", .{});
        return null;
    };

    const buf_size: usize = 1024;
    const buf = fba.allocator().alloc(u8, buf_size + 4) catch {
        setError("wimg_redo: failed to allocate buffer", .{});
        return null;
    };

    const json_len = database.redo(buf.ptr + 4, buf_size) catch |err| {
        setError("wimg_redo: failed: {s}", .{@errorName(err)});
        fba.allocator().free(buf);
        return null;
    } orelse {
        fba.allocator().free(buf);
        return null;
    };

    const len_bytes: [4]u8 = @bitCast(@as(u32, @intCast(json_len)));
    buf[0] = len_bytes[0];
    buf[1] = len_bytes[1];
    buf[2] = len_bytes[2];
    buf[3] = len_bytes[3];

    return buf.ptr;
}

// --- Sync ---

/// Get all rows changed since `since_ts` (unix ms). Returns length-prefixed JSON.
export fn wimg_get_changes(since_ts: i64) ?[*]const u8 {
    var database = global_db orelse {
        setError("wimg_get_changes: database not initialized", .{});
        return null;
    };

    const buf_size: usize = 8 * 1024 * 1024; // 8 MB
    const buf = fba.allocator().alloc(u8, buf_size + 4) catch {
        setError("wimg_get_changes: failed to allocate buffer", .{});
        return null;
    };

    const json_len = database.getChangesJson(since_ts, buf.ptr + 4, buf_size) catch |err| {
        setError("wimg_get_changes: query failed: {s}", .{@errorName(err)});
        fba.allocator().free(buf);
        return null;
    } orelse {
        setError("wimg_get_changes: buffer too small", .{});
        fba.allocator().free(buf);
        return null;
    };

    const len_bytes: [4]u8 = @bitCast(@as(u32, @intCast(json_len)));
    buf[0] = len_bytes[0];
    buf[1] = len_bytes[1];
    buf[2] = len_bytes[2];
    buf[3] = len_bytes[3];

    return buf.ptr;
}

/// Apply incoming sync changes (JSON). Returns count of applied rows, or -1 on error.
export fn wimg_apply_changes(data: [*]const u8, len: u32) i32 {
    var database = global_db orelse {
        setError("wimg_apply_changes: database not initialized", .{});
        return -1;
    };

    const result = database.applyChanges(data[0..len]) catch |err| {
        setError("wimg_apply_changes: failed: {s}", .{@errorName(err)});
        return -1;
    };

    return result;
}

// --- Accounts ---

/// Get all accounts as JSON array.
export fn wimg_get_accounts() ?[*]const u8 {
    var database = global_db orelse {
        setError("wimg_get_accounts: database not initialized", .{});
        return null;
    };

    const buf_size: usize = 8 * 1024;
    const buf = fba.allocator().alloc(u8, buf_size + 4) catch {
        setError("wimg_get_accounts: failed to allocate buffer", .{});
        return null;
    };

    const json_len = database.getAccountsJson(buf.ptr + 4, buf_size) catch |err| {
        setError("wimg_get_accounts: query failed: {s}", .{@errorName(err)});
        fba.allocator().free(buf);
        return null;
    } orelse {
        setError("wimg_get_accounts: buffer too small", .{});
        fba.allocator().free(buf);
        return null;
    };

    const len_bytes: [4]u8 = @bitCast(@as(u32, @intCast(json_len)));
    buf[0] = len_bytes[0];
    buf[1] = len_bytes[1];
    buf[2] = len_bytes[2];
    buf[3] = len_bytes[3];

    return buf.ptr;
}

/// Add an account. JSON input: {"id":"...","name":"...","color":"#..."}
export fn wimg_add_account(data: [*]const u8, len: u32) i32 {
    var database = global_db orelse {
        setError("wimg_add_account: database not initialized", .{});
        return -1;
    };

    const json = data[0..len];
    const id = jsonExtractString(json, "\"id\"") orelse {
        setError("wimg_add_account: missing id field", .{});
        return -1;
    };
    const name_val = jsonExtractString(json, "\"name\"") orelse {
        setError("wimg_add_account: missing name field", .{});
        return -1;
    };
    const color = jsonExtractString(json, "\"color\"") orelse "#4361ee";

    database.insertAccount(
        id.ptr,
        @intCast(id.len),
        name_val.ptr,
        @intCast(name_val.len),
        color.ptr,
        @intCast(color.len),
    ) catch |err| {
        setError("wimg_add_account: insert failed: {s}", .{@errorName(err)});
        return -1;
    };
    return 0;
}

/// Update an account. JSON input: {"id":"...","name":"...","color":"#..."}
export fn wimg_update_account(data: [*]const u8, len: u32) i32 {
    var database = global_db orelse {
        setError("wimg_update_account: database not initialized", .{});
        return -1;
    };

    const json = data[0..len];
    const id = jsonExtractString(json, "\"id\"") orelse {
        setError("wimg_update_account: missing id field", .{});
        return -1;
    };
    const name_val = jsonExtractString(json, "\"name\"") orelse {
        setError("wimg_update_account: missing name field", .{});
        return -1;
    };
    const color = jsonExtractString(json, "\"color\"") orelse "#4361ee";

    database.updateAccount(
        id.ptr,
        @intCast(id.len),
        name_val.ptr,
        @intCast(name_val.len),
        color.ptr,
        @intCast(color.len),
    ) catch |err| {
        setError("wimg_update_account: update failed: {s}", .{@errorName(err)});
        return -1;
    };
    return 0;
}

/// Delete an account by ID.
export fn wimg_delete_account(id: [*]const u8, id_len: u32) i32 {
    var database = global_db orelse {
        setError("wimg_delete_account: database not initialized", .{});
        return -1;
    };

    database.deleteAccount(id, id_len) catch |err| {
        setError("wimg_delete_account: failed: {s}", .{@errorName(err)});
        return -1;
    };
    return 0;
}

/// Get transactions filtered by account. Pass empty string / 0 len for all.
export fn wimg_get_transactions_filtered(acct: [*]const u8, acct_len: u32) ?[*]const u8 {
    var database = global_db orelse {
        setError("wimg_get_transactions_filtered: database not initialized", .{});
        return null;
    };

    const buf_size: usize = 8 * 1024 * 1024; // 8 MB
    const buf = fba.allocator().alloc(u8, buf_size + 4) catch {
        setError("wimg_get_transactions_filtered: failed to allocate buffer", .{});
        return null;
    };

    const json_len = database.getTransactionsJsonFiltered(buf.ptr + 4, buf_size, acct, acct_len) catch |err| {
        setError("wimg_get_transactions_filtered: query failed: {s}", .{@errorName(err)});
        fba.allocator().free(buf);
        return null;
    } orelse {
        setError("wimg_get_transactions_filtered: buffer too small (4MB exceeded)", .{});
        fba.allocator().free(buf);
        return null;
    };

    const len_bytes: [4]u8 = @bitCast(@as(u32, @intCast(json_len)));
    buf[0] = len_bytes[0];
    buf[1] = len_bytes[1];
    buf[2] = len_bytes[2];
    buf[3] = len_bytes[3];

    return buf.ptr;
}

/// Get summary filtered by account.
export fn wimg_get_summary_filtered(year: u32, month: u32, acct: [*]const u8, acct_len: u32) ?[*]const u8 {
    const database = global_db orelse {
        setError("wimg_get_summary_filtered: database not initialized", .{});
        return null;
    };

    const buf_size: usize = 8 * 1024;
    const buf = fba.allocator().alloc(u8, buf_size + 4) catch {
        setError("wimg_get_summary_filtered: failed to allocate buffer", .{});
        return null;
    };

    const json_len = summary.getSummaryJsonFiltered(
        database.handle,
        @intCast(year),
        @intCast(month),
        buf.ptr + 4,
        buf_size,
        acct,
        acct_len,
    ) orelse {
        sqliteError("wimg_get_summary_filtered: failed", database.handle);
        fba.allocator().free(buf);
        return null;
    };

    const len_bytes: [4]u8 = @bitCast(@as(u32, @intCast(json_len)));
    buf[0] = len_bytes[0];
    buf[1] = len_bytes[1];
    buf[2] = len_bytes[2];
    buf[3] = len_bytes[3];

    return buf.ptr;
}

// --- Recurring ---

/// Detect recurring payment patterns from transaction history.
/// Returns count of patterns detected, or -1 on error.
export fn wimg_detect_recurring() i32 {
    var database = global_db orelse {
        setError("wimg_detect_recurring: database not initialized", .{});
        return -1;
    };

    const count = recurring.detectRecurring(&database) catch |err| {
        setError("wimg_detect_recurring: failed: {s}", .{@errorName(err)});
        return -1;
    };

    return count;
}

/// Get all active recurring patterns as JSON array.
export fn wimg_get_recurring() ?[*]const u8 {
    var database = global_db orelse {
        setError("wimg_get_recurring: database not initialized", .{});
        return null;
    };

    const buf_size: usize = 32 * 1024; // 32 KB
    const buf = fba.allocator().alloc(u8, buf_size + 4) catch {
        setError("wimg_get_recurring: failed to allocate buffer", .{});
        return null;
    };

    const json_len = database.getRecurringJson(buf.ptr + 4, buf_size) catch |err| {
        setError("wimg_get_recurring: query failed: {s}", .{@errorName(err)});
        fba.allocator().free(buf);
        return null;
    } orelse {
        setError("wimg_get_recurring: buffer too small", .{});
        fba.allocator().free(buf);
        return null;
    };

    const len_bytes: [4]u8 = @bitCast(@as(u32, @intCast(json_len)));
    buf[0] = len_bytes[0];
    buf[1] = len_bytes[1];
    buf[2] = len_bytes[2];
    buf[3] = len_bytes[3];

    return buf.ptr;
}

/// Get all category metadata as a JSON array (static, no DB needed).
/// Returns length-prefixed JSON: [{"id":0,"name":"...","color":"#...","icon":"..."}, ...]
export fn wimg_get_categories() ?[*]const u8 {
    const Category = types.Category;
    const all_cats = [_]Category{
        .uncategorized, .groceries,     .dining,        .transport,
        .housing,       .utilities,     .entertainment, .shopping,
        .health,        .insurance,     .income,        .transfer,
        .cash,          .subscriptions, .travel,        .education,
        .other,
    };

    var buf: [4096]u8 = undefined;
    var pos: usize = 0;

    buf[pos] = '[';
    pos += 1;

    for (all_cats, 0..) |cat, i| {
        if (i > 0) {
            buf[pos] = ',';
            pos += 1;
        }

        const p1 = "{\"id\":";
        @memcpy(buf[pos .. pos + p1.len], p1);
        pos += p1.len;
        pos += db_mod.formatInt(buf[pos..], @as(u32, @backingInt(cat))) orelse return null;

        const p2 = ",\"name\":\"";
        @memcpy(buf[pos .. pos + p2.len], p2);
        pos += p2.len;

        const name = cat.germanName();
        pos += db_mod.jsonEscapeString(buf[pos..], name) orelse return null;

        const p3 = "\",\"color\":\"";
        @memcpy(buf[pos .. pos + p3.len], p3);
        pos += p3.len;

        const color = cat.color();
        @memcpy(buf[pos .. pos + color.len], color);
        pos += color.len;

        const p4 = "\",\"icon\":\"";
        @memcpy(buf[pos .. pos + p4.len], p4);
        pos += p4.len;

        const icon = cat.icon();
        pos += db_mod.jsonEscapeString(buf[pos..], icon) orelse return null;

        const p5 = "\"}";
        @memcpy(buf[pos .. pos + p5.len], p5);
        pos += p5.len;
    }

    buf[pos] = ']';
    pos += 1;

    return makeLengthPrefixed(buf[0..pos]);
}

// --- Lifecycle ---

/// Close the database and free resources.
/// Close the database and free resources.
export fn wimg_close() void {
    if (global_db) |*database| {
        database.close();
        global_db = null;
    }
}

/// Free a pointer previously returned by other wimg_ functions.
export fn wimg_free(ptr: [*]const u8, len: u32) void {
    _ = len;
    _ = ptr;
    fba.reset();
}

/// Expose memory allocation for the JS host to write data into WASM memory.
export fn wimg_alloc(size: u32) ?[*]u8 {
    const buf = fba.allocator().alloc(u8, size) catch return null;
    return buf.ptr;
}
// --- Snapshots ---

/// Take a monthly snapshot for the given year/month. Returns 0 on success, -1 on error.
export fn wimg_take_snapshot(year: u32, month: u32) i32 {
    var database = global_db orelse {
        setError("wimg_take_snapshot: database not initialized", .{});
        return -1;
    };

    database.takeSnapshot(year, month) catch |err| {
        setError("wimg_take_snapshot: failed: {s}", .{@errorName(err)});
        return -1;
    };

    return 0;
}

/// Get all snapshots as length-prefixed JSON array.
export fn wimg_get_snapshots() ?[*]const u8 {
    var database = global_db orelse {
        setError("wimg_get_snapshots: database not initialized", .{});
        return null;
    };

    const buf_size: usize = 64 * 1024; // 64 KB
    const buf = fba.allocator().alloc(u8, buf_size + 4) catch {
        setError("wimg_get_snapshots: failed to allocate buffer", .{});
        return null;
    };

    const json_len = database.getSnapshotsJson(buf.ptr + 4, buf_size) catch |err| {
        setError("wimg_get_snapshots: query failed: {s}", .{@errorName(err)});
        fba.allocator().free(buf);
        return null;
    } orelse {
        setError("wimg_get_snapshots: buffer too small", .{});
        fba.allocator().free(buf);
        return null;
    };

    const len_bytes: [4]u8 = @bitCast(@as(u32, @intCast(json_len)));
    buf[0] = len_bytes[0];
    buf[1] = len_bytes[1];
    buf[2] = len_bytes[2];
    buf[3] = len_bytes[3];

    return buf.ptr;
}

// --- Export ---

/// Export all transactions as CSV. Returns length-prefixed CSV string.
export fn wimg_export_csv() ?[*]const u8 {
    var database = global_db orelse {
        setError("wimg_export_csv: database not initialized", .{});
        return null;
    };

    const buf_size: usize = 8 * 1024 * 1024; // 8 MB
    const buf = fba.allocator().alloc(u8, buf_size + 4) catch {
        setError("wimg_export_csv: failed to allocate buffer", .{});
        return null;
    };

    const csv_len = database.exportTransactionsCsv(buf.ptr + 4, buf_size) catch |err| {
        setError("wimg_export_csv: query failed: {s}", .{@errorName(err)});
        fba.allocator().free(buf);
        return null;
    } orelse {
        setError("wimg_export_csv: buffer too small", .{});
        fba.allocator().free(buf);
        return null;
    };

    const len_bytes: [4]u8 = @bitCast(@as(u32, @intCast(csv_len)));
    buf[0] = len_bytes[0];
    buf[1] = len_bytes[1];
    buf[2] = len_bytes[2];
    buf[3] = len_bytes[3];

    return buf.ptr;
}

/// Export the full database as JSON. Returns length-prefixed JSON string.
export fn wimg_export_db() ?[*]const u8 {
    var database = global_db orelse {
        setError("wimg_export_db: database not initialized", .{});
        return null;
    };

    const buf_size: usize = 8 * 1024 * 1024; // 8 MB
    const buf = fba.allocator().alloc(u8, buf_size + 4) catch {
        setError("wimg_export_db: failed to allocate buffer", .{});
        return null;
    };

    const json_len = database.exportDbJson(buf.ptr + 4, buf_size) catch |err| {
        setError("wimg_export_db: query failed: {s}", .{@errorName(err)});
        fba.allocator().free(buf);
        return null;
    } orelse {
        setError("wimg_export_db: buffer too small", .{});
        fba.allocator().free(buf);
        return null;
    };

    const len_bytes: [4]u8 = @bitCast(@as(u32, @intCast(json_len)));
    buf[0] = len_bytes[0];
    buf[1] = len_bytes[1];
    buf[2] = len_bytes[2];
    buf[3] = len_bytes[3];

    return buf.ptr;
}

/// Run arbitrary SQL and return JSON result. Input: null-terminated SQL string.
/// Returns length-prefixed JSON: {"columns":[...],"rows":[...],"count":N,"truncated":bool}
export fn wimg_query(sql_ptr: [*]const u8, sql_len: u32) ?[*]const u8 {
    var database = global_db orelse {
        setError("wimg_query: database not initialized", .{});
        return null;
    };

    // Copy SQL to a null-terminated buffer
    const sql_buf = fba.allocator().alloc(u8, sql_len + 1) catch {
        setError("wimg_query: alloc failed", .{});
        return null;
    };
    defer fba.allocator().free(sql_buf);
    @memcpy(sql_buf[0..sql_len], sql_ptr[0..sql_len]);
    sql_buf[sql_len] = 0;

    const buf_size: usize = 2 * 1024 * 1024; // 2 MB result buffer
    const buf = fba.allocator().alloc(u8, buf_size + 4) catch {
        setError("wimg_query: failed to allocate buffer", .{});
        return null;
    };

    const json_len = database.rawQuery(@ptrCast(sql_buf.ptr), buf.ptr + 4, buf_size) catch |err| {
        // Try to get SQLite error message
        if (database.lastError()) |errmsg| {
            const msg = std.mem.span(errmsg);
            setError("wimg_query: {s}", .{msg});
        } else {
            setError("wimg_query: {s}", .{@errorName(err)});
        }
        fba.allocator().free(buf);
        return null;
    } orelse {
        setError("wimg_query: result too large for buffer", .{});
        fba.allocator().free(buf);
        return null;
    };

    const len_bytes: [4]u8 = @bitCast(@as(u32, @intCast(json_len)));
    buf[0] = len_bytes[0];
    buf[1] = len_bytes[1];
    buf[2] = len_bytes[2];
    buf[3] = len_bytes[3];

    return buf.ptr;
}

// --- DB persistence (OPFS) — WASM only ---
// These functions use the in-memory VFS which only exists for wasm32.
// On native (iOS/macOS), SQLite uses the real filesystem directly.

comptime {
    if (is_wasm) {
        @export(&wimg_db_ptr, .{ .name = "wimg_db_ptr" });
        @export(&wimg_db_size, .{ .name = "wimg_db_size" });
        @export(&wimg_db_load, .{ .name = "wimg_db_load" });
    }
}

extern fn wasm_vfs_get_db_ptr(name: [*:0]const u8) ?[*]const u8;
extern fn wasm_vfs_get_db_size(name: [*:0]const u8) i32;
extern fn wasm_vfs_load_db(name: [*:0]const u8, data: [*]const u8, size: i32) i32;

fn wimg_db_ptr() callconv(.c) ?[*]const u8 {
    return wasm_vfs_get_db_ptr("/wimg.db");
}

fn wimg_db_size() callconv(.c) u32 {
    const size = wasm_vfs_get_db_size("/wimg.db");
    return if (size > 0) @intCast(size) else 0;
}

fn wimg_db_load(data: [*]const u8, size: u32) callconv(.c) i32 {
    log("wimg_db_load: loading {d} bytes", .{size});
    const rc = wasm_vfs_load_db("/wimg.db", data, @intCast(size));
    if (rc != 0) {
        setError("wimg_db_load: failed with rc={d}", .{rc});
        return -1;
    }
    return 0;
}

// --- Crypto (E2E encryption for sync) ---

/// Derive a 32-byte encryption key from a sync key using HKDF-SHA256.
/// Returns a length-prefixed 32-byte key, or null on error.
export fn wimg_derive_key(sync_key_ptr: [*]const u8, sync_key_len: u32) ?[*]const u8 {
    const sync_key = sync_key_ptr[0..sync_key_len];
    const key = crypto.deriveKey(sync_key);
    return makeLengthPrefixed(&key);
}

/// Encrypt plaintext using XChaCha20-Poly1305.
/// Takes plaintext + 32-byte key + 24-byte nonce.
/// Returns length-prefixed base64(nonce + ciphertext + tag), or null on error.
export fn wimg_encrypt_field(
    pt_ptr: [*]const u8,
    pt_len: u32,
    key_ptr: [*]const u8,
    nonce_ptr: [*]const u8,
) ?[*]const u8 {
    const plaintext = pt_ptr[0..pt_len];
    const key: [32]u8 = key_ptr[0..32].*;
    const nonce: [24]u8 = nonce_ptr[0..24].*;

    // Encrypted output: nonce(24) + ciphertext(pt_len) + tag(16)
    const enc_size = 24 + pt_len + 16;
    const enc_buf = fba.allocator().alloc(u8, enc_size) catch {
        setError("wimg_encrypt_field: alloc failed", .{});
        return null;
    };

    const enc_len = crypto.encryptField(plaintext, key, nonce, enc_buf) catch {
        setError("wimg_encrypt_field: encryption failed", .{});
        return null;
    };

    // Base64 encode
    const b64_len = std.base64.standard.Encoder.calcSize(enc_len);
    const b64_buf = fba.allocator().alloc(u8, b64_len) catch {
        setError("wimg_encrypt_field: b64 alloc failed", .{});
        return null;
    };
    const encoded = std.base64.standard.Encoder.encode(b64_buf, enc_buf[0..enc_len]);

    return makeLengthPrefixed(encoded);
}

/// Decrypt a base64-encoded ciphertext using XChaCha20-Poly1305.
/// Takes base64(nonce + ciphertext + tag) + 32-byte key.
/// Returns length-prefixed plaintext, or null on error.
export fn wimg_decrypt_field(
    ct_ptr: [*]const u8,
    ct_len: u32,
    key_ptr: [*]const u8,
) ?[*]const u8 {
    const b64_input = ct_ptr[0..ct_len];
    const key: [32]u8 = key_ptr[0..32].*;

    // Decode base64
    const decoded_size = std.base64.standard.Decoder.calcSizeForSlice(b64_input) catch {
        setError("wimg_decrypt_field: invalid base64", .{});
        return null;
    };
    const decoded_buf = fba.allocator().alloc(u8, decoded_size) catch {
        setError("wimg_decrypt_field: alloc failed", .{});
        return null;
    };
    std.base64.standard.Decoder.decode(decoded_buf, b64_input) catch {
        setError("wimg_decrypt_field: base64 decode failed", .{});
        return null;
    };

    // Decrypt: input is nonce(24) + ciphertext + tag(16), so plaintext = decoded_size - 40
    const pt_len_max = if (decoded_size > 40) decoded_size - 40 else 0;
    const pt_buf = fba.allocator().alloc(u8, pt_len_max) catch {
        setError("wimg_decrypt_field: pt alloc failed", .{});
        return null;
    };

    const pt_len = crypto.decryptField(decoded_buf[0..decoded_size], key, pt_buf) catch {
        setError("wimg_decrypt_field: decryption failed", .{});
        return null;
    };

    return makeLengthPrefixed(pt_buf[0..pt_len]);
}

// --- FinTS (native-only) ---

// Global FinTS session state — only exists on native targets
var fints_session: if (!is_wasm) fints_mod.FintsSession else void = if (!is_wasm) fints_mod.FintsSession.init("", "", "", "") else {};

comptime {
    if (!is_wasm) {
        @export(&wimg_fints_connect, .{ .name = "wimg_fints_connect" });
        @export(&wimg_fints_send_tan, .{ .name = "wimg_fints_send_tan" });
        @export(&wimg_fints_fetch, .{ .name = "wimg_fints_fetch" });
        @export(&wimg_fints_get_banks, .{ .name = "wimg_fints_get_banks" });
        @export(&wimg_fints_get_tan_media, .{ .name = "wimg_fints_get_tan_media" });
        @export(&wimg_fints_set_tan_medium, .{ .name = "wimg_fints_set_tan_medium" });
        @export(&wimg_set_http_callback, .{ .name = "wimg_set_http_callback" });
    }
}

fn wimg_set_http_callback(cb: fints_http_mod.HttpCallback) callconv(.c) void {
    fints_http_mod.setCallback(cb);
}

/// Send HKEND to close the current dialog. Best-effort, ignores errors.
fn sendDialogEnd(session: *fints_mod.FintsSession, sec_func: []const u8, msg_buf: *[8192]u8, resp_buf: *[65536]u8) void {
    const end_len = fints_mod.buildDialogEndWithSecFunc(session, sec_func, msg_buf) orelse return;
    _ = fints_http_mod.sendFintsMessage(
        std.heap.page_allocator,
        session.urlSlice(),
        msg_buf[0..end_len],
        resp_buf,
    ) catch {};
}

fn classifyHhduc(payload: []const u8) []const u8 {
    if (payload.len >= 4) {
        const type_len: usize = (@as(usize, payload[0]) << 8) | @as(usize, payload[1]);
        if (type_len > 0 and 2 + type_len + 2 <= payload.len) {
            const mime = payload[2 .. 2 + type_len];
            if (std.mem.startsWith(u8, mime, "image/")) {
                return "matrix-container-image";
            }
        }
    }
    if (payload.len >= 4 and payload[0] == 0x89 and payload[1] == 'P' and payload[2] == 'N' and payload[3] == 'G') {
        return "png-binary";
    }
    if (payload.len >= 2 and payload[0] == 0xFF and payload[1] == 0xD8) {
        return "jpeg-binary";
    }
    if (std.mem.startsWith(u8, payload, "GIF87a") or std.mem.startsWith(u8, payload, "GIF89a")) {
        return "gif-binary";
    }
    if (std.mem.startsWith(u8, payload, "data:image/")) {
        return "image-data-uri";
    }
    if (std.mem.startsWith(u8, payload, "iVBO")) {
        return "png-base64-ascii";
    }
    if (std.mem.startsWith(u8, payload, "CHLGUC")) {
        return "hhd-uc-chlguc";
    }
    if (payload.len > 0 and payload[0] >= 32 and payload[0] <= 126) {
        return "ascii-text";
    }
    return "binary-unknown";
}

fn looksLikeImageBytes(data: []const u8) bool {
    if (data.len >= 4 and data[0] == 0x89 and data[1] == 'P' and data[2] == 'N' and data[3] == 'G') return true;
    if (data.len >= 2 and data[0] == 0xFF and data[1] == 0xD8) return true;
    if (std.mem.startsWith(u8, data, "GIF87a") or std.mem.startsWith(u8, data, "GIF89a")) return true;
    if (data.len >= 12 and std.mem.eql(u8, data[0..4], "RIFF") and std.mem.eql(u8, data[8..12], "WEBP")) return true;
    if (std.mem.startsWith(u8, data, "BM")) return true; // BMP
    return false;
}

fn maybeDecodeBase64Image(source: []const u8, decoded_buf: []u8) ?[]const u8 {
    if (source.len < 16) return null;
    const decoder = std.base64.standard.Decoder;
    const decoded_len = decoder.calcSizeForSlice(source) catch return null;
    if (decoded_len == 0 or decoded_len > decoded_buf.len) return null;
    decoder.decode(decoded_buf[0..decoded_len], source) catch return null;
    const decoded = decoded_buf[0..decoded_len];
    if (looksLikeImageBytes(decoded)) return decoded;
    return null;
}

fn pngHasIend(data: []const u8) bool {
    if (data.len < 12) return false;
    // IEND chunk marker appears as 49 45 4E 44
    return std.mem.indexOf(u8, data, "IEND") != null;
}

fn extractMatrixImagePayload(raw: []const u8) ?[]const u8 {
    if (raw.len < 6) return null;
    const type_len: usize = (@as(usize, raw[0]) << 8) | @as(usize, raw[1]);
    if (type_len == 0 or 2 + type_len + 2 > raw.len) return null;
    const mime_start: usize = 2;
    const mime_end: usize = mime_start + type_len;
    const mime = raw[mime_start..mime_end];
    if (!std.mem.startsWith(u8, mime, "image/")) return null;

    const content_len_start: usize = mime_end;
    const content_len_be: usize = (@as(usize, raw[content_len_start]) << 8) | @as(usize, raw[content_len_start + 1]);
    const content_len_le: usize = (@as(usize, raw[content_len_start + 1]) << 8) | @as(usize, raw[content_len_start]);
    const content_start: usize = content_len_start + 2;
    const remaining = raw.len - content_start;

    const content_len: usize = blk: {
        if (content_len_be > 0 and content_len_be <= remaining) break :blk content_len_be;
        if (content_len_le > 0 and content_len_le <= remaining) break :blk content_len_le;
        // Some banks provide malformed/variant length fields; fall back to full remainder.
        break :blk remaining;
    };
    if (content_len == 0) return null;

    return raw[content_start .. content_start + content_len];
}

fn normalizePhotoTanPayload(raw: []const u8, decoded_buf: []u8) []const u8 {
    if (extractMatrixImagePayload(raw)) |img_payload| {
        if (maybeDecodeBase64Image(img_payload, decoded_buf)) |decoded| {
            return decoded;
        }
        if (looksLikeImageBytes(img_payload)) {
            return img_payload;
        }
        return img_payload;
    }

    var source = raw;
    if (std.mem.startsWith(u8, source, "data:image/")) {
        if (std.mem.indexOf(u8, source, ",")) |comma| {
            source = source[comma + 1 ..];
        }
    }

    if (maybeDecodeBase64Image(source, decoded_buf)) |decoded| {
        return decoded;
    }
    return raw;
}

fn isNoChallenge(challenge: []const u8) bool {
    if (challenge.len == 0) return true;
    var start: usize = 0;
    while (start < challenge.len and (challenge[start] == ' ' or challenge[start] == '\t' or challenge[start] == '\r' or challenge[start] == '\n')) : (start += 1) {}
    if (start >= challenge.len) return true;
    return std.ascii.startsWithIgnoreCase(challenge[start..], "nochallenge");
}

/// Update selected TAN security function from sync response (python-fints style).
/// Parse 3920 capability text and pick first advertised two-step method.
fn selectTanSecFuncFromSync(sync_resp: *const fints_mod.ParsedResponse, session: *fints_mod.FintsSession) void {
    var selected_buf: [3]u8 = undefined;
    var has_selected = false;
    for (sync_resp.codes[0..sync_resp.code_count]) |*c| {
        if (!std.mem.eql(u8, c.codeSlice(), "3920")) continue;
        const txt = c.textSlice();
        var i: usize = 0;
        while (i + 2 < txt.len) : (i += 1) {
            const a = txt[i];
            const b = txt[i + 1];
            const d = txt[i + 2];
            if (a < '0' or a > '9' or b < '0' or b > '9' or d < '0' or d > '9') continue;

            const token = txt[i .. i + 3];
            // Keep one-step only as fallback; prefer first advertised two-step mechanism.
            if (std.mem.eql(u8, token, "999")) continue;
            @memcpy(selected_buf[0..3], token);
            has_selected = true;
            break;
        }
        // Some banks (e.g. Comdirect) return only procedure labels ("photoTAN")
        // instead of numeric IDs in 3920 text. Map known labels to sec_func IDs.
        if (!has_selected) {
            if (containsIgnoreCase(txt, "phototan") or containsIgnoreCase(txt, "photo tan")) {
                @memcpy(selected_buf[0..3], "902");
                has_selected = true;
            } else if (containsIgnoreCase(txt, "mobiletan") or containsIgnoreCase(txt, "sms")) {
                @memcpy(selected_buf[0..3], "901");
                has_selected = true;
            }
        }
        if (has_selected) break;
    }

    if (has_selected) {
        @memcpy(session.tan_sec_func[0..3], selected_buf[0..3]);
        session.tan_sec_func_len = 3;
    }
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (haystack.len < needle.len) return false;
    const limit = haystack.len - needle.len + 1;
    for (0..limit) |i| {
        var ok = true;
        for (needle, 0..) |n, j| {
            const h = std.ascii.toLower(haystack[i + j]);
            const nl = std.ascii.toLower(n);
            if (h != nl) {
                ok = false;
                break;
            }
        }
        if (ok) return true;
    }
    return false;
}

fn extractTouchdownToken(resp: *const fints_mod.ParsedResponse, out_buf: []u8) []const u8 {
    for (resp.codes[0..resp.code_count]) |*c| {
        if (!std.mem.eql(u8, c.codeSlice(), "3040")) continue;
        // Prefer structured parameter field first, then fallback to message text.
        const candidates = [_][]const u8{
            c.parameterSlice(),
            c.textSlice(),
        };

        for (candidates) |candidate| {
            const token = normalizeTouchdownToken(candidate, out_buf);
            if (token.len > 0) return token;
        }
    }
    return "";
}

fn normalizeTouchdownToken(raw: []const u8, out_buf: []u8) []const u8 {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len == 0) return "";

    var token = trimmed;

    // If localized text embeds the token, keep the tail after ":" or "=".
    if (std.mem.lastIndexOfScalar(u8, token, ':')) |idx| {
        if (idx + 1 < token.len) token = token[idx + 1 ..];
    } else if (std.mem.lastIndexOfScalar(u8, token, '=')) |idx| {
        if (idx + 1 < token.len) token = token[idx + 1 ..];
    }

    token = std.mem.trim(u8, token, " \t\r\n'\"");
    if (token.len == 0 or token.len > out_buf.len) return "";

    // Reject obvious non-token values.
    if (std.mem.indexOfScalar(u8, token, ' ') != null) return "";

    @memcpy(out_buf[0..token.len], token);
    return out_buf[0..token.len];
}

/// Connect to a bank via FinTS. Input JSON: {"blz":"...","user":"...","pin":"..."}
/// Returns length-prefixed JSON: {"status":"ok"} or {"status":"tan_required","challenge":"..."}
fn wimg_fints_connect(data: [*]const u8, len: u32) callconv(.c) ?[*]const u8 {
    if (is_wasm) return null;

    const json = data[0..len];

    const blz = jsonExtractString(json, "\"blz\"") orelse {
        setError("wimg_fints_connect: missing blz field", .{});
        return null;
    };
    const user = jsonExtractString(json, "\"user\"") orelse {
        setError("wimg_fints_connect: missing user field", .{});
        return null;
    };
    const pin = jsonExtractString(json, "\"pin\"") orelse {
        setError("wimg_fints_connect: missing pin field", .{});
        return null;
    };
    const product = jsonExtractString(json, "\"product\"") orelse "F7C4049477F6136957A46EC28";

    // Look up bank
    const bank = banks_mod.findByBlz(blz) orelse {
        setError("wimg_fints_connect: unknown BLZ {s}", .{blz});
        return null;
    };

    // Initialize session (bank_family auto-detected from URL in FintsSession.init)
    fints_session = fints_mod.FintsSession.init(blz, bank.urlSlice(), user, pin);
    const prod_len = @min(product.len, 25);
    @memcpy(fints_session.product_id[0..prod_len], product[0..prod_len]);
    fints_session.product_id_len = @intCast(prod_len);

    if (!is_wasm) {
        dbg.print("[FinTS Zig] bank_family={s} for BLZ {s}\n", .{
            @tagName(fints_session.bank_family),
            blz,
        });
    }

    // Step 1: Sync dialog (sec_func=999, HKSYN to get system_id)
    var msg_buf: [8192]u8 = undefined;
    var resp_buf: [65536]u8 = undefined;

    const sync_len = fints_mod.buildSyncInit(&fints_session, &msg_buf) orelse {
        setError("wimg_fints_connect: failed to build sync init", .{});
        return null;
    };

    const sync_resp_len = fints_http_mod.sendFintsMessage(
        std.heap.page_allocator,
        fints_session.urlSlice(),
        msg_buf[0..sync_len],
        &resp_buf,
    ) catch {
        setError("wimg_fints_connect: sync HTTP request failed", .{});
        return null;
    };

    var sync_resp = fints_mod.ParsedResponse.init();
    fints_mod.parseResponse(&fints_session, resp_buf[0..sync_resp_len], &sync_resp);
    selectTanSecFuncFromSync(&sync_resp, &fints_session);
    fints_session.msg_num += 1;

    // Debug: log what parseResponse extracted (native uses stderr, visible in Xcode console)
    if (!is_wasm) {
        dbg.print("[FinTS Zig] sync resp_len={d}, codes={d}, has_tan={}\n", .{
            sync_resp_len,
            sync_resp.code_count,
            fints_session.has_pending_tan,
        });
        dbg.print("[FinTS Zig] dialog_id='{s}' (len={d})\n", .{
            fints_session.dialogIdSlice(),
            fints_session.dialog_id_len,
        });
        dbg.print("[FinTS Zig] system_id='{s}' (len={d})\n", .{
            fints_session.systemIdSlice(),
            fints_session.system_id_len,
        });
        // First 200 bytes of response to see HNHBK
        const preview_len = @min(sync_resp_len, 200);
        dbg.print("[FinTS Zig] resp[0..{d}]='{s}'\n", .{ preview_len, resp_buf[0..preview_len] });
    }

    // End sync dialog and reset for next dialog
    // Close sync dialog using sync security function (999), independent of later TAN method.
    _ = sendDialogEnd(&fints_session, "999", &msg_buf, &resp_buf);

    // Check sync result
    if (sync_resp.hasError()) {
        fints_session.clearPin();
        return makeLengthPrefixed("{\"status\":\"error\",\"message\":\"Sync failed\"}");
    }

    // Return status with tan_medium_required flag so UI knows if picker is needed
    var debug_buf: [512]u8 = undefined;
    const did = fints_session.dialogIdSlice();
    const sid = fints_session.systemIdSlice();
    const tan_med_req = if (fints_session.tan_medium_required) "true" else "false";
    const debug_json = std.fmt.bufPrint(&debug_buf, "{{\"status\":\"ok\",\"tan_medium_required\":{s},\"_debug_dialog_id\":\"{s}\",\"_debug_system_id\":\"{s}\",\"_debug_did_len\":{d},\"_debug_sid_len\":{d}}}", .{ tan_med_req, did, sid, did.len, sid.len }) catch return makeLengthPrefixed("{\"status\":\"ok\"}");

    // Reset dialog state for fetch (keeps system_id, PIN, product_id)
    fints_session.resetDialog();
    fints_session.has_pending_tan = false; // nochallenge from sync is irrelevant

    return makeLengthPrefixed(debug_json);
}

/// Submit a TAN. Input JSON: {"tan":"123456"}
/// Returns length-prefixed JSON: {"status":"ok"} or {"status":"error","message":"..."}
fn wimg_fints_send_tan(data: [*]const u8, len: u32) callconv(.c) ?[*]const u8 {
    if (is_wasm) return null;

    const json = data[0..len];
    const tan = jsonExtractString(json, "\"tan\"") orelse {
        setError("wimg_fints_send_tan: missing tan field", .{});
        return null;
    };
    if (fints_session.challenge_ref_len == 0) {
        return makeLengthPrefixed("{\"status\":\"error\",\"message\":\"Missing TAN task reference (challenge_ref)\"}");
    }
    if (fints_session.pin_len == 0) {
        return makeLengthPrefixed("{\"status\":\"error\",\"message\":\"PIN missing in session, please reconnect\"}");
    }

    var msg_buf: [8192]u8 = undefined;
    var resp_buf: [65536]u8 = undefined;
    var tan_payload = tan;
    const decoupled_start = fints_session.decoupled;
    const max_polls: u8 = if (fints_session.decoupled_max_poll_number > 0) fints_session.decoupled_max_poll_number else 10;
    const first_wait: u8 = if (fints_session.wait_before_first_poll > 0) fints_session.wait_before_first_poll else 4;
    const next_wait: u8 = if (fints_session.wait_before_next_poll > 0) fints_session.wait_before_next_poll else 2;
    var poll_count: u8 = 0;

    while (true) {
        const msg_len = fints_mod.buildTanResponse(&fints_session, tan_payload, &msg_buf) orelse {
            setError("wimg_fints_send_tan: failed to build TAN response", .{});
            return null;
        };
        if (!is_wasm) {
            dbg.print("[FinTS Zig] send tan: task_reference='{s}' (len={d})\n", .{
                fints_session.challenge_ref[0..fints_session.challenge_ref_len],
                fints_session.challenge_ref_len,
            });
            const req_preview = @min(msg_len, 280);
            dbg.print("[FinTS Zig] send tan msg[0..{d}]='{s}'\n", .{ req_preview, msg_buf[0..req_preview] });
        }

        const resp_len = fints_http_mod.sendFintsMessage(
            std.heap.page_allocator,
            fints_session.urlSlice(),
            msg_buf[0..msg_len],
            &resp_buf,
        ) catch {
            setError("wimg_fints_send_tan: HTTP request failed", .{});
            return null;
        };

        var resp = fints_mod.ParsedResponse.init();
        fints_mod.parseResponse(&fints_session, resp_buf[0..resp_len], &resp);
        fints_session.msg_num += 1;

        if (!is_wasm) {
            dbg.print("[FinTS Zig] fetch hkkaz: resp_len={d}, codes={d}, mt940_len={d}, has_tan={}\n", .{
                resp_len,
                resp.code_count,
                resp.mt940_len,
                fints_session.has_pending_tan,
            });
            for (resp.codes[0..resp.code_count]) |*c| {
                dbg.print("[FinTS Zig] fetch hkkaz code: {s} '{s}'\n", .{ c.codeSlice(), c.textSlice() });
            }
            if (resp.mt940_len == 0) {
                const p_len = @min(resp_len, 260);
                dbg.print("[FinTS Zig] fetch hkkaz resp[0..{d}]='{s}'\n", .{ p_len, resp_buf[0..p_len] });
            } else {
                const p_len = @min(@as(usize, resp.mt940_len), 120);
                dbg.print("[FinTS Zig] fetch hkkaz mt940[0..{d}]='{s}'\n", .{ p_len, resp.mt940_data[0..p_len] });
            }
        }

        if (!is_wasm) {
            dbg.print("[FinTS Zig] send tan: resp_len={d}, codes={d}, has_tan={}, challenge_len={d}, hhduc_len={d}\n", .{
                resp_len,
                resp.code_count,
                fints_session.has_pending_tan,
                fints_session.challenge_len,
                fints_session.challenge_hhduc_len,
            });
            for (resp.codes[0..resp.code_count]) |*c| {
                dbg.print("[FinTS Zig] send tan code: {s} '{s}'\n", .{ c.codeSlice(), c.textSlice() });
            }
            const p_len = @min(resp_len, 300);
            dbg.print("[FinTS Zig] send tan resp[0..{d}]='{s}'\n", .{ p_len, resp_buf[0..p_len] });
        }

        if (resp.hasError()) {
            var result_buf: [1024]u8 = undefined;
            if (resp.code_count > 0) {
                const c = resp.codes[resp.code_count - 1];
                const msg = std.fmt.bufPrint(&result_buf, "{{\"status\":\"error\",\"message\":\"{s} {s}\"}}", .{
                    c.codeSlice(),
                    c.textSlice(),
                }) catch return makeLengthPrefixed("{\"status\":\"error\",\"message\":\"TAN rejected\"}");
                return makeLengthPrefixed(msg);
            }
            return makeLengthPrefixed("{\"status\":\"error\",\"message\":\"TAN rejected\"}");
        }

        // If TAN submit response already contains statement payload, TAN flow is complete.
        if (resp.mt940_len > 0) {
            fints_session.has_pending_tan = false;
            fints_session.challenge_len = 0;
            fints_session.challenge_hhduc_len = 0;
        }

        // Some flows return another TAN/challenge step.
        if (fints_session.has_pending_tan and resp.mt940_len == 0) {
            var result_buf: [16384]u8 = undefined;
            const challenge = fints_session.challenge[0..fints_session.challenge_len];

            // Bank can return HITAN with "nochallenge" (or empty challenge) to signal
            // that no SCA step is required. Do not surface TAN UI in that case.
            if (isNoChallenge(challenge)) {
                fints_session.has_pending_tan = false;
                fints_session.challenge_len = 0;
                fints_session.challenge_hhduc_len = 0;
                return makeLengthPrefixed("{\"status\":\"ok\"}");
            }

            // Decoupled process: poll status using HKTAN process S until completion or timeout.
            if (decoupled_start and fints_session.decoupled) {
                if (!fints_session.automated_polling_allowed) {
                    const result_json = std.fmt.bufPrint(&result_buf, "{{\"status\":\"tan_required\",\"challenge\":\"{s}\",\"decoupled\":{}}}", .{
                        challenge,
                        true,
                    }) catch return makeLengthPrefixed("{\"status\":\"tan_required\",\"decoupled\":true}");
                    return makeLengthPrefixed(result_json);
                }
                if (poll_count >= max_polls) {
                    const result_json = std.fmt.bufPrint(&result_buf, "{{\"status\":\"tan_required\",\"challenge\":\"{s}\",\"decoupled\":{}}}", .{
                        challenge,
                        true,
                    }) catch return makeLengthPrefixed("{\"status\":\"tan_required\",\"decoupled\":true}");
                    return makeLengthPrefixed(result_json);
                }

                const wait_secs: u8 = if (poll_count == 0) first_wait else next_wait;
                poll_count += 1;
                if (wait_secs > 0) {
                    var ts: std.c.timespec = .{ .sec = @intCast(wait_secs), .nsec = 0 };
                    _ = std.c.nanosleep(&ts, null);
                }
                tan_payload = "";
                continue;
            }

            if (fints_session.challenge_hhduc_len > 0) {
                const hhduc = fints_session.challenge_hhduc[0..fints_session.challenge_hhduc_len];
                var decoded_hhduc_buf: [8192]u8 = undefined;
                const normalized_hhduc = normalizePhotoTanPayload(hhduc, &decoded_hhduc_buf);
                const b64_encoder = std.base64.standard.Encoder;
                var b64_buf: [12288]u8 = undefined;
                const b64_data = b64_encoder.encode(&b64_buf, normalized_hhduc);
                const result_json = std.fmt.bufPrint(&result_buf, "{{\"status\":\"tan_required\",\"challenge\":\"{s}\",\"phototan\":\"{s}\",\"decoupled\":{}}}", .{
                    challenge,
                    b64_data,
                    fints_session.decoupled,
                }) catch return makeLengthPrefixed("{\"status\":\"tan_required\"}");
                return makeLengthPrefixed(result_json);
            }
            const result_json = std.fmt.bufPrint(&result_buf, "{{\"status\":\"tan_required\",\"challenge\":\"{s}\",\"decoupled\":{}}}", .{
                challenge,
                fints_session.decoupled,
            }) catch return makeLengthPrefixed("{\"status\":\"tan_required\"}");
            return makeLengthPrefixed(result_json);
        }

        fints_session.has_pending_tan = false;
        fints_session.has_active_dialog = true; // dialog ready for HKKAZ
        return makeLengthPrefixed("{\"status\":\"ok\"}");
    }
}

/// Fetch bank statements. Input JSON: {"from":"2026-01-01","to":"2026-03-01"}
/// Opens a new authenticated dialog, sends HKKAZ, parses MT940, inserts transactions.
/// Returns length-prefixed JSON: {"imported":N,"duplicates":N} or {"status":"tan_required",...}
fn wimg_fints_fetch(data: [*]const u8, len: u32) callconv(.c) ?[*]const u8 {
    if (is_wasm) return null;

    var database = global_db orelse {
        setError("wimg_fints_fetch: database not initialized", .{});
        return null;
    };

    const json = data[0..len];
    const from_raw = jsonExtractString(json, "\"from\"") orelse "";
    const to_raw = jsonExtractString(json, "\"to\"") orelse "";

    // Convert YYYY-MM-DD to YYYYMMDD for FinTS
    var from_buf: [8]u8 = undefined;
    var to_buf: [8]u8 = undefined;
    const from = if (from_raw.len == 10 and from_raw[4] == '-') blk: {
        @memcpy(from_buf[0..4], from_raw[0..4]);
        @memcpy(from_buf[4..6], from_raw[5..7]);
        @memcpy(from_buf[6..8], from_raw[8..10]);
        break :blk from_buf[0..8];
    } else from_raw;
    const to = if (to_raw.len == 10 and to_raw[4] == '-') blk: {
        @memcpy(to_buf[0..4], to_raw[0..4]);
        @memcpy(to_buf[4..6], to_raw[5..7]);
        @memcpy(to_buf[6..8], to_raw[8..10]);
        break :blk to_buf[0..8];
    } else to_raw;

    var msg_buf: [8192]u8 = undefined;
    var resp_buf: [65536]u8 = undefined;

    // If we have an active dialog (post-TAN), skip auth init and go straight to HKKAZ
    if (!fints_session.has_active_dialog) {
        // Step 1: Open a new authenticated dialog for HKKAZ
        fints_session.resetDialog();

        const auth_len = fints_mod.buildAuthInit(&fints_session, &msg_buf) orelse {
            setError("wimg_fints_fetch: failed to build auth init", .{});
            fints_session.clearPin();
            return null;
        };

        // Debug: log auth init raw message
        if (!is_wasm) {
            const req_preview = @min(auth_len, 450);
            dbg.print("[FinTS Zig] auth init msg[0..{d}]='{s}'\n", .{ req_preview, msg_buf[0..req_preview] });
            dbg.print("[FinTS Zig] auth init total_len={d}\n", .{auth_len});
        }

        const auth_resp_len = fints_http_mod.sendFintsMessage(
            std.heap.page_allocator,
            fints_session.urlSlice(),
            msg_buf[0..auth_len],
            &resp_buf,
        ) catch {
            setError("wimg_fints_fetch: auth HTTP request failed", .{});
            fints_session.clearPin();
            return null;
        };

        var auth_resp = fints_mod.ParsedResponse.init();
        fints_mod.parseResponse(&fints_session, resp_buf[0..auth_resp_len], &auth_resp);
        fints_session.msg_num += 1;

        if (!is_wasm) {
            dbg.print("[FinTS Zig] fetch auth: resp_len={d}, codes={d}, has_tan={}, dialog_id='{s}'\n", .{
                auth_resp_len,
                auth_resp.code_count,
                fints_session.has_pending_tan,
                fints_session.dialogIdSlice(),
            });
            dbg.print("[FinTS Zig] fetch auth: challenge_len={d}, hhduc_len={d}\n", .{
                fints_session.challenge_len,
                fints_session.challenge_hhduc_len,
            });
            if (fints_session.challenge_hhduc_len > 0) {
                const hh = fints_session.challenge_hhduc[0..fints_session.challenge_hhduc_len];
                const p0: u8 = if (hh.len > 0) hh[0] else 0;
                const p1: u8 = if (hh.len > 1) hh[1] else 0;
                const p2: u8 = if (hh.len > 2) hh[2] else 0;
                const p3: u8 = if (hh.len > 3) hh[3] else 0;
                dbg.print("[FinTS Zig] fetch auth: hhduc kind={s}, first4={x:0>2} {x:0>2} {x:0>2} {x:0>2}\n", .{
                    classifyHhduc(hh),
                    p0,
                    p1,
                    p2,
                    p3,
                });
                if (hh.len >= 4) {
                    const type_len: usize = (@as(usize, hh[0]) << 8) | @as(usize, hh[1]);
                    if (type_len > 0 and 2 + type_len <= hh.len) {
                        const mime = hh[2 .. 2 + type_len];
                        if (std.mem.startsWith(u8, mime, "image/")) {
                            dbg.print("[FinTS Zig] fetch auth: hhduc mime={s}\n", .{mime});
                        }
                    }
                }
            }
            // Show response codes
            for (auth_resp.codes[0..auth_resp.code_count]) |*c| {
                dbg.print("[FinTS Zig] fetch auth code: {s} '{s}'\n", .{ c.codeSlice(), c.textSlice() });
            }
            const p_len = @min(auth_resp_len, 450);
            dbg.print("[FinTS Zig] fetch auth resp[0..{d}]='{s}'\n", .{ p_len, resp_buf[0..p_len] });
        }

        if (auth_resp.hasError()) {
            // python-fints parity: when bank requests TAN mechanism selection (3920),
            // pick a two-step method and retry auth-init once.
            var requested_tan_method = false;
            for (auth_resp.codes[0..auth_resp.code_count]) |*c| {
                if (std.mem.eql(u8, c.codeSlice(), "3920")) {
                    requested_tan_method = true;
                    break;
                }
            }
            if (requested_tan_method and std.mem.eql(u8, fints_session.tanSecFuncSlice(), "999")) {
                selectTanSecFuncFromSync(&auth_resp, &fints_session);
                fints_session.resetDialog();

                const retry_auth_len = fints_mod.buildAuthInit(&fints_session, &msg_buf) orelse {
                    setError("wimg_fints_fetch: failed to build retry auth init", .{});
                    fints_session.clearPin();
                    return null;
                };
                const retry_auth_resp_len = fints_http_mod.sendFintsMessage(
                    std.heap.page_allocator,
                    fints_session.urlSlice(),
                    msg_buf[0..retry_auth_len],
                    &resp_buf,
                ) catch {
                    setError("wimg_fints_fetch: retry auth HTTP request failed", .{});
                    fints_session.clearPin();
                    return null;
                };
                auth_resp = fints_mod.ParsedResponse.init();
                fints_mod.parseResponse(&fints_session, resp_buf[0..retry_auth_resp_len], &auth_resp);
                fints_session.msg_num += 1;
                if (!auth_resp.hasError()) {
                    // Continue normal flow from successful retry.
                } else {
                    fints_session.clearPin();
                    return makeLengthPrefixed("{\"status\":\"error\",\"message\":\"Authentication failed\"}");
                }
            } else {
                fints_session.clearPin();
                return makeLengthPrefixed("{\"status\":\"error\",\"message\":\"Authentication failed\"}");
            }
        }

        // Handle TAN from auth init
        if (fints_session.has_pending_tan) {
            const challenge = fints_session.challenge[0..fints_session.challenge_len];

            // nochallenge = SCA not required, continue to HKKAZ
            if (isNoChallenge(challenge)) {
                fints_session.has_pending_tan = false;
            } else {
                // Real TAN challenge (e.g. photoTAN) — return to user for TAN entry
                // Dialog stays open; after sendTan, fetch will be called again with has_active_dialog=true
                var result_buf: [16384]u8 = undefined;

                if (fints_session.challenge_hhduc_len > 0) {
                    const hhduc = fints_session.challenge_hhduc[0..fints_session.challenge_hhduc_len];
                    var decoded_hhduc_buf: [8192]u8 = undefined;
                    const normalized_hhduc = normalizePhotoTanPayload(hhduc, &decoded_hhduc_buf);
                    if (!is_wasm) {
                        dbg.print("[FinTS Zig] fetch auth: normalized phototan kind={s}, len={d}\n", .{
                            classifyHhduc(normalized_hhduc),
                            normalized_hhduc.len,
                        });
                        const n0: u8 = if (normalized_hhduc.len > 0) normalized_hhduc[0] else 0;
                        const n1: u8 = if (normalized_hhduc.len > 1) normalized_hhduc[1] else 0;
                        const n2: u8 = if (normalized_hhduc.len > 2) normalized_hhduc[2] else 0;
                        const n3: u8 = if (normalized_hhduc.len > 3) normalized_hhduc[3] else 0;
                        dbg.print("[FinTS Zig] fetch auth: normalized first4={x:0>2} {x:0>2} {x:0>2} {x:0>2}\n", .{ n0, n1, n2, n3 });
                        if (normalized_hhduc.len >= 4 and normalized_hhduc[0] == 0x89 and normalized_hhduc[1] == 'P' and normalized_hhduc[2] == 'N' and normalized_hhduc[3] == 'G') {
                            dbg.print("[FinTS Zig] fetch auth: normalized png has_iend={}\n", .{pngHasIend(normalized_hhduc)});
                        }
                    }
                    const b64_encoder = std.base64.standard.Encoder;
                    var b64_buf: [12288]u8 = undefined;
                    const b64_data = b64_encoder.encode(&b64_buf, normalized_hhduc);
                    const result_json = std.fmt.bufPrint(&result_buf, "{{\"status\":\"tan_required\",\"challenge\":\"{s}\",\"phototan\":\"{s}\",\"decoupled\":{}}}", .{
                        challenge,
                        b64_data,
                        fints_session.decoupled,
                    }) catch return null;
                    return makeLengthPrefixed(result_json);
                }

                const result_json = std.fmt.bufPrint(&result_buf, "{{\"status\":\"tan_required\",\"challenge\":\"{s}\",\"decoupled\":{}}}", .{
                    challenge,
                    fints_session.decoupled,
                }) catch return null;
                return makeLengthPrefixed(result_json);
            }
        }
    }

    // Step 2: Send HKKAZ in this dialog (either after nochallenge or after TAN confirmation).
    // Handle continuation pages via touchdown token (HIRMS 3040), like python-fints.
    const FetchMode = enum { mt940, camt };

    var imported: u32 = 0;
    var duplicates: u32 = 0;
    var saw_mt940 = false;
    var saw_camt = false;
    // Track the latest closing balance across all statement pages. The page with
    // the newest value date carries the current account balance.
    var balance_cents: i64 = 0;
    var balance_date_int: u32 = 0; // YYYYMMDD
    var fetch_mode: FetchMode = .mt940;
    var used_camt_fallback = false;
    var page_count: u8 = 0;
    var touchdown_buf: [128]u8 = undefined;
    var touchdown: []const u8 = "";
    var resp = fints_mod.ParsedResponse.init();
    const bank = banks_mod.findByBlz(&fints_session.blz);
    const account_name = if (bank) |b| b.nameSlice() else "FinTS";

    while (true) {
        const msg_len = switch (fetch_mode) {
            .mt940 => fints_mod.buildFetchStatements(&fints_session, from, to, touchdown, &msg_buf),
            .camt => fints_mod.buildFetchStatementsCamt(&fints_session, from, to, touchdown, &msg_buf),
        } orelse {
            setError("wimg_fints_fetch: failed to build fetch request", .{});
            fints_session.clearPin();
            return null;
        };
        if (!is_wasm) {
            const req_preview = @min(msg_len, 450);
            if (fetch_mode == .mt940) {
                dbg.print("[FinTS Zig] fetch hkkaz negotiated_ver={d}\n", .{fints_session.hikaz_version});
            } else {
                dbg.print("[FinTS Zig] fetch hkcaz camt_format='{s}'\n", .{fints_session.camtFormatSlice()});
            }
            dbg.print("[FinTS Zig] fetch mode={s} msg[0..{d}]='{s}'\n", .{
                if (fetch_mode == .mt940) "mt940" else "camt",
                req_preview,
                msg_buf[0..req_preview],
            });
            if (fints_session.account_ktv_len > 0) {
                dbg.print("[FinTS Zig] fetch account_ktv='{s}'\n", .{fints_session.accountKtvSlice()});
            } else {
                dbg.print("[FinTS Zig] fetch account_ktv missing, fallback user_id='{s}'\n", .{fints_session.userIdSlice()});
            }
            if (touchdown.len > 0) {
                dbg.print("[FinTS Zig] fetch touchdown='{s}'\n", .{touchdown});
            }
        }

        const resp_len = fints_http_mod.sendFintsMessage(
            std.heap.page_allocator,
            fints_session.urlSlice(),
            msg_buf[0..msg_len],
            &resp_buf,
        ) catch {
            setError("wimg_fints_fetch: HTTP request failed", .{});
            fints_session.clearPin();
            return null;
        };

        resp = fints_mod.ParsedResponse.init();
        fints_mod.parseResponse(&fints_session, resp_buf[0..resp_len], &resp);
        fints_session.msg_num += 1;

        // TAN challenge requested for HKKAZ only when no statement payload was returned.
        if (fints_session.has_pending_tan and resp.mt940_len == 0 and resp.camt_len == 0) {
            var result_buf: [16384]u8 = undefined;
            const challenge = fints_session.challenge[0..fints_session.challenge_len];
            if (isNoChallenge(challenge)) {
                fints_session.has_pending_tan = false;
                fints_session.challenge_len = 0;
                fints_session.challenge_hhduc_len = 0;
            } else {
                if (fints_session.challenge_hhduc_len > 0) {
                    const hhduc = fints_session.challenge_hhduc[0..fints_session.challenge_hhduc_len];
                    var decoded_hhduc_buf: [8192]u8 = undefined;
                    const normalized_hhduc = normalizePhotoTanPayload(hhduc, &decoded_hhduc_buf);
                    const b64_encoder = std.base64.standard.Encoder;
                    var b64_buf: [12288]u8 = undefined;
                    const b64_data = b64_encoder.encode(&b64_buf, normalized_hhduc);
                    const result_json = std.fmt.bufPrint(&result_buf, "{{\"status\":\"tan_required\",\"challenge\":\"{s}\",\"phototan\":\"{s}\",\"decoupled\":{}}}", .{
                        challenge,
                        b64_data,
                        fints_session.decoupled,
                    }) catch return null;
                    return makeLengthPrefixed(result_json);
                }
                const result_json = std.fmt.bufPrint(&result_buf, "{{\"status\":\"tan_required\",\"challenge\":\"{s}\",\"decoupled\":{}}}", .{
                    challenge,
                    fints_session.decoupled,
                }) catch return null;
                return makeLengthPrefixed(result_json);
            }
        }

        if (resp.mt940_len > 0) {
            saw_mt940 = true;

            var txn_buf: [2000]Transaction = undefined;
            const mt940_result = mt940_mod.parseMt940(
                resp.mt940_data[0..resp.mt940_len],
                account_name,
                &txn_buf,
            );

            if (mt940_result.closing_balance_date > balance_date_int) {
                balance_date_int = mt940_result.closing_balance_date;
                balance_cents = mt940_result.closing_balance;
            }

            if (!is_wasm) {
                dbg.print("[FinTS Zig] fetch hkkaz mt940 parsed count={d}, errors={d}, mt940_len={d}\n", .{
                    mt940_result.count,
                    mt940_result.errors,
                    resp.mt940_len,
                });
                const preview_len = @min(@as(usize, resp.mt940_len), 180);
                if (preview_len > 0) {
                    dbg.print("[FinTS Zig] fetch hkkaz mt940 preview[0..{d}]='{s}'\n", .{
                        preview_len,
                        resp.mt940_data[0..preview_len],
                    });
                }
            }

            for (txn_buf[0..mt940_result.count]) |*txn| {
                const inserted = database.insertTransaction(txn) catch {
                    continue;
                };
                if (inserted) {
                    imported += 1;
                    if (txn.category == .uncategorized) {
                        const matched = categories.matchRules(database.handle, txn.descriptionSlice());
                        if (matched != .uncategorized) {
                            database.setCategoryById(&txn.id, matched) catch {};
                        }
                    }
                } else {
                    duplicates += 1;
                }
            }
        } else if (resp.camt_len > 0) {
            saw_camt = true;

            var txn_buf: [2000]Transaction = undefined;
            const camt_result = camt_mod.parseCamt(
                resp.camt_data[0..resp.camt_len],
                account_name,
                &txn_buf,
            );

            if (camt_result.closing_balance_date > balance_date_int) {
                balance_date_int = camt_result.closing_balance_date;
                balance_cents = camt_result.closing_balance;
            }

            if (!is_wasm) {
                dbg.print("[FinTS Zig] fetch hkcaz camt parsed count={d}, errors={d}, camt_len={d}\n", .{
                    camt_result.count,
                    camt_result.errors,
                    resp.camt_len,
                });
                const preview_len = @min(@as(usize, resp.camt_len), 180);
                if (preview_len > 0) {
                    dbg.print("[FinTS Zig] fetch hkcaz camt preview[0..{d}]='{s}'\n", .{
                        preview_len,
                        resp.camt_data[0..preview_len],
                    });
                }
            }

            for (txn_buf[0..camt_result.count]) |*txn| {
                const inserted = database.insertTransaction(txn) catch {
                    continue;
                };
                if (inserted) {
                    imported += 1;
                    if (txn.category == .uncategorized) {
                        const matched = categories.matchRules(database.handle, txn.descriptionSlice());
                        if (matched != .uncategorized) {
                            database.setCategoryById(&txn.id, matched) catch {};
                        }
                    }
                } else {
                    duplicates += 1;
                }
            }
        }

        const next_touchdown = extractTouchdownToken(&resp, &touchdown_buf);
        if (next_touchdown.len == 0) {
            if (fetch_mode == .mt940 and !saw_mt940 and fints_session.supports_camt) {
                fetch_mode = .camt;
                used_camt_fallback = true;
                touchdown = "";
                page_count = 0;
                if (!is_wasm) {
                    dbg.print("[FinTS Zig] fetch fallback: switching from HKKAZ to HKCAZ\n", .{});
                }
                continue;
            }
            break;
        }
        touchdown = next_touchdown;
        page_count += 1;
        if (page_count >= 30) break; // safety guard against endless touchdown loops
    }

    if (!saw_mt940 and !saw_camt) {
        _ = sendDialogEnd(&fints_session, fints_session.tanSecFuncSlice(), &msg_buf, &resp_buf);
        fints_session.clearPin();
        var result_buf: [1024]u8 = undefined;
        var pos: usize = 0;

        const prefix = "{\"status\":\"error\",\"message\":\"No statement payload from bank";
        if (prefix.len > result_buf.len) return makeLengthPrefixed("{\"status\":\"error\",\"message\":\"No statement payload from bank\"}");
        @memcpy(result_buf[pos .. pos + prefix.len], prefix);
        pos += prefix.len;

        if (resp.code_count > 0) {
            var selected_idx: usize = 0;
            var found_non_success = false;
            for (resp.codes[0..resp.code_count], 0..) |*c, i| {
                if (!c.isSuccess()) {
                    selected_idx = i;
                    found_non_success = true;
                    break;
                }
            }
            if (!found_non_success) selected_idx = resp.code_count - 1;
            const selected = resp.codes[selected_idx];

            const middle = " (";
            if (pos + middle.len <= result_buf.len) {
                @memcpy(result_buf[pos .. pos + middle.len], middle);
                pos += middle.len;
            }

            const code = selected.codeSlice();
            if (pos + code.len <= result_buf.len) {
                @memcpy(result_buf[pos .. pos + code.len], code);
                pos += code.len;
            }

            const sep = ": ";
            if (pos + sep.len <= result_buf.len) {
                @memcpy(result_buf[pos .. pos + sep.len], sep);
                pos += sep.len;
            }

            pos += db_mod.jsonEscapeString(result_buf[pos..], selected.textSlice()) orelse 0;

            const close = ")";
            if (pos + close.len <= result_buf.len) {
                @memcpy(result_buf[pos .. pos + close.len], close);
                pos += close.len;
            }
        }

        const suffix = "\"}";
        if (pos + suffix.len > result_buf.len) return makeLengthPrefixed("{\"status\":\"error\",\"message\":\"No statement payload from bank\"}");
        @memcpy(result_buf[pos .. pos + suffix.len], suffix);
        pos += suffix.len;

        return makeLengthPrefixed(result_buf[0..pos]);
    }

    if (!is_wasm) {
        if (used_camt_fallback) {
            dbg.print("[FinTS Zig] fetch fallback used: HKCAZ/HICAZ path\n", .{});
        }
        dbg.print("[FinTS Zig] fetch hkkaz import result imported={d}, duplicates={d}\n", .{ imported, duplicates });
    }

    // Auto-create account entry
    database.ensureAccount(account_name, account_name, "#4361ee") catch {};

    // Persist the statement closing balance so the UI can show a real account
    // balance instead of a meaningless sum of fetched transactions.
    if (balance_date_int > 0) {
        var date_buf: [10]u8 = undefined;
        const y = balance_date_int / 10000;
        const m = (balance_date_int / 100) % 100;
        const d = balance_date_int % 100;
        const date_str = std.fmt.bufPrint(&date_buf, "{d:0>4}-{d:0>2}-{d:0>2}", .{ y, m, d }) catch "";
        if (date_str.len > 0) {
            database.setAccountBalance(account_name, balance_cents, date_str) catch {};
        }
    }

    // End dialog
    _ = sendDialogEnd(&fints_session, fints_session.tanSecFuncSlice(), &msg_buf, &resp_buf);
    fints_session.clearPin();

    var result_buf: [256]u8 = undefined;
    const result_json = std.fmt.bufPrint(&result_buf, "{{\"imported\":{d},\"duplicates\":{d}}}", .{ imported, duplicates }) catch return null;
    return makeLengthPrefixed(result_json);
}

/// Get the list of supported banks as JSON.
/// Returns length-prefixed JSON array.
fn wimg_fints_get_banks() callconv(.c) ?[*]const u8 {
    if (is_wasm) return null;

    var buf: [262144]u8 = undefined; // 256KB — ~1750 banks × ~140 bytes each
    const len = banks_mod.toJson(&buf) orelse {
        setError("wimg_fints_get_banks: buffer too small", .{});
        return null;
    };
    return makeLengthPrefixed(buf[0..len]);
}

/// Fetch available TAN media from the bank via HKTAB.
/// Requires an active session (call wimg_fints_connect first).
/// Returns length-prefixed JSON object:
/// - success: {"status":"ok","media":[{"name":"...","status":1},...]}
/// - error:   {"status":"error","message":"..."}
fn wimg_fints_get_tan_media() callconv(.c) ?[*]const u8 {
    if (is_wasm) return null;

    if (!fints_session.tan_medium_required) {
        // Bank does not require TAN medium selection.
        return makeLengthPrefixed("{\"status\":\"ok\",\"media\":[]}");
    }

    if (fints_session.pin_len == 0) {
        return makeLengthPrefixed("{\"status\":\"error\",\"message\":\"PIN missing in session, please reconnect\"}");
    }

    var msg_buf: [8192]u8 = undefined;
    var resp_buf: [65536]u8 = undefined;

    // Build and send HKTAB request
    const msg_len = fints_mod.buildFetchTanMedia(&fints_session, &msg_buf) orelse {
        setError("wimg_fints_get_tan_media: failed to build HKTAB message", .{});
        return makeLengthPrefixed("{\"status\":\"error\",\"message\":\"Failed to build HKTAB message\"}");
    };

    const resp_len = fints_http_mod.sendFintsMessage(
        std.heap.page_allocator,
        fints_session.urlSlice(),
        msg_buf[0..msg_len],
        &resp_buf,
    ) catch {
        setError("wimg_fints_get_tan_media: HTTP request failed", .{});
        return makeLengthPrefixed("{\"status\":\"error\",\"message\":\"HKTAB HTTP request failed\"}");
    };

    var resp = fints_mod.ParsedResponse.init();
    fints_mod.parseResponse(&fints_session, resp_buf[0..resp_len], &resp);
    fints_session.msg_num += 1;

    if (!is_wasm) {
        dbg.print("[FinTS Zig] HKTAB resp: tan_media_count={d}\n", .{resp.tan_media_count});
    }

    // Build JSON object with TAN media array
    var json_buf: [3072]u8 = undefined;
    var json_pos: usize = 0;
    const prefix = "{\"status\":\"ok\",\"media\":[";
    if (prefix.len > json_buf.len) return makeLengthPrefixed("{\"status\":\"error\",\"message\":\"Internal buffer overflow\"}");
    @memcpy(json_buf[json_pos .. json_pos + prefix.len], prefix);
    json_pos += prefix.len;

    for (resp.tan_media[0..resp.tan_media_count], 0..) |*media, i| {
        if (i > 0) {
            json_buf[json_pos] = ',';
            json_pos += 1;
        }
        const entry_prefix = "{\"name\":\"";
        if (json_pos + entry_prefix.len >= json_buf.len) break;
        @memcpy(json_buf[json_pos .. json_pos + entry_prefix.len], entry_prefix);
        json_pos += entry_prefix.len;
        json_pos += db_mod.jsonEscapeString(json_buf[json_pos..], media.nameSlice()) orelse 0;
        const entry_suffix = "\",\"status\":";
        if (json_pos + entry_suffix.len >= json_buf.len) break;
        @memcpy(json_buf[json_pos .. json_pos + entry_suffix.len], entry_suffix);
        json_pos += entry_suffix.len;
        const status_text = std.fmt.bufPrint(json_buf[json_pos..], "{d}", .{media.status}) catch break;
        json_pos += status_text.len;
        if (json_pos >= json_buf.len) break;
        json_buf[json_pos] = '}';
        json_pos += 1;
    }

    const close = "]}";
    if (json_pos + close.len > json_buf.len) return makeLengthPrefixed("{\"status\":\"error\",\"message\":\"Internal buffer overflow\"}");
    @memcpy(json_buf[json_pos .. json_pos + close.len], close);
    json_pos += close.len;

    return makeLengthPrefixed(json_buf[0..json_pos]);
}

/// Set the selected TAN medium name in the session.
/// Input JSON: {"name":"iPhone von Max"}
/// This must be called before wimg_fints_fetch if the bank requires medium selection.
fn wimg_fints_set_tan_medium(data: [*]const u8, len: u32) callconv(.c) ?[*]const u8 {
    if (is_wasm) return null;

    const json = data[0..len];
    const name = jsonExtractString(json, "\"name\"") orelse {
        return makeLengthPrefixed("{\"status\":\"error\",\"message\":\"Missing name field\"}");
    };

    const n_len = @min(name.len, fints_session.tan_medium_name.len);
    @memcpy(fints_session.tan_medium_name[0..n_len], name[0..n_len]);
    fints_session.tan_medium_name_len = @intCast(n_len);

    if (!is_wasm) {
        dbg.print("[FinTS Zig] TAN medium set to '{s}'\n", .{fints_session.tan_medium_name[0..n_len]});
    }

    return makeLengthPrefixed("{\"status\":\"ok\"}");
}

// --- Helpers ---

fn makeLengthPrefixed(data: []const u8) ?[*]const u8 {
    const out = fba.allocator().alloc(u8, data.len + 5) catch return null;
    const len_bytes: [4]u8 = @bitCast(@as(u32, @intCast(data.len)));
    out[0] = len_bytes[0];
    out[1] = len_bytes[1];
    out[2] = len_bytes[2];
    out[3] = len_bytes[3];
    @memcpy(out[4 .. 4 + data.len], data);
    out[4 + data.len] = 0;
    return out.ptr;
}

fn formatImportResultEx(buf: *[512]u8, result: *const ImportResult, format: parser.CsvFormat, categorized: u32) ?usize {
    const template = "{{\"total_rows\":{d},\"imported\":{d},\"skipped_duplicates\":{d},\"errors\":{d},\"format\":\"{s}\",\"categorized\":{d}}}";
    const slice = std.fmt.bufPrint(buf, template, .{
        result.total_rows,
        result.imported,
        result.skipped_duplicates,
        result.errors,
        format.name(),
        categorized,
    }) catch return null;
    return slice.len;
}

// --- Simple JSON field extractors (no allocator needed) ---

fn jsonExtractString(json: []const u8, key: []const u8) ?[]const u8 {
    // Find key position
    const key_pos = findSubstring(json, key) orelse return null;
    var i = key_pos + key.len;

    // Skip whitespace and colon
    while (i < json.len and (json[i] == ' ' or json[i] == ':' or json[i] == '\t')) : (i += 1) {}

    // Expect opening quote
    if (i >= json.len or json[i] != '"') return null;
    i += 1;

    // Find closing quote (no escape handling needed for simple IDs/names)
    const start = i;
    while (i < json.len and json[i] != '"') : (i += 1) {}
    if (i >= json.len) return null;

    return json[start..i];
}

fn jsonExtractNumber(json: []const u8, key: []const u8) ?i64 {
    const key_pos = findSubstring(json, key) orelse return null;
    var i = key_pos + key.len;

    while (i < json.len and (json[i] == ' ' or json[i] == ':' or json[i] == '\t')) : (i += 1) {}

    // Parse number (may be decimal like 1234.56, convert to cents)
    var negative = false;
    if (i < json.len and json[i] == '-') {
        negative = true;
        i += 1;
    }

    var whole: i64 = 0;
    while (i < json.len and json[i] >= '0' and json[i] <= '9') : (i += 1) {
        whole = whole * 10 + (json[i] - '0');
    }

    var frac: i64 = 0;
    var frac_digits: u8 = 0;
    if (i < json.len and json[i] == '.') {
        i += 1;
        while (i < json.len and json[i] >= '0' and json[i] <= '9' and frac_digits < 2) : (i += 1) {
            frac = frac * 10 + (json[i] - '0');
            frac_digits += 1;
        }
    }
    if (frac_digits == 1) frac *= 10;

    var cents = whole * 100 + frac;
    if (negative) cents = -cents;
    return cents;
}

fn findSubstring(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0) return 0;
    if (haystack.len < needle.len) return null;
    const limit = haystack.len - needle.len + 1;
    for (0..limit) |i| {
        if (std.mem.eql(u8, haystack[i .. i + needle.len], needle)) return i;
    }
    return null;
}

const AccountInfo = struct { id: []const u8, name: []const u8, color: []const u8 };

fn accountInfoForFormat(format: parser.CsvFormat) AccountInfo {
    return switch (format) {
        .comdirect => .{ .id = "comdirect", .name = "Comdirect", .color = "#f5a623" },
        .trade_republic => .{ .id = "trade_republic", .name = "Trade Republic", .color = "#1a1a2e" },
        .scalable_capital => .{ .id = "scalable_capital", .name = "Scalable Capital", .color = "#6c5ce7" },
        .unknown => .{ .id = "unknown", .name = "Unbekannt", .color = "#4361ee" },
    };
}

test "extractTouchdownToken prefers structured parameter field" {
    var resp = fints_mod.ParsedResponse.init();
    resp.code_count = 1;
    @memcpy(resp.codes[0].code[0..4], "3040");
    @memcpy(resp.codes[0].parameter[0..8], "TD123456");
    resp.codes[0].parameter_len = 8;
    const text = "Weitere Daten folgen:ALT";
    @memcpy(resp.codes[0].text[0..text.len], text);
    resp.codes[0].text_len = @intCast(text.len);

    var out: [64]u8 = undefined;
    const tok = extractTouchdownToken(&resp, &out);
    try std.testing.expectEqualStrings("TD123456", tok);
}

test "extractTouchdownToken parses token from localized text fallback" {
    var resp = fints_mod.ParsedResponse.init();
    resp.code_count = 1;
    @memcpy(resp.codes[0].code[0..4], "3040");
    const text = "Weitere Daten folgen, Aufsetzpunkt: ABCD-01";
    @memcpy(resp.codes[0].text[0..text.len], text);
    resp.codes[0].text_len = @intCast(text.len);

    var out: [64]u8 = undefined;
    const tok = extractTouchdownToken(&resp, &out);
    try std.testing.expectEqualStrings("ABCD-01", tok);
}

test "extractTouchdownToken ignores non-token text" {
    var resp = fints_mod.ParsedResponse.init();
    resp.code_count = 1;
    @memcpy(resp.codes[0].code[0..4], "3040");
    const text = "Weitere Daten folgen";
    @memcpy(resp.codes[0].text[0..text.len], text);
    resp.codes[0].text_len = @intCast(text.len);

    var out: [64]u8 = undefined;
    const tok = extractTouchdownToken(&resp, &out);
    try std.testing.expectEqual(@as(usize, 0), tok.len);
}

test "selectTanSecFuncFromSync maps photoTAN label to 902" {
    var s = fints_mod.FintsSession.init("20041177", "https://x.de/f", "u", "p");
    @memcpy(s.tan_sec_func[0..3], "999");
    s.tan_sec_func_len = 3;

    var resp = fints_mod.ParsedResponse.init();
    resp.code_count = 1;
    @memcpy(resp.codes[0].code[0..4], "3920");
    const txt = "Verfuegbare TAN-Verfahren?: photoTAN.";
    @memcpy(resp.codes[0].text[0..txt.len], txt);
    resp.codes[0].text_len = @intCast(txt.len);

    selectTanSecFuncFromSync(&resp, &s);
    try std.testing.expectEqualStrings("902", s.tanSecFuncSlice());
}
