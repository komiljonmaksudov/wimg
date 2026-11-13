const std = @import("std");
const types = @import("types.zig");
const parser = @import("parser.zig");

const Transaction = types.Transaction;
const Date = types.Date;

pub const CamtResult = struct {
    count: u32,
    errors: u32,
    closing_balance: i64 = 0, // cents
    closing_balance_date: u32 = 0, // YYYYMMDD of the closing balance (0 = unknown)
};

/// Parse CAMT XML (camt.052/053) into Transaction structs.
/// This intentionally supports the most common statement entry tags only.
pub fn parseCamt(data: []const u8, account: []const u8, out: []Transaction) CamtResult {
    return parseCamtMode(data, account, out, false);
}

/// Not-yet-booked entries (HICAZ DE 4): every entry counts, and one without a
/// booking date falls back to its value date.
pub fn parseCamtPending(data: []const u8, account: []const u8, out: []Transaction) CamtResult {
    return parseCamtMode(data, account, out, true);
}

/// `<Sts>PDNG</Sts>` (camt.052/053 v2) or `<Sts><Cd>PDNG</Cd></Sts>` (v8+).
fn isPendingEntry(entry: []const u8) bool {
    const sts = extractTagText(entry, "Sts") orelse return false;
    return std.mem.indexOf(u8, sts, "PDNG") != null;
}

fn parseCamtMode(data: []const u8, account: []const u8, out: []Transaction, pending: bool) CamtResult {
    var result = CamtResult{ .count = 0, .errors = 0 };
    if (data.len == 0 or out.len == 0) return result;

    var pos: usize = 0;
    while (result.count < out.len) {
        const start = findEntryStart(data, pos) orelse break;
        const end_rel = std.mem.indexOfPos(u8, data, start, "</Ntry>") orelse break;
        const end = end_rel + "</Ntry>".len;
        const entry = data[start..end];
        pos = end;

        // A pending entry is never a booked transaction, wherever the bank put it.
        if (!pending and isPendingEntry(entry)) continue;

        var txn: Transaction = undefined;
        if (!parseEntry(entry, account, &txn, pending)) {
            result.errors += 1;
            continue;
        }
        out[result.count] = txn;
        result.count += 1;
    }

    extractClosingBalance(data, &result);

    return result;
}

/// Scan all `<Bal>` blocks for the closing booked balance (Cd=CLBD) and keep
/// the one with the latest date. CAMT places these at statement level, outside
/// the `<Ntry>` entries.
fn extractClosingBalance(data: []const u8, result: *CamtResult) void {
    var search_from: usize = 0;
    while (true) {
        const open = findBalStart(data, search_from) orelse break;
        const end_rel = std.mem.indexOfPos(u8, data, open, "</Bal>") orelse break;
        const end = end_rel + "</Bal>".len;
        const block = data[open..end];
        search_from = end;

        // Only the closing booked balance (CLBD). Match "<Cd>" exactly — a
        // prefix search would also hit "<CdOrPrtry>" and "<CdtDbtInd>".
        const code_start = std.mem.indexOf(u8, block, "<Cd>") orelse continue;
        const code_content = code_start + "<Cd>".len;
        const code_end = std.mem.indexOfPos(u8, block, code_content, "</Cd>") orelse continue;
        const code = std.mem.trim(u8, block[code_content..code_end], " \t\r\n");
        if (!std.mem.eql(u8, code, "CLBD")) continue;

        const amt = extractAmountField(block) orelse continue;
        const abs = parseIsoAmount(amt.text) orelse continue;
        const cdt_dbt = extractTagText(block, "CdtDbtInd") orelse "";
        const is_debit = std.mem.eql(u8, std.mem.trim(u8, cdt_dbt, " \t\r\n"), "DBIT");
        const signed: i64 = if (is_debit) -abs else abs;

        // Date sits in <Dt><Dt>YYYY-MM-DD</Dt></Dt> (or <DtTm>). The generic
        // tag extractor can't cope with the same-name nesting, so just scan from
        // the first <Dt to the first digit and let parseIsoDate read the date.
        var bal_date: u32 = 0;
        if (std.mem.indexOf(u8, block, "<Dt")) |dt_pos| {
            var i = dt_pos;
            while (i < block.len and (block[i] < '0' or block[i] > '9')) : (i += 1) {}
            if (parseIsoDate(block[i..])) |d| {
                bal_date = @as(u32, d.year) * 10000 + @as(u32, d.month) * 100 + @as(u32, d.day);
            }
        }

        if (bal_date >= result.closing_balance_date) {
            result.closing_balance = signed;
            result.closing_balance_date = bal_date;
        }
    }
}

