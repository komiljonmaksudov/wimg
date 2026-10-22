const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const categories = @import("categories.zig");
const c = @import("sqlite_c.zig");

const Transaction = types.Transaction;
const Date = types.Date;
const Category = types.Category;
const ImportResult = types.ImportResult;

// Time: on WASM, import from JS host; on native, call libc gettimeofday
// directly to avoid threading an Io instance through every call site.
const is_wasm = builtin.cpu.arch == .wasm32;
extern fn js_time_ms() i64;

pub fn nowMs() i64 {
    if (is_wasm) {
        return js_time_ms();
    } else {
        var tv: std.c.timeval = undefined;
        _ = std.c.gettimeofday(&tv, null);
        return @as(i64, tv.sec) * 1000 + @divTrunc(@as(i64, tv.usec), 1000);
    }
}

pub const DbError = error{
    OpenFailed,
    ExecFailed,
    PrepareFailed,
    BindFailed,
    StepFailed,
};

const CURRENT_SCHEMA_VERSION = 15;
const MAX_UNDO_ENTRIES = 50;

pub const Db = struct {
    handle: *c.sqlite3,

    const schema_sql =
        \\CREATE TABLE IF NOT EXISTS transactions (
        \\  id TEXT PRIMARY KEY,
        \\  date_year INTEGER NOT NULL,
        \\  date_month INTEGER NOT NULL,
        \\  date_day INTEGER NOT NULL,
        \\  description TEXT NOT NULL,
        \\  amount_cents INTEGER NOT NULL,
        \\  currency TEXT NOT NULL DEFAULT 'EUR',
        \\  category INTEGER NOT NULL DEFAULT 0,
        \\  account TEXT NOT NULL DEFAULT '',
        \\  excluded INTEGER NOT NULL DEFAULT 0,
        \\  updated_at INTEGER NOT NULL DEFAULT 0
        \\);
        \\CREATE INDEX IF NOT EXISTS idx_transactions_date
        \\  ON transactions(date_year, date_month, date_day);
        \\CREATE TABLE IF NOT EXISTS meta (
        \\  key TEXT PRIMARY KEY,
        \\  value TEXT NOT NULL
        \\);
        \\CREATE TABLE IF NOT EXISTS rules (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  pattern TEXT NOT NULL,
        \\  category INTEGER NOT NULL,
        \\  priority INTEGER NOT NULL DEFAULT 0,
        \\  updated_at INTEGER NOT NULL DEFAULT 0
        \\);
        \\CREATE TABLE IF NOT EXISTS debts (
        \\  id TEXT PRIMARY KEY,
        \\  name TEXT NOT NULL,
        \\  total INTEGER NOT NULL,
        \\  paid INTEGER NOT NULL DEFAULT 0,
        \\  monthly INTEGER NOT NULL DEFAULT 0,
        \\  deleted INTEGER NOT NULL DEFAULT 0,
        \\  updated_at INTEGER NOT NULL DEFAULT 0
        \\);
        \\CREATE TABLE IF NOT EXISTS accounts (
        \\  id TEXT PRIMARY KEY,
        \\  name TEXT NOT NULL,
        \\  bank TEXT NOT NULL DEFAULT '',
        \\  color TEXT NOT NULL DEFAULT '#4361ee',
        \\  deleted INTEGER NOT NULL DEFAULT 0,
        \\  balance_cents INTEGER NOT NULL DEFAULT 0,
        \\  balance_date TEXT NOT NULL DEFAULT '',
        \\  updated_at INTEGER NOT NULL DEFAULT 0
        \\);
        \\CREATE TABLE IF NOT EXISTS undo_history (
        \\  seq INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  op INTEGER NOT NULL,
        \\  tbl TEXT NOT NULL,
        \\  row_id TEXT NOT NULL,
        \\  col TEXT,
        \\  old_val TEXT,
        \\  new_val TEXT,
        \\  undone INTEGER NOT NULL DEFAULT 0
        \\);
        \\CREATE TABLE IF NOT EXISTS recurring_patterns (
        \\  id TEXT PRIMARY KEY,
        \\  merchant TEXT NOT NULL,
        \\  amount INTEGER NOT NULL,
        \\  interval TEXT NOT NULL,
        \\  category INTEGER NOT NULL DEFAULT 0,
        \\  last_seen TEXT NOT NULL,
        \\  next_due TEXT,
        \\  active INTEGER NOT NULL DEFAULT 1,
        \\  prev_amount INTEGER,
        \\  updated_at INTEGER NOT NULL DEFAULT 0
        \\);
        \\CREATE TABLE IF NOT EXISTS snapshots (
        \\  id TEXT PRIMARY KEY,
        \\  date TEXT NOT NULL,
        \\  net_worth INTEGER NOT NULL DEFAULT 0,
        \\  income INTEGER NOT NULL DEFAULT 0,
        \\  expenses INTEGER NOT NULL DEFAULT 0,
        \\  tx_count INTEGER NOT NULL DEFAULT 0,
        \\  breakdown TEXT NOT NULL DEFAULT '[]',
        \\  updated_at INTEGER NOT NULL DEFAULT 0
        \\);
        \\CREATE TABLE IF NOT EXISTS savings_goals (
        \\  id TEXT PRIMARY KEY,
        \\  name TEXT NOT NULL,
        \\  icon TEXT NOT NULL DEFAULT '🎯',
        \\  target INTEGER NOT NULL,
        \\  current INTEGER NOT NULL DEFAULT 0,
        \\  deadline TEXT,
        \\  deleted INTEGER NOT NULL DEFAULT 0,
        \\  updated_at INTEGER NOT NULL DEFAULT 0
        \\);
    ;

    pub fn init(path: [*:0]const u8) DbError!Db {
        var handle: ?*c.sqlite3 = null;
        const rc = c.sqlite3_open(path, &handle);
        if (rc != c.SQLITE_OK or handle == null) {
            if (handle) |h| _ = c.sqlite3_close(h);
            return DbError.OpenFailed;
        }

        var self = Db{ .handle = handle.? };
        try self.exec(schema_sql);

        // Enable WAL mode for better concurrent reads
        self.exec("PRAGMA journal_mode=WAL;") catch {};

        // Run migrations for existing databases
        try self.migrate();

        return self;
    }

    fn migrate(self: *Db) DbError!void {
        const version = self.getMetaInt("schema_version") orelse 0;

        if (version < 1) {
            // v1: add updated_at to transactions (may already exist from fresh schema)
            self.exec("ALTER TABLE transactions ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0;") catch {};
        }

        if (version < 2) {
            // v2: seed default categorization rules
            self.seedDefaultRules() catch {};
        }

        if (version < 3) {
            // v3: undo_history table
            self.exec(
                \\CREATE TABLE IF NOT EXISTS undo_history (
                \\  seq INTEGER PRIMARY KEY AUTOINCREMENT,
                \\  op INTEGER NOT NULL,
                \\  tbl TEXT NOT NULL,
                \\  row_id TEXT NOT NULL,
                \\  col TEXT,
                \\  old_val TEXT,
                \\  new_val TEXT,
                \\  undone INTEGER NOT NULL DEFAULT 0
                \\);
            ) catch {};
        }

        if (version < 4) {
            // v4: multi-account support
            self.exec("ALTER TABLE transactions ADD COLUMN account TEXT NOT NULL DEFAULT '';") catch {};
            self.exec(
                \\CREATE TABLE IF NOT EXISTS accounts (
                \\  id TEXT PRIMARY KEY,
                \\  name TEXT NOT NULL,
                \\  bank TEXT NOT NULL DEFAULT '',
                \\  color TEXT NOT NULL DEFAULT '#4361ee',
                \\  updated_at INTEGER NOT NULL DEFAULT 0
                \\);
            ) catch {};
        }

        if (version < 5) {
            // v5: exclude/hide transactions from summaries
            self.exec("ALTER TABLE transactions ADD COLUMN excluded INTEGER NOT NULL DEFAULT 0;") catch {};
        }

        if (version < 6) {
            // v6: stamp real timestamps on rows that still have updated_at=0
            // (pre-sync era data). Required for sync to work (Worker filters updated_at > 0).
            const now = nowMs();
            const tables = [_][*:0]const u8{
                "UPDATE transactions SET updated_at = ?1 WHERE updated_at = 0;",
                "UPDATE debts SET updated_at = ?1 WHERE updated_at = 0;",
                "UPDATE accounts SET updated_at = ?1 WHERE updated_at = 0;",
                "UPDATE rules SET updated_at = ?1 WHERE updated_at = 0;",
            };
            for (tables) |sql| {
                var stmt: ?*c.sqlite3_stmt = null;
                if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) == c.SQLITE_OK) {
                    if (stmt) |s| {
                        _ = c.sqlite3_bind_int64(s, 1, now);
                        _ = c.sqlite3_step(s);
                        _ = c.sqlite3_finalize(s);
                    }
                }
            }
        }

        if (version < 7) {
            // v7: soft-delete for debts and accounts (needed for sync)
            self.exec("ALTER TABLE debts ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0;") catch {};
            self.exec("ALTER TABLE accounts ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0;") catch {};
        }

        if (version < 8) {
            // v8: recurring payment detection
            self.exec(
                \\CREATE TABLE IF NOT EXISTS recurring_patterns (
                \\  id TEXT PRIMARY KEY,
                \\  merchant TEXT NOT NULL,
                \\  amount INTEGER NOT NULL,
                \\  interval TEXT NOT NULL,
                \\  category INTEGER NOT NULL DEFAULT 0,
                \\  last_seen TEXT NOT NULL,
                \\  next_due TEXT,
                \\  active INTEGER NOT NULL DEFAULT 1,
                \\  prev_amount INTEGER,
                \\  updated_at INTEGER NOT NULL DEFAULT 0
                \\);
            ) catch {};
        }

        if (version < 9) {
            // v9: monthly snapshots for historical data
            self.exec(
                \\CREATE TABLE IF NOT EXISTS snapshots (
                \\  id TEXT PRIMARY KEY,
                \\  date TEXT NOT NULL,
                \\  net_worth INTEGER NOT NULL DEFAULT 0,
                \\  income INTEGER NOT NULL DEFAULT 0,
                \\  expenses INTEGER NOT NULL DEFAULT 0,
                \\  tx_count INTEGER NOT NULL DEFAULT 0,
                \\  breakdown TEXT NOT NULL DEFAULT '[]',
                \\  updated_at INTEGER NOT NULL DEFAULT 0
                \\);
            ) catch {};
        }

        if (version < 13) {
            // v13: remove embeddings table (Phase 5.9 — embeddings removed)
            self.exec("DROP TABLE IF EXISTS embeddings;") catch {};
        }

        if (version < 14) {
            // v14: savings goals (Phase 6.4)
            self.exec(
                \\CREATE TABLE IF NOT EXISTS savings_goals (
                \\  id TEXT PRIMARY KEY,
                \\  name TEXT NOT NULL,
                \\  icon TEXT NOT NULL DEFAULT '🎯',
                \\  target INTEGER NOT NULL,
                \\  current INTEGER NOT NULL DEFAULT 0,
                \\  deadline TEXT,
                \\  deleted INTEGER NOT NULL DEFAULT 0,
                \\  updated_at INTEGER NOT NULL DEFAULT 0
                \\);
            ) catch {};
        }

        if (version < 15) {
            // v15: per-account balance from FinTS statement closing balance
            self.exec("ALTER TABLE accounts ADD COLUMN balance_cents INTEGER NOT NULL DEFAULT 0;") catch {};
            self.exec("ALTER TABLE accounts ADD COLUMN balance_date TEXT NOT NULL DEFAULT '';") catch {};
        }

        // Store current version
        if (version < CURRENT_SCHEMA_VERSION) {
            self.setMeta("schema_version", "15") catch {};
        }
    }

    pub fn getMetaInt(self: *Db, key: [*:0]const u8) ?i32 {
        const sql = "SELECT value FROM meta WHERE key = ?1;";
        var stmt: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK or stmt == null) return null;
        defer _ = c.sqlite3_finalize(stmt.?);

        const s = stmt.?;
        if (c.sqlite3_bind_text(s, 1, key, -1, c.SQLITE_STATIC) != c.SQLITE_OK) return null;

        if (c.sqlite3_step(s) != c.SQLITE_ROW) return null;

        const val_ptr = c.sqlite3_column_text(s, 0) orelse return null;
        const val_len: usize = @intCast(c.sqlite3_column_bytes(s, 0));
        const val = val_ptr[0..val_len];

        // Parse integer from string
        var result: i32 = 0;
        for (val) |ch| {
            if (ch >= '0' and ch <= '9') {
                result = result * 10 + @as(i32, ch - '0');
            }
        }
        return result;
    }

    pub fn setMeta(self: *Db, key: [*:0]const u8, value: [*:0]const u8) DbError!void {
        const sql = "INSERT OR REPLACE INTO meta (key, value) VALUES (?1, ?2);";
        var stmt: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);

        const s = stmt.?;
        if (c.sqlite3_bind_text(s, 1, key, -1, c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 2, value, -1, c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;
    }

    fn seedDefaultRules(self: *Db) DbError!void {
        const rules = [_]struct { pattern: [*:0]const u8, category: u8, priority: u8 }{
            // Groceries (1)
            .{ .pattern = "REWE", .category = 1, .priority = 10 },
            .{ .pattern = "LIDL", .category = 1, .priority = 10 },
            .{ .pattern = "ALDI", .category = 1, .priority = 10 },
            .{ .pattern = "EDEKA", .category = 1, .priority = 10 },
            .{ .pattern = "NETTO", .category = 1, .priority = 10 },
            .{ .pattern = "PENNY", .category = 1, .priority = 10 },
            .{ .pattern = "KAUFLAND", .category = 1, .priority = 10 },
            // Dining (2)
            .{ .pattern = "LIEFERANDO", .category = 2, .priority = 10 },
            .{ .pattern = "MCDONALD", .category = 2, .priority = 10 },
            .{ .pattern = "BURGER KING", .category = 2, .priority = 10 },
            // Transport (3)
            .{ .pattern = "DB VERTRIEB", .category = 3, .priority = 10 },
            .{ .pattern = "DEUTSCHE BAHN", .category = 3, .priority = 10 },
            .{ .pattern = "SHELL", .category = 3, .priority = 5 },
            .{ .pattern = "ARAL", .category = 3, .priority = 5 },
            .{ .pattern = "TIER", .category = 3, .priority = 5 },
            // Housing (4)
            .{ .pattern = "MIETE", .category = 4, .priority = 20 },
            // Utilities (5)
            .{ .pattern = "STROM", .category = 5, .priority = 15 },
            .{ .pattern = "WSW", .category = 5, .priority = 15 },
            .{ .pattern = "STADTWERKE", .category = 5, .priority = 15 },
            .{ .pattern = "VODAFONE", .category = 5, .priority = 10 },
            .{ .pattern = "TELEKOM", .category = 5, .priority = 10 },
            .{ .pattern = "O2", .category = 5, .priority = 10 },
            // Entertainment (6)
            .{ .pattern = "SPOTIFY", .category = 6, .priority = 10 },
            .{ .pattern = "KINO", .category = 6, .priority = 10 },
            // Shopping (7)
            .{ .pattern = "AMAZON", .category = 7, .priority = 5 },
            .{ .pattern = "ZALANDO", .category = 7, .priority = 10 },
            .{ .pattern = "IKEA", .category = 7, .priority = 10 },
            .{ .pattern = "DM DROGERIE", .category = 7, .priority = 10 },
            .{ .pattern = "ROSSMANN", .category = 7, .priority = 10 },
            // Health (8)
            .{ .pattern = "APOTHEKE", .category = 8, .priority = 10 },
            .{ .pattern = "ARZT", .category = 8, .priority = 10 },
            // Insurance (9)
            .{ .pattern = "VERSICHERUNG", .category = 9, .priority = 10 },
            .{ .pattern = "ALLIANZ", .category = 9, .priority = 10 },
            .{ .pattern = "HUK", .category = 9, .priority = 10 },
            // Income (10)
            .{ .pattern = "GEHALT", .category = 10, .priority = 20 },
            .{ .pattern = "LOHN", .category = 10, .priority = 20 },
            // Subscriptions (13)
            .{ .pattern = "NETFLIX", .category = 13, .priority = 10 },
            .{ .pattern = "DISNEY", .category = 13, .priority = 10 },
            .{ .pattern = "APPLE.COM", .category = 13, .priority = 10 },
            .{ .pattern = "GOOGLE STORAGE", .category = 13, .priority = 10 },
            // Education (15)
            .{ .pattern = "FOM", .category = 15, .priority = 15 },
        };

        const sql = "INSERT OR IGNORE INTO rules (pattern, category, priority) VALUES (?1, ?2, ?3);";
        var stmt: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);

        const s = stmt.?;
        for (rules) |rule| {
            _ = c.sqlite3_reset(s);
            if (c.sqlite3_bind_text(s, 1, rule.pattern, -1, c.SQLITE_STATIC) != c.SQLITE_OK) continue;
            if (c.sqlite3_bind_int(s, 2, @intCast(rule.category)) != c.SQLITE_OK) continue;
            if (c.sqlite3_bind_int(s, 3, @intCast(rule.priority)) != c.SQLITE_OK) continue;
            _ = c.sqlite3_step(s);
        }
    }

    pub fn close(self: *Db) void {
        _ = c.sqlite3_close(self.handle);
    }

    fn exec(self: *Db, sql: [*:0]const u8) DbError!void {
        const rc = c.sqlite3_exec(self.handle, sql, null, null, null);
        if (rc != c.SQLITE_OK) return DbError.ExecFailed;
    }

    /// Run arbitrary SQL and write JSON result to buf. Returns bytes written, or null if buf too small.
    pub fn rawQuery(self: *Db, sql: [*:0]const u8, buf: [*]u8, buf_size: usize) DbError!?usize {
        var stmt: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);

        const s = stmt.?;
        const col_count: usize = @intCast(c.sqlite3_column_count(s));

        // Collect column names
        var col_names: [64][*:0]const u8 = undefined;
        const cols = @min(col_count, 64);
        for (0..cols) |i| {
            col_names[i] = c.sqlite3_column_name(s, @intCast(i)) orelse "?";
        }

        var w_storage = std.Io.Writer.fixed(buf[0..buf_size]);
        const w = &w_storage;

        w.writeAll("{\"columns\":[") catch return null;
        for (0..cols) |i| {
            if (i > 0) w.writeByte(',') catch return null;
            w.writeByte('"') catch return null;
            w.writeAll(std.mem.span(col_names[i])) catch return null;
            w.writeByte('"') catch return null;
        }
        w.writeAll("],\"rows\":[") catch return null;

        var row_idx: usize = 0;
        const max_rows: usize = 500;
        while (c.sqlite3_step(s) == c.SQLITE_ROW) {
            if (row_idx >= max_rows) break;
            if (row_idx > 0) w.writeByte(',') catch return null;
            w.writeByte('[') catch return null;
            for (0..cols) |i| {
                if (i > 0) w.writeByte(',') catch return null;
                const col_type = c.sqlite3_column_type(s, @intCast(i));
                if (col_type == c.SQLITE_NULL) {
                    w.writeAll("null") catch return null;
                } else if (col_type == 1) { // INTEGER
                    const v = c.sqlite3_column_int64(s, @intCast(i));
                    w.print("{d}", .{v}) catch return null;
                } else if (col_type == 2) { // FLOAT
                    const v = c.sqlite3_column_double(s, @intCast(i));
                    w.print("{d}", .{v}) catch return null;
                } else if (col_type == 4) { // SQLITE_BLOB
                    const len: usize = @intCast(c.sqlite3_column_bytes(s, @intCast(i)));
                    w.print("\"<BLOB {d} bytes>\"", .{len}) catch return null;
                } else { // TEXT
                    const ptr = c.sqlite3_column_text(s, @intCast(i));
                    const len: usize = @intCast(c.sqlite3_column_bytes(s, @intCast(i)));
                    w.writeByte('"') catch return null;
                    if (ptr) |p| {
                        // Escape JSON special chars
                        const text = p[0..len];
                        for (text) |ch| {
                            switch (ch) {
                                '"' => w.writeAll("\\\"") catch return null,
                                '\\' => w.writeAll("\\\\") catch return null,
                                '\n' => w.writeAll("\\n") catch return null,
                                '\r' => w.writeAll("\\r") catch return null,
                                '\t' => w.writeAll("\\t") catch return null,
                                else => {
                                    if (ch < 0x20) {
                                        // Escape control characters as \u00XX
                                        w.print("\\u{d:0>4}", .{@as(u16, ch)}) catch return null;
                                    } else {
                                        w.writeByte(ch) catch return null;
                                    }
                                },
                            }
                        }
                    }
                    w.writeByte('"') catch return null;
                }
            }
            w.writeByte(']') catch return null;
            row_idx += 1;
        }

        w.writeAll("]") catch return null;
        // Add row count + truncated flag
        w.print(",\"count\":{d},\"truncated\":{s}}}", .{ row_idx, if (row_idx >= max_rows) "true" else "false" }) catch return null;

        return w.end;
    }

    /// Get the last SQLite error message
    pub fn lastError(self: *Db) ?[*:0]const u8 {
        return c.sqlite3_errmsg(self.handle);
    }

    pub fn insertTransaction(self: *Db, txn: *const Transaction) DbError!bool {
        const sql =
            \\INSERT OR IGNORE INTO transactions
            \\  (id, date_year, date_month, date_day, description, amount_cents, currency, category, account, updated_at)
            \\VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10);
        ;

        var stmt: ?*c.sqlite3_stmt = null;
        var rc = c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK or stmt == null) {
            return DbError.PrepareFailed;
        }
        defer _ = c.sqlite3_finalize(stmt.?);

        const s = stmt.?;

        // Bind id (hex hash string)
        rc = c.sqlite3_bind_text(s, 1, &txn.id, 32, c.SQLITE_STATIC);
        if (rc != c.SQLITE_OK) return DbError.BindFailed;

        rc = c.sqlite3_bind_int(s, 2, @intCast(txn.date.year));
        if (rc != c.SQLITE_OK) return DbError.BindFailed;

        rc = c.sqlite3_bind_int(s, 3, @intCast(txn.date.month));
        if (rc != c.SQLITE_OK) return DbError.BindFailed;

        rc = c.sqlite3_bind_int(s, 4, @intCast(txn.date.day));
        if (rc != c.SQLITE_OK) return DbError.BindFailed;

        rc = c.sqlite3_bind_text(s, 5, @ptrCast(&txn.description), @intCast(txn.description_len), c.SQLITE_STATIC);
        if (rc != c.SQLITE_OK) return DbError.BindFailed;

        rc = c.sqlite3_bind_int64(s, 6, @intCast(txn.amount_cents));
        if (rc != c.SQLITE_OK) return DbError.BindFailed;

        rc = c.sqlite3_bind_text(s, 7, &txn.currency, 3, c.SQLITE_STATIC);
        if (rc != c.SQLITE_OK) return DbError.BindFailed;

        rc = c.sqlite3_bind_int(s, 8, @intCast(@backingInt(txn.category)));
        if (rc != c.SQLITE_OK) return DbError.BindFailed;

        rc = c.sqlite3_bind_text(s, 9, @ptrCast(&txn.account), @intCast(txn.account_len), c.SQLITE_STATIC);
        if (rc != c.SQLITE_OK) return DbError.BindFailed;

        rc = c.sqlite3_bind_int64(s, 10, nowMs());
        if (rc != c.SQLITE_OK) return DbError.BindFailed;

        rc = c.sqlite3_step(s);
        if (rc != c.SQLITE_DONE) return DbError.StepFailed;

        // Returns true if row was inserted (not a duplicate)
        return c.sqlite3_changes(self.handle) > 0;
    }

    pub fn setCategory(self: *Db, id: [*]const u8, id_len: usize, category: u8) DbError!void {
        // Capture old category for undo history
        const old_cat = self.queryInt("SELECT category FROM transactions WHERE id = ?1;", id, id_len);

        const sql = "UPDATE transactions SET category = ?1, updated_at = ?3 WHERE id = ?2;";

        var stmt: ?*c.sqlite3_stmt = null;
        const rc0 = c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null);
        if (rc0 != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);

        const s = stmt.?;

        if (c.sqlite3_bind_int(s, 1, @intCast(category)) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 2, @ptrCast(id), @intCast(id_len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 3, nowMs()) != c.SQLITE_OK) return DbError.BindFailed;

        const rc = c.sqlite3_step(s);
        if (rc != c.SQLITE_DONE) return DbError.StepFailed;

        // Record history: UPDATE on transactions.category
        if (old_cat) |old| {
            var old_buf: [4]u8 = undefined;
            const old_len = formatInt(&old_buf, @as(u32, @intCast(old))) orelse return;
            var new_buf: [4]u8 = undefined;
            const new_len = formatInt(&new_buf, @as(u32, category)) orelse return;
            self.recordHistory(1, "transactions", id[0..id_len], "category", old_buf[0..old_len], new_buf[0..new_len]) catch {};
        }

        // Auto-learn: extract keyword from description, insert rule if new
        if (category != 0) {
            self.learnRule(id, id_len, category) catch {};
        }
    }

    /// Auto-learn a categorization rule from a manual user action.
    /// Extracts a merchant keyword from the transaction description and inserts
    /// a low-priority rule if no rule with that pattern already exists.
    fn learnRule(self: *Db, id: [*]const u8, id_len: usize, category: u8) DbError!void {
        // 1. Get description for this transaction
        const desc_sql = "SELECT description FROM transactions WHERE id = ?1;";
        var desc_stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, desc_sql, -1, &desc_stmt, null) != c.SQLITE_OK or desc_stmt == null)
            return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(desc_stmt.?);

        if (c.sqlite3_bind_text(desc_stmt.?, 1, @ptrCast(id), @intCast(id_len), c.SQLITE_STATIC) != c.SQLITE_OK)
            return DbError.BindFailed;
        if (c.sqlite3_step(desc_stmt.?) != c.SQLITE_ROW) return;

        const desc_ptr = c.sqlite3_column_text(desc_stmt.?, 0) orelse return;
        const desc_len: usize = @intCast(c.sqlite3_column_bytes(desc_stmt.?, 0));
        if (desc_len == 0) return;

        // 2. Extract merchant keyword
        const keyword = categories.extractKeyword(desc_ptr[0..desc_len]) orelse return;

        // 3. Check if a rule with this pattern already exists
        const check_sql = "SELECT COUNT(*) FROM rules WHERE pattern = ?1 COLLATE NOCASE;";
        var check_stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, check_sql, -1, &check_stmt, null) != c.SQLITE_OK or check_stmt == null)
            return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(check_stmt.?);

        if (c.sqlite3_bind_text(check_stmt.?, 1, @ptrCast(keyword.ptr), @intCast(keyword.len), c.SQLITE_STATIC) != c.SQLITE_OK)
            return DbError.BindFailed;
        if (c.sqlite3_step(check_stmt.?) == c.SQLITE_ROW) {
            if (c.sqlite3_column_int(check_stmt.?, 0) > 0) return; // rule exists
        }

        // 4. Insert learned rule with low priority (1) so seed rules always win
        const ins_sql = "INSERT INTO rules (pattern, category, priority, updated_at) VALUES (?1, ?2, 1, ?3);";
        var ins_stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, ins_sql, -1, &ins_stmt, null) != c.SQLITE_OK or ins_stmt == null)
            return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(ins_stmt.?);

        if (c.sqlite3_bind_text(ins_stmt.?, 1, @ptrCast(keyword.ptr), @intCast(keyword.len), c.SQLITE_STATIC) != c.SQLITE_OK)
            return DbError.BindFailed;
        if (c.sqlite3_bind_int(ins_stmt.?, 2, @intCast(category)) != c.SQLITE_OK)
            return DbError.BindFailed;
        if (c.sqlite3_bind_int64(ins_stmt.?, 3, nowMs()) != c.SQLITE_OK)
            return DbError.BindFailed;
        _ = c.sqlite3_step(ins_stmt.?);
    }

    /// Update category for a transaction by ID (32-byte hex), using prepared statement.
    pub fn setCategoryById(self: *Db, id: *const [32]u8, category: Category) DbError!void {
        const sql = "UPDATE transactions SET category = ?1 WHERE id = ?2;";

        var stmt: ?*c.sqlite3_stmt = null;
        const rc0 = c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null);
        if (rc0 != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);

        const s = stmt.?;
        if (c.sqlite3_bind_int(s, 1, @intCast(@backingInt(category))) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 2, id, 32, c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;
    }

    pub fn setExcluded(self: *Db, id: [*]const u8, id_len: usize, excluded: u8) DbError!void {
        // Capture old value for undo history
        const old_val = self.queryInt("SELECT excluded FROM transactions WHERE id = ?1;", id, id_len);

        const sql = "UPDATE transactions SET excluded = ?1, updated_at = ?3 WHERE id = ?2;";

        var stmt: ?*c.sqlite3_stmt = null;
        const rc0 = c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null);
        if (rc0 != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);

        const s = stmt.?;

        if (c.sqlite3_bind_int(s, 1, @intCast(excluded)) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 2, @ptrCast(id), @intCast(id_len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 3, nowMs()) != c.SQLITE_OK) return DbError.BindFailed;

        const rc = c.sqlite3_step(s);
        if (rc != c.SQLITE_DONE) return DbError.StepFailed;

        // Record history: UPDATE on transactions.excluded
        if (old_val) |old| {
            var old_buf: [4]u8 = undefined;
            const old_len = formatInt(&old_buf, @as(u32, @intCast(old))) orelse return;
            var new_buf: [4]u8 = undefined;
            const new_len = formatInt(&new_buf, @as(u32, excluded)) orelse return;
            self.recordHistory(1, "transactions", id[0..id_len], "excluded", old_buf[0..old_len], new_buf[0..new_len]) catch {};
        }
    }

    // --- Debts ---

    pub fn insertDebt(self: *Db, id: [*]const u8, id_len: u32, name: [*]const u8, name_len: u32, total: i64, monthly: i64) DbError!void {
        const sql = "INSERT OR REPLACE INTO debts (id, name, total, paid, monthly, updated_at) VALUES (?1, ?2, ?3, 0, ?4, ?5);";

        var stmt: ?*c.sqlite3_stmt = null;
        const rc0 = c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null);
        if (rc0 != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);

        const s = stmt.?;
        if (c.sqlite3_bind_text(s, 1, id, @intCast(id_len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 2, name, @intCast(name_len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 3, total) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 4, monthly) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 5, nowMs()) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;

        // Record history: INSERT on debts, new_val = debt JSON
        var val_buf: [512]u8 = undefined;
        const val_len = self.formatDebtJson(&val_buf, id[0..id_len], name[0..name_len], total, 0, monthly) orelse return;
        self.recordHistory(2, "debts", id[0..id_len], null, null, val_buf[0..val_len]) catch {};
    }

    pub fn markDebtPaid(self: *Db, id: [*]const u8, id_len: u32, amount: i64) DbError!void {
        // Capture old paid value for undo history
        const old_paid = self.queryInt64("SELECT paid FROM debts WHERE id = ?1;", id, id_len);

        const sql = "UPDATE debts SET paid = MIN(paid + ?1, total), updated_at = ?3 WHERE id = ?2;";

        var stmt: ?*c.sqlite3_stmt = null;
        const rc0 = c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null);
        if (rc0 != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);

        const s = stmt.?;
        if (c.sqlite3_bind_int64(s, 1, amount) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 2, id, @intCast(id_len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 3, nowMs()) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;

        // Record history: UPDATE on debts.paid
        if (old_paid) |old| {
            // Query new paid value
            const new_paid = self.queryInt64("SELECT paid FROM debts WHERE id = ?1;", id, id_len) orelse return;
            var old_buf: [20]u8 = undefined;
            const old_len = formatSignedInt(&old_buf, old) orelse return;
            var new_buf: [20]u8 = undefined;
            const new_len = formatSignedInt(&new_buf, new_paid) orelse return;
            self.recordHistory(1, "debts", id[0..id_len], "paid", old_buf[0..old_len], new_buf[0..new_len]) catch {};
        }
    }

    pub fn deleteDebt(self: *Db, id: [*]const u8, id_len: u32) DbError!void {
        // Capture full debt row for undo history before soft-deleting
        var old_buf: [512]u8 = undefined;
        const old_len = self.queryDebtJson(&old_buf, id, id_len);

        const sql = "UPDATE debts SET deleted = 1, updated_at = ?2 WHERE id = ?1;";

        var stmt: ?*c.sqlite3_stmt = null;
        const rc0 = c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null);
        if (rc0 != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);

        const s = stmt.?;
        if (c.sqlite3_bind_text(s, 1, id, @intCast(id_len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 2, nowMs()) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;

        // Record history: DELETE on debts, old_val = full debt JSON
        if (old_len) |ol| {
            self.recordHistory(3, "debts", id[0..id_len], null, old_buf[0..ol], null) catch {};
        }
    }

    // --- Savings Goals ---

    pub fn insertGoal(self: *Db, id: [*]const u8, id_len: u32, name: [*]const u8, name_len: u32, icon: [*]const u8, icon_len: u32, target: i64, deadline: ?[*]const u8, deadline_len: u32) DbError!void {
        const sql = "INSERT OR REPLACE INTO savings_goals (id, name, icon, target, current, deadline, updated_at) VALUES (?1, ?2, ?3, ?4, 0, ?5, ?6);";

        var stmt: ?*c.sqlite3_stmt = null;
        const rc0 = c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null);
        if (rc0 != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);

        const s = stmt.?;
        if (c.sqlite3_bind_text(s, 1, id, @intCast(id_len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 2, name, @intCast(name_len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 3, icon, @intCast(icon_len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 4, target) != c.SQLITE_OK) return DbError.BindFailed;
        if (deadline) |dl| {
            if (c.sqlite3_bind_text(s, 5, dl, @intCast(deadline_len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        } else {
            if (c.sqlite3_bind_null(s, 5) != c.SQLITE_OK) return DbError.BindFailed;
        }
        if (c.sqlite3_bind_int64(s, 6, nowMs()) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;

        // Record history: INSERT on savings_goals
        var val_buf: [512]u8 = undefined;
        const val_len = self.formatGoalJson(&val_buf, id[0..id_len], name[0..name_len], icon[0..icon_len], target, 0, if (deadline) |dl| dl[0..deadline_len] else null) orelse return;
        self.recordHistory(2, "savings_goals", id[0..id_len], null, null, val_buf[0..val_len]) catch {};
    }

    pub fn contributeGoal(self: *Db, id: [*]const u8, id_len: u32, amount: i64) DbError!void {
        // Capture old current value for undo history
        const old_current = self.queryInt64("SELECT current FROM savings_goals WHERE id = ?1;", id, id_len);

        const sql = "UPDATE savings_goals SET current = MIN(current + ?1, target), updated_at = ?3 WHERE id = ?2;";

        var stmt: ?*c.sqlite3_stmt = null;
        const rc0 = c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null);
        if (rc0 != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);

        const s = stmt.?;
        if (c.sqlite3_bind_int64(s, 1, amount) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 2, id, @intCast(id_len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 3, nowMs()) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;

        // Record history: UPDATE on savings_goals.current
        if (old_current) |old| {
            const new_current = self.queryInt64("SELECT current FROM savings_goals WHERE id = ?1;", id, id_len) orelse return;
            var old_buf: [20]u8 = undefined;
            const old_len = formatSignedInt(&old_buf, old) orelse return;
            var new_buf: [20]u8 = undefined;
            const new_len = formatSignedInt(&new_buf, new_current) orelse return;
            self.recordHistory(1, "savings_goals", id[0..id_len], "current", old_buf[0..old_len], new_buf[0..new_len]) catch {};
        }
    }

    pub fn deleteGoal(self: *Db, id: [*]const u8, id_len: u32) DbError!void {
        // Capture full goal row for undo history before soft-deleting
        var old_buf: [512]u8 = undefined;
        const old_len = self.queryGoalJson(&old_buf, id, id_len);

        const sql = "UPDATE savings_goals SET deleted = 1, updated_at = ?2 WHERE id = ?1;";

        var stmt: ?*c.sqlite3_stmt = null;
        const rc0 = c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null);
        if (rc0 != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);

        const s = stmt.?;
        if (c.sqlite3_bind_text(s, 1, id, @intCast(id_len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 2, nowMs()) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;

        // Record history: DELETE on savings_goals, old_val = full goal JSON
        if (old_len) |ol| {
            self.recordHistory(3, "savings_goals", id[0..id_len], null, old_buf[0..ol], null) catch {};
        }
    }

    // --- Recurring Patterns ---

    pub fn insertOrUpdateRecurring(
        self: *Db,
        id: [*]const u8,
        id_len: u32,
        merchant: [*]const u8,
        merchant_len: u32,
        amount: i64,
        interval_str: [*]const u8,
        interval_len: u32,
        category: i32,
        last_seen: [*]const u8,
        last_seen_len: u32,
        next_due: ?[*]const u8,
        next_due_len: u32,
        prev_amount: ?i64,
        active: i32,
    ) DbError!void {
        const sql = "INSERT OR REPLACE INTO recurring_patterns (id, merchant, amount, interval, category, last_seen, next_due, active, prev_amount, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10);";

        var stmt: ?*c.sqlite3_stmt = null;
        const rc0 = c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null);
        if (rc0 != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);

        const s = stmt.?;
        if (c.sqlite3_bind_text(s, 1, id, @intCast(id_len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 2, merchant, @intCast(merchant_len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 3, amount) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 4, interval_str, @intCast(interval_len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int(s, 5, category) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 6, last_seen, @intCast(last_seen_len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (next_due) |nd| {
            if (c.sqlite3_bind_text(s, 7, nd, @intCast(next_due_len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        } else {
            if (c.sqlite3_bind_null(s, 7) != c.SQLITE_OK) return DbError.BindFailed;
        }
        if (c.sqlite3_bind_int(s, 8, active) != c.SQLITE_OK) return DbError.BindFailed;
        if (prev_amount) |pa| {
            if (c.sqlite3_bind_int64(s, 9, pa) != c.SQLITE_OK) return DbError.BindFailed;
        } else {
            if (c.sqlite3_bind_null(s, 9) != c.SQLITE_OK) return DbError.BindFailed;
        }
        if (c.sqlite3_bind_int64(s, 10, nowMs()) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;
    }

    pub fn getRecurringJson(self: *Db, buf: [*]u8, buf_len: usize) DbError!?usize {
        const sql = "SELECT id, merchant, amount, interval, category, last_seen, next_due, active, prev_amount FROM recurring_patterns WHERE active = 1 ORDER BY merchant;";

        var stmt: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);

        const s = stmt.?;
        var pos: usize = 0;

        if (pos >= buf_len) return null;
        buf[pos] = '[';
        pos += 1;

        var first = true;
        while (c.sqlite3_step(s) == c.SQLITE_ROW) {
            const id_ptr = c.sqlite3_column_text(s, 0) orelse continue;
            const id_len: usize = @intCast(c.sqlite3_column_bytes(s, 0));
            const merch_ptr = c.sqlite3_column_text(s, 1) orelse continue;
            const merch_len: usize = @intCast(c.sqlite3_column_bytes(s, 1));
            const amount = c.sqlite3_column_int64(s, 2);
            const intv_ptr = c.sqlite3_column_text(s, 3) orelse continue;
            const intv_len: usize = @intCast(c.sqlite3_column_bytes(s, 3));
            const category = c.sqlite3_column_int(s, 4);
            const ls_ptr = c.sqlite3_column_text(s, 5) orelse continue;
            const ls_len: usize = @intCast(c.sqlite3_column_bytes(s, 5));
            const nd_ptr = c.sqlite3_column_text(s, 6);
            const nd_len: usize = @intCast(c.sqlite3_column_bytes(s, 6));
            const active = c.sqlite3_column_int(s, 7);
            const prev_amt_type = c.sqlite3_column_type(s, 8);
            const prev_amt: ?i64 = if (prev_amt_type == c.SQLITE_NULL) null else c.sqlite3_column_int64(s, 8);

            if (!first) {
                if (pos >= buf_len) return null;
                buf[pos] = ',';
                pos += 1;
            }

            // {"id":"
            const p1 = "{\"id\":\"";
            if (pos + p1.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p1.len], p1);
            pos += p1.len;
            pos += jsonEscapeString(buf[pos..buf_len], id_ptr[0..id_len]) orelse return null;

            // ","merchant":"
            const p2 = "\",\"merchant\":\"";
            if (pos + p2.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p2.len], p2);
            pos += p2.len;
            pos += jsonEscapeString(buf[pos..buf_len], merch_ptr[0..merch_len]) orelse return null;

            // ","amount":
            const p3 = "\",\"amount\":";
            if (pos + p3.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p3.len], p3);
            pos += p3.len;
            pos += formatAmount(buf[pos..buf_len], amount) orelse return null;

            // ,"interval":"
            const p4 = ",\"interval\":\"";
            if (pos + p4.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p4.len], p4);
            pos += p4.len;
            pos += jsonEscapeString(buf[pos..buf_len], intv_ptr[0..intv_len]) orelse return null;

            // ","category":
            const p5 = "\",\"category\":";
            if (pos + p5.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p5.len], p5);
            pos += p5.len;
            pos += formatSignedInt(buf[pos..buf_len], @as(i64, category)) orelse return null;

            // ,"last_seen":"
            const p6 = ",\"last_seen\":\"";
            if (pos + p6.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p6.len], p6);
            pos += p6.len;
            pos += jsonEscapeString(buf[pos..buf_len], ls_ptr[0..ls_len]) orelse return null;

            // ","next_due":
            const p7 = "\",\"next_due\":";
            if (pos + p7.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p7.len], p7);
            pos += p7.len;
            if (nd_ptr) |nd| {
                if (pos >= buf_len) return null;
                buf[pos] = '"';
                pos += 1;
                pos += jsonEscapeString(buf[pos..buf_len], nd[0..nd_len]) orelse return null;
                if (pos >= buf_len) return null;
                buf[pos] = '"';
                pos += 1;
            } else {
                const null_s = "null";
                if (pos + null_s.len > buf_len) return null;
                @memcpy(buf[pos .. pos + null_s.len], null_s);
                pos += null_s.len;
            }

            // ,"active":
            const p8 = ",\"active\":";
            if (pos + p8.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p8.len], p8);
            pos += p8.len;
            pos += formatSignedInt(buf[pos..buf_len], @as(i64, active)) orelse return null;

            // ,"prev_amount":
            const p9 = ",\"prev_amount\":";
            if (pos + p9.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p9.len], p9);
            pos += p9.len;
            if (prev_amt) |pa| {
                pos += formatAmount(buf[pos..buf_len], pa) orelse return null;
            } else {
                const null_s = "null";
                if (pos + null_s.len > buf_len) return null;
                @memcpy(buf[pos .. pos + null_s.len], null_s);
                pos += null_s.len;
            }

            // ,"price_change":
            const p10 = ",\"price_change\":";
            if (pos + p10.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p10.len], p10);
            pos += p10.len;
            if (prev_amt) |pa| {
                const diff = amount - pa;
                if (diff > 50 or diff < -50) {
                    pos += formatAmount(buf[pos..buf_len], diff) orelse return null;
                } else {
                    const null_s = "null";
                    if (pos + null_s.len > buf_len) return null;
                    @memcpy(buf[pos .. pos + null_s.len], null_s);
                    pos += null_s.len;
                }
            } else {
                const null_s = "null";
                if (pos + null_s.len > buf_len) return null;
                @memcpy(buf[pos .. pos + null_s.len], null_s);
                pos += null_s.len;
            }

            if (pos >= buf_len) return null;
            buf[pos] = '}';
            pos += 1;

            first = false;
        }

        if (pos >= buf_len) return null;
        buf[pos] = ']';
        pos += 1;

        return pos;
    }

    pub fn clearRecurring(self: *Db) DbError!void {
        self.exec("DELETE FROM recurring_patterns;") catch return DbError.ExecFailed;
    }

    // --- Undo/Redo helpers ---

    fn queryInt(self: *Db, sql: [*:0]const u8, id: [*]const u8, id_len: usize) ?i32 {
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return null;
        defer _ = c.sqlite3_finalize(stmt.?);
        const s = stmt.?;
        if (c.sqlite3_bind_text(s, 1, @ptrCast(id), @intCast(id_len), c.SQLITE_STATIC) != c.SQLITE_OK) return null;
        if (c.sqlite3_step(s) != c.SQLITE_ROW) return null;
        return c.sqlite3_column_int(s, 0);
    }

    fn queryInt64(self: *Db, sql: [*:0]const u8, id: [*]const u8, id_len: usize) ?i64 {
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return null;
        defer _ = c.sqlite3_finalize(stmt.?);
        const s = stmt.?;
        if (c.sqlite3_bind_text(s, 1, @ptrCast(id), @intCast(id_len), c.SQLITE_STATIC) != c.SQLITE_OK) return null;
        if (c.sqlite3_step(s) != c.SQLITE_ROW) return null;
        return c.sqlite3_column_int64(s, 0);
    }

    fn queryDebtJson(self: *Db, buf: *[512]u8, id: [*]const u8, id_len: u32) ?usize {
        const sql = "SELECT id, name, total, paid, monthly FROM debts WHERE id = ?1;";
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return null;
        defer _ = c.sqlite3_finalize(stmt.?);
        const s = stmt.?;
        if (c.sqlite3_bind_text(s, 1, @ptrCast(id), @intCast(id_len), c.SQLITE_STATIC) != c.SQLITE_OK) return null;
        if (c.sqlite3_step(s) != c.SQLITE_ROW) return null;

        const did_ptr = c.sqlite3_column_text(s, 0) orelse return null;
        const did_len: usize = @intCast(c.sqlite3_column_bytes(s, 0));
        const name_ptr = c.sqlite3_column_text(s, 1) orelse return null;
        const name_len: usize = @intCast(c.sqlite3_column_bytes(s, 1));
        const total = c.sqlite3_column_int64(s, 2);
        const paid = c.sqlite3_column_int64(s, 3);
        const monthly = c.sqlite3_column_int64(s, 4);

        return self.formatDebtJson(buf, did_ptr[0..did_len], name_ptr[0..name_len], total, paid, monthly);
    }

    fn formatDebtJson(_: *Db, buf: *[512]u8, id: []const u8, name: []const u8, total: i64, paid: i64, monthly: i64) ?usize {
        var pos: usize = 0;

        const p1 = "{\"id\":\"";
        if (pos + p1.len > buf.len) return null;
        @memcpy(buf[pos .. pos + p1.len], p1);
        pos += p1.len;

        pos += jsonEscapeString(buf[pos..], id) orelse return null;

        const p2 = "\",\"name\":\"";
        if (pos + p2.len > buf.len) return null;
        @memcpy(buf[pos .. pos + p2.len], p2);
        pos += p2.len;

        pos += jsonEscapeString(buf[pos..], name) orelse return null;

        const p3 = "\",\"total\":";
        if (pos + p3.len > buf.len) return null;
        @memcpy(buf[pos .. pos + p3.len], p3);
        pos += p3.len;

        pos += formatSignedInt(buf[pos..], total) orelse return null;

        const p4 = ",\"paid\":";
        if (pos + p4.len > buf.len) return null;
        @memcpy(buf[pos .. pos + p4.len], p4);
        pos += p4.len;

        pos += formatSignedInt(buf[pos..], paid) orelse return null;

        const p5 = ",\"monthly\":";
        if (pos + p5.len > buf.len) return null;
        @memcpy(buf[pos .. pos + p5.len], p5);
        pos += p5.len;

        pos += formatSignedInt(buf[pos..], monthly) orelse return null;

        if (pos >= buf.len) return null;
        buf[pos] = '}';
        pos += 1;

        return pos;
    }

    fn queryGoalJson(self: *Db, buf: *[512]u8, id: [*]const u8, id_len: u32) ?usize {
        const sql = "SELECT id, name, icon, target, current, deadline FROM savings_goals WHERE id = ?1;";
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return null;
        defer _ = c.sqlite3_finalize(stmt.?);
        const s = stmt.?;
        if (c.sqlite3_bind_text(s, 1, @ptrCast(id), @intCast(id_len), c.SQLITE_STATIC) != c.SQLITE_OK) return null;
        if (c.sqlite3_step(s) != c.SQLITE_ROW) return null;

        const gid_ptr = c.sqlite3_column_text(s, 0) orelse return null;
        const gid_len: usize = @intCast(c.sqlite3_column_bytes(s, 0));
        const name_ptr = c.sqlite3_column_text(s, 1) orelse return null;
        const name_len: usize = @intCast(c.sqlite3_column_bytes(s, 1));
        const icon_ptr = c.sqlite3_column_text(s, 2) orelse return null;
        const icon_len: usize = @intCast(c.sqlite3_column_bytes(s, 2));
        const target = c.sqlite3_column_int64(s, 3);
        const current = c.sqlite3_column_int64(s, 4);
        const dl_type = c.sqlite3_column_type(s, 5);
        var deadline: ?[]const u8 = null;
        if (dl_type != c.SQLITE_NULL) {
            const dl_ptr = c.sqlite3_column_text(s, 5) orelse null;
            if (dl_ptr) |dp| {
                const dl_len: usize = @intCast(c.sqlite3_column_bytes(s, 5));
                deadline = dp[0..dl_len];
            }
        }

        return self.formatGoalJson(buf, gid_ptr[0..gid_len], name_ptr[0..name_len], icon_ptr[0..icon_len], target, current, deadline);
    }

    fn formatGoalJson(_: *Db, buf: *[512]u8, id: []const u8, name: []const u8, icon: []const u8, target: i64, current: i64, deadline: ?[]const u8) ?usize {
        var pos: usize = 0;

        const p1 = "{\"id\":\"";
        if (pos + p1.len > buf.len) return null;
        @memcpy(buf[pos .. pos + p1.len], p1);
        pos += p1.len;

        pos += jsonEscapeString(buf[pos..], id) orelse return null;

        const p2 = "\",\"name\":\"";
        if (pos + p2.len > buf.len) return null;
        @memcpy(buf[pos .. pos + p2.len], p2);
        pos += p2.len;

        pos += jsonEscapeString(buf[pos..], name) orelse return null;

        const p3 = "\",\"icon\":\"";
        if (pos + p3.len > buf.len) return null;
        @memcpy(buf[pos .. pos + p3.len], p3);
        pos += p3.len;

        pos += jsonEscapeString(buf[pos..], icon) orelse return null;

        const p4 = "\",\"target\":";
        if (pos + p4.len > buf.len) return null;
        @memcpy(buf[pos .. pos + p4.len], p4);
        pos += p4.len;

        pos += formatSignedInt(buf[pos..], target) orelse return null;

        const p5 = ",\"current\":";
        if (pos + p5.len > buf.len) return null;
        @memcpy(buf[pos .. pos + p5.len], p5);
        pos += p5.len;

        pos += formatSignedInt(buf[pos..], current) orelse return null;

        const p6 = ",\"deadline\":";
        if (pos + p6.len > buf.len) return null;
        @memcpy(buf[pos .. pos + p6.len], p6);
        pos += p6.len;

        if (deadline) |dl| {
            if (pos >= buf.len) return null;
            buf[pos] = '"';
            pos += 1;
            pos += jsonEscapeString(buf[pos..], dl) orelse return null;
            if (pos >= buf.len) return null;
            buf[pos] = '"';
            pos += 1;
        } else {
            const null_str = "null";
            if (pos + null_str.len > buf.len) return null;
            @memcpy(buf[pos .. pos + null_str.len], null_str);
            pos += null_str.len;
        }

        if (pos >= buf.len) return null;
        buf[pos] = '}';
        pos += 1;

        return pos;
    }

    fn recordHistory(self: *Db, op: u8, tbl: []const u8, row_id: []const u8, col: ?[]const u8, old_val: ?[]const u8, new_val: ?[]const u8) DbError!void {
        // Clear redo stack
        self.exec("DELETE FROM undo_history WHERE undone = 1;") catch {};

        const sql = "INSERT INTO undo_history (op, tbl, row_id, col, old_val, new_val, undone) VALUES (?1, ?2, ?3, ?4, ?5, ?6, 0);";
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);

        const s = stmt.?;
        if (c.sqlite3_bind_int(s, 1, @intCast(op)) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 2, @ptrCast(tbl.ptr), @intCast(tbl.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 3, @ptrCast(row_id.ptr), @intCast(row_id.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;

        // Unbound params default to NULL in SQLite, so only bind non-null values
        if (col) |cv| {
            if (c.sqlite3_bind_text(s, 4, @ptrCast(cv.ptr), @intCast(cv.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        }

        if (old_val) |ov| {
            if (c.sqlite3_bind_text(s, 5, @ptrCast(ov.ptr), @intCast(ov.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        }

        if (new_val) |nv| {
            if (c.sqlite3_bind_text(s, 6, @ptrCast(nv.ptr), @intCast(nv.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        }

        if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;

        // Prune to max entries
        self.exec("DELETE FROM undo_history WHERE seq NOT IN (SELECT seq FROM undo_history ORDER BY seq DESC LIMIT 50);") catch {};
    }

    /// Undo the last action. Returns JSON describing what was undone, written into buf.
    /// Returns null if nothing to undo.
    pub fn undo(self: *Db, buf: [*]u8, buf_len: usize) DbError!?usize {
        // Find highest seq where undone=0
        const find_sql = "SELECT seq, op, tbl, row_id, col, old_val, new_val FROM undo_history WHERE undone = 0 ORDER BY seq DESC LIMIT 1;";
        var find_stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, find_sql, -1, &find_stmt, null) != c.SQLITE_OK or find_stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(find_stmt.?);

        const fs = find_stmt.?;
        if (c.sqlite3_step(fs) != c.SQLITE_ROW) return null; // nothing to undo

        const seq = c.sqlite3_column_int64(fs, 0);
        const op: u8 = @intCast(c.sqlite3_column_int(fs, 1));
        const tbl_ptr = c.sqlite3_column_text(fs, 2) orelse return null;
        const tbl_len: usize = @intCast(c.sqlite3_column_bytes(fs, 2));
        const row_id_ptr = c.sqlite3_column_text(fs, 3) orelse return null;
        const row_id_len: usize = @intCast(c.sqlite3_column_bytes(fs, 3));
        const col_ptr = c.sqlite3_column_text(fs, 4);
        const col_len: usize = @intCast(c.sqlite3_column_bytes(fs, 4));
        const old_ptr = c.sqlite3_column_text(fs, 5);
        const old_len: usize = @intCast(c.sqlite3_column_bytes(fs, 5));

        const tbl = tbl_ptr[0..tbl_len];
        const row_id = row_id_ptr[0..row_id_len];

        // Apply reverse operation
        switch (op) {
            1 => {
                // UPDATE → restore old_val
                if (col_ptr == null or old_ptr == null) return null;
                const col = col_ptr.?[0..col_len];
                const old_val = old_ptr.?[0..old_len];
                try self.applyUpdate(tbl, row_id, col, old_val);
            },
            2 => {
                // INSERT → DELETE the row
                try self.applyDelete(tbl, row_id);
            },
            3 => {
                // DELETE → re-INSERT from old_val JSON
                if (old_ptr == null) return null;
                const old_val = old_ptr.?[0..old_len];
                try self.applyReinsert(tbl, old_val);
            },
            else => return null,
        }

        // Mark as undone
        try self.markUndone(seq, 1);

        // Format result JSON
        return self.formatUndoResult(buf, buf_len, op, tbl, row_id, col_ptr, col_len);
    }

    /// Redo the last undone action. Returns JSON describing what was redone.
    pub fn redo(self: *Db, buf: [*]u8, buf_len: usize) DbError!?usize {
        // Find lowest seq where undone=1
        const find_sql = "SELECT seq, op, tbl, row_id, col, old_val, new_val FROM undo_history WHERE undone = 1 ORDER BY seq ASC LIMIT 1;";
        var find_stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, find_sql, -1, &find_stmt, null) != c.SQLITE_OK or find_stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(find_stmt.?);

        const fs = find_stmt.?;
        if (c.sqlite3_step(fs) != c.SQLITE_ROW) return null; // nothing to redo

        const seq = c.sqlite3_column_int64(fs, 0);
        const op: u8 = @intCast(c.sqlite3_column_int(fs, 1));
        const tbl_ptr = c.sqlite3_column_text(fs, 2) orelse return null;
        const tbl_len: usize = @intCast(c.sqlite3_column_bytes(fs, 2));
        const row_id_ptr = c.sqlite3_column_text(fs, 3) orelse return null;
        const row_id_len: usize = @intCast(c.sqlite3_column_bytes(fs, 3));
        const col_ptr = c.sqlite3_column_text(fs, 4);
        const col_len: usize = @intCast(c.sqlite3_column_bytes(fs, 4));
        const new_ptr = c.sqlite3_column_text(fs, 6);
        const new_len: usize = @intCast(c.sqlite3_column_bytes(fs, 6));

        const tbl = tbl_ptr[0..tbl_len];
        const row_id = row_id_ptr[0..row_id_len];

        // Re-apply original operation
        switch (op) {
            1 => {
                // UPDATE → set new_val
                if (col_ptr == null or new_ptr == null) return null;
                const col = col_ptr.?[0..col_len];
                const new_val = new_ptr.?[0..new_len];
                try self.applyUpdate(tbl, row_id, col, new_val);
            },
            2 => {
                // INSERT → re-INSERT from new_val
                if (new_ptr == null) return null;
                const new_val = new_ptr.?[0..new_len];
                try self.applyReinsert(tbl, new_val);
            },
            3 => {
                // DELETE → DELETE the row
                try self.applyDelete(tbl, row_id);
            },
            else => return null,
        }

        // Mark as not undone
        try self.markUndone(seq, 0);

        return self.formatUndoResult(buf, buf_len, op, tbl, row_id, col_ptr, col_len);
    }

    fn applyUpdate(self: *Db, tbl: []const u8, row_id: []const u8, col: []const u8, val: []const u8) DbError!void {
        const now = nowMs();
        // Validate table+column against allowlist
        if (std.mem.eql(u8, tbl, "transactions") and std.mem.eql(u8, col, "category")) {
            // Parse integer value
            var int_val: i32 = 0;
            for (val) |ch| {
                if (ch >= '0' and ch <= '9') {
                    int_val = int_val * 10 + @as(i32, ch - '0');
                }
            }
            const sql = "UPDATE transactions SET category = ?1, updated_at = ?3 WHERE id = ?2;";
            var stmt: ?*c.sqlite3_stmt = null;
            if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
            defer _ = c.sqlite3_finalize(stmt.?);
            const s = stmt.?;
            if (c.sqlite3_bind_int(s, 1, int_val) != c.SQLITE_OK) return DbError.BindFailed;
            if (c.sqlite3_bind_text(s, 2, @ptrCast(row_id.ptr), @intCast(row_id.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
            if (c.sqlite3_bind_int64(s, 3, now) != c.SQLITE_OK) return DbError.BindFailed;
            if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;
        } else if (std.mem.eql(u8, tbl, "transactions") and std.mem.eql(u8, col, "excluded")) {
            // Parse integer value
            var int_val: i32 = 0;
            for (val) |ch| {
                if (ch >= '0' and ch <= '9') {
                    int_val = int_val * 10 + @as(i32, ch - '0');
                }
            }
            const sql = "UPDATE transactions SET excluded = ?1, updated_at = ?3 WHERE id = ?2;";
            var stmt: ?*c.sqlite3_stmt = null;
            if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
            defer _ = c.sqlite3_finalize(stmt.?);
            const s = stmt.?;
            if (c.sqlite3_bind_int(s, 1, int_val) != c.SQLITE_OK) return DbError.BindFailed;
            if (c.sqlite3_bind_text(s, 2, @ptrCast(row_id.ptr), @intCast(row_id.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
            if (c.sqlite3_bind_int64(s, 3, now) != c.SQLITE_OK) return DbError.BindFailed;
            if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;
        } else if (std.mem.eql(u8, tbl, "debts") and std.mem.eql(u8, col, "paid")) {
            // Parse i64 value
            const int_val = parseI64(val);
            const sql = "UPDATE debts SET paid = ?1, updated_at = ?3 WHERE id = ?2;";
            var stmt: ?*c.sqlite3_stmt = null;
            if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
            defer _ = c.sqlite3_finalize(stmt.?);
            const s = stmt.?;
            if (c.sqlite3_bind_int64(s, 1, int_val) != c.SQLITE_OK) return DbError.BindFailed;
            if (c.sqlite3_bind_text(s, 2, @ptrCast(row_id.ptr), @intCast(row_id.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
            if (c.sqlite3_bind_int64(s, 3, now) != c.SQLITE_OK) return DbError.BindFailed;
            if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;
        } else if (std.mem.eql(u8, tbl, "savings_goals") and std.mem.eql(u8, col, "current")) {
            const int_val = parseI64(val);
            const sql = "UPDATE savings_goals SET current = ?1, updated_at = ?3 WHERE id = ?2;";
            var stmt: ?*c.sqlite3_stmt = null;
            if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
            defer _ = c.sqlite3_finalize(stmt.?);
            const s = stmt.?;
            if (c.sqlite3_bind_int64(s, 1, int_val) != c.SQLITE_OK) return DbError.BindFailed;
            if (c.sqlite3_bind_text(s, 2, @ptrCast(row_id.ptr), @intCast(row_id.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
            if (c.sqlite3_bind_int64(s, 3, now) != c.SQLITE_OK) return DbError.BindFailed;
            if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;
        }
        // Unknown table/col combos are silently ignored (safe)
    }

    fn applyDelete(self: *Db, tbl: []const u8, row_id: []const u8) DbError!void {
        const sql: [*:0]const u8 = if (std.mem.eql(u8, tbl, "debts"))
            "UPDATE debts SET deleted = 1, updated_at = ?2 WHERE id = ?1;"
        else if (std.mem.eql(u8, tbl, "accounts"))
            "UPDATE accounts SET deleted = 1, updated_at = ?2 WHERE id = ?1;"
        else if (std.mem.eql(u8, tbl, "savings_goals"))
            "UPDATE savings_goals SET deleted = 1, updated_at = ?2 WHERE id = ?1;"
        else
            return;

        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);
        const s = stmt.?;
        if (c.sqlite3_bind_text(s, 1, @ptrCast(row_id.ptr), @intCast(row_id.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 2, nowMs()) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;
    }

    fn applyReinsert(self: *Db, tbl: []const u8, json: []const u8) DbError!void {
        if (std.mem.eql(u8, tbl, "debts")) {
            const id = jsonExtractStringFromSlice(json, "\"id\"") orelse return DbError.ExecFailed;
            const name = jsonExtractStringFromSlice(json, "\"name\"") orelse return DbError.ExecFailed;
            const total = jsonExtractI64FromSlice(json, "\"total\"");
            const paid = jsonExtractI64FromSlice(json, "\"paid\"");
            const monthly = jsonExtractI64FromSlice(json, "\"monthly\"");

            const sql = "INSERT OR REPLACE INTO debts (id, name, total, paid, monthly, deleted, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, 0, ?6);";
            var stmt: ?*c.sqlite3_stmt = null;
            if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
            defer _ = c.sqlite3_finalize(stmt.?);
            const s = stmt.?;
            if (c.sqlite3_bind_text(s, 1, @ptrCast(id.ptr), @intCast(id.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
            if (c.sqlite3_bind_text(s, 2, @ptrCast(name.ptr), @intCast(name.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
            if (c.sqlite3_bind_int64(s, 3, total) != c.SQLITE_OK) return DbError.BindFailed;
            if (c.sqlite3_bind_int64(s, 4, paid) != c.SQLITE_OK) return DbError.BindFailed;
            if (c.sqlite3_bind_int64(s, 5, monthly) != c.SQLITE_OK) return DbError.BindFailed;
            if (c.sqlite3_bind_int64(s, 6, nowMs()) != c.SQLITE_OK) return DbError.BindFailed;
            if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;
        } else if (std.mem.eql(u8, tbl, "savings_goals")) {
            const id = jsonExtractStringFromSlice(json, "\"id\"") orelse return DbError.ExecFailed;
            const name = jsonExtractStringFromSlice(json, "\"name\"") orelse return DbError.ExecFailed;
            const icon = jsonExtractStringFromSlice(json, "\"icon\"") orelse "🎯";
            const target = jsonExtractI64FromSlice(json, "\"target\"");
            const current = jsonExtractI64FromSlice(json, "\"current\"");
            const deadline = jsonExtractStringFromSlice(json, "\"deadline\"");

            const sql = "INSERT OR REPLACE INTO savings_goals (id, name, icon, target, current, deadline, deleted, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, 0, ?7);";
            var stmt: ?*c.sqlite3_stmt = null;
            if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
            defer _ = c.sqlite3_finalize(stmt.?);
            const s = stmt.?;
            if (c.sqlite3_bind_text(s, 1, @ptrCast(id.ptr), @intCast(id.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
            if (c.sqlite3_bind_text(s, 2, @ptrCast(name.ptr), @intCast(name.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
            if (c.sqlite3_bind_text(s, 3, @ptrCast(icon.ptr), @intCast(icon.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
            if (c.sqlite3_bind_int64(s, 4, target) != c.SQLITE_OK) return DbError.BindFailed;
            if (c.sqlite3_bind_int64(s, 5, current) != c.SQLITE_OK) return DbError.BindFailed;
            if (deadline) |dl| {
                if (c.sqlite3_bind_text(s, 6, @ptrCast(dl.ptr), @intCast(dl.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
            } else {
                if (c.sqlite3_bind_null(s, 6) != c.SQLITE_OK) return DbError.BindFailed;
            }
            if (c.sqlite3_bind_int64(s, 7, nowMs()) != c.SQLITE_OK) return DbError.BindFailed;
            if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;
        }
    }

    fn markUndone(self: *Db, seq: i64, val: u8) DbError!void {
        const sql = "UPDATE undo_history SET undone = ?1 WHERE seq = ?2;";
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);
        const s = stmt.?;
        if (c.sqlite3_bind_int(s, 1, @intCast(val)) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 2, seq) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;
    }

    fn formatUndoResult(_: *Db, buf: [*]u8, buf_len: usize, op: u8, tbl: []const u8, row_id: []const u8, col_ptr: ?[*]const u8, col_len: usize) ?usize {
        var pos: usize = 0;
        const op_str = switch (op) {
            1 => "update",
            2 => "insert",
            3 => "delete",
            else => "unknown",
        };

        // {"op":"...","table":"...","row_id":"..."}
        const p1 = "{\"op\":\"";
        if (pos + p1.len > buf_len) return null;
        @memcpy(buf[pos .. pos + p1.len], p1);
        pos += p1.len;

        if (pos + op_str.len > buf_len) return null;
        @memcpy(buf[pos .. pos + op_str.len], op_str);
        pos += op_str.len;

        const p2 = "\",\"table\":\"";
        if (pos + p2.len > buf_len) return null;
        @memcpy(buf[pos .. pos + p2.len], p2);
        pos += p2.len;

        if (pos + tbl.len > buf_len) return null;
        @memcpy(buf[pos .. pos + tbl.len], tbl);
        pos += tbl.len;

        const p3 = "\",\"row_id\":\"";
        if (pos + p3.len > buf_len) return null;
        @memcpy(buf[pos .. pos + p3.len], p3);
        pos += p3.len;

        if (pos + row_id.len > buf_len) return null;
        @memcpy(buf[pos .. pos + row_id.len], row_id);
        pos += row_id.len;

        if (col_ptr != null and col_len > 0) {
            const p4 = "\",\"column\":\"";
            if (pos + p4.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p4.len], p4);
            pos += p4.len;

            const col = col_ptr.?[0..col_len];
            if (pos + col.len > buf_len) return null;
            @memcpy(buf[pos .. pos + col.len], col);
            pos += col.len;
        }

        const p5 = "\"}";
        if (pos + p5.len > buf_len) return null;
        @memcpy(buf[pos .. pos + p5.len], p5);
        pos += p5.len;

        return pos;
    }

    pub fn getDebtsJson(self: *Db, buf: [*]u8, buf_len: usize) DbError!?usize {
        const sql = "SELECT id, name, total, paid, monthly FROM debts WHERE deleted = 0 ORDER BY name;";

        var stmt: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);

        const s = stmt.?;
        var pos: usize = 0;

        if (pos >= buf_len) return null;
        buf[pos] = '[';
        pos += 1;

        var first = true;
        while (c.sqlite3_step(s) == c.SQLITE_ROW) {
            const id_ptr = c.sqlite3_column_text(s, 0) orelse continue;
            const id_len: usize = @intCast(c.sqlite3_column_bytes(s, 0));
            const name_ptr = c.sqlite3_column_text(s, 1) orelse continue;
            const name_len: usize = @intCast(c.sqlite3_column_bytes(s, 1));
            const total = c.sqlite3_column_int64(s, 2);
            const paid = c.sqlite3_column_int64(s, 3);
            const monthly = c.sqlite3_column_int64(s, 4);

            if (!first) {
                if (pos >= buf_len) return null;
                buf[pos] = ',';
                pos += 1;
            }

            // {"id":"...","name":"...","total":...,"paid":...,"monthly":...}
            const p1 = "{\"id\":\"";
            if (pos + p1.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p1.len], p1);
            pos += p1.len;

            pos += jsonEscapeString(buf[pos..buf_len], id_ptr[0..id_len]) orelse return null;

            const p2 = "\",\"name\":\"";
            if (pos + p2.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p2.len], p2);
            pos += p2.len;

            pos += jsonEscapeString(buf[pos..buf_len], name_ptr[0..name_len]) orelse return null;

            const p3 = "\",\"total\":";
            if (pos + p3.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p3.len], p3);
            pos += p3.len;

            pos += formatAmount(buf[pos..buf_len], total) orelse return null;

            const p4 = ",\"paid\":";
            if (pos + p4.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p4.len], p4);
            pos += p4.len;

            pos += formatAmount(buf[pos..buf_len], paid) orelse return null;

            const p5 = ",\"monthly\":";
            if (pos + p5.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p5.len], p5);
            pos += p5.len;

            pos += formatAmount(buf[pos..buf_len], monthly) orelse return null;

            if (pos >= buf_len) return null;
            buf[pos] = '}';
            pos += 1;

            first = false;
        }

        if (pos >= buf_len) return null;
        buf[pos] = ']';
        pos += 1;

        return pos;
    }

    pub fn getGoalsJson(self: *Db, buf: [*]u8, buf_len: usize) DbError!?usize {
        const sql = "SELECT id, name, icon, target, current, deadline FROM savings_goals WHERE deleted = 0 ORDER BY name;";

        var stmt: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);

        const s = stmt.?;
        var pos: usize = 0;

        if (pos >= buf_len) return null;
        buf[pos] = '[';
        pos += 1;

        var first = true;
        while (c.sqlite3_step(s) == c.SQLITE_ROW) {
            const id_ptr = c.sqlite3_column_text(s, 0) orelse continue;
            const id_len: usize = @intCast(c.sqlite3_column_bytes(s, 0));
            const name_ptr = c.sqlite3_column_text(s, 1) orelse continue;
            const name_len: usize = @intCast(c.sqlite3_column_bytes(s, 1));
            const icon_ptr = c.sqlite3_column_text(s, 2) orelse continue;
            const icon_len: usize = @intCast(c.sqlite3_column_bytes(s, 2));
            const target = c.sqlite3_column_int64(s, 3);
            const current = c.sqlite3_column_int64(s, 4);
            const dl_type = c.sqlite3_column_type(s, 5);

            if (!first) {
                if (pos >= buf_len) return null;
                buf[pos] = ',';
                pos += 1;
            }

            // {"id":"...","name":"...","icon":"...","target":...,"current":...,"deadline":...}
            const p1 = "{\"id\":\"";
            if (pos + p1.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p1.len], p1);
            pos += p1.len;

            pos += jsonEscapeString(buf[pos..buf_len], id_ptr[0..id_len]) orelse return null;

            const p2 = "\",\"name\":\"";
            if (pos + p2.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p2.len], p2);
            pos += p2.len;

            pos += jsonEscapeString(buf[pos..buf_len], name_ptr[0..name_len]) orelse return null;

            const p3 = "\",\"icon\":\"";
            if (pos + p3.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p3.len], p3);
            pos += p3.len;

            pos += jsonEscapeString(buf[pos..buf_len], icon_ptr[0..icon_len]) orelse return null;

            const p4 = "\",\"target\":";
            if (pos + p4.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p4.len], p4);
            pos += p4.len;

            pos += formatAmount(buf[pos..buf_len], target) orelse return null;

            const p5 = ",\"current\":";
            if (pos + p5.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p5.len], p5);
            pos += p5.len;

            pos += formatAmount(buf[pos..buf_len], current) orelse return null;

            const p6 = ",\"deadline\":";
            if (pos + p6.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p6.len], p6);
            pos += p6.len;

            if (dl_type != c.SQLITE_NULL) {
                const dl_ptr = c.sqlite3_column_text(s, 5);
                if (dl_ptr) |dp| {
                    const dl_len: usize = @intCast(c.sqlite3_column_bytes(s, 5));
                    if (pos >= buf_len) return null;
                    buf[pos] = '"';
                    pos += 1;
                    pos += jsonEscapeString(buf[pos..buf_len], dp[0..dl_len]) orelse return null;
                    if (pos >= buf_len) return null;
                    buf[pos] = '"';
                    pos += 1;
                } else {
                    const null_str = "null";
                    if (pos + null_str.len > buf_len) return null;
                    @memcpy(buf[pos .. pos + null_str.len], null_str);
                    pos += null_str.len;
                }
            } else {
                const null_str = "null";
                if (pos + null_str.len > buf_len) return null;
                @memcpy(buf[pos .. pos + null_str.len], null_str);
                pos += null_str.len;
            }

            if (pos >= buf_len) return null;
            buf[pos] = '}';
            pos += 1;

            first = false;
        }

        if (pos >= buf_len) return null;
        buf[pos] = ']';
        pos += 1;

        return pos;
    }

    /// Write all transactions as JSON into the provided buffer.
    /// Returns the number of bytes written, or null if buffer is too small.
    pub fn getTransactionsJson(self: *Db, buf: [*]u8, buf_len: usize) DbError!?usize {
        return self.getTransactionsJsonFiltered(buf, buf_len, null, 0);
    }

    /// Write transactions as JSON, optionally filtered by account.
    pub fn getTransactionsJsonFiltered(self: *Db, buf: [*]u8, buf_len: usize, acct_ptr: ?[*]const u8, acct_len: u32) DbError!?usize {
        const has_filter = acct_ptr != null and acct_len > 0;
        const sql_all =
            \\SELECT id, date_year, date_month, date_day, description, amount_cents, currency, category, account, excluded
            \\FROM transactions
            \\ORDER BY date_year DESC, date_month DESC, date_day DESC, rowid DESC;
        ;
        const sql_filtered =
            \\SELECT id, date_year, date_month, date_day, description, amount_cents, currency, category, account, excluded
            \\FROM transactions
            \\WHERE account = ?1
            \\ORDER BY date_year DESC, date_month DESC, date_day DESC, rowid DESC;
        ;

        const sql = if (has_filter) sql_filtered else sql_all;

        var stmt: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);

        const s = stmt.?;
        if (has_filter) {
            if (c.sqlite3_bind_text(s, 1, @ptrCast(acct_ptr.?), @intCast(acct_len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        }

        var pos: usize = 0;

        // Opening bracket
        if (pos >= buf_len) return null;
        buf[pos] = '[';
        pos += 1;

        var first = true;
        while (c.sqlite3_step(s) == c.SQLITE_ROW) {
            // Get column values
            const id_ptr = c.sqlite3_column_text(s, 0);
            const year = c.sqlite3_column_int(s, 1);
            const month = c.sqlite3_column_int(s, 2);
            const day = c.sqlite3_column_int(s, 3);
            const desc_ptr = c.sqlite3_column_text(s, 4);
            const desc_len: usize = @intCast(c.sqlite3_column_bytes(s, 4));
            const amount = c.sqlite3_column_int64(s, 5);
            const curr_ptr = c.sqlite3_column_text(s, 6);
            const cat = c.sqlite3_column_int(s, 7);
            const a_ptr = c.sqlite3_column_text(s, 8);
            const a_len: usize = @intCast(c.sqlite3_column_bytes(s, 8));
            const excluded: u8 = @intCast(c.sqlite3_column_int(s, 9));

            if (id_ptr == null or desc_ptr == null or curr_ptr == null) continue;

            // Format JSON object
            const slice = buf[pos..buf_len];

            const written = jsonFormatTransaction(
                slice,
                buf_len - pos,
                first,
                id_ptr.?,
                @intCast(year),
                @intCast(month),
                @intCast(day),
                desc_ptr.?,
                desc_len,
                amount,
                curr_ptr.?,
                @intCast(cat),
                if (a_ptr) |p| p[0..a_len] else "",
                excluded,
            ) orelse return null;

            pos += written;
            first = false;
        }

        // Closing bracket
        if (pos >= buf_len) return null;
        buf[pos] = ']';
        pos += 1;

        return pos;
    }

    // --- Accounts ---

    pub fn ensureAccount(self: *Db, account_id: []const u8, display_name: []const u8, color: []const u8) DbError!void {
        const sql = "INSERT OR IGNORE INTO accounts (id, name, bank, color, updated_at) VALUES (?1, ?2, ?3, ?4, ?5);";
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);
        const s = stmt.?;
        if (c.sqlite3_bind_text(s, 1, @ptrCast(account_id.ptr), @intCast(account_id.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 2, @ptrCast(display_name.ptr), @intCast(display_name.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 3, @ptrCast(account_id.ptr), @intCast(account_id.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 4, @ptrCast(color.ptr), @intCast(color.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 5, nowMs()) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;
    }

    /// Update an account's balance, but only when `balance_date` is at least as
    /// recent as the stored one — touchdown statement pages can arrive in any
    /// order and we want the latest closing balance to win. `balance_date` is
    /// ISO "YYYY-MM-DD" (lexically comparable); empty string means unknown.
    pub fn setAccountBalance(self: *Db, account_id: []const u8, balance_cents: i64, balance_date: []const u8) DbError!void {
        const sql =
            \\UPDATE accounts
            \\SET balance_cents = ?2, balance_date = ?3, updated_at = ?4
            \\WHERE id = ?1 AND ?3 >= balance_date;
        ;
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);
        const s = stmt.?;
        if (c.sqlite3_bind_text(s, 1, @ptrCast(account_id.ptr), @intCast(account_id.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 2, balance_cents) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 3, @ptrCast(balance_date.ptr), @intCast(balance_date.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 4, nowMs()) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;
    }

    pub fn getAccountsJson(self: *Db, buf: [*]u8, buf_len: usize) DbError!?usize {
        const sql = "SELECT id, name, bank, color, balance_cents, balance_date FROM accounts WHERE deleted = 0 ORDER BY name;";
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);

        const s = stmt.?;
        var pos: usize = 0;

        if (pos >= buf_len) return null;
        buf[pos] = '[';
        pos += 1;

        var first = true;
        while (c.sqlite3_step(s) == c.SQLITE_ROW) {
            const id_ptr = c.sqlite3_column_text(s, 0) orelse continue;
            const id_len: usize = @intCast(c.sqlite3_column_bytes(s, 0));
            const name_ptr = c.sqlite3_column_text(s, 1) orelse continue;
            const name_len: usize = @intCast(c.sqlite3_column_bytes(s, 1));
            const bank_ptr = c.sqlite3_column_text(s, 2) orelse continue;
            const bank_len: usize = @intCast(c.sqlite3_column_bytes(s, 2));
            const color_ptr = c.sqlite3_column_text(s, 3) orelse continue;
            const color_len: usize = @intCast(c.sqlite3_column_bytes(s, 3));
            const balance_cents = c.sqlite3_column_int64(s, 4);
            const bal_date_ptr = c.sqlite3_column_text(s, 5);
            const bal_date_len: usize = @intCast(c.sqlite3_column_bytes(s, 5));

            if (!first) {
                if (pos >= buf_len) return null;
                buf[pos] = ',';
                pos += 1;
            }

            // {"id":"...","name":"...","bank":"...","color":"..."}
            const p1 = "{\"id\":\"";
            if (pos + p1.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p1.len], p1);
            pos += p1.len;
            pos += jsonEscapeString(buf[pos..buf_len], id_ptr[0..id_len]) orelse return null;

            const p2 = "\",\"name\":\"";
            if (pos + p2.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p2.len], p2);
            pos += p2.len;
            pos += jsonEscapeString(buf[pos..buf_len], name_ptr[0..name_len]) orelse return null;

            const p3 = "\",\"bank\":\"";
            if (pos + p3.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p3.len], p3);
            pos += p3.len;
            pos += jsonEscapeString(buf[pos..buf_len], bank_ptr[0..bank_len]) orelse return null;

            const p4 = "\",\"color\":\"";
            if (pos + p4.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p4.len], p4);
            pos += p4.len;
            pos += jsonEscapeString(buf[pos..buf_len], color_ptr[0..color_len]) orelse return null;

            const p5 = "\",\"balance_cents\":";
            if (pos + p5.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p5.len], p5);
            pos += p5.len;
            pos += formatInt(buf[pos..buf_len], balance_cents) orelse return null;

            const p6 = ",\"balance_date\":\"";
            if (pos + p6.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p6.len], p6);
            pos += p6.len;
            if (bal_date_ptr) |bp| {
                pos += jsonEscapeString(buf[pos..buf_len], bp[0..bal_date_len]) orelse return null;
            }

            const p7 = "\"}";
            if (pos + p7.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p7.len], p7);
            pos += p7.len;

            first = false;
        }

        if (pos >= buf_len) return null;
        buf[pos] = ']';
        pos += 1;

        return pos;
    }

    pub fn insertAccount(self: *Db, id: [*]const u8, id_len: u32, name_val: [*]const u8, name_len: u32, color: [*]const u8, color_len: u32) DbError!void {
        const sql = "INSERT OR REPLACE INTO accounts (id, name, bank, color, updated_at) VALUES (?1, ?2, ?1, ?3, ?4);";
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);
        const s = stmt.?;
        if (c.sqlite3_bind_text(s, 1, id, @intCast(id_len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 2, name_val, @intCast(name_len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 3, color, @intCast(color_len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 4, nowMs()) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;
    }

    pub fn updateAccount(self: *Db, id: [*]const u8, id_len: u32, name_val: [*]const u8, name_len: u32, color: [*]const u8, color_len: u32) DbError!void {
        const sql = "UPDATE accounts SET name = ?2, color = ?3, updated_at = ?4 WHERE id = ?1;";
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);
        const s = stmt.?;
        if (c.sqlite3_bind_text(s, 1, id, @intCast(id_len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 2, name_val, @intCast(name_len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 3, color, @intCast(color_len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 4, nowMs()) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;
    }

    pub fn deleteAccount(self: *Db, id: [*]const u8, id_len: u32) DbError!void {
        const sql = "UPDATE accounts SET deleted = 1, updated_at = ?2 WHERE id = ?1;";
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);
        const s = stmt.?;
        if (c.sqlite3_bind_text(s, 1, id, @intCast(id_len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 2, nowMs()) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;
    }

    // --- Snapshots ---

    /// Take a monthly snapshot: compute summary for year/month and INSERT OR REPLACE.
    pub fn takeSnapshot(self: *Db, year: u32, month: u32) DbError!void {
        // Compute summary using SQL (same as summary.zig)
        const sql =
            \\SELECT category,
            \\  SUM(CASE WHEN amount_cents > 0 THEN amount_cents ELSE 0 END) as income,
            \\  SUM(CASE WHEN amount_cents < 0 THEN amount_cents ELSE 0 END) as expenses,
            \\  COUNT(*) as cnt
            \\FROM transactions
            \\WHERE date_year = ?1 AND date_month = ?2 AND excluded = 0
            \\GROUP BY category
            \\ORDER BY expenses ASC;
        ;

        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);
        const s = stmt.?;
        if (c.sqlite3_bind_int(s, 1, @intCast(year)) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int(s, 2, @intCast(month)) != c.SQLITE_OK) return DbError.BindFailed;

        var total_income: i64 = 0;
        var total_expenses: i64 = 0;
        var total_count: i32 = 0;

        const max_cats = 20;
        var cat_ids: [max_cats]u8 = undefined;
        var cat_amounts: [max_cats]i64 = undefined;
        var cat_count: usize = 0;

        while (c.sqlite3_step(s) == c.SQLITE_ROW) {
            const cat_id: u8 = @intCast(c.sqlite3_column_int(s, 0));
            const income = c.sqlite3_column_int64(s, 1);
            const expenses = c.sqlite3_column_int64(s, 2);
            const cnt = c.sqlite3_column_int(s, 3);

            total_income += income;
            total_expenses += expenses;
            total_count += cnt;

            if (expenses < 0 and cat_count < max_cats) {
                cat_ids[cat_count] = cat_id;
                cat_amounts[cat_count] = -expenses;
                cat_count += 1;
            }
        }

        // Build breakdown JSON: [{"id":N,"amount":X.XX},...]
        var bk_buf: [2048]u8 = undefined;
        var bk_pos: usize = 0;
        bk_buf[bk_pos] = '[';
        bk_pos += 1;
        for (0..cat_count) |i| {
            if (i > 0) {
                bk_buf[bk_pos] = ',';
                bk_pos += 1;
            }
            const p1 = "{\"id\":";
            @memcpy(bk_buf[bk_pos .. bk_pos + p1.len], p1);
            bk_pos += p1.len;
            bk_pos += formatInt(bk_buf[bk_pos..], @as(u32, cat_ids[i])) orelse return DbError.ExecFailed;
            const p2 = ",\"amount\":";
            @memcpy(bk_buf[bk_pos .. bk_pos + p2.len], p2);
            bk_pos += p2.len;
            bk_pos += formatAmount(bk_buf[bk_pos..], cat_amounts[i]) orelse return DbError.ExecFailed;
            bk_buf[bk_pos] = '}';
            bk_pos += 1;
        }
        bk_buf[bk_pos] = ']';
        bk_pos += 1;

        // Build id: "YYYY-MM"
        var id_buf: [7]u8 = undefined;
        id_buf[0] = '0' + @as(u8, @intCast(year / 1000));
        id_buf[1] = '0' + @as(u8, @intCast((year / 100) % 10));
        id_buf[2] = '0' + @as(u8, @intCast((year / 10) % 10));
        id_buf[3] = '0' + @as(u8, @intCast(year % 10));
        id_buf[4] = '-';
        id_buf[5] = '0' + @as(u8, @intCast(month / 10));
        id_buf[6] = '0' + @as(u8, @intCast(month % 10));

        // Build date: "YYYY-MM-01"
        var date_buf: [10]u8 = undefined;
        @memcpy(date_buf[0..7], &id_buf);
        date_buf[7] = '-';
        date_buf[8] = '0';
        date_buf[9] = '1';

        const ins_sql = "INSERT OR REPLACE INTO snapshots (id, date, net_worth, income, expenses, tx_count, breakdown, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8);";
        var ins_stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, ins_sql, -1, &ins_stmt, null) != c.SQLITE_OK or ins_stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(ins_stmt.?);
        const is = ins_stmt.?;
        if (c.sqlite3_bind_text(is, 1, &id_buf, 7, c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(is, 2, &date_buf, 10, c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(is, 3, total_income + total_expenses) != c.SQLITE_OK) return DbError.BindFailed; // net_worth = income - |expenses|
        if (c.sqlite3_bind_int64(is, 4, total_income) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(is, 5, -total_expenses) != c.SQLITE_OK) return DbError.BindFailed; // store as positive
        if (c.sqlite3_bind_int(is, 6, total_count) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(is, 7, &bk_buf, @intCast(bk_pos), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(is, 8, nowMs()) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_step(is) != c.SQLITE_DONE) return DbError.StepFailed;
    }

    /// Get all snapshots as JSON array.
    pub fn getSnapshotsJson(self: *Db, buf: [*]u8, buf_len: usize) DbError!?usize {
        const sql = "SELECT id, date, net_worth, income, expenses, tx_count, breakdown FROM snapshots ORDER BY date DESC;";
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);

        const s = stmt.?;
        var pos: usize = 0;

        if (pos >= buf_len) return null;
        buf[pos] = '[';
        pos += 1;

        var first = true;
        while (c.sqlite3_step(s) == c.SQLITE_ROW) {
            const id_ptr = c.sqlite3_column_text(s, 0) orelse continue;
            const id_len: usize = @intCast(c.sqlite3_column_bytes(s, 0));
            const date_ptr = c.sqlite3_column_text(s, 1) orelse continue;
            const date_len: usize = @intCast(c.sqlite3_column_bytes(s, 1));
            const net_worth = c.sqlite3_column_int64(s, 2);
            const income = c.sqlite3_column_int64(s, 3);
            const expenses = c.sqlite3_column_int64(s, 4);
            const tx_count = c.sqlite3_column_int(s, 5);
            const bk_ptr = c.sqlite3_column_text(s, 6) orelse continue;
            const bk_len: usize = @intCast(c.sqlite3_column_bytes(s, 6));

            if (!first) {
                if (pos >= buf_len) return null;
                buf[pos] = ',';
                pos += 1;
            }

            const p1 = "{\"id\":\"";
            if (pos + p1.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p1.len], p1);
            pos += p1.len;
            pos += jsonEscapeString(buf[pos..buf_len], id_ptr[0..id_len]) orelse return null;

            const p2 = "\",\"date\":\"";
            if (pos + p2.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p2.len], p2);
            pos += p2.len;
            pos += jsonEscapeString(buf[pos..buf_len], date_ptr[0..date_len]) orelse return null;

            const p3 = "\",\"net_worth\":";
            if (pos + p3.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p3.len], p3);
            pos += p3.len;
            pos += formatAmount(buf[pos..buf_len], net_worth) orelse return null;

            const p4 = ",\"income\":";
            if (pos + p4.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p4.len], p4);
            pos += p4.len;
            pos += formatAmount(buf[pos..buf_len], income) orelse return null;

            const p5 = ",\"expenses\":";
            if (pos + p5.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p5.len], p5);
            pos += p5.len;
            pos += formatAmount(buf[pos..buf_len], expenses) orelse return null;

            const p6 = ",\"tx_count\":";
            if (pos + p6.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p6.len], p6);
            pos += p6.len;
            pos += formatSignedInt(buf[pos..buf_len], @as(i64, tx_count)) orelse return null;

            // breakdown is already JSON — embed raw
            const p7 = ",\"by_category\":";
            if (pos + p7.len > buf_len) return null;
            @memcpy(buf[pos .. pos + p7.len], p7);
            pos += p7.len;
            if (pos + bk_len > buf_len) return null;
            @memcpy(buf[pos .. pos + bk_len], bk_ptr[0..bk_len]);
            pos += bk_len;

            if (pos >= buf_len) return null;
            buf[pos] = '}';
            pos += 1;
            first = false;
        }

        if (pos >= buf_len) return null;
        buf[pos] = ']';
        pos += 1;

        return pos;
    }

    // --- Export ---

    /// Export all transactions as CSV into the provided buffer.
    /// Returns bytes written, or null if buffer too small.
    pub fn exportTransactionsCsv(self: *Db, buf: [*]u8, buf_len: usize) DbError!?usize {
        const sql =
            \\SELECT id, date_year, date_month, date_day, description, amount_cents, currency, category, account
            \\FROM transactions
            \\ORDER BY date_year DESC, date_month DESC, date_day DESC;
        ;

        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);

        const s = stmt.?;
        var pos: usize = 0;

        // CSV header
        const header = "Date,Description,Amount,Currency,Category,Account\n";
        if (pos + header.len > buf_len) return null;
        @memcpy(buf[pos .. pos + header.len], header);
        pos += header.len;

        while (c.sqlite3_step(s) == c.SQLITE_ROW) {
            const year: u16 = @intCast(c.sqlite3_column_int(s, 1));
            const month: u8 = @intCast(c.sqlite3_column_int(s, 2));
            const day: u8 = @intCast(c.sqlite3_column_int(s, 3));
            const desc_ptr = c.sqlite3_column_text(s, 4) orelse continue;
            const desc_len: usize = @intCast(c.sqlite3_column_bytes(s, 4));
            const amount = c.sqlite3_column_int64(s, 5);
            const curr_ptr = c.sqlite3_column_text(s, 6) orelse continue;
            const cat: u8 = @intCast(c.sqlite3_column_int(s, 7));
            const acct_ptr = c.sqlite3_column_text(s, 8);
            const acct_len: usize = @intCast(c.sqlite3_column_bytes(s, 8));

            // Date: YYYY-MM-DD
            pos += formatDate(buf[pos..buf_len], year, month, day) orelse return null;

            // ,Description (CSV-escape: wrap in quotes if contains comma/quote/newline)
            if (pos >= buf_len) return null;
            buf[pos] = ',';
            pos += 1;
            pos += csvEscapeField(buf[pos..buf_len], desc_ptr[0..desc_len]) orelse return null;

            // ,Amount
            if (pos >= buf_len) return null;
            buf[pos] = ',';
            pos += 1;
            pos += formatAmount(buf[pos..buf_len], amount) orelse return null;

            // ,Currency
            if (pos >= buf_len) return null;
            buf[pos] = ',';
            pos += 1;
            if (pos + 3 > buf_len) return null;
            @memcpy(buf[pos .. pos + 3], curr_ptr[0..3]);
            pos += 3;

            // ,Category
            if (pos >= buf_len) return null;
            buf[pos] = ',';
            pos += 1;
            const cat_name = types.Category.fromInt(cat).germanName();
            pos += csvEscapeField(buf[pos..buf_len], cat_name) orelse return null;

            // ,Account
            if (pos >= buf_len) return null;
            buf[pos] = ',';
            pos += 1;
            if (acct_ptr) |ap| {
                pos += csvEscapeField(buf[pos..buf_len], ap[0..acct_len]) orelse return null;
            }

            // Newline
            if (pos >= buf_len) return null;
            buf[pos] = '\n';
            pos += 1;
        }

        return pos;
    }

    /// Export the full database as JSON. All tables dumped into a single object.
    /// Returns bytes written, or null if buffer too small.
    pub fn exportDbJson(self: *Db, buf: [*]u8, buf_len: usize) DbError!?usize {
        var pos: usize = 0;

        // {"version":9,"exported_at":...,"transactions":
        const p1 = "{\"version\":9,\"exported_at\":";
        if (pos + p1.len > buf_len) return null;
        @memcpy(buf[pos .. pos + p1.len], p1);
        pos += p1.len;
        pos += formatSignedInt(buf[pos..buf_len], nowMs()) orelse return null;

        // ,"transactions":
        const p2 = ",\"transactions\":";
        if (pos + p2.len > buf_len) return null;
        @memcpy(buf[pos .. pos + p2.len], p2);
        pos += p2.len;
        const tx_len = try self.getTransactionsJson(buf + pos, buf_len - pos) orelse return null;
        pos += tx_len;

        // ,"accounts":
        const p3 = ",\"accounts\":";
        if (pos + p3.len > buf_len) return null;
        @memcpy(buf[pos .. pos + p3.len], p3);
        pos += p3.len;
        const acct_len = try self.getAccountsJson(buf + pos, buf_len - pos) orelse return null;
        pos += acct_len;

        // ,"debts":
        const p4 = ",\"debts\":";
        if (pos + p4.len > buf_len) return null;
        @memcpy(buf[pos .. pos + p4.len], p4);
        pos += p4.len;
        const debt_len = try self.getDebtsJson(buf + pos, buf_len - pos) orelse return null;
        pos += debt_len;

        // ,"recurring_patterns":
        const p5 = ",\"recurring_patterns\":";
        if (pos + p5.len > buf_len) return null;
        @memcpy(buf[pos .. pos + p5.len], p5);
        pos += p5.len;
        const rec_len = try self.getRecurringJson(buf + pos, buf_len - pos) orelse return null;
        pos += rec_len;

        // ,"snapshots":
        const p6 = ",\"snapshots\":";
        if (pos + p6.len > buf_len) return null;
        @memcpy(buf[pos .. pos + p6.len], p6);
        pos += p6.len;
        const snap_len = try self.getSnapshotsJson(buf + pos, buf_len - pos) orelse return null;
        pos += snap_len;

        // ,"rules":
        const p7 = ",\"rules\":";
        if (pos + p7.len > buf_len) return null;
        @memcpy(buf[pos .. pos + p7.len], p7);
        pos += p7.len;
        const rules_len = try self.getRulesJson(buf + pos, buf_len - pos) orelse return null;
        pos += rules_len;

        // ,"savings_goals":
        const p8 = ",\"savings_goals\":";
        if (pos + p8.len > buf_len) return null;
        @memcpy(buf[pos .. pos + p8.len], p8);
        pos += p8.len;
        const goals_len = try self.getGoalsJson(buf + pos, buf_len - pos) orelse return null;
        pos += goals_len;

        // Close object
        if (pos >= buf_len) return null;
        buf[pos] = '}';
        pos += 1;

        return pos;
    }

    /// Get all rules as JSON array.
    pub fn getRulesJson(self: *Db, buf: [*]u8, buf_len: usize) DbError!?usize {
        const sql = "SELECT id, pattern, category, priority FROM rules ORDER BY priority DESC;";
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);

        const s = stmt.?;
        var pos: usize = 0;

        if (pos >= buf_len) return null;
        buf[pos] = '[';
        pos += 1;

        var first = true;
        while (c.sqlite3_step(s) == c.SQLITE_ROW) {
            const id_val = c.sqlite3_column_int(s, 0);
            const pat_ptr = c.sqlite3_column_text(s, 1) orelse continue;
            const pat_len: usize = @intCast(c.sqlite3_column_bytes(s, 1));
            const category = c.sqlite3_column_int(s, 2);
            const priority = c.sqlite3_column_int(s, 3);

            if (!first) {
                if (pos >= buf_len) return null;
                buf[pos] = ',';
                pos += 1;
            }

            const q1 = "{\"id\":";
            if (pos + q1.len > buf_len) return null;
            @memcpy(buf[pos .. pos + q1.len], q1);
            pos += q1.len;
            pos += formatSignedInt(buf[pos..buf_len], @as(i64, id_val)) orelse return null;

            const q2 = ",\"pattern\":\"";
            if (pos + q2.len > buf_len) return null;
            @memcpy(buf[pos .. pos + q2.len], q2);
            pos += q2.len;
            pos += jsonEscapeString(buf[pos..buf_len], pat_ptr[0..pat_len]) orelse return null;

            const q3 = "\",\"category\":";
            if (pos + q3.len > buf_len) return null;
            @memcpy(buf[pos .. pos + q3.len], q3);
            pos += q3.len;
            pos += formatSignedInt(buf[pos..buf_len], @as(i64, category)) orelse return null;

            const q4 = ",\"priority\":";
            if (pos + q4.len > buf_len) return null;
            @memcpy(buf[pos .. pos + q4.len], q4);
            pos += q4.len;
            pos += formatSignedInt(buf[pos..buf_len], @as(i64, priority)) orelse return null;

            if (pos >= buf_len) return null;
            buf[pos] = '}';
            pos += 1;
            first = false;
        }

        if (pos >= buf_len) return null;
        buf[pos] = ']';
        pos += 1;

        return pos;
    }

    // --- Sync: getChangesJson / applyChanges ---

    /// Get all rows changed since `since_ts` as JSON matching the sync contract.
    /// Returns bytes written, or null if buffer too small.
    pub fn getChangesJson(self: *Db, since_ts: i64, buf: [*]u8, buf_len: usize) DbError!?usize {
        var pos: usize = 0;

        // Opening: {"rows":[
        const hdr = "{\"rows\":[";
        if (pos + hdr.len > buf_len) return null;
        @memcpy(buf[pos .. pos + hdr.len], hdr);
        pos += hdr.len;

        var first = true;

        // --- transactions ---
        {
            const sql =
                \\SELECT id, date_year, date_month, date_day, description, amount_cents, currency, category, account, excluded, updated_at
                \\FROM transactions WHERE updated_at >= ?1;
            ;
            var stmt: ?*c.sqlite3_stmt = null;
            if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
            defer _ = c.sqlite3_finalize(stmt.?);
            const s = stmt.?;
            if (c.sqlite3_bind_int64(s, 1, since_ts) != c.SQLITE_OK) return DbError.BindFailed;

            while (c.sqlite3_step(s) == c.SQLITE_ROW) {
                if (!first) {
                    if (pos >= buf_len) return null;
                    buf[pos] = ',';
                    pos += 1;
                }

                const id_ptr = c.sqlite3_column_text(s, 0) orelse continue;
                const id_len: usize = @intCast(c.sqlite3_column_bytes(s, 0));
                const year = c.sqlite3_column_int(s, 1);
                const month = c.sqlite3_column_int(s, 2);
                const day = c.sqlite3_column_int(s, 3);
                const desc_ptr = c.sqlite3_column_text(s, 4) orelse continue;
                const desc_len: usize = @intCast(c.sqlite3_column_bytes(s, 4));
                const amount = c.sqlite3_column_int64(s, 5);
                const curr_ptr = c.sqlite3_column_text(s, 6) orelse continue;
                const curr_len: usize = @intCast(c.sqlite3_column_bytes(s, 6));
                const cat = c.sqlite3_column_int(s, 7);
                const acct_ptr = c.sqlite3_column_text(s, 8);
                const acct_len: usize = @intCast(c.sqlite3_column_bytes(s, 8));
                const excl = c.sqlite3_column_int(s, 9);
                const updated = c.sqlite3_column_int64(s, 10);

                // {"table":"transactions","id":"...","data":{...},"updated_at":N}
                const p1 = "{\"table\":\"transactions\",\"id\":\"";
                if (pos + p1.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p1.len], p1);
                pos += p1.len;

                pos += jsonEscapeString(buf[pos..buf_len], id_ptr[0..id_len]) orelse return null;

                const p2 = "\",\"data\":{\"date_year\":";
                if (pos + p2.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p2.len], p2);
                pos += p2.len;

                pos += formatSignedInt(buf[pos..buf_len], @as(i64, year)) orelse return null;

                const p_dm = ",\"date_month\":";
                if (pos + p_dm.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p_dm.len], p_dm);
                pos += p_dm.len;
                pos += formatSignedInt(buf[pos..buf_len], @as(i64, month)) orelse return null;

                const p_dd = ",\"date_day\":";
                if (pos + p_dd.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p_dd.len], p_dd);
                pos += p_dd.len;
                pos += formatSignedInt(buf[pos..buf_len], @as(i64, day)) orelse return null;

                const p_desc = ",\"description\":\"";
                if (pos + p_desc.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p_desc.len], p_desc);
                pos += p_desc.len;
                pos += jsonEscapeString(buf[pos..buf_len], desc_ptr[0..desc_len]) orelse return null;

                const p_amt = "\",\"amount_cents\":";
                if (pos + p_amt.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p_amt.len], p_amt);
                pos += p_amt.len;
                pos += formatSignedInt(buf[pos..buf_len], amount) orelse return null;

                const p_cur = ",\"currency\":\"";
                if (pos + p_cur.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p_cur.len], p_cur);
                pos += p_cur.len;
                if (curr_len > 0) {
                    pos += jsonEscapeString(buf[pos..buf_len], curr_ptr[0..curr_len]) orelse return null;
                }

                const p_cat = "\",\"category\":";
                if (pos + p_cat.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p_cat.len], p_cat);
                pos += p_cat.len;
                pos += formatSignedInt(buf[pos..buf_len], @as(i64, cat)) orelse return null;

                const p_acct = ",\"account\":\"";
                if (pos + p_acct.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p_acct.len], p_acct);
                pos += p_acct.len;
                if (acct_ptr) |ap| {
                    pos += jsonEscapeString(buf[pos..buf_len], ap[0..acct_len]) orelse return null;
                }

                const p_excl = "\",\"excluded\":";
                if (pos + p_excl.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p_excl.len], p_excl);
                pos += p_excl.len;
                pos += formatSignedInt(buf[pos..buf_len], @as(i64, excl)) orelse return null;

                const p_close = "},\"updated_at\":";
                if (pos + p_close.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p_close.len], p_close);
                pos += p_close.len;
                pos += formatSignedInt(buf[pos..buf_len], updated) orelse return null;

                if (pos >= buf_len) return null;
                buf[pos] = '}';
                pos += 1;

                first = false;
            }
        }

        // --- debts ---
        {
            const sql = "SELECT id, name, total, paid, monthly, deleted, updated_at FROM debts WHERE updated_at >= ?1;";
            var stmt: ?*c.sqlite3_stmt = null;
            if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
            defer _ = c.sqlite3_finalize(stmt.?);
            const s = stmt.?;
            if (c.sqlite3_bind_int64(s, 1, since_ts) != c.SQLITE_OK) return DbError.BindFailed;

            while (c.sqlite3_step(s) == c.SQLITE_ROW) {
                if (!first) {
                    if (pos >= buf_len) return null;
                    buf[pos] = ',';
                    pos += 1;
                }

                const id_ptr = c.sqlite3_column_text(s, 0) orelse continue;
                const id_len: usize = @intCast(c.sqlite3_column_bytes(s, 0));
                const name_ptr = c.sqlite3_column_text(s, 1) orelse continue;
                const name_len: usize = @intCast(c.sqlite3_column_bytes(s, 1));
                const total = c.sqlite3_column_int64(s, 2);
                const paid = c.sqlite3_column_int64(s, 3);
                const monthly = c.sqlite3_column_int64(s, 4);
                const deleted = c.sqlite3_column_int(s, 5);
                const updated = c.sqlite3_column_int64(s, 6);

                const p1 = "{\"table\":\"debts\",\"id\":\"";
                if (pos + p1.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p1.len], p1);
                pos += p1.len;
                pos += jsonEscapeString(buf[pos..buf_len], id_ptr[0..id_len]) orelse return null;

                const p2 = "\",\"data\":{\"name\":\"";
                if (pos + p2.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p2.len], p2);
                pos += p2.len;
                pos += jsonEscapeString(buf[pos..buf_len], name_ptr[0..name_len]) orelse return null;

                const p3 = "\",\"total\":";
                if (pos + p3.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p3.len], p3);
                pos += p3.len;
                pos += formatSignedInt(buf[pos..buf_len], total) orelse return null;

                const p4 = ",\"paid\":";
                if (pos + p4.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p4.len], p4);
                pos += p4.len;
                pos += formatSignedInt(buf[pos..buf_len], paid) orelse return null;

                const p5 = ",\"monthly\":";
                if (pos + p5.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p5.len], p5);
                pos += p5.len;
                pos += formatSignedInt(buf[pos..buf_len], monthly) orelse return null;

                const p_del = ",\"deleted\":";
                if (pos + p_del.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p_del.len], p_del);
                pos += p_del.len;
                pos += formatSignedInt(buf[pos..buf_len], @as(i64, deleted)) orelse return null;

                const p_close = "},\"updated_at\":";
                if (pos + p_close.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p_close.len], p_close);
                pos += p_close.len;
                pos += formatSignedInt(buf[pos..buf_len], updated) orelse return null;

                if (pos >= buf_len) return null;
                buf[pos] = '}';
                pos += 1;
                first = false;
            }
        }

        // --- accounts ---
        {
            const sql = "SELECT id, name, bank, color, deleted, updated_at FROM accounts WHERE updated_at >= ?1;";
            var stmt: ?*c.sqlite3_stmt = null;
            if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
            defer _ = c.sqlite3_finalize(stmt.?);
            const s = stmt.?;
            if (c.sqlite3_bind_int64(s, 1, since_ts) != c.SQLITE_OK) return DbError.BindFailed;

            while (c.sqlite3_step(s) == c.SQLITE_ROW) {
                if (!first) {
                    if (pos >= buf_len) return null;
                    buf[pos] = ',';
                    pos += 1;
                }

                const id_ptr = c.sqlite3_column_text(s, 0) orelse continue;
                const id_len: usize = @intCast(c.sqlite3_column_bytes(s, 0));
                const name_ptr = c.sqlite3_column_text(s, 1) orelse continue;
                const name_len: usize = @intCast(c.sqlite3_column_bytes(s, 1));
                const bank_ptr = c.sqlite3_column_text(s, 2) orelse continue;
                const bank_len: usize = @intCast(c.sqlite3_column_bytes(s, 2));
                const color_ptr = c.sqlite3_column_text(s, 3) orelse continue;
                const color_len: usize = @intCast(c.sqlite3_column_bytes(s, 3));
                const deleted = c.sqlite3_column_int(s, 4);
                const updated = c.sqlite3_column_int64(s, 5);

                const p1 = "{\"table\":\"accounts\",\"id\":\"";
                if (pos + p1.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p1.len], p1);
                pos += p1.len;
                pos += jsonEscapeString(buf[pos..buf_len], id_ptr[0..id_len]) orelse return null;

                const p2 = "\",\"data\":{\"name\":\"";
                if (pos + p2.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p2.len], p2);
                pos += p2.len;
                pos += jsonEscapeString(buf[pos..buf_len], name_ptr[0..name_len]) orelse return null;

                const p3 = "\",\"bank\":\"";
                if (pos + p3.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p3.len], p3);
                pos += p3.len;
                pos += jsonEscapeString(buf[pos..buf_len], bank_ptr[0..bank_len]) orelse return null;

                const p4 = "\",\"color\":\"";
                if (pos + p4.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p4.len], p4);
                pos += p4.len;
                pos += jsonEscapeString(buf[pos..buf_len], color_ptr[0..color_len]) orelse return null;

                const p_del = "\",\"deleted\":";
                if (pos + p_del.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p_del.len], p_del);
                pos += p_del.len;
                pos += formatSignedInt(buf[pos..buf_len], @as(i64, deleted)) orelse return null;

                const p_close = "},\"updated_at\":";
                if (pos + p_close.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p_close.len], p_close);
                pos += p_close.len;
                pos += formatSignedInt(buf[pos..buf_len], updated) orelse return null;

                if (pos >= buf_len) return null;
                buf[pos] = '}';
                pos += 1;
                first = false;
            }
        }

        // --- recurring_patterns ---
        {
            const sql = "SELECT id, merchant, amount, interval, category, last_seen, next_due, active, prev_amount, updated_at FROM recurring_patterns WHERE updated_at >= ?1;";
            var stmt: ?*c.sqlite3_stmt = null;
            if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
            defer _ = c.sqlite3_finalize(stmt.?);
            const s = stmt.?;
            if (c.sqlite3_bind_int64(s, 1, since_ts) != c.SQLITE_OK) return DbError.BindFailed;

            while (c.sqlite3_step(s) == c.SQLITE_ROW) {
                if (!first) {
                    if (pos >= buf_len) return null;
                    buf[pos] = ',';
                    pos += 1;
                }

                const id_ptr = c.sqlite3_column_text(s, 0) orelse continue;
                const id_len: usize = @intCast(c.sqlite3_column_bytes(s, 0));
                const merch_ptr = c.sqlite3_column_text(s, 1) orelse continue;
                const merch_len: usize = @intCast(c.sqlite3_column_bytes(s, 1));
                const amount = c.sqlite3_column_int64(s, 2);
                const intv_ptr = c.sqlite3_column_text(s, 3) orelse continue;
                const intv_len: usize = @intCast(c.sqlite3_column_bytes(s, 3));
                const category = c.sqlite3_column_int(s, 4);
                const ls_ptr = c.sqlite3_column_text(s, 5) orelse continue;
                const ls_len: usize = @intCast(c.sqlite3_column_bytes(s, 5));
                const nd_ptr = c.sqlite3_column_text(s, 6);
                const nd_len: usize = @intCast(c.sqlite3_column_bytes(s, 6));
                const active = c.sqlite3_column_int(s, 7);
                const prev_amt_type = c.sqlite3_column_type(s, 8);
                const prev_amt: ?i64 = if (prev_amt_type == c.SQLITE_NULL) null else c.sqlite3_column_int64(s, 8);
                const updated = c.sqlite3_column_int64(s, 9);

                const p1 = "{\"table\":\"recurring_patterns\",\"id\":\"";
                if (pos + p1.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p1.len], p1);
                pos += p1.len;
                pos += jsonEscapeString(buf[pos..buf_len], id_ptr[0..id_len]) orelse return null;

                const p2 = "\",\"data\":{\"merchant\":\"";
                if (pos + p2.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p2.len], p2);
                pos += p2.len;
                pos += jsonEscapeString(buf[pos..buf_len], merch_ptr[0..merch_len]) orelse return null;

                const p3 = "\",\"amount\":";
                if (pos + p3.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p3.len], p3);
                pos += p3.len;
                pos += formatSignedInt(buf[pos..buf_len], amount) orelse return null;

                const p4 = ",\"interval\":\"";
                if (pos + p4.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p4.len], p4);
                pos += p4.len;
                pos += jsonEscapeString(buf[pos..buf_len], intv_ptr[0..intv_len]) orelse return null;

                const p5 = "\",\"category\":";
                if (pos + p5.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p5.len], p5);
                pos += p5.len;
                pos += formatSignedInt(buf[pos..buf_len], @as(i64, category)) orelse return null;

                const p6 = ",\"last_seen\":\"";
                if (pos + p6.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p6.len], p6);
                pos += p6.len;
                pos += jsonEscapeString(buf[pos..buf_len], ls_ptr[0..ls_len]) orelse return null;

                // next_due
                const p7 = "\",\"next_due\":";
                if (pos + p7.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p7.len], p7);
                pos += p7.len;
                if (nd_ptr) |nd| {
                    if (pos >= buf_len) return null;
                    buf[pos] = '"';
                    pos += 1;
                    pos += jsonEscapeString(buf[pos..buf_len], nd[0..nd_len]) orelse return null;
                    if (pos >= buf_len) return null;
                    buf[pos] = '"';
                    pos += 1;
                } else {
                    const null_s = "null";
                    if (pos + null_s.len > buf_len) return null;
                    @memcpy(buf[pos .. pos + null_s.len], null_s);
                    pos += null_s.len;
                }

                const p8 = ",\"active\":";
                if (pos + p8.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p8.len], p8);
                pos += p8.len;
                pos += formatSignedInt(buf[pos..buf_len], @as(i64, active)) orelse return null;

                // prev_amount
                const p9 = ",\"prev_amount\":";
                if (pos + p9.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p9.len], p9);
                pos += p9.len;
                if (prev_amt) |pa| {
                    pos += formatSignedInt(buf[pos..buf_len], pa) orelse return null;
                } else {
                    const null_s = "null";
                    if (pos + null_s.len > buf_len) return null;
                    @memcpy(buf[pos .. pos + null_s.len], null_s);
                    pos += null_s.len;
                }

                const p_close = "},\"updated_at\":";
                if (pos + p_close.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p_close.len], p_close);
                pos += p_close.len;
                pos += formatSignedInt(buf[pos..buf_len], updated) orelse return null;

                if (pos >= buf_len) return null;
                buf[pos] = '}';
                pos += 1;
                first = false;
            }
        }

        // --- snapshots ---
        {
            const sql = "SELECT id, date, net_worth, income, expenses, tx_count, breakdown, updated_at FROM snapshots WHERE updated_at >= ?1;";
            var stmt: ?*c.sqlite3_stmt = null;
            if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
            defer _ = c.sqlite3_finalize(stmt.?);
            const s = stmt.?;
            if (c.sqlite3_bind_int64(s, 1, since_ts) != c.SQLITE_OK) return DbError.BindFailed;

            while (c.sqlite3_step(s) == c.SQLITE_ROW) {
                if (!first) {
                    if (pos >= buf_len) return null;
                    buf[pos] = ',';
                    pos += 1;
                }

                const id_ptr = c.sqlite3_column_text(s, 0) orelse continue;
                const id_len: usize = @intCast(c.sqlite3_column_bytes(s, 0));
                const date_ptr = c.sqlite3_column_text(s, 1) orelse continue;
                const date_len: usize = @intCast(c.sqlite3_column_bytes(s, 1));
                const net_worth = c.sqlite3_column_int64(s, 2);
                const income = c.sqlite3_column_int64(s, 3);
                const expenses = c.sqlite3_column_int64(s, 4);
                const tx_count = c.sqlite3_column_int(s, 5);
                const bk_ptr = c.sqlite3_column_text(s, 6) orelse continue;
                const bk_len: usize = @intCast(c.sqlite3_column_bytes(s, 6));
                const updated = c.sqlite3_column_int64(s, 7);

                const p1 = "{\"table\":\"snapshots\",\"id\":\"";
                if (pos + p1.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p1.len], p1);
                pos += p1.len;
                pos += jsonEscapeString(buf[pos..buf_len], id_ptr[0..id_len]) orelse return null;

                const p2 = "\",\"data\":{\"date\":\"";
                if (pos + p2.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p2.len], p2);
                pos += p2.len;
                pos += jsonEscapeString(buf[pos..buf_len], date_ptr[0..date_len]) orelse return null;

                const p3 = "\",\"net_worth\":";
                if (pos + p3.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p3.len], p3);
                pos += p3.len;
                pos += formatSignedInt(buf[pos..buf_len], net_worth) orelse return null;

                const p4 = ",\"income\":";
                if (pos + p4.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p4.len], p4);
                pos += p4.len;
                pos += formatSignedInt(buf[pos..buf_len], income) orelse return null;

                const p5 = ",\"expenses\":";
                if (pos + p5.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p5.len], p5);
                pos += p5.len;
                pos += formatSignedInt(buf[pos..buf_len], expenses) orelse return null;

                const p6 = ",\"tx_count\":";
                if (pos + p6.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p6.len], p6);
                pos += p6.len;
                pos += formatSignedInt(buf[pos..buf_len], @as(i64, tx_count)) orelse return null;

                // breakdown is stored as JSON string — embed escaped
                const p7 = ",\"breakdown\":\"";
                if (pos + p7.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p7.len], p7);
                pos += p7.len;
                pos += jsonEscapeString(buf[pos..buf_len], bk_ptr[0..bk_len]) orelse return null;

                const p_close = "\"},\"updated_at\":";
                if (pos + p_close.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p_close.len], p_close);
                pos += p_close.len;
                pos += formatSignedInt(buf[pos..buf_len], updated) orelse return null;

                if (pos >= buf_len) return null;
                buf[pos] = '}';
                pos += 1;
                first = false;
            }
        }

        // --- savings_goals ---
        {
            const sql = "SELECT id, name, icon, target, current, deadline, deleted, updated_at FROM savings_goals WHERE updated_at >= ?1;";
            var stmt: ?*c.sqlite3_stmt = null;
            if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
            defer _ = c.sqlite3_finalize(stmt.?);
            const s = stmt.?;
            if (c.sqlite3_bind_int64(s, 1, since_ts) != c.SQLITE_OK) return DbError.BindFailed;

            while (c.sqlite3_step(s) == c.SQLITE_ROW) {
                if (!first) {
                    if (pos >= buf_len) return null;
                    buf[pos] = ',';
                    pos += 1;
                }

                const id_ptr = c.sqlite3_column_text(s, 0) orelse continue;
                const id_len: usize = @intCast(c.sqlite3_column_bytes(s, 0));
                const name_ptr = c.sqlite3_column_text(s, 1) orelse continue;
                const name_len: usize = @intCast(c.sqlite3_column_bytes(s, 1));
                const icon_ptr = c.sqlite3_column_text(s, 2) orelse continue;
                const icon_len: usize = @intCast(c.sqlite3_column_bytes(s, 2));
                const target = c.sqlite3_column_int64(s, 3);
                const current = c.sqlite3_column_int64(s, 4);
                const dl_type = c.sqlite3_column_type(s, 5);
                const deleted = c.sqlite3_column_int(s, 6);
                const updated = c.sqlite3_column_int64(s, 7);

                const p1 = "{\"table\":\"savings_goals\",\"id\":\"";
                if (pos + p1.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p1.len], p1);
                pos += p1.len;
                pos += jsonEscapeString(buf[pos..buf_len], id_ptr[0..id_len]) orelse return null;

                const p2 = "\",\"data\":{\"name\":\"";
                if (pos + p2.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p2.len], p2);
                pos += p2.len;
                pos += jsonEscapeString(buf[pos..buf_len], name_ptr[0..name_len]) orelse return null;

                const p3 = "\",\"icon\":\"";
                if (pos + p3.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p3.len], p3);
                pos += p3.len;
                pos += jsonEscapeString(buf[pos..buf_len], icon_ptr[0..icon_len]) orelse return null;

                const p4 = "\",\"target\":";
                if (pos + p4.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p4.len], p4);
                pos += p4.len;
                pos += formatSignedInt(buf[pos..buf_len], target) orelse return null;

                const p5 = ",\"current\":";
                if (pos + p5.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p5.len], p5);
                pos += p5.len;
                pos += formatSignedInt(buf[pos..buf_len], current) orelse return null;

                // deadline
                const p_dl = ",\"deadline\":";
                if (pos + p_dl.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p_dl.len], p_dl);
                pos += p_dl.len;
                if (dl_type != c.SQLITE_NULL) {
                    const dl_ptr = c.sqlite3_column_text(s, 5);
                    if (dl_ptr) |dp| {
                        const dl_len: usize = @intCast(c.sqlite3_column_bytes(s, 5));
                        if (pos >= buf_len) return null;
                        buf[pos] = '"';
                        pos += 1;
                        pos += jsonEscapeString(buf[pos..buf_len], dp[0..dl_len]) orelse return null;
                        if (pos >= buf_len) return null;
                        buf[pos] = '"';
                        pos += 1;
                    } else {
                        const ns = "null";
                        if (pos + ns.len > buf_len) return null;
                        @memcpy(buf[pos .. pos + ns.len], ns);
                        pos += ns.len;
                    }
                } else {
                    const ns = "null";
                    if (pos + ns.len > buf_len) return null;
                    @memcpy(buf[pos .. pos + ns.len], ns);
                    pos += ns.len;
                }

                const p_del = ",\"deleted\":";
                if (pos + p_del.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p_del.len], p_del);
                pos += p_del.len;
                pos += formatSignedInt(buf[pos..buf_len], @as(i64, deleted)) orelse return null;

                const p_close = "},\"updated_at\":";
                if (pos + p_close.len > buf_len) return null;
                @memcpy(buf[pos .. pos + p_close.len], p_close);
                pos += p_close.len;
                pos += formatSignedInt(buf[pos..buf_len], updated) orelse return null;

                if (pos >= buf_len) return null;
                buf[pos] = '}';
                pos += 1;
                first = false;
            }
        }

        // Close: ]}
        const footer = "]}";
        if (pos + footer.len > buf_len) return null;
        @memcpy(buf[pos .. pos + footer.len], footer);
        pos += footer.len;

        return pos;
    }

    /// Apply incoming sync changes (JSON). Returns count of applied rows.
    /// Expects JSON: {"rows":[{"table":"...","id":"...","data":{...},"updated_at":N},...]}
    pub fn applyChanges(self: *Db, json: []const u8) DbError!i32 {
        // Find the "rows" array
        const rows_key = "\"rows\"";
        const rows_pos = findInSlice(json, rows_key) orelse return 0;
        var i = rows_pos + rows_key.len;

        // Skip to '['
        while (i < json.len and json[i] != '[') : (i += 1) {}
        if (i >= json.len) return 0;
        i += 1; // skip '['

        var applied: i32 = 0;

        while (i < json.len) {
            // Skip whitespace/commas
            while (i < json.len and (json[i] == ' ' or json[i] == ',' or json[i] == '\n' or json[i] == '\r' or json[i] == '\t')) : (i += 1) {}
            if (i >= json.len or json[i] == ']') break;
            if (json[i] != '{') break;

            // Find matching closing brace for this row object (skip quoted strings)
            const obj_start = i;
            var depth: i32 = 0;
            while (i < json.len) : (i += 1) {
                if (json[i] == '"') {
                    i += 1; // skip opening quote
                    while (i < json.len) : (i += 1) {
                        if (json[i] == '\\') {
                            i += 1;
                            continue;
                        }
                        if (json[i] == '"') break;
                    }
                    continue;
                }
                if (json[i] == '{') depth += 1;
                if (json[i] == '}') {
                    depth -= 1;
                    if (depth == 0) {
                        i += 1;
                        break;
                    }
                }
            }
            const obj = json[obj_start..i];

            // Extract fields
            const table = jsonExtractStringFromSlice(obj, "\"table\"") orelse continue;
            const row_id = jsonExtractStringFromSlice(obj, "\"id\"") orelse continue;
            const updated_at = jsonExtractI64FromSlice(obj, "\"updated_at\"");
            if (updated_at == 0) continue;

            // Check local updated_at
            if (std.mem.eql(u8, table, "transactions")) {
                const local_ts = self.getRowUpdatedAt("transactions", row_id);
                if (updated_at <= local_ts) continue;
                // Extract data fields and INSERT OR REPLACE
                const data_str = self.extractDataObject(obj) orelse continue;
                self.applyTransactionChange(row_id, data_str, updated_at) catch continue;
                applied += 1;
            } else if (std.mem.eql(u8, table, "debts")) {
                const local_ts = self.getRowUpdatedAt("debts", row_id);
                if (updated_at <= local_ts) continue;
                const data_str = self.extractDataObject(obj) orelse continue;
                const is_deleted = jsonExtractI64FromSlice(data_str, "\"deleted\"");
                if (is_deleted != 0) {
                    self.applySoftDelete("debts", row_id, updated_at) catch continue;
                } else {
                    self.applyDebtChange(row_id, data_str, updated_at) catch continue;
                }
                applied += 1;
            } else if (std.mem.eql(u8, table, "accounts")) {
                const local_ts = self.getRowUpdatedAt("accounts", row_id);
                if (updated_at <= local_ts) continue;
                const data_str = self.extractDataObject(obj) orelse continue;
                const is_deleted = jsonExtractI64FromSlice(data_str, "\"deleted\"");
                if (is_deleted != 0) {
                    self.applySoftDelete("accounts", row_id, updated_at) catch continue;
                } else {
                    self.applyAccountChange(row_id, data_str, updated_at) catch continue;
                }
                applied += 1;
            } else if (std.mem.eql(u8, table, "recurring_patterns")) {
                const local_ts = self.getRowUpdatedAt("recurring_patterns", row_id);
                if (updated_at <= local_ts) continue;
                const data_str = self.extractDataObject(obj) orelse continue;
                self.applyRecurringChange(row_id, data_str, updated_at) catch continue;
                applied += 1;
            } else if (std.mem.eql(u8, table, "snapshots")) {
                const local_ts = self.getRowUpdatedAt("snapshots", row_id);
                if (updated_at <= local_ts) continue;
                const data_str = self.extractDataObject(obj) orelse continue;
                self.applySnapshotChange(row_id, data_str, updated_at) catch continue;
                applied += 1;
            } else if (std.mem.eql(u8, table, "savings_goals")) {
                const local_ts = self.getRowUpdatedAt("savings_goals", row_id);
                if (updated_at <= local_ts) continue;
                const data_str = self.extractDataObject(obj) orelse continue;
                const is_deleted = jsonExtractI64FromSlice(data_str, "\"deleted\"");
                if (is_deleted != 0) {
                    self.applySoftDelete("savings_goals", row_id, updated_at) catch continue;
                } else {
                    self.applyGoalChange(row_id, data_str, updated_at) catch continue;
                }
                applied += 1;
            }
        }

        return applied;
    }

    fn getRowUpdatedAt(self: *Db, table: []const u8, row_id: []const u8) i64 {
        // Build query: SELECT updated_at FROM {table} WHERE id = ?1
        // We only support known tables to avoid SQL injection
        const sql: [*:0]const u8 = if (std.mem.eql(u8, table, "transactions"))
            "SELECT updated_at FROM transactions WHERE id = ?1;"
        else if (std.mem.eql(u8, table, "debts"))
            "SELECT updated_at FROM debts WHERE id = ?1;"
        else if (std.mem.eql(u8, table, "accounts"))
            "SELECT updated_at FROM accounts WHERE id = ?1;"
        else if (std.mem.eql(u8, table, "recurring_patterns"))
            "SELECT updated_at FROM recurring_patterns WHERE id = ?1;"
        else if (std.mem.eql(u8, table, "snapshots"))
            "SELECT updated_at FROM snapshots WHERE id = ?1;"
        else if (std.mem.eql(u8, table, "savings_goals"))
            "SELECT updated_at FROM savings_goals WHERE id = ?1;"
        else
            return 0;

        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return 0;
        defer _ = c.sqlite3_finalize(stmt.?);
        const s = stmt.?;
        if (c.sqlite3_bind_text(s, 1, @ptrCast(row_id.ptr), @intCast(row_id.len), c.SQLITE_STATIC) != c.SQLITE_OK) return 0;
        if (c.sqlite3_step(s) != c.SQLITE_ROW) return 0;
        return c.sqlite3_column_int64(s, 0);
    }

    fn extractDataObject(_: *Db, obj: []const u8) ?[]const u8 {
        const key = "\"data\"";
        const key_pos = findInSlice(obj, key) orelse return null;
        var j = key_pos + key.len;
        while (j < obj.len and (obj[j] == ' ' or obj[j] == ':' or obj[j] == '\t')) : (j += 1) {}
        if (j >= obj.len or obj[j] != '{') return null;
        const start = j;
        var depth: i32 = 0;
        while (j < obj.len) : (j += 1) {
            if (obj[j] == '"') {
                j += 1; // skip opening quote
                while (j < obj.len) : (j += 1) {
                    if (obj[j] == '\\') {
                        j += 1;
                        continue;
                    }
                    if (obj[j] == '"') break;
                }
                continue;
            }
            if (obj[j] == '{') depth += 1;
            if (obj[j] == '}') {
                depth -= 1;
                if (depth == 0) return obj[start .. j + 1];
            }
        }
        return null;
    }

    fn applyTransactionChange(self: *Db, row_id: []const u8, data: []const u8, updated_at: i64) DbError!void {
        const date_year = jsonExtractI64FromSlice(data, "\"date_year\"");
        const date_month = jsonExtractI64FromSlice(data, "\"date_month\"");
        const date_day = jsonExtractI64FromSlice(data, "\"date_day\"");
        const desc_escaped = jsonExtractStringFromSlice(data, "\"description\"") orelse return DbError.ExecFailed;
        const amount = jsonExtractI64FromSlice(data, "\"amount_cents\"");
        const curr_escaped = jsonExtractStringFromSlice(data, "\"currency\"") orelse "EUR";
        const category = jsonExtractI64FromSlice(data, "\"category\"");
        const acct_escaped = jsonExtractStringFromSlice(data, "\"account\"") orelse "";
        const excluded = jsonExtractI64FromSlice(data, "\"excluded\"");

        // Unescape JSON strings before storing in SQLite
        var desc_buf: [4096]u8 = undefined;
        const desc_len = jsonUnescapeString(&desc_buf, desc_escaped) orelse return DbError.ExecFailed;
        const desc = desc_buf[0..desc_len];

        var curr_buf: [16]u8 = undefined;
        const curr_len = jsonUnescapeString(&curr_buf, curr_escaped) orelse return DbError.ExecFailed;
        const currency = curr_buf[0..curr_len];

        var acct_buf: [256]u8 = undefined;
        const acct_len = jsonUnescapeString(&acct_buf, acct_escaped) orelse return DbError.ExecFailed;
        const account = acct_buf[0..acct_len];

        const sql =
            \\INSERT OR REPLACE INTO transactions
            \\  (id, date_year, date_month, date_day, description, amount_cents, currency, category, account, excluded, updated_at)
            \\VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11);
        ;
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);
        const s = stmt.?;
        if (c.sqlite3_bind_text(s, 1, @ptrCast(row_id.ptr), @intCast(row_id.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 2, date_year) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 3, date_month) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 4, date_day) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 5, @ptrCast(desc.ptr), @intCast(desc.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 6, amount) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 7, @ptrCast(currency.ptr), @intCast(currency.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 8, category) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 9, @ptrCast(account.ptr), @intCast(account.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 10, excluded) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 11, updated_at) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;
    }

    fn applyDebtChange(self: *Db, row_id: []const u8, data: []const u8, updated_at: i64) DbError!void {
        const name_escaped = jsonExtractStringFromSlice(data, "\"name\"") orelse return DbError.ExecFailed;
        const total = jsonExtractI64FromSlice(data, "\"total\"");
        const paid = jsonExtractI64FromSlice(data, "\"paid\"");
        const monthly = jsonExtractI64FromSlice(data, "\"monthly\"");

        var name_buf: [512]u8 = undefined;
        const name_len = jsonUnescapeString(&name_buf, name_escaped) orelse return DbError.ExecFailed;
        const name = name_buf[0..name_len];

        const sql = "INSERT OR REPLACE INTO debts (id, name, total, paid, monthly, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6);";
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);
        const s = stmt.?;
        if (c.sqlite3_bind_text(s, 1, @ptrCast(row_id.ptr), @intCast(row_id.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 2, @ptrCast(name.ptr), @intCast(name.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 3, total) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 4, paid) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 5, monthly) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 6, updated_at) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;
    }

    fn applyAccountChange(self: *Db, row_id: []const u8, data: []const u8, updated_at: i64) DbError!void {
        const name_escaped = jsonExtractStringFromSlice(data, "\"name\"") orelse return DbError.ExecFailed;
        const bank_escaped = jsonExtractStringFromSlice(data, "\"bank\"") orelse "";
        const color_escaped = jsonExtractStringFromSlice(data, "\"color\"") orelse "#4361ee";

        var name_buf: [256]u8 = undefined;
        const name_len = jsonUnescapeString(&name_buf, name_escaped) orelse return DbError.ExecFailed;
        const name = name_buf[0..name_len];

        var bank_buf: [256]u8 = undefined;
        const bank_len = jsonUnescapeString(&bank_buf, bank_escaped) orelse return DbError.ExecFailed;
        const bank = bank_buf[0..bank_len];

        var color_buf: [32]u8 = undefined;
        const color_len = jsonUnescapeString(&color_buf, color_escaped) orelse return DbError.ExecFailed;
        const color = color_buf[0..color_len];

        const sql = "INSERT OR REPLACE INTO accounts (id, name, bank, color, updated_at) VALUES (?1, ?2, ?3, ?4, ?5);";
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);
        const s = stmt.?;
        if (c.sqlite3_bind_text(s, 1, @ptrCast(row_id.ptr), @intCast(row_id.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 2, @ptrCast(name.ptr), @intCast(name.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 3, @ptrCast(bank.ptr), @intCast(bank.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 4, @ptrCast(color.ptr), @intCast(color.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 5, updated_at) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;
    }

    fn applyRecurringChange(self: *Db, row_id: []const u8, data: []const u8, updated_at: i64) DbError!void {
        const merchant_escaped = jsonExtractStringFromSlice(data, "\"merchant\"") orelse return DbError.ExecFailed;
        const amount = jsonExtractI64FromSlice(data, "\"amount\"");
        const interval_escaped = jsonExtractStringFromSlice(data, "\"interval\"") orelse return DbError.ExecFailed;
        const category = jsonExtractI64FromSlice(data, "\"category\"");
        const last_seen_escaped = jsonExtractStringFromSlice(data, "\"last_seen\"") orelse return DbError.ExecFailed;
        const next_due_escaped = jsonExtractStringFromSlice(data, "\"next_due\"");
        const active = jsonExtractI64FromSlice(data, "\"active\"");
        const prev_amount = jsonExtractI64FromSlice(data, "\"prev_amount\"");

        var merch_buf: [512]u8 = undefined;
        const merch_len = jsonUnescapeString(&merch_buf, merchant_escaped) orelse return DbError.ExecFailed;
        const merchant = merch_buf[0..merch_len];

        var intv_buf: [32]u8 = undefined;
        const intv_len = jsonUnescapeString(&intv_buf, interval_escaped) orelse return DbError.ExecFailed;
        const interval_str = intv_buf[0..intv_len];

        var ls_buf: [32]u8 = undefined;
        const ls_len = jsonUnescapeString(&ls_buf, last_seen_escaped) orelse return DbError.ExecFailed;
        const last_seen = ls_buf[0..ls_len];

        var nd_buf: [32]u8 = undefined;
        var nd_slice: ?[]const u8 = null;
        if (next_due_escaped) |nde| {
            const nd_len = jsonUnescapeString(&nd_buf, nde) orelse return DbError.ExecFailed;
            nd_slice = nd_buf[0..nd_len];
        }

        const sql = "INSERT OR REPLACE INTO recurring_patterns (id, merchant, amount, interval, category, last_seen, next_due, active, prev_amount, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10);";
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);
        const s = stmt.?;
        if (c.sqlite3_bind_text(s, 1, @ptrCast(row_id.ptr), @intCast(row_id.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 2, @ptrCast(merchant.ptr), @intCast(merchant.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 3, amount) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 4, @ptrCast(interval_str.ptr), @intCast(interval_str.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 5, category) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 6, @ptrCast(last_seen.ptr), @intCast(last_seen.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (nd_slice) |nd| {
            if (c.sqlite3_bind_text(s, 7, @ptrCast(nd.ptr), @intCast(nd.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        } else {
            if (c.sqlite3_bind_null(s, 7) != c.SQLITE_OK) return DbError.BindFailed;
        }
        if (c.sqlite3_bind_int64(s, 8, active) != c.SQLITE_OK) return DbError.BindFailed;
        if (prev_amount != 0) {
            if (c.sqlite3_bind_int64(s, 9, prev_amount) != c.SQLITE_OK) return DbError.BindFailed;
        } else {
            if (c.sqlite3_bind_null(s, 9) != c.SQLITE_OK) return DbError.BindFailed;
        }
        if (c.sqlite3_bind_int64(s, 10, updated_at) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;
    }

    fn applySnapshotChange(self: *Db, row_id: []const u8, data: []const u8, updated_at: i64) DbError!void {
        const date_escaped = jsonExtractStringFromSlice(data, "\"date\"") orelse return DbError.ExecFailed;
        const net_worth = jsonExtractI64FromSlice(data, "\"net_worth\"");
        const income = jsonExtractI64FromSlice(data, "\"income\"");
        const expenses = jsonExtractI64FromSlice(data, "\"expenses\"");
        const tx_count = jsonExtractI64FromSlice(data, "\"tx_count\"");
        const breakdown_escaped = jsonExtractStringFromSlice(data, "\"breakdown\"") orelse "[]";

        var date_buf: [32]u8 = undefined;
        const date_len = jsonUnescapeString(&date_buf, date_escaped) orelse return DbError.ExecFailed;
        const date = date_buf[0..date_len];

        var bk_buf: [4096]u8 = undefined;
        const bk_len = jsonUnescapeString(&bk_buf, breakdown_escaped) orelse return DbError.ExecFailed;
        const breakdown = bk_buf[0..bk_len];

        const sql = "INSERT OR REPLACE INTO snapshots (id, date, net_worth, income, expenses, tx_count, breakdown, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8);";
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);
        const s = stmt.?;
        if (c.sqlite3_bind_text(s, 1, @ptrCast(row_id.ptr), @intCast(row_id.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 2, @ptrCast(date.ptr), @intCast(date.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 3, net_worth) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 4, income) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 5, expenses) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 6, tx_count) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 7, @ptrCast(breakdown.ptr), @intCast(breakdown.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 8, updated_at) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;
    }

    fn applyGoalChange(self: *Db, row_id: []const u8, data_slice: []const u8, updated_at: i64) DbError!void {
        const name_escaped = jsonExtractStringFromSlice(data_slice, "\"name\"") orelse return DbError.ExecFailed;
        const icon_escaped = jsonExtractStringFromSlice(data_slice, "\"icon\"") orelse "🎯";
        const target = jsonExtractI64FromSlice(data_slice, "\"target\"");
        const current = jsonExtractI64FromSlice(data_slice, "\"current\"");
        const deadline_escaped = jsonExtractStringFromSlice(data_slice, "\"deadline\"");

        var name_buf: [512]u8 = undefined;
        const name_len = jsonUnescapeString(&name_buf, name_escaped) orelse return DbError.ExecFailed;
        const name = name_buf[0..name_len];

        var icon_buf: [32]u8 = undefined;
        const icon_len = jsonUnescapeString(&icon_buf, icon_escaped) orelse return DbError.ExecFailed;
        const icon = icon_buf[0..icon_len];

        var dl_buf: [32]u8 = undefined;
        var dl_slice: ?[]const u8 = null;
        if (deadline_escaped) |dle| {
            const dl_len = jsonUnescapeString(&dl_buf, dle) orelse return DbError.ExecFailed;
            dl_slice = dl_buf[0..dl_len];
        }

        const sql = "INSERT OR REPLACE INTO savings_goals (id, name, icon, target, current, deadline, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7);";
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);
        const s = stmt.?;
        if (c.sqlite3_bind_text(s, 1, @ptrCast(row_id.ptr), @intCast(row_id.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 2, @ptrCast(name.ptr), @intCast(name.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_text(s, 3, @ptrCast(icon.ptr), @intCast(icon.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 4, target) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 5, current) != c.SQLITE_OK) return DbError.BindFailed;
        if (dl_slice) |dl| {
            if (c.sqlite3_bind_text(s, 6, @ptrCast(dl.ptr), @intCast(dl.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        } else {
            if (c.sqlite3_bind_null(s, 6) != c.SQLITE_OK) return DbError.BindFailed;
        }
        if (c.sqlite3_bind_int64(s, 7, updated_at) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;
    }

    /// Apply a soft-delete from sync: mark the row as deleted locally.
    fn applySoftDelete(self: *Db, table: []const u8, row_id: []const u8, updated_at: i64) DbError!void {
        const sql: [*:0]const u8 = if (std.mem.eql(u8, table, "debts"))
            "UPDATE debts SET deleted = 1, updated_at = ?2 WHERE id = ?1;"
        else if (std.mem.eql(u8, table, "accounts"))
            "UPDATE accounts SET deleted = 1, updated_at = ?2 WHERE id = ?1;"
        else if (std.mem.eql(u8, table, "savings_goals"))
            "UPDATE savings_goals SET deleted = 1, updated_at = ?2 WHERE id = ?1;"
        else
            return;

        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);
        const s = stmt.?;
        if (c.sqlite3_bind_text(s, 1, @ptrCast(row_id.ptr), @intCast(row_id.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_bind_int64(s, 2, updated_at) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_step(s) != c.SQLITE_DONE) return DbError.StepFailed;
    }
};

fn jsonFormatTransaction(
    buf: []u8,
    buf_len: usize,
    first: bool,
    id_ptr: [*]const u8,
    year: u16,
    month: u8,
    day: u8,
    desc_ptr: [*]const u8,
    desc_len: usize,
    amount_cents: i64,
    curr_ptr: [*]const u8,
    category: u8,
    account: []const u8,
    excluded: u8,
) ?usize {
    _ = buf_len;

    // Build JSON manually to avoid allocator dependency
    var pos: usize = 0;

    if (!first) {
        if (pos >= buf.len) return null;
        buf[pos] = ',';
        pos += 1;
    }

    // {"id":"
    const prefix = "{\"id\":\"";
    if (pos + prefix.len > buf.len) return null;
    @memcpy(buf[pos .. pos + prefix.len], prefix);

    pos += prefix.len;

    // id value (32 hex chars)
    if (pos + 32 > buf.len) return null;
    @memcpy(buf[pos .. pos + 32], id_ptr[0..32]);
    pos += 32;

    // ","date":"YYYY-MM-DD"
    const date_pre = "\",\"date\":\"";
    if (pos + date_pre.len + 10 > buf.len) return null;
    @memcpy(buf[pos .. pos + date_pre.len], date_pre);
    pos += date_pre.len;

    // Format date
    pos += formatDate(buf[pos..], year, month, day) orelse return null;

    // ","description":"
    const desc_pre = "\",\"description\":\"";
    if (pos + desc_pre.len > buf.len) return null;
    @memcpy(buf[pos .. pos + desc_pre.len], desc_pre);
    pos += desc_pre.len;

    // Escaped description
    pos += jsonEscapeString(buf[pos..], desc_ptr[0..desc_len]) orelse return null;

    // ","amount":
    const amt_pre = "\",\"amount\":";
    if (pos + amt_pre.len > buf.len) return null;
    @memcpy(buf[pos .. pos + amt_pre.len], amt_pre);
    pos += amt_pre.len;

    // Format amount as decimal (cents -> X.XX)
    pos += formatAmount(buf[pos..], amount_cents) orelse return null;

    // ,"currency":"
    const cur_pre = ",\"currency\":\"";
    if (pos + cur_pre.len + 3 > buf.len) return null;
    @memcpy(buf[pos .. pos + cur_pre.len], cur_pre);
    pos += cur_pre.len;
    @memcpy(buf[pos .. pos + 3], curr_ptr[0..3]);
    pos += 3;

    // ","category":N
    const cat_pre = "\",\"category\":";
    if (pos + cat_pre.len > buf.len) return null;
    @memcpy(buf[pos .. pos + cat_pre.len], cat_pre);
    pos += cat_pre.len;

    pos += formatInt(buf[pos..], category) orelse return null;

    // ,"account":"..."
    const acct_pre = ",\"account\":\"";
    if (pos + acct_pre.len > buf.len) return null;
    @memcpy(buf[pos .. pos + acct_pre.len], acct_pre);
    pos += acct_pre.len;
    pos += jsonEscapeString(buf[pos..], account) orelse return null;

    // ","excluded":N
    const excl_pre = "\",\"excluded\":";
    if (pos + excl_pre.len > buf.len) return null;
    @memcpy(buf[pos .. pos + excl_pre.len], excl_pre);
    pos += excl_pre.len;
    pos += formatInt(buf[pos..], excluded) orelse return null;

    // }
    if (pos >= buf.len) return null;
    buf[pos] = '}';
    pos += 1;

    return pos;
}

fn formatDate(buf: []u8, year: u16, month: u8, day: u8) ?usize {
    if (buf.len < 10) return null;
    // YYYY-MM-DD
    buf[0] = '0' + @as(u8, @intCast(year / 1000));
    buf[1] = '0' + @as(u8, @intCast((year / 100) % 10));
    buf[2] = '0' + @as(u8, @intCast((year / 10) % 10));
    buf[3] = '0' + @as(u8, @intCast(year % 10));
    buf[4] = '-';
    buf[5] = '0' + month / 10;
    buf[6] = '0' + month % 10;
    buf[7] = '-';
    buf[8] = '0' + day / 10;
    buf[9] = '0' + day % 10;
    return 10;
}

pub fn formatSignedInt(buf: []u8, value: i64) ?usize {
    var pos: usize = 0;
    var val = value;
    if (val < 0) {
        if (pos >= buf.len) return null;
        buf[pos] = '-';
        pos += 1;
        val = -val;
    }
    pos += formatInt(buf[pos..], @as(u64, @intCast(val))) orelse return null;
    return pos;
}

fn parseI64(s: []const u8) i64 {
    var result: i64 = 0;
    var negative = false;
    for (s) |ch| {
        if (ch == '-') {
            negative = true;
        } else if (ch >= '0' and ch <= '9') {
            result = result * 10 + @as(i64, ch - '0');
        }
    }
    return if (negative) -result else result;
}

fn jsonExtractStringFromSlice(json: []const u8, key: []const u8) ?[]const u8 {
    const key_pos = findInSlice(json, key) orelse return null;
    var i = key_pos + key.len;
    while (i < json.len and (json[i] == ' ' or json[i] == ':' or json[i] == '\t')) : (i += 1) {}
    if (i >= json.len or json[i] != '"') return null;
    i += 1;
    const start = i;
    while (i < json.len) : (i += 1) {
        if (json[i] == '\\') {
            i += 1; // skip escaped char
            continue;
        }
        if (json[i] == '"') break;
    }
    if (i >= json.len) return null;
    return json[start..i];
}

fn jsonExtractI64FromSlice(json: []const u8, key: []const u8) i64 {
    const key_pos = findInSlice(json, key) orelse return 0;
    var i = key_pos + key.len;
    while (i < json.len and (json[i] == ' ' or json[i] == ':' or json[i] == '\t')) : (i += 1) {}
    var negative = false;
    if (i < json.len and json[i] == '-') {
        negative = true;
        i += 1;
    }
    var result: i64 = 0;
    while (i < json.len and json[i] >= '0' and json[i] <= '9') : (i += 1) {
        result = result * 10 + @as(i64, json[i] - '0');
    }
    return if (negative) -result else result;
}

fn findInSlice(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0) return 0;
    if (haystack.len < needle.len) return null;
    const limit = haystack.len - needle.len + 1;
    for (0..limit) |i| {
        if (std.mem.eql(u8, haystack[i .. i + needle.len], needle)) return i;
    }
    return null;
}

pub fn formatAmount(buf: []u8, cents: i64) ?usize {
    var pos: usize = 0;
    var val = cents;

    if (val < 0) {
        if (pos >= buf.len) return null;
        buf[pos] = '-';
        pos += 1;
        val = -val;
    }

    const whole: u64 = @intCast(@divTrunc(val, 100));
    const frac: u64 = @intCast(@mod(val, 100));

    pos += formatInt(buf[pos..], whole) orelse return null;

    if (pos >= buf.len) return null;
    buf[pos] = '.';
    pos += 1;

    if (pos + 2 > buf.len) return null;
    buf[pos] = '0' + @as(u8, @intCast(frac / 10));
    buf[pos + 1] = '0' + @as(u8, @intCast(frac % 10));
    pos += 2;

    return pos;
}

pub fn formatInt(buf: []u8, value: anytype) ?usize {
    var val = value;
    if (val == 0) {
        if (buf.len < 1) return null;
        buf[0] = '0';
        return 1;
    }

    // Write digits in reverse, then flip
    var tmp: [20]u8 = undefined;
    var len: usize = 0;
    while (val > 0) : (len += 1) {
        tmp[len] = '0' + @as(u8, @intCast(@mod(val, 10)));
        val = @divTrunc(val, 10);
    }

    if (len > buf.len) return null;
    for (0..len) |i| {
        buf[i] = tmp[len - 1 - i];
    }
    return len;
}

fn csvEscapeField(buf: []u8, src: []const u8) ?usize {
    // Check if quoting is needed
    var needs_quote = false;
    for (src) |ch| {
        if (ch == ',' or ch == '"' or ch == '\n' or ch == '\r') {
            needs_quote = true;
            break;
        }
    }
    if (!needs_quote) {
        if (src.len > buf.len) return null;
        @memcpy(buf[0..src.len], src);
        return src.len;
    }

    var pos: usize = 0;
    if (pos >= buf.len) return null;
    buf[pos] = '"';
    pos += 1;
    for (src) |ch| {
        if (ch == '"') {
            if (pos + 2 > buf.len) return null;
            buf[pos] = '"';
            buf[pos + 1] = '"';
            pos += 2;
        } else {
            if (pos >= buf.len) return null;
            buf[pos] = ch;
            pos += 1;
        }
    }
    if (pos >= buf.len) return null;
    buf[pos] = '"';
    pos += 1;
    return pos;
}

pub fn jsonEscapeString(buf: []u8, src: []const u8) ?usize {
    var pos: usize = 0;
    var i: usize = 0;
    while (i < src.len) {
        const ch = src[i];
        switch (ch) {
            '"' => {
                if (pos + 2 > buf.len) return null;
                buf[pos] = '\\';
                buf[pos + 1] = '"';
                pos += 2;
            },
            '\\' => {
                if (pos + 2 > buf.len) return null;
                buf[pos] = '\\';
                buf[pos + 1] = '\\';
                pos += 2;
            },
            '\n' => {
                if (pos + 2 > buf.len) return null;
                buf[pos] = '\\';
                buf[pos + 1] = 'n';
                pos += 2;
            },
            '\r' => {
                if (pos + 2 > buf.len) return null;
                buf[pos] = '\\';
                buf[pos + 1] = 'r';
                pos += 2;
            },
            '\t' => {
                if (pos + 2 > buf.len) return null;
                buf[pos] = '\\';
                buf[pos + 1] = 't';
                pos += 2;
            },
            else => {
                if (ch < 0x20) {
                    // Control characters: escape as \u00XX
                    if (pos + 6 > buf.len) return null;
                    buf[pos] = '\\';
                    buf[pos + 1] = 'u';
                    buf[pos + 2] = '0';
                    buf[pos + 3] = '0';
                    buf[pos + 4] = hexDigit(ch >> 4);
                    buf[pos + 5] = hexDigit(ch & 0x0F);
                    pos += 6;
                } else if (ch >= 0x80) {
                    // UTF-8 multi-byte sequence detection
                    const seq_len = utf8SeqLen(ch);
                    if (seq_len > 1 and i + seq_len <= src.len and utf8ContinuationsValid(src[i + 1 .. i + seq_len])) {
                        // Valid UTF-8 sequence — pass through raw (valid in JSON strings)
                        if (pos + seq_len > buf.len) return null;
                        @memcpy(buf[pos .. pos + seq_len], src[i .. i + seq_len]);
                        pos += seq_len;
                        i += seq_len;
                        continue;
                    }
                    // Lone high byte (ISO-8859-1 fallback): escape as \u00XX
                    if (pos + 6 > buf.len) return null;
                    buf[pos] = '\\';
                    buf[pos + 1] = 'u';
                    buf[pos + 2] = '0';
                    buf[pos + 3] = '0';
                    buf[pos + 4] = hexDigit(ch >> 4);
                    buf[pos + 5] = hexDigit(ch & 0x0F);
                    pos += 6;
                } else {
                    if (pos >= buf.len) return null;
                    buf[pos] = ch;
                    pos += 1;
                }
            },
        }
        i += 1;
    }
    return pos;
}

/// Unescape a JSON string value, converting escape sequences to actual characters.
/// Returns the length of the unescaped string written to dst, or null if dst is too small.
fn jsonUnescapeString(dst: []u8, src: []const u8) ?usize {
    var pos: usize = 0;
    var i: usize = 0;
    while (i < src.len) {
        if (src[i] == '\\' and i + 1 < src.len) {
            switch (src[i + 1]) {
                '"' => {
                    if (pos >= dst.len) return null;
                    dst[pos] = '"';
                    pos += 1;
                    i += 2;
                },
                '\\' => {
                    if (pos >= dst.len) return null;
                    dst[pos] = '\\';
                    pos += 1;
                    i += 2;
                },
                'n' => {
                    if (pos >= dst.len) return null;
                    dst[pos] = '\n';
                    pos += 1;
                    i += 2;
                },
                'r' => {
                    if (pos >= dst.len) return null;
                    dst[pos] = '\r';
                    pos += 1;
                    i += 2;
                },
                't' => {
                    if (pos >= dst.len) return null;
                    dst[pos] = '\t';
                    pos += 1;
                    i += 2;
                },
                '/' => {
                    if (pos >= dst.len) return null;
                    dst[pos] = '/';
                    pos += 1;
                    i += 2;
                },
                'u' => {
                    // \uXXXX — parse 4 hex digits → code point → UTF-8
                    if (i + 5 >= src.len) {
                        if (pos >= dst.len) return null;
                        dst[pos] = src[i];
                        pos += 1;
                        i += 1;
                        continue;
                    }
                    const hex = src[i + 2 .. i + 6];
                    const cp = parseHex4(hex) orelse {
                        if (pos >= dst.len) return null;
                        dst[pos] = src[i];
                        pos += 1;
                        i += 1;
                        continue;
                    };
                    if (cp < 0x80) {
                        if (pos >= dst.len) return null;
                        dst[pos] = @intCast(cp);
                        pos += 1;
                    } else if (cp < 0x800) {
                        if (pos + 2 > dst.len) return null;
                        dst[pos] = @intCast(0xC0 | (cp >> 6));
                        dst[pos + 1] = @intCast(0x80 | (cp & 0x3F));
                        pos += 2;
                    } else {
                        if (pos + 3 > dst.len) return null;
                        dst[pos] = @intCast(0xE0 | (cp >> 12));
                        dst[pos + 1] = @intCast(0x80 | ((cp >> 6) & 0x3F));
                        dst[pos + 2] = @intCast(0x80 | (cp & 0x3F));
                        pos += 3;
                    }
                    i += 6;
                },
                else => {
                    if (pos >= dst.len) return null;
                    dst[pos] = src[i];
                    pos += 1;
                    i += 1;
                },
            }
        } else {
            if (pos >= dst.len) return null;
            dst[pos] = src[i];
            pos += 1;
            i += 1;
        }
    }
    return pos;
}

fn parseHex4(hex: []const u8) ?u21 {
    if (hex.len < 4) return null;
    var result: u21 = 0;
    for (hex[0..4]) |ch| {
        result <<= 4;
        if (ch >= '0' and ch <= '9') {
            result |= @as(u21, ch - '0');
        } else if (ch >= 'a' and ch <= 'f') {
            result |= @as(u21, ch - 'a' + 10);
        } else if (ch >= 'A' and ch <= 'F') {
            result |= @as(u21, ch - 'A' + 10);
        } else {
            return null;
        }
    }
    return result;
}

/// Return the expected byte length of a UTF-8 sequence from the lead byte.
/// Returns 1 for invalid lead bytes (continuation bytes or 0xFE/0xFF).
fn utf8SeqLen(lead: u8) usize {
    if (lead & 0xE0 == 0xC0) return 2; // 110xxxxx
    if (lead & 0xF0 == 0xE0) return 3; // 1110xxxx
    if (lead & 0xF8 == 0xF0) return 4; // 11110xxx
    return 1; // not a valid lead byte
}

/// Check that all bytes are valid UTF-8 continuation bytes (10xxxxxx).
fn utf8ContinuationsValid(bytes: []const u8) bool {
    for (bytes) |b| {
        if (b & 0xC0 != 0x80) return false;
    }
    return true;
}

fn hexDigit(val: u8) u8 {
    return if (val < 10) '0' + val else 'a' + (val - 10);
}

// ============================================================
// Tests
// ============================================================

test "formatInt: zero" {
    var buf: [20]u8 = undefined;
    const len = formatInt(&buf, @as(u64, 0)).?;
    try std.testing.expectEqualStrings("0", buf[0..len]);
}

test "formatInt: small number" {
    var buf: [20]u8 = undefined;
    const len = formatInt(&buf, @as(u64, 42)).?;
    try std.testing.expectEqualStrings("42", buf[0..len]);
}

test "formatInt: large number" {
    var buf: [20]u8 = undefined;
    const len = formatInt(&buf, @as(u64, 12345)).?;
    try std.testing.expectEqualStrings("12345", buf[0..len]);
}

test "formatInt: buffer too small" {
    var buf: [2]u8 = undefined;
    try std.testing.expect(formatInt(&buf, @as(u64, 12345)) == null);
}

test "formatAmount: positive cents" {
    var buf: [20]u8 = undefined;
    const len = formatAmount(&buf, 12345).?;
    try std.testing.expectEqualStrings("123.45", buf[0..len]);
}

test "formatAmount: negative cents" {
    var buf: [20]u8 = undefined;
    const len = formatAmount(&buf, -500).?;
    try std.testing.expectEqualStrings("-5.00", buf[0..len]);
}

test "formatAmount: zero" {
    var buf: [20]u8 = undefined;
    const len = formatAmount(&buf, 0).?;
    try std.testing.expectEqualStrings("0.00", buf[0..len]);
}

test "formatAmount: small cents" {
    var buf: [20]u8 = undefined;
    const len = formatAmount(&buf, 7).?;
    try std.testing.expectEqualStrings("0.07", buf[0..len]);
}

test "jsonEscapeString: plain ASCII" {
    var buf: [100]u8 = undefined;
    const len = jsonEscapeString(&buf, "hello world").?;
    try std.testing.expectEqualStrings("hello world", buf[0..len]);
}

test "jsonEscapeString: quotes" {
    var buf: [100]u8 = undefined;
    const len = jsonEscapeString(&buf, "say \"hi\"").?;
    try std.testing.expectEqualStrings("say \\\"hi\\\"", buf[0..len]);
}

test "jsonEscapeString: backslash" {
    var buf: [100]u8 = undefined;
    const len = jsonEscapeString(&buf, "a\\b").?;
    try std.testing.expectEqualStrings("a\\\\b", buf[0..len]);
}

test "jsonEscapeString: newline" {
    var buf: [100]u8 = undefined;
    const len = jsonEscapeString(&buf, "line1\nline2").?;
    try std.testing.expectEqualStrings("line1\\nline2", buf[0..len]);
}

test "jsonEscapeString: control char" {
    var buf: [100]u8 = undefined;
    const input = [_]u8{ 'a', 0x01, 'b' };
    const len = jsonEscapeString(&buf, &input).?;
    try std.testing.expectEqualStrings("a\\u0001b", buf[0..len]);
}

test "jsonEscapeString: tab" {
    var buf: [100]u8 = undefined;
    const len = jsonEscapeString(&buf, "a\tb").?;
    try std.testing.expectEqualStrings("a\\tb", buf[0..len]);
}

test "jsonEscapeString: UTF-8 emoji passed through" {
    var buf: [100]u8 = undefined;
    // 🛒 = F0 9F 9B 92 (valid 4-byte UTF-8)
    const cart = "\xf0\x9f\x9b\x92";
    const len = jsonEscapeString(&buf, cart).?;
    try std.testing.expectEqualStrings(cart, buf[0..len]);
}

test "jsonEscapeString: UTF-8 2-byte char passed through" {
    var buf: [100]u8 = undefined;
    // ü = C3 BC (valid 2-byte UTF-8)
    const input = "\xc3\xbc";
    const len = jsonEscapeString(&buf, input).?;
    try std.testing.expectEqualStrings(input, buf[0..len]);
}

test "jsonEscapeString: UTF-8 3-byte char passed through" {
    var buf: [100]u8 = undefined;
    // ⚡ = E2 9A A1 (valid 3-byte UTF-8)
    const input = "\xe2\x9a\xa1";
    const len = jsonEscapeString(&buf, input).?;
    try std.testing.expectEqualStrings(input, buf[0..len]);
}

test "jsonEscapeString: lone high byte escaped as ISO-8859-1" {
    var buf: [100]u8 = undefined;
    // 0xFC alone = ü in ISO-8859-1, but not valid UTF-8 lead (needs continuation)
    const input = [_]u8{ 'a', 0xFC, 'b' };
    const len = jsonEscapeString(&buf, &input).?;
    try std.testing.expectEqualStrings("a\\u00fcb", buf[0..len]);
}

test "jsonEscapeString: mixed ASCII and emoji" {
    var buf: [200]u8 = undefined;
    // "hello 🛒 world"
    const input = "hello \xf0\x9f\x9b\x92 world";
    const len = jsonEscapeString(&buf, input).?;
    try std.testing.expectEqualStrings(input, buf[0..len]);
}

test "jsonEscapeString: all category icons pass through" {
    const types_mod = @import("types.zig");
    const all_cats = [_]types_mod.Category{
        .uncategorized, .groceries,     .dining,        .transport,
        .housing,       .utilities,     .entertainment, .shopping,
        .health,        .insurance,     .income,        .transfer,
        .cash,          .subscriptions, .travel,        .education,
        .other,
    };
    var buf: [100]u8 = undefined;
    for (all_cats) |cat| {
        const icon = cat.icon();
        const len = jsonEscapeString(&buf, icon).?;
        // Single-byte icons (like "?") pass through as-is
        // Multi-byte UTF-8 icons should pass through unchanged
        try std.testing.expectEqualStrings(icon, buf[0..len]);
    }
}

test "formatSignedInt: positive" {
    var buf: [20]u8 = undefined;
    const len = formatSignedInt(&buf, 42).?;
    try std.testing.expectEqualStrings("42", buf[0..len]);
}

test "formatSignedInt: negative" {
    var buf: [20]u8 = undefined;
    const len = formatSignedInt(&buf, -99).?;
    try std.testing.expectEqualStrings("-99", buf[0..len]);
}

test "formatSignedInt: zero" {
    var buf: [20]u8 = undefined;
    const len = formatSignedInt(&buf, 0).?;
    try std.testing.expectEqualStrings("0", buf[0..len]);
}

// --- Stress / edge case tests ---

test "formatInt: max u32" {
    var buf: [20]u8 = undefined;
    const len = formatInt(&buf, @as(u64, 4294967295)).?;
    try std.testing.expectEqualStrings("4294967295", buf[0..len]);
}

test "formatInt: single digit boundary" {
    var buf: [20]u8 = undefined;
    try std.testing.expectEqualStrings("9", buf[0..formatInt(&buf, @as(u64, 9)).?]);
    try std.testing.expectEqualStrings("10", buf[0..formatInt(&buf, @as(u64, 10)).?]);
}

test "formatInt: buffer exactly fits" {
    var buf: [3]u8 = undefined;
    const len = formatInt(&buf, @as(u64, 999)).?;
    try std.testing.expectEqualStrings("999", buf[0..len]);
}

test "formatInt: buffer one byte short" {
    var buf: [3]u8 = undefined;
    try std.testing.expect(formatInt(&buf, @as(u64, 1000)) == null);
}

test "formatAmount: large salary" {
    var buf: [20]u8 = undefined;
    const len = formatAmount(&buf, 350000).?; // 3500.00 EUR
    try std.testing.expectEqualStrings("3500.00", buf[0..len]);
}

test "formatAmount: very large amount" {
    var buf: [20]u8 = undefined;
    const len = formatAmount(&buf, 99999999).?; // 999,999.99
    try std.testing.expectEqualStrings("999999.99", buf[0..len]);
}

test "formatAmount: one cent" {
    var buf: [20]u8 = undefined;
    const len = formatAmount(&buf, 1).?;
    try std.testing.expectEqualStrings("0.01", buf[0..len]);
}

test "formatAmount: buffer too small" {
    var buf: [3]u8 = undefined;
    // "0.00" needs 4 chars, buf only has 3
    try std.testing.expect(formatAmount(&buf, 0) == null);
}

test "jsonEscapeString: high byte ISO-8859-1" {
    var buf: [100]u8 = undefined;
    // ü = 0xFC in ISO-8859-1
    const input = [_]u8{0xFC};
    const len = jsonEscapeString(&buf, &input).?;
    try std.testing.expectEqualStrings("\\u00fc", buf[0..len]);
}

test "jsonEscapeString: mixed special chars" {
    var buf: [200]u8 = undefined;
    const len = jsonEscapeString(&buf, "line1\nline2\ttab\"quote\"\\back").?;
    try std.testing.expectEqualStrings("line1\\nline2\\ttab\\\"quote\\\"\\\\back", buf[0..len]);
}

test "jsonEscapeString: empty string" {
    var buf: [10]u8 = undefined;
    const len = jsonEscapeString(&buf, "").?;
    try std.testing.expectEqual(@as(usize, 0), len);
}

test "jsonEscapeString: buffer too small for escape" {
    var buf: [1]u8 = undefined;
    // needs 2 bytes for \", but buffer is only 1
    try std.testing.expect(jsonEscapeString(&buf, "\"") == null);
}

test "jsonEscapeString: long string with many escapes" {
    var buf: [2000]u8 = undefined;
    // 100 quotes = 200 bytes output
    const input = &@as([100]u8, @splat('"'));
    const len = jsonEscapeString(&buf, input).?;
    try std.testing.expectEqual(@as(usize, 200), len);
    // Verify pattern: every pair is \"
    var i: usize = 0;
    while (i < 200) : (i += 2) {
        try std.testing.expectEqual(@as(u8, '\\'), buf[i]);
        try std.testing.expectEqual(@as(u8, '"'), buf[i + 1]);
    }
}

test "formatSignedInt: large negative" {
    var buf: [20]u8 = undefined;
    const len = formatSignedInt(&buf, -999999).?;
    try std.testing.expectEqualStrings("-999999", buf[0..len]);
}

test "formatSignedInt: large positive" {
    var buf: [20]u8 = undefined;
    const len = formatSignedInt(&buf, 999999).?;
    try std.testing.expectEqualStrings("999999", buf[0..len]);
}

// ============================================================
// jsonUnescapeString tests
// ============================================================

test "jsonUnescapeString: plain ASCII passthrough" {
    var buf: [64]u8 = undefined;
    const len = jsonUnescapeString(&buf, "Hello World").?;
    try std.testing.expectEqualStrings("Hello World", buf[0..len]);
}

test "jsonUnescapeString: escaped quotes" {
    var buf: [64]u8 = undefined;
    const len = jsonUnescapeString(&buf, "Hello \\\"World\\\"").?;
    try std.testing.expectEqualStrings("Hello \"World\"", buf[0..len]);
}

test "jsonUnescapeString: escaped backslash" {
    var buf: [64]u8 = undefined;
    const len = jsonUnescapeString(&buf, "path\\\\to\\\\file").?;
    try std.testing.expectEqualStrings("path\\to\\file", buf[0..len]);
}

test "jsonUnescapeString: escaped newline and tab" {
    var buf: [64]u8 = undefined;
    const len = jsonUnescapeString(&buf, "line1\\nline2\\ttab").?;
    try std.testing.expectEqualStrings("line1\nline2\ttab", buf[0..len]);
}

test "jsonUnescapeString: unicode escape \\u00FC → ü (UTF-8)" {
    var buf: [64]u8 = undefined;
    const len = jsonUnescapeString(&buf, "Auftr\\u00e4ge").?;
    try std.testing.expectEqualStrings("Aufträge", buf[0..len]);
}

test "jsonUnescapeString: unicode escape ASCII range \\u0041 → A" {
    var buf: [64]u8 = undefined;
    const len = jsonUnescapeString(&buf, "\\u0041BC").?;
    try std.testing.expectEqualStrings("ABC", buf[0..len]);
}

test "jsonUnescapeString: empty string" {
    var buf: [64]u8 = undefined;
    const len = jsonUnescapeString(&buf, "").?;
    try std.testing.expectEqual(@as(usize, 0), len);
}

test "jsonUnescapeString: roundtrip escape then unescape" {
    const original = "Rewe \"Markt\" Köln/Sülz";
    var escaped_buf: [256]u8 = undefined;
    const escaped_len = jsonEscapeString(&escaped_buf, original).?;
    const escaped = escaped_buf[0..escaped_len];

    var unescaped_buf: [256]u8 = undefined;
    const unescaped_len = jsonUnescapeString(&unescaped_buf, escaped).?;
    try std.testing.expectEqualStrings(original, unescaped_buf[0..unescaped_len]);
}

test "jsonUnescapeString: German bank description with special chars" {
    var buf: [256]u8 = undefined;
    const len = jsonUnescapeString(&buf, "Auftraggeber: M\\u00fcller GmbH & Co. KG").?;
    try std.testing.expectEqualStrings("Auftraggeber: Müller GmbH & Co. KG", buf[0..len]);
}

test "sync roundtrip: applyChanges preserves description with quotes" {
    // Simulate the full sync path: getChangesJson → JSON → applyChanges
    var db = try Db.init(":memory:");
    defer db.close();

    // Insert a transaction with special chars in description
    const insert_sql =
        \\INSERT INTO transactions (id, date_year, date_month, date_day, description, amount_cents, currency, category, account, excluded, updated_at)
        \\VALUES ('test123456789012345678901234', 2026, 1, 15, 'Rewe "Markt" Köln', -4299, 'EUR', 1, 'comdirect', 0, 1000);
    ;
    db.exec(insert_sql) catch return error.TestUnexpectedResult;

    // Simulate incoming sync JSON (as would arrive from the Worker after re-encoding)
    const sync_json =
        \\{"rows":[{"table":"transactions","id":"test123456789012345678901234","data":{"date_year":2026,"date_month":1,"date_day":15,"description":"Rewe \"Markt\" K\u00f6ln","amount_cents":-4299,"currency":"EUR","category":2,"account":"comdirect","excluded":0},"updated_at":2000}]}
    ;

    const applied = try db.applyChanges(sync_json);
    try std.testing.expectEqual(@as(i32, 1), applied);

    // Verify the description was stored correctly (unescaped)
    const verify_sql = "SELECT description, category FROM transactions WHERE id = 'test123456789012345678901234';";
    var stmt: ?*c.sqlite3_stmt = null;
    if (c.sqlite3_prepare_v2(db.handle, verify_sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null)
        return error.TestUnexpectedResult;
    defer _ = c.sqlite3_finalize(stmt.?);
    const s = stmt.?;
    if (c.sqlite3_step(s) != c.SQLITE_ROW) return error.TestUnexpectedResult;

    const desc_ptr = c.sqlite3_column_text(s, 0) orelse return error.TestUnexpectedResult;
    const desc_len: usize = @intCast(c.sqlite3_column_bytes(s, 0));
    try std.testing.expectEqualStrings("Rewe \"Markt\" Köln", desc_ptr[0..desc_len]);

    // Category should have been updated (from 1 to 2) since updated_at 2000 > 1000
    const cat = c.sqlite3_column_int(s, 1);
    try std.testing.expectEqual(@as(c_int, 2), cat);
}

// ============================================================
// Integration: MT940 → DB pipeline
// ============================================================

test "MT940 → DB: parse and insert transactions from bank statement" {
    const mt940 = @import("mt940.zig");

    // Real-world-like MT940 bank statement
    const mt940_data =
        \\:20:STARTUMS
        \\:25:20041133/1234567890
        \\:28C:0/1
        \\:60F:C260301EUR5000,00
        \\:61:2603010301D45,99NMSC
        \\:86:?00KARTENZAHLUNG?20SVWZ+REWE SAGT DANKE 54321?30COBADEFF?31DE89370400440532013000?32REWE Markt GmbH
        \\:61:2603020302D9,90NMSC
        \\:86:?00LASTSCHRIFT?20SVWZ+Netflix Monatsabo?32NETFLIX INTL
        \\:61:2603050305C3500,00NMSC
        \\:86:?00GEHALT/LOHN?20SVWZ+GEHALT MAERZ 2026?32ARBEITGEBER GMBH
        \\:61:2603100310D750,00NMSC
        \\:86:?00DAUERAUFTRAG?20SVWZ+Miete Maerz 2026?32VERMIETER GMBH
        \\:62F:C260310EUR3694,11
        \\-
    ;

    // Parse MT940
    var txns: [100]Transaction = undefined;
    const result = mt940.parseMt940(mt940_data, "Comdirect", &txns);
    try std.testing.expectEqual(@as(u32, 4), result.count);
    try std.testing.expectEqual(@as(u32, 0), result.errors);

    // Open in-memory DB
    var db = try Db.init(":memory:");
    defer db.close();

    // Insert all transactions
    var imported: u32 = 0;
    var duplicates: u32 = 0;
    for (txns[0..result.count]) |*txn| {
        const inserted = try db.insertTransaction(txn);
        if (inserted) imported += 1 else duplicates += 1;
    }
    try std.testing.expectEqual(@as(u32, 4), imported);
    try std.testing.expectEqual(@as(u32, 0), duplicates);

    // Re-insert same transactions → all should be duplicates
    var dup2: u32 = 0;
    for (txns[0..result.count]) |*txn| {
        const inserted = try db.insertTransaction(txn);
        if (!inserted) dup2 += 1;
    }
    try std.testing.expectEqual(@as(u32, 4), dup2);

    // Query back and verify via JSON
    const buf_size: usize = 64 * 1024;
    var json_buf: [buf_size]u8 = undefined;
    const json_len = try db.getTransactionsJson(&json_buf, buf_size) orelse return error.TestUnexpectedResult;
    const json = json_buf[0..json_len];

    // Verify key data is present in the JSON output
    try std.testing.expect(std.mem.indexOf(u8, json, "REWE SAGT DANKE") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "Netflix Monatsabo") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "GEHALT MAERZ 2026") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "Miete Maerz 2026") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "Comdirect") != null);

    // Verify amounts: -45.99, -9.90, +3500.00, -750.00
    try std.testing.expect(std.mem.indexOf(u8, json, "-45.99") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "-9.90") != null or std.mem.indexOf(u8, json, "-9.9") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "3500.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "-750.0") != null);
}
