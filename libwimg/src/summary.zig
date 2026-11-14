const std = @import("std");
const types = @import("types.zig");
const c = @import("sqlite_c.zig");
const db_mod = @import("db.zig");

const Category = types.Category;

/// Generate a monthly summary as JSON, optionally filtered by account.
pub fn getSummaryJsonFiltered(handle: *c.sqlite3, year: u16, month: u8, buf: [*]u8, buf_len: usize, acct_ptr: ?[*]const u8, acct_len: u32) ?usize {
    const has_filter = acct_ptr != null and acct_len > 0;

    const sql_all =
        \\SELECT category,
        \\  SUM(CASE WHEN amount_cents > 0 THEN amount_cents ELSE 0 END) as income,
        \\  SUM(CASE WHEN amount_cents < 0 THEN amount_cents ELSE 0 END) as expenses,
        \\  COUNT(*) as cnt
        \\FROM transactions
        \\WHERE date_year = ?1 AND date_month = ?2 AND excluded = 0
        \\  AND account NOT IN (SELECT id FROM accounts WHERE hidden = 1)
        \\GROUP BY category
        \\ORDER BY expenses ASC;
    ;

    const sql_filtered =
        \\SELECT category,
        \\  SUM(CASE WHEN amount_cents > 0 THEN amount_cents ELSE 0 END) as income,
        \\  SUM(CASE WHEN amount_cents < 0 THEN amount_cents ELSE 0 END) as expenses,
        \\  COUNT(*) as cnt
        \\FROM transactions
        \\WHERE date_year = ?1 AND date_month = ?2 AND excluded = 0 AND account = ?3
        \\GROUP BY category
        \\ORDER BY expenses ASC;
    ;

    const sql = if (has_filter) sql_filtered else sql_all;

    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(handle, sql, -1, &stmt, null);
    if (rc != c.SQLITE_OK or stmt == null) return null;
    defer _ = c.sqlite3_finalize(stmt.?);

    const s = stmt.?;
    if (c.sqlite3_bind_int(s, 1, @intCast(year)) != c.SQLITE_OK) return null;
    if (c.sqlite3_bind_int(s, 2, @intCast(month)) != c.SQLITE_OK) return null;
    if (has_filter) {
        if (c.sqlite3_bind_text(s, 3, @ptrCast(acct_ptr.?), @intCast(acct_len), c.SQLITE_STATIC) != c.SQLITE_OK) return null;
    }

    // Collect results into a fixed array (max 17 categories)
    var total_income: i64 = 0;
    var total_expenses: i64 = 0;
    var total_count: i32 = 0;

    const max_cats = 20;
    var cat_ids: [max_cats]u8 = undefined;
    var cat_amounts: [max_cats]i64 = undefined; // absolute expense amounts (positive)
    var cat_counts: [max_cats]i32 = undefined;
    var cat_count: usize = 0;

    while (c.sqlite3_step(s) == c.SQLITE_ROW) {
        const cat_id: u8 = @intCast(c.sqlite3_column_int(s, 0));
        const income = c.sqlite3_column_int64(s, 1);
        const expenses = c.sqlite3_column_int64(s, 2);
        const cnt = c.sqlite3_column_int(s, 3);

        total_income += income;
        total_expenses += expenses;
        total_count += cnt;

        // Track expense categories (negative amounts made positive for display)
        if (expenses < 0 and cat_count < max_cats) {
            cat_ids[cat_count] = cat_id;
            cat_amounts[cat_count] = -expenses; // make positive
            cat_counts[cat_count] = cnt;
            cat_count += 1;
        }
    }

    // Build JSON
    var pos: usize = 0;

    // {"year":YYYY,"month":M,"income":X.XX,"expenses":X.XX,"available":X.XX,"tx_count":N
    const p1 = "{\"year\":";
    if (pos + p1.len > buf_len) return null;
    @memcpy(buf[pos .. pos + p1.len], p1);
    pos += p1.len;
    pos += db_mod.formatInt(buf[pos..buf_len], @as(u32, year)) orelse return null;

    const p2 = ",\"month\":";
    if (pos + p2.len > buf_len) return null;
    @memcpy(buf[pos .. pos + p2.len], p2);
    pos += p2.len;
    pos += db_mod.formatInt(buf[pos..buf_len], @as(u32, month)) orelse return null;

    const p3 = ",\"income\":";
    if (pos + p3.len > buf_len) return null;
    @memcpy(buf[pos .. pos + p3.len], p3);
    pos += p3.len;
    pos += db_mod.formatAmount(buf[pos..buf_len], total_income) orelse return null;

    const p4 = ",\"expenses\":";
    if (pos + p4.len > buf_len) return null;
    @memcpy(buf[pos .. pos + p4.len], p4);
    pos += p4.len;
    // expenses is negative, so negate for positive display
    pos += db_mod.formatAmount(buf[pos..buf_len], -total_expenses) orelse return null;

    const p5 = ",\"available\":";
    if (pos + p5.len > buf_len) return null;
    @memcpy(buf[pos .. pos + p5.len], p5);
    pos += p5.len;
    pos += db_mod.formatAmount(buf[pos..buf_len], total_income + total_expenses) orelse return null;

    const p6 = ",\"tx_count\":";
    if (pos + p6.len > buf_len) return null;
    @memcpy(buf[pos .. pos + p6.len], p6);
    pos += p6.len;
    pos += db_mod.formatInt(buf[pos..buf_len], @as(u32, @intCast(total_count))) orelse return null;

    // ,"by_category":[...]
    const p7 = ",\"by_category\":[";
    if (pos + p7.len > buf_len) return null;
    @memcpy(buf[pos .. pos + p7.len], p7);
    pos += p7.len;

    for (0..cat_count) |i| {
        if (i > 0) {
            if (pos >= buf_len) return null;
            buf[pos] = ',';
            pos += 1;
        }

        // {"id":N,"name":"...","amount":X.XX,"count":N}
        const cp1 = "{\"id\":";
        if (pos + cp1.len > buf_len) return null;
        @memcpy(buf[pos .. pos + cp1.len], cp1);
        pos += cp1.len;
        pos += db_mod.formatInt(buf[pos..buf_len], @as(u32, cat_ids[i])) orelse return null;

        const cp2 = ",\"name\":\"";
        if (pos + cp2.len > buf_len) return null;
        @memcpy(buf[pos .. pos + cp2.len], cp2);
        pos += cp2.len;

        const cat_name = Category.fromInt(cat_ids[i]).germanName();
        if (pos + cat_name.len > buf_len) return null;
        @memcpy(buf[pos .. pos + cat_name.len], cat_name);
        pos += cat_name.len;

        const cp3 = "\",\"amount\":";
        if (pos + cp3.len > buf_len) return null;
        @memcpy(buf[pos .. pos + cp3.len], cp3);
        pos += cp3.len;
        pos += db_mod.formatAmount(buf[pos..buf_len], cat_amounts[i]) orelse return null;

        const cp4 = ",\"count\":";
        if (pos + cp4.len > buf_len) return null;
        @memcpy(buf[pos .. pos + cp4.len], cp4);
        pos += cp4.len;
        pos += db_mod.formatInt(buf[pos..buf_len], @as(u32, @intCast(cat_counts[i]))) orelse return null;

        if (pos >= buf_len) return null;
        buf[pos] = '}';
        pos += 1;
    }

    // Close by_category array and main object
    const ending = "]}";
    if (pos + ending.len > buf_len) return null;
    @memcpy(buf[pos .. pos + ending.len], ending);
    pos += ending.len;

    return pos;
}