fn findBalStart(data: []const u8, from: usize) ?usize {
    const direct = std.mem.indexOfPos(u8, data, from, "<Bal>");
    const with_attrs = std.mem.indexOfPos(u8, data, from, "<Bal ");
    return switch (direct != null and with_attrs != null) {
        true => @min(direct.?, with_attrs.?),
        false => direct orelse with_attrs,
    };
}

fn parseEntry(entry: []const u8, account: []const u8, out_txn: *Transaction, pending: bool) bool {
    const amount = extractAmountField(entry) orelse return false;
    const amount_abs = parseIsoAmount(amount.text) orelse return false;

    const cdt_dbt = extractTagText(entry, "CdtDbtInd") orelse "";
    const is_debit = std.mem.eql(u8, cdt_dbt, "DBIT");
    out_txn.amount_cents = if (is_debit) -amount_abs else amount_abs;

    const date_block = extractTagText(entry, "BookgDt") orelse
        (if (pending) extractTagText(entry, "ValDt") else null) orelse return false;
    const dt = extractTagText(date_block, "Dt") orelse extractTagText(date_block, "DtTm") orelse return false;
    out_txn.date = parseIsoDate(dt) orelse return false;

    var ustrd_buf: [512]u8 = undefined;
    const ustrd = extractAllUstrd(entry, &ustrd_buf);
    const desc = if (ustrd.len > 0)
        ustrd
    else
        (extractTagText(entry, "AddtlNtryInf") orelse "CAMT Buchung");
    const desc_trimmed = std.mem.trim(u8, desc, " \t\r\n");
    const desc_effective = if (desc_trimmed.len > 0) desc_trimmed else "CAMT Buchung";
    // Strip NUL and other C0 control bytes (see mt940.zig finalizeTxnDescription
    // for the rationale — same JSONDecoder pitfall).
    var clean: [256]u8 = undefined;
    const cap = @min(desc_effective.len, clean.len);
    var written: usize = 0;
    var k: usize = 0;
    while (k < cap) : (k += 1) {
        const b = desc_effective[k];
        if (b == 0) continue;
        if (b < 0x20 and b != '\t' and b != '\n' and b != '\r') continue;
        clean[written] = b;
        written += 1;
    }
    out_txn.description_len = @intCast(parser.toUtf8(&out_txn.description, clean[0..written]));

    setCurrency(out_txn, amount.ccy);
    out_txn.category = .uncategorized;
    parser.setAccount(out_txn, account);
    // Hash the raw bytes, not the UTF-8 text (same rule as MT940).
    out_txn.id = parser.computeHash(out_txn.date, clean[0..written], out_txn.amount_cents, account);
    return true;
}

const AmountField = struct {
    text: []const u8,
    ccy: ?[]const u8,
};

fn extractAmountField(entry: []const u8) ?AmountField {
    const open_prefix = "<Amt";
    const start = std.mem.indexOf(u8, entry, open_prefix) orelse return null;
    var open_end = start + open_prefix.len;
    while (open_end < entry.len and entry[open_end] != '>') : (open_end += 1) {}
    if (open_end >= entry.len) return null;

    const close = "</Amt>";
    const content_start = open_end + 1;
    const content_end = std.mem.indexOfPos(u8, entry, content_start, close) orelse return null;
    const content = entry[content_start..content_end];
    const open_tag = entry[start .. open_end + 1];

    return .{
        .text = content,
        .ccy = extractAttributeValue(open_tag, "Ccy"),
    };
}

fn extractAttributeValue(tag_text: []const u8, attr_name: []const u8) ?[]const u8 {
    var pattern_buf: [32]u8 = undefined;
    if (attr_name.len + 2 > pattern_buf.len) return null;
    @memcpy(pattern_buf[0..attr_name.len], attr_name);
    pattern_buf[attr_name.len] = '=';
    pattern_buf[attr_name.len + 1] = '"';
    const pattern = pattern_buf[0 .. attr_name.len + 2];

    const start = std.mem.indexOf(u8, tag_text, pattern) orelse return null;
    const value_start = start + pattern.len;
    const value_end_rel = std.mem.indexOfPos(u8, tag_text, value_start, "\"") orelse return null;
    if (value_end_rel <= value_start) return null;
    return tag_text[value_start..value_end_rel];
}

fn setCurrency(txn: *Transaction, ccy: ?[]const u8) void {
    const selected = ccy orelse "EUR";
    if (selected.len == 3) {
        @memcpy(txn.currency[0..3], selected[0..3]);
    } else {
        txn.currency = "EUR".*;
    }
}

fn extractAllUstrd(entry: []const u8, out_buf: *[512]u8) []const u8 {
    const open_prefix = "<Ustrd";
    const close = "</Ustrd>";
    var search_from: usize = 0;
    var out_len: usize = 0;

    while (true) {
        const start = std.mem.indexOfPos(u8, entry, search_from, open_prefix) orelse break;
        var open_end = start + open_prefix.len;
        while (open_end < entry.len and entry[open_end] != '>') : (open_end += 1) {}
        if (open_end >= entry.len) break;

        const content_start = open_end + 1;
        const content_end = std.mem.indexOfPos(u8, entry, content_start, close) orelse break;
        const content_trimmed = std.mem.trim(u8, entry[content_start..content_end], " \t\r\n");

        if (content_trimmed.len > 0) {
            if (out_len > 0 and out_len < out_buf.len) {
                out_buf[out_len] = ' ';
                out_len += 1;
            }
            const copy_len = @min(content_trimmed.len, out_buf.len - out_len);
            @memcpy(out_buf[out_len .. out_len + copy_len], content_trimmed[0..copy_len]);
            out_len += copy_len;
            if (copy_len < content_trimmed.len) break;
        }

        search_from = content_end + close.len;
    }

    return out_buf[0..out_len];
}

fn findEntryStart(data: []const u8, from: usize) ?usize {
    const direct = std.mem.indexOfPos(u8, data, from, "<Ntry>");
    const with_attrs = std.mem.indexOfPos(u8, data, from, "<Ntry ");
    return switch (direct != null and with_attrs != null) {
        true => @min(direct.?, with_attrs.?),
        false => direct orelse with_attrs,
    };
}

fn extractTagText(haystack: []const u8, tag_name: []const u8) ?[]const u8 {
    var open_prefix_buf: [32]u8 = undefined;
    var close_buf: [40]u8 = undefined;
    if (tag_name.len + 1 > open_prefix_buf.len) return null;
    if (tag_name.len + 3 > close_buf.len) return null;

    open_prefix_buf[0] = '<';
    @memcpy(open_prefix_buf[1 .. 1 + tag_name.len], tag_name);
    const open_prefix = open_prefix_buf[0 .. tag_name.len + 1];

    close_buf[0] = '<';
    close_buf[1] = '/';
    @memcpy(close_buf[2 .. 2 + tag_name.len], tag_name);
    close_buf[2 + tag_name.len] = '>';
    const close = close_buf[0 .. tag_name.len + 3];

    const start = std.mem.indexOf(u8, haystack, open_prefix) orelse return null;
    var open_end = start + open_prefix.len;
    while (open_end < haystack.len and haystack[open_end] != '>') : (open_end += 1) {}
    if (open_end >= haystack.len) return null;
    const content_start = open_end + 1;

    const end_rel = std.mem.indexOfPos(u8, haystack, content_start, close) orelse return null;
    return haystack[content_start..end_rel];
}

fn parseIsoDate(raw: []const u8) ?Date {
    if (raw.len >= 10 and raw[4] == '-' and raw[7] == '-') {
        const year = std.fmt.parseInt(u16, raw[0..4], 10) catch return null;
        const month = std.fmt.parseInt(u8, raw[5..7], 10) catch return null;
        const day = std.fmt.parseInt(u8, raw[8..10], 10) catch return null;
        return .{ .year = year, .month = month, .day = day };
    }
    if (raw.len >= 8) {
        const year = std.fmt.parseInt(u16, raw[0..4], 10) catch return null;
        const month = std.fmt.parseInt(u8, raw[4..6], 10) catch return null;
        const day = std.fmt.parseInt(u8, raw[6..8], 10) catch return null;
        return .{ .year = year, .month = month, .day = day };
    }
    return null;
}

fn parseIsoAmount(raw: []const u8) ?i64 {
    const s = std.mem.trim(u8, raw, " \t\r\n");
    if (s.len == 0) return null;

    var whole: i64 = 0;
    var frac: i64 = 0;
    var frac_digits: u8 = 0;
    var seen_sep = false;
    var negative = false;

    var i: usize = 0;
    if (s[0] == '-') {
        negative = true;
        i = 1;
    }

    while (i < s.len) : (i += 1) {
        const ch = s[i];
        if (ch == '.' or ch == ',') {
            if (seen_sep) return null;
            seen_sep = true;
            continue;
        }
        if (ch < '0' or ch > '9') return null;
        const digit: i64 = @intCast(ch - '0');
        if (!seen_sep) {
            whole = whole * 10 + digit;
        } else if (frac_digits < 2) {
            frac = frac * 10 + digit;
            frac_digits += 1;
        }
    }

    if (frac_digits == 1) frac *= 10;
    var cents = whole * 100 + frac;
    if (negative) cents = -cents;
    return cents;
}

test "parseCamt basic entry" {
    const xml =
        "<Document><BkToCstmrStmt><Stmt>" ++
        "<Ntry><Amt Ccy=\"EUR\">12.34</Amt><CdtDbtInd>DBIT</CdtDbtInd><BookgDt><Dt>2026-03-18</Dt></BookgDt><AddtlNtryInf>Kartenzahlung</AddtlNtryInf></Ntry>" ++
        "</Stmt></BkToCstmrStmt></Document>";
    var txns: [4]Transaction = undefined;
    const res = parseCamt(xml, "Comdirect", &txns);
    try std.testing.expectEqual(@as(u32, 1), res.count);
    try std.testing.expectEqual(@as(u32, 0), res.errors);
    try std.testing.expectEqual(@as(i64, -1234), txns[0].amount_cents);
    try std.testing.expectEqual(@as(u16, 2026), txns[0].date.year);
    try std.testing.expectEqualStrings("EUR", txns[0].currency[0..]);
}

test "parseCamt prefers Ustrd description" {
    const xml =
        "<Document><BkToCstmrStmt><Stmt>" ++
        "<Ntry><Amt Ccy=\"EUR\">500.00</Amt><CdtDbtInd>CRDT</CdtDbtInd><BookgDt><Dt>2026-03-17</Dt></BookgDt><RmtInf><Ustrd>Gehalt Maerz</Ustrd></RmtInf></Ntry>" ++
        "</Stmt></BkToCstmrStmt></Document>";
    var txns: [2]Transaction = undefined;
    const res = parseCamt(xml, "Comdirect", &txns);
    try std.testing.expectEqual(@as(u32, 1), res.count);
    try std.testing.expectEqualStrings("Gehalt Maerz", txns[0].descriptionSlice());
}

test "parseCamt concatenates multiple Ustrd tags" {
    const xml =
        "<Document><BkToCstmrStmt><Stmt>" ++
        "<Ntry><Amt Ccy=\"EUR\">15.00</Amt><CdtDbtInd>DBIT</CdtDbtInd><BookgDt><Dt>2026-03-19</Dt></BookgDt><RmtInf><Ustrd>Teil eins</Ustrd><Ustrd>Teil zwei</Ustrd></RmtInf></Ntry>" ++
        "</Stmt></BkToCstmrStmt></Document>";
    var txns: [2]Transaction = undefined;
    const res = parseCamt(xml, "Comdirect", &txns);
    try std.testing.expectEqual(@as(u32, 1), res.count);
    try std.testing.expectEqualStrings("Teil eins Teil zwei", txns[0].descriptionSlice());
}

test "parseCamt extracts CLBD closing balance" {
    const xml =
        "<Document><BkToCstmrStmt><Stmt>" ++
        "<Bal><Tp><CdOrPrtry><Cd>OPBD</Cd></CdOrPrtry></Tp><Amt Ccy=\"EUR\">100.00</Amt><CdtDbtInd>CRDT</CdtDbtInd><Dt><Dt>2026-06-01</Dt></Dt></Bal>" ++
        "<Bal><Tp><CdOrPrtry><Cd>CLBD</Cd></CdOrPrtry></Tp><Amt Ccy=\"EUR\">265.71</Amt><CdtDbtInd>CRDT</CdtDbtInd><Dt><Dt>2026-06-23</Dt></Dt></Bal>" ++
        "<Ntry><Amt Ccy=\"EUR\">12.34</Amt><CdtDbtInd>DBIT</CdtDbtInd><BookgDt><Dt>2026-06-18</Dt></BookgDt><AddtlNtryInf>Test</AddtlNtryInf></Ntry>" ++
        "</Stmt></BkToCstmrStmt></Document>";
    var txns: [4]Transaction = undefined;
    const res = parseCamt(xml, "Comdirect", &txns);
    try std.testing.expectEqual(@as(u32, 1), res.count);
    try std.testing.expectEqual(@as(i64, 26571), res.closing_balance);
    try std.testing.expectEqual(@as(u32, 20260623), res.closing_balance_date);
}

test "parseCamt handles debit closing balance" {
    const xml =
        "<Document><BkToCstmrStmt><Stmt>" ++
        "<Bal><Tp><CdOrPrtry><Cd>CLBD</Cd></CdOrPrtry></Tp><Amt Ccy=\"EUR\">50.00</Amt><CdtDbtInd>DBIT</CdtDbtInd><Dt><Dt>2026-06-23</Dt></Dt></Bal>" ++
        "</Stmt></BkToCstmrStmt></Document>";
    var txns: [1]Transaction = undefined;
    const res = parseCamt(xml, "Comdirect", &txns);
    try std.testing.expectEqual(@as(i64, -5000), res.closing_balance);
}

test "parseCamt reads Amt Ccy attribute" {
    const xml =
        "<Document><BkToCstmrStmt><Stmt>" ++
        "<Ntry><Amt Ccy=\"USD\">1.00</Amt><CdtDbtInd>CRDT</CdtDbtInd><BookgDt><Dt>2026-03-20</Dt></BookgDt><AddtlNtryInf>Test</AddtlNtryInf></Ntry>" ++
        "</Stmt></BkToCstmrStmt></Document>";
    var txns: [1]Transaction = undefined;
    const res = parseCamt(xml, "Comdirect", &txns);
    try std.testing.expectEqual(@as(u32, 1), res.count);
    try std.testing.expectEqualStrings("USD", txns[0].currency[0..]);
}

test "booked parse skips entries the bank marks as pending" {
    const xml =
        "<Document><Ntry><Amt Ccy=\"EUR\">10.00</Amt><CdtDbtInd>DBIT</CdtDbtInd><Sts><Cd>BOOK</Cd></Sts><BookgDt><Dt>2026-11-10</Dt></BookgDt><AddtlNtryInf>Gebucht</AddtlNtryInf></Ntry>" ++
        "<Ntry><Amt Ccy=\"EUR\">5.00</Amt><CdtDbtInd>DBIT</CdtDbtInd><Sts><Cd>PDNG</Cd></Sts><ValDt><Dt>2026-11-12</Dt></ValDt><AddtlNtryInf>Vorgemerkt</AddtlNtryInf></Ntry></Document>";
    var out: [4]Transaction = undefined;
    const r = parseCamt(xml, "acc", &out);
    try std.testing.expectEqual(@as(u32, 1), r.count);
    try std.testing.expectEqual(@as(u32, 0), r.errors);
    try std.testing.expectEqualStrings("Gebucht", out[0].descriptionSlice());
}

test "pending parse reads entries without booking date via value date" {
    const xml =
        "<Document><Ntry><Amt Ccy=\"EUR\">5.00</Amt><CdtDbtInd>DBIT</CdtDbtInd><Sts>PDNG</Sts><ValDt><Dt>2026-11-12</Dt></ValDt><AddtlNtryInf>Vorgemerkt</AddtlNtryInf></Ntry></Document>";
    var out: [4]Transaction = undefined;
    const r = parseCamtPending(xml, "acc", &out);
    try std.testing.expectEqual(@as(u32, 1), r.count);
    try std.testing.expectEqual(@as(i64, -500), out[0].amount_cents);
    try std.testing.expectEqual(@as(u16, 12), @as(u16, out[0].date.day));
}
