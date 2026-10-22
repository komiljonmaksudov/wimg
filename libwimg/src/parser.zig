const std = @import("std");
const types = @import("types.zig");

const Transaction = types.Transaction;
const Date = types.Date;
const Category = types.Category;
const ImportResult = types.ImportResult;

pub const ParseError = error{
    InvalidDate,
    InvalidAmount,
    TooFewColumns,
    DescriptionTooLong,
};

pub const CsvFormat = enum(u8) {
    unknown = 0,
    comdirect = 1,
    trade_republic = 2,
    scalable_capital = 3,

    pub fn name(self: CsvFormat) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .comdirect => "comdirect",
            .trade_republic => "trade_republic",
            .scalable_capital => "scalable_capital",
        };
    }
};

/// Auto-detect CSV format from the first few lines.
pub fn detectCsvFormat(data: []const u8) CsvFormat {
    // Look at first 1KB for header clues
    const check_len = @min(data.len, 1024);
    const header = data[0..check_len];

    // Comdirect: German, semicolons, starts with "Buchungstag" or metadata rows
    if (containsAscii(header, "Buchungstag") or containsAscii(header, "Umsatz in EUR")) {
        return .comdirect;
    }

    // Trade Republic: "Date","Type","Description" pattern (comma-separated)
    if (containsAscii(header, "\"Date\"") and containsAscii(header, "\"Type\"")) {
        return .trade_republic;
    }
    // Also: Date,Type,Description (unquoted)
    if (startsWithHeader(header, "Date,Type,")) {
        return .trade_republic;
    }

    // Scalable Capital: semicolons, "Datum" or "Buchungsdatum"
    if (containsAscii(header, "Buchungsdatum") and containsAscii(header, "Betrag")) {
        return .scalable_capital;
    }

    // Fallback: check if semicolons with dd.MM.yyyy → likely Comdirect
    if (containsSemicolon(header) and containsGermanDate(header)) {
        return .comdirect;
    }

    return .unknown;
}

/// Parse CSV, auto-detecting the format. Returns the detected format.
pub fn parseCsv(
    data: []const u8,
    out_txns: []Transaction,
    out_result: *ImportResult,
) CsvFormat {
    const format = detectCsvFormat(data);

    switch (format) {
        .comdirect => parseComdirectCsv(data, out_txns, out_result),
        .trade_republic => parseTradeRepublicCsv(data, out_txns, out_result),
        .scalable_capital => parseScalableCapitalCsv(data, out_txns, out_result),
        .unknown => {
            // Try Comdirect as default
            parseComdirectCsv(data, out_txns, out_result);
        },
    }

    return format;
}

// ============================================================
// Batch CSV Processing
// ============================================================

pub const ParseCursor = struct {
    byte_offset: usize = 0,
    format: CsvFormat = .unknown,
    header_found: bool = false,
};

/// Parse CSV in batches. Caller loops until cursor.byte_offset >= data.len.
/// On each call, fills out_txns up to capacity, then saves position in cursor.
/// First call auto-detects format. Reuses the same buffer across iterations.
pub fn parseCsvBatch(
    data: []const u8,
    cursor: *ParseCursor,
    out_txns: []Transaction,
    out_result: *ImportResult,
) void {
    // Detect format on first call
    if (cursor.byte_offset == 0) {
        cursor.format = detectCsvFormat(data);
    }

    switch (cursor.format) {
        .comdirect => parseComdirectBatch(data, cursor, out_txns, out_result),
        .trade_republic => parseTRBatch(data, cursor, out_txns, out_result),
        .scalable_capital => parseScalableBatch(data, cursor, out_txns, out_result),
        .unknown => parseComdirectBatch(data, cursor, out_txns, out_result),
    }
}

fn parseComdirectBatch(
    data: []const u8,
    cursor: *ParseCursor,
    out_txns: []Transaction,
    out_result: *ImportResult,
) void {
    out_result.* = .{
        .total_rows = 0,
        .imported = 0,
        .skipped_duplicates = 0,
        .errors = 0,
    };

    var pos = cursor.byte_offset;
    var txn_idx: u32 = 0;

    while (pos < data.len) {
        const line_start = pos;
        while (pos < data.len and data[pos] != '\n') : (pos += 1) {}
        const line_end = pos;
        if (pos < data.len) pos += 1; // skip \n

        const line = trimCr(data[line_start..line_end]);
        if (line.len == 0) continue;
        if (!looksLikeDateStart(line)) continue;

        if (txn_idx >= out_txns.len) {
            // Buffer full — rewind to this line for next batch
            cursor.byte_offset = line_start;
            return;
        }

        out_result.total_rows += 1;

        if (parseComdirectLine(line)) |txn| {
            out_txns[txn_idx] = txn;
            txn_idx += 1;
            out_result.imported += 1;
        } else {
            out_result.errors += 1;
        }
    }

    cursor.byte_offset = data.len;
}

fn parseTRBatch(
    data: []const u8,
    cursor: *ParseCursor,
    out_txns: []Transaction,
    out_result: *ImportResult,
) void {
    out_result.* = .{
        .total_rows = 0,
        .imported = 0,
        .skipped_duplicates = 0,
        .errors = 0,
    };

    var pos = cursor.byte_offset;
    var txn_idx: u32 = 0;

    while (pos < data.len) {
        const line_start = pos;
        while (pos < data.len and data[pos] != '\n') : (pos += 1) {}
        const line_end = pos;
        if (pos < data.len) pos += 1;

        const line = trimCr(data[line_start..line_end]);
        if (line.len == 0) continue;

        // Skip header line (once)
        if (!cursor.header_found) {
            if (containsAscii(line, "Date") or containsAscii(line, "date")) {
                cursor.header_found = true;
                continue;
            }
            cursor.header_found = true;
        }

        if (txn_idx >= out_txns.len) {
            cursor.byte_offset = line_start;
            return;
        }

        out_result.total_rows += 1;

        if (parseTradeRepublicLine(line)) |txn| {
            out_txns[txn_idx] = txn;
            txn_idx += 1;
            out_result.imported += 1;
        } else {
            out_result.errors += 1;
        }
    }

    cursor.byte_offset = data.len;
}

fn parseScalableBatch(
    data: []const u8,
    cursor: *ParseCursor,
    out_txns: []Transaction,
    out_result: *ImportResult,
) void {
    out_result.* = .{
        .total_rows = 0,
        .imported = 0,
        .skipped_duplicates = 0,
        .errors = 0,
    };

    var pos = cursor.byte_offset;
    var txn_idx: u32 = 0;

    while (pos < data.len) {
        const line_start = pos;
        while (pos < data.len and data[pos] != '\n') : (pos += 1) {}
        const line_end = pos;
        if (pos < data.len) pos += 1;

        const line = trimCr(data[line_start..line_end]);
        if (line.len == 0) continue;

        if (!cursor.header_found) {
            if (containsAscii(line, "Buchungsdatum") or containsAscii(line, "Datum") or containsAscii(line, "Date")) {
                cursor.header_found = true;
                continue;
            }
            cursor.header_found = true;
        }

        if (txn_idx >= out_txns.len) {
            cursor.byte_offset = line_start;
            return;
        }

        out_result.total_rows += 1;

        if (parseScalableLine(line)) |txn| {
            out_txns[txn_idx] = txn;
            txn_idx += 1;
            out_result.imported += 1;
        } else {
            out_result.errors += 1;
        }
    }

    cursor.byte_offset = data.len;
}

// ============================================================
// Comdirect Parser
// ============================================================

/// Parse a Comdirect CSV export.
/// Format: semicolon-delimited, ISO-8859-1 encoded, dd.MM.yyyy dates,
/// German number format (1.234,56).
pub fn parseComdirectCsv(
    data: []const u8,
    out_txns: []Transaction,
    out_result: *ImportResult,
) void {
    out_result.* = .{
        .total_rows = 0,
        .imported = 0,
        .skipped_duplicates = 0,
        .errors = 0,
    };

    var line_iter = splitLines(data);
    var txn_idx: u32 = 0;

    while (line_iter.next()) |raw_line| {
        const line = trimCr(raw_line);
        if (line.len == 0) continue;

        // Skip header/metadata lines — a transaction line starts with a date dd.MM.yyyy
        if (!looksLikeDateStart(line)) continue;

        out_result.total_rows += 1;

        if (txn_idx >= out_txns.len) {
            out_result.skipped_full += 1;
            continue;
        }

        if (parseComdirectLine(line)) |txn| {
            out_txns[txn_idx] = txn;
            txn_idx += 1;
            out_result.imported += 1;
        } else {
            out_result.errors += 1;
        }
    }
}

fn parseComdirectLine(line: []const u8) ?Transaction {
    var cols: [10][]const u8 = undefined;
    const col_count = splitCsvFields(line, ';', &cols);

    if (col_count < 5) return null;

    const date = parseGermanDate(trim(cols[0])) orelse return null;
    const description_raw = trim(cols[3]);
    const amount_str = trim(cols[4]);
    const amount = parseGermanAmount(amount_str) orelse return null;

    var txn: Transaction = undefined;
    txn.date = date;
    txn.amount_cents = amount;
    txn.currency = "EUR".*;
    txn.category = .uncategorized;
    setAccount(&txn, "comdirect");

    const desc_len = @min(description_raw.len, 256);
    @memcpy(txn.description[0..desc_len], description_raw[0..desc_len]);
    txn.description_len = @intCast(desc_len);

    txn.id = computeHash(date, description_raw, amount, txn.accountSlice());
    return txn;
}

// ============================================================
// Trade Republic Parser
// ============================================================

/// Parse a Trade Republic CSV export.
/// Format: comma-delimited, UTF-8, YYYY-MM-DD dates, English decimal format.
/// Columns: Date,Type,Description,Amount (may vary)
fn parseTradeRepublicCsv(
    data: []const u8,
    out_txns: []Transaction,
    out_result: *ImportResult,
) void {
    out_result.* = .{
        .total_rows = 0,
        .imported = 0,
        .skipped_duplicates = 0,
        .errors = 0,
    };

    var line_iter = splitLines(data);
    var txn_idx: u32 = 0;
    var header_skipped = false;

    while (line_iter.next()) |raw_line| {
        const line = trimCr(raw_line);
        if (line.len == 0) continue;

        // Skip header line
        if (!header_skipped) {
            if (containsAscii(line, "Date") or containsAscii(line, "date")) {
                header_skipped = true;
                continue;
            }
            header_skipped = true;
        }

        out_result.total_rows += 1;

        if (txn_idx >= out_txns.len) {
            out_result.skipped_full += 1;
            continue;
        }

        if (parseTradeRepublicLine(line)) |txn| {
            out_txns[txn_idx] = txn;
            txn_idx += 1;
            out_result.imported += 1;
        } else {
            out_result.errors += 1;
        }
    }
}

fn parseTradeRepublicLine(line: []const u8) ?Transaction {
    // CSV with possible quoted fields — simple comma split (no embedded commas in fields expected)
    var cols: [10][]const u8 = undefined;
    var col_count: usize = 0;

    var col_iter = std.mem.splitScalar(u8, line, ',');
    while (col_iter.next()) |col| {
        if (col_count >= 10) break;
        cols[col_count] = stripQuotes(trim(col));
        col_count += 1;
    }

    // Need at least: Date, Type, Description, Amount
    if (col_count < 4) return null;

    const date = parseIsoDate(cols[0]) orelse return null;
    // cols[1] = type (e.g., "Purchase", "Dividend", "Deposit")
    const description_raw = cols[2];
    const amount = parseEnglishAmount(cols[3]) orelse return null;

    var txn: Transaction = undefined;
    txn.date = date;
    txn.amount_cents = amount;
    txn.currency = "EUR".*;
    txn.category = .uncategorized;
    setAccount(&txn, "trade_republic");

    const desc_len = @min(description_raw.len, 256);
    @memcpy(txn.description[0..desc_len], description_raw[0..desc_len]);
    txn.description_len = @intCast(desc_len);

    txn.id = computeHash(date, description_raw, amount, txn.accountSlice());
    return txn;
}

// ============================================================
// Scalable Capital Parser
// ============================================================

/// Parse a Scalable Capital CSV export.
/// Format: semicolon-delimited, UTF-8, dd.MM.yyyy or YYYY-MM-DD dates.
fn parseScalableCapitalCsv(
    data: []const u8,
    out_txns: []Transaction,
    out_result: *ImportResult,
) void {
    out_result.* = .{
        .total_rows = 0,
        .imported = 0,
        .skipped_duplicates = 0,
        .errors = 0,
    };

    var line_iter = splitLines(data);
    var txn_idx: u32 = 0;
    var header_skipped = false;

    while (line_iter.next()) |raw_line| {
        const line = trimCr(raw_line);
        if (line.len == 0) continue;

        if (!header_skipped) {
            if (containsAscii(line, "Buchungsdatum") or containsAscii(line, "Datum") or containsAscii(line, "Date")) {
                header_skipped = true;
                continue;
            }
            header_skipped = true;
        }

        out_result.total_rows += 1;

        if (txn_idx >= out_txns.len) {
            out_result.skipped_full += 1;
            continue;
        }

        if (parseScalableLine(line)) |txn| {
            out_txns[txn_idx] = txn;
            txn_idx += 1;
            out_result.imported += 1;
        } else {
            out_result.errors += 1;
        }
    }
}

fn parseScalableLine(line: []const u8) ?Transaction {
    var cols: [10][]const u8 = undefined;
    const col_count = splitCsvFields(line, ';', &cols);

    // stripQuotes on each field (splitCsvFields already strips outer quotes for quoted fields,
    // but unquoted fields may still have quotes in raw Scalable exports)
    for (cols[0..col_count]) |*col| {
        col.* = stripQuotes(trim(col.*));
    }

    // Need at least: Buchungsdatum, Beschreibung/Typ, Betrag
    if (col_count < 3) return null;

    // Try ISO date first, then German date
    const date = parseIsoDate(cols[0]) orelse parseGermanDate(cols[0]) orelse return null;

    // Description is typically in column 1 or 2
    const description_raw = if (col_count >= 4) cols[2] else cols[1];
    // Amount is the last meaningful column
    const amount_str = if (col_count >= 4) cols[3] else cols[2];
    const amount = parseGermanAmount(amount_str) orelse parseEnglishAmount(amount_str) orelse return null;

    var txn: Transaction = undefined;
    txn.date = date;
    txn.amount_cents = amount;
    txn.currency = "EUR".*;
    txn.category = .uncategorized;
    setAccount(&txn, "scalable_capital");

    const desc_len = @min(description_raw.len, 256);
    @memcpy(txn.description[0..desc_len], description_raw[0..desc_len]);
    txn.description_len = @intCast(desc_len);

    txn.id = computeHash(date, description_raw, amount, txn.accountSlice());
    return txn;
}

// ============================================================
// Date Parsers
// ============================================================

/// Parse "dd.MM.yyyy" into a Date struct.
fn parseGermanDate(s: []const u8) ?Date {
    const clean = stripQuotes(s);
    if (clean.len < 10) return null;

    const day = parseTwoDigit(clean[0..2]) orelse return null;
    if (clean[2] != '.') return null;
    const month = parseTwoDigit(clean[3..5]) orelse return null;
    if (clean[5] != '.') return null;
    const year = parseFourDigit(clean[6..10]) orelse return null;

    if (month < 1 or month > 12 or day < 1 or day > 31) return null;
    return Date{ .year = year, .month = month, .day = day };
}

/// Parse "YYYY-MM-DD" into a Date struct.
fn parseIsoDate(s: []const u8) ?Date {
    const clean = stripQuotes(s);
    if (clean.len < 10) return null;

    const year = parseFourDigit(clean[0..4]) orelse return null;
    if (clean[4] != '-') return null;
    const month = parseTwoDigit(clean[5..7]) orelse return null;
    if (clean[7] != '-') return null;
    const day = parseTwoDigit(clean[8..10]) orelse return null;

    if (month < 1 or month > 12 or day < 1 or day > 31) return null;
    return Date{ .year = year, .month = month, .day = day };
}

// ============================================================
// Amount Parsers
// ============================================================

/// Parse German-format amount: "1.234,56" or "-1.234,56"
fn parseGermanAmount(s: []const u8) ?i64 {
    const clean = stripQuotes(s);
    if (clean.len == 0) return null;

    var negative = false;
    var start: usize = 0;
    if (clean[0] == '-') {
        negative = true;
        start = 1;
    } else if (clean[0] == '+') {
        start = 1;
    }

    var whole: i64 = 0;
    var frac: i64 = 0;
    var in_frac = false;
    var frac_digits: u8 = 0;

    for (clean[start..]) |ch| {
        if (ch == '.') {
            continue; // Thousands separator
        } else if (ch == ',') {
            in_frac = true;
            continue;
        } else if (ch >= '0' and ch <= '9') {
            if (in_frac) {
                if (frac_digits < 2) {
                    frac = frac * 10 + (ch - '0');
                    frac_digits += 1;
                }
            } else {
                whole = whole * 10 + (ch - '0');
            }
        } else if (ch == ' ' or ch == '"') {
            continue;
        } else {
            return null;
        }
    }

    if (frac_digits == 1) frac *= 10;

    var cents = whole * 100 + frac;
    if (negative) cents = -cents;
    return cents;
}

/// Parse English-format amount: "1234.56" or "-1234.56"
fn parseEnglishAmount(s: []const u8) ?i64 {
    const clean = stripQuotes(trim(s));
    if (clean.len == 0) return null;

    var negative = false;
    var start: usize = 0;
    if (clean[0] == '-') {
        negative = true;
        start = 1;
    } else if (clean[0] == '+') {
        start = 1;
    }

    var whole: i64 = 0;
    var frac: i64 = 0;
    var in_frac = false;
    var frac_digits: u8 = 0;

    for (clean[start..]) |ch| {
        if (ch == ',') {
            continue; // Thousands separator in English format
        } else if (ch == '.') {
            in_frac = true;
            continue;
        } else if (ch >= '0' and ch <= '9') {
            if (in_frac) {
                if (frac_digits < 2) {
                    frac = frac * 10 + (ch - '0');
                    frac_digits += 1;
                }
            } else {
                whole = whole * 10 + (ch - '0');
            }
        } else if (ch == ' ' or ch == '"') {
            continue;
        } else {
            return null;
        }
    }

    if (frac_digits == 1) frac *= 10;

    var cents = whole * 100 + frac;
    if (negative) cents = -cents;
    return cents;
}

// ============================================================
// Hash + Helpers
// ============================================================

pub fn computeHash(date: Date, description: []const u8, amount: i64, account: []const u8) [32]u8 {
    var hasher = std.hash.Fnv1a_128.init();

    var date_buf: [10]u8 = undefined;
    date_buf[0] = @intCast(date.day / 10 + '0');
    date_buf[1] = @intCast(date.day % 10 + '0');
    date_buf[2] = '.';
    date_buf[3] = @intCast(date.month / 10 + '0');
    date_buf[4] = @intCast(date.month % 10 + '0');
    date_buf[5] = '.';
    date_buf[6] = @intCast(date.year / 1000 + '0');
    date_buf[7] = @intCast((date.year / 100) % 10 + '0');
    date_buf[8] = @intCast((date.year / 10) % 10 + '0');
    date_buf[9] = @intCast(date.year % 10 + '0');
    hasher.update(&date_buf);

    hasher.update(description);

    const amt_bytes: [8]u8 = @bitCast(amount);
    hasher.update(&amt_bytes);

    hasher.update(account);

    const hash_val = hasher.final();
    const hash_bytes: [16]u8 = @bitCast(hash_val);

    const hex = "0123456789abcdef";
    var result: [32]u8 = undefined;
    for (hash_bytes, 0..) |byte, i| {
        result[i * 2] = hex[byte >> 4];
        result[i * 2 + 1] = hex[byte & 0x0f];
    }
    return result;
}

pub fn setAccount(txn: *Transaction, name: []const u8) void {
    const len = @min(name.len, 64);
    @memcpy(txn.account[0..len], name[0..len]);
    txn.account_len = @intCast(len);
}

fn splitLines(data: []const u8) std.mem.SplitIterator(u8, .scalar) {
    return std.mem.splitScalar(u8, data, '\n');
}

fn trimCr(line: []const u8) []const u8 {
    if (line.len > 0 and line[line.len - 1] == '\r') {
        return line[0 .. line.len - 1];
    }
    return line;
}

fn trim(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\r\n");
}

fn stripQuotes(s: []const u8) []const u8 {
    var result = s;
    if (result.len >= 2 and result[0] == '"' and result[result.len - 1] == '"') {
        result = result[1 .. result.len - 1];
    }
    return result;
}

/// Split a CSV line into fields, respecting quoted fields.
/// Quoted fields may contain the separator character without splitting.
fn splitCsvFields(line: []const u8, sep: u8, out: *[10][]const u8) usize {
    var count: usize = 0;
    var pos: usize = 0;

    while (pos < line.len and count < 10) {
        if (line[pos] == '"') {
            // Quoted field — find closing quote
            const start = pos + 1;
            pos += 1;
            while (pos < line.len) {
                if (line[pos] == '"') {
                    if (pos + 1 < line.len and line[pos + 1] == '"') {
                        pos += 2; // escaped quote
                    } else {
                        break; // closing quote
                    }
                } else {
                    pos += 1;
                }
            }
            const end = pos;
            out[count] = line[start..end];
            count += 1;
            // Skip closing quote + separator
            if (pos < line.len) pos += 1; // skip "
            if (pos < line.len and line[pos] == sep) pos += 1; // skip sep
        } else {
            // Unquoted field — find separator
            const start = pos;
            while (pos < line.len and line[pos] != sep) : (pos += 1) {}
            out[count] = line[start..pos];
            count += 1;
            if (pos < line.len) pos += 1; // skip sep
        }
    }

    return count;
}

fn looksLikeDateStart(line: []const u8) bool {
    const s = trim(line);
    if (s.len < 10) return false;
    const c0 = s[0];
    const c1 = s[1];
    if (c0 == '"') {
        if (s.len < 12) return false;
        return s[1] >= '0' and s[1] <= '9' and s[2] >= '0' and s[2] <= '9' and s[3] == '.';
    }
    return c0 >= '0' and c0 <= '9' and c1 >= '0' and c1 <= '9' and s[2] == '.';
}

fn parseTwoDigit(s: []const u8) ?u8 {
    if (s.len < 2) return null;
    const d0 = s[0];
    const d1 = s[1];
    if (d0 < '0' or d0 > '9' or d1 < '0' or d1 > '9') return null;
    return (d0 - '0') * 10 + (d1 - '0');
}

fn parseFourDigit(s: []const u8) ?u16 {
    if (s.len < 4) return null;
    var result: u16 = 0;
    for (s[0..4]) |ch| {
        if (ch < '0' or ch > '9') return null;
        result = result * 10 + (ch - '0');
    }
    return result;
}

// --- Detection helpers ---

fn containsAscii(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (haystack.len < needle.len) return false;
    const limit = haystack.len - needle.len + 1;
    for (0..limit) |i| {
        if (std.mem.eql(u8, haystack[i .. i + needle.len], needle)) return true;
    }
    return false;
}

fn startsWithHeader(data: []const u8, prefix: []const u8) bool {
    if (data.len < prefix.len) return false;
    // Skip BOM if present
    var start: usize = 0;
    if (data.len >= 3 and data[0] == 0xEF and data[1] == 0xBB and data[2] == 0xBF) {
        start = 3;
    }
    const trimmed = trim(data[start..]);
    if (trimmed.len < prefix.len) return false;
    return std.mem.eql(u8, trimmed[0..prefix.len], prefix);
}

fn containsSemicolon(data: []const u8) bool {
    for (data) |ch| {
        if (ch == ';') return true;
    }
    return false;
}

fn containsGermanDate(data: []const u8) bool {
    // Look for dd.MM.yyyy pattern
    if (data.len < 10) return false;
    for (0..data.len - 9) |i| {
        if (data[i] >= '0' and data[i] <= '9' and
            data[i + 1] >= '0' and data[i + 1] <= '9' and
            data[i + 2] == '.' and
            data[i + 3] >= '0' and data[i + 3] <= '9' and
            data[i + 4] >= '0' and data[i + 4] <= '9' and
            data[i + 5] == '.')
        {
            return true;
        }
    }
    return false;
}

// ============================================================
// Tests
// ============================================================

// --- Format detection ---

test "detectCsvFormat: Comdirect header" {
    const header = "Buchungstag;Wertstellung;Vorgang;Buchungstext;Umsatz in EUR\n";
    try std.testing.expectEqual(CsvFormat.comdirect, detectCsvFormat(header));
}

test "detectCsvFormat: Trade Republic quoted header" {
    const header = "\"Date\",\"Type\",\"Description\",\"Amount\"\n";
    try std.testing.expectEqual(CsvFormat.trade_republic, detectCsvFormat(header));
}

test "detectCsvFormat: Trade Republic unquoted header" {
    const header = "Date,Type,Description,Amount\n";
    try std.testing.expectEqual(CsvFormat.trade_republic, detectCsvFormat(header));
}

test "detectCsvFormat: Scalable Capital header" {
    const header = "Buchungsdatum;Typ;Beschreibung;Betrag\n";
    try std.testing.expectEqual(CsvFormat.scalable_capital, detectCsvFormat(header));
}

test "detectCsvFormat: empty data" {
    try std.testing.expectEqual(CsvFormat.unknown, detectCsvFormat(""));
}

test "detectCsvFormat: garbage data" {
    try std.testing.expectEqual(CsvFormat.unknown, detectCsvFormat("hello world foo bar"));
}

test "CsvFormat.name returns string" {
    try std.testing.expectEqualStrings("comdirect", CsvFormat.comdirect.name());
    try std.testing.expectEqualStrings("trade_republic", CsvFormat.trade_republic.name());
    try std.testing.expectEqualStrings("scalable_capital", CsvFormat.scalable_capital.name());
    try std.testing.expectEqualStrings("unknown", CsvFormat.unknown.name());
}

// --- Date parsing ---

test "parseGermanDate valid" {
    const d = parseGermanDate("01.02.2026").?;
    try std.testing.expectEqual(@as(u16, 2026), d.year);
    try std.testing.expectEqual(@as(u8, 2), d.month);
    try std.testing.expectEqual(@as(u8, 1), d.day);
}

test "parseGermanDate another valid" {
    const d = parseGermanDate("31.12.2025").?;
    try std.testing.expectEqual(@as(u16, 2025), d.year);
    try std.testing.expectEqual(@as(u8, 12), d.month);
    try std.testing.expectEqual(@as(u8, 31), d.day);
}

test "parseGermanDate invalid string" {
    try std.testing.expect(parseGermanDate("invalid") == null);
}

test "parseGermanDate too short" {
    try std.testing.expect(parseGermanDate("01.02.20") == null);
}

test "parseGermanDate month 0 invalid" {
    try std.testing.expect(parseGermanDate("01.00.2026") == null);
}

test "parseGermanDate month 13 invalid" {
    try std.testing.expect(parseGermanDate("01.13.2026") == null);
}

test "parseGermanDate day 0 invalid" {
    try std.testing.expect(parseGermanDate("00.01.2026") == null);
}

test "parseGermanDate day 32 invalid" {
    try std.testing.expect(parseGermanDate("32.01.2026") == null);
}

test "parseGermanDate with surrounding quotes" {
    const d = parseGermanDate("\"15.06.2026\"").?;
    try std.testing.expectEqual(@as(u8, 15), d.day);
    try std.testing.expectEqual(@as(u8, 6), d.month);
}

test "parseIsoDate valid" {
    const d = parseIsoDate("2026-02-01").?;
    try std.testing.expectEqual(@as(u16, 2026), d.year);
    try std.testing.expectEqual(@as(u8, 2), d.month);
    try std.testing.expectEqual(@as(u8, 1), d.day);
}

test "parseIsoDate another valid" {
    const d = parseIsoDate("2025-12-31").?;
    try std.testing.expectEqual(@as(u16, 2025), d.year);
    try std.testing.expectEqual(@as(u8, 12), d.month);
    try std.testing.expectEqual(@as(u8, 31), d.day);
}

test "parseIsoDate invalid" {
    try std.testing.expect(parseIsoDate("invalid") == null);
}

test "parseIsoDate too short" {
    try std.testing.expect(parseIsoDate("2026-02") == null);
}

test "parseIsoDate month 0" {
    try std.testing.expect(parseIsoDate("2026-00-01") == null);
}

test "parseIsoDate month 13" {
    try std.testing.expect(parseIsoDate("2026-13-01") == null);
}

// --- Amount parsing ---

test "parseGermanAmount standard" {
    try std.testing.expectEqual(@as(i64, 123456), parseGermanAmount("1.234,56").?);
}

test "parseGermanAmount negative" {
    try std.testing.expectEqual(@as(i64, -4250), parseGermanAmount("-42,50").?);
}

test "parseGermanAmount positive sign" {
    try std.testing.expectEqual(@as(i64, 1000), parseGermanAmount("+10,00").?);
}

test "parseGermanAmount empty" {
    try std.testing.expect(parseGermanAmount("") == null);
}

test "parseGermanAmount no decimals" {
    try std.testing.expectEqual(@as(i64, 100), parseGermanAmount("1").?);
}

test "parseGermanAmount single decimal" {
    try std.testing.expectEqual(@as(i64, 1050), parseGermanAmount("10,5").?);
}

test "parseGermanAmount with quotes" {
    try std.testing.expectEqual(@as(i64, 2500), parseGermanAmount("\"25,00\"").?);
}

test "parseEnglishAmount standard" {
    try std.testing.expectEqual(@as(i64, 123456), parseEnglishAmount("1234.56").?);
}

test "parseEnglishAmount negative" {
    try std.testing.expectEqual(@as(i64, -4250), parseEnglishAmount("-42.50").?);
}

test "parseEnglishAmount single decimal digit" {
    try std.testing.expectEqual(@as(i64, 1050), parseEnglishAmount("10.5").?);
}

test "parseEnglishAmount empty" {
    try std.testing.expect(parseEnglishAmount("") == null);
}

test "parseEnglishAmount with thousands separator" {
    try std.testing.expectEqual(@as(i64, 123456), parseEnglishAmount("1,234.56").?);
}

test "parseEnglishAmount positive sign" {
    try std.testing.expectEqual(@as(i64, 500), parseEnglishAmount("+5.00").?);
}

// --- Hash ---

test "computeHash is deterministic" {
    const d = Date{ .year = 2026, .month = 3, .day = 5 };
    const h1 = computeHash(d, "REWE", 1234, "comdirect");
    const h2 = computeHash(d, "REWE", 1234, "comdirect");
    try std.testing.expectEqualSlices(u8, &h1, &h2);
}

test "computeHash different description yields different hash" {
    const d = Date{ .year = 2026, .month = 3, .day = 5 };
    const h1 = computeHash(d, "REWE", 1234, "comdirect");
    const h2 = computeHash(d, "ALDI", 1234, "comdirect");
    try std.testing.expect(!std.mem.eql(u8, &h1, &h2));
}

test "computeHash different account yields different hash" {
    const d = Date{ .year = 2026, .month = 3, .day = 5 };
    const h1 = computeHash(d, "REWE", 1234, "comdirect");
    const h2 = computeHash(d, "REWE", 1234, "trade_republic");
    try std.testing.expect(!std.mem.eql(u8, &h1, &h2));
}

test "computeHash result is 32 hex characters" {
    const d = Date{ .year = 2026, .month = 3, .day = 5 };
    const h = computeHash(d, "Test", 100, "acc");
    for (h) |ch| {
        try std.testing.expect((ch >= '0' and ch <= '9') or (ch >= 'a' and ch <= 'f'));
    }
    try std.testing.expectEqual(@as(usize, 32), h.len);
}

// --- Full CSV parsing ---

test "parseComdirectCsv: single transaction" {
    const csv = "Buchungstag;Wertstellung;Vorgang;Buchungstext;Umsatz in EUR\n" ++
        "05.03.2026;05.03.2026;Lastschrift;REWE Supermarkt;-42,50\n";
    var txns: [10]Transaction = undefined;
    var result: ImportResult = undefined;
    parseComdirectCsv(csv, &txns, &result);
    try std.testing.expectEqual(@as(u32, 1), result.total_rows);
    try std.testing.expectEqual(@as(u32, 1), result.imported);
    try std.testing.expectEqual(@as(u32, 0), result.errors);
    try std.testing.expectEqual(@as(i64, -4250), txns[0].amount_cents);
    try std.testing.expectEqual(@as(u8, 5), txns[0].date.day);
    try std.testing.expectEqual(@as(u8, 3), txns[0].date.month);
    try std.testing.expectEqualStrings("comdirect", txns[0].accountSlice());
}

test "parseTradeRepublicCsv: single transaction via parseCsv" {
    const csv = "Date,Type,Description,Amount\n" ++
        "2026-03-05,Purchase,MSCI World ETF,-100.50\n";
    var txns: [10]Transaction = undefined;
    var result: ImportResult = undefined;
    const fmt = parseCsv(csv, &txns, &result);
    try std.testing.expectEqual(CsvFormat.trade_republic, fmt);
    try std.testing.expectEqual(@as(u32, 1), result.imported);
    try std.testing.expectEqual(@as(i64, -10050), txns[0].amount_cents);
    try std.testing.expectEqualStrings("trade_republic", txns[0].accountSlice());
}

test "parseScalableCapitalCsv: single transaction via parseCsv" {
    const csv = "Buchungsdatum;Typ;Beschreibung;Betrag\n" ++
        "05.03.2026;Kauf;ETF Sparplan;-50,00\n";
    var txns: [10]Transaction = undefined;
    var result: ImportResult = undefined;
    const fmt = parseCsv(csv, &txns, &result);
    try std.testing.expectEqual(CsvFormat.scalable_capital, fmt);
    try std.testing.expectEqual(@as(u32, 1), result.imported);
    try std.testing.expectEqual(@as(i64, -5000), txns[0].amount_cents);
    try std.testing.expectEqualStrings("scalable_capital", txns[0].accountSlice());
}

test "parseCsv: empty data" {
    var txns: [10]Transaction = undefined;
    var result: ImportResult = undefined;
    _ = parseCsv("", &txns, &result);
    try std.testing.expectEqual(@as(u32, 0), result.imported);
    try std.testing.expectEqual(@as(u32, 0), result.total_rows);
}

test "parseComdirectCsv: buffer overflow counts skipped_full" {
    const csv = "05.03.2026;05.03.2026;Lastschrift;REWE;-10,00\n" ++
        "06.03.2026;06.03.2026;Lastschrift;ALDI;-20,00\n" ++
        "07.03.2026;07.03.2026;Lastschrift;LIDL;-30,00\n";
    var txns: [2]Transaction = undefined;
    var result: ImportResult = undefined;
    parseComdirectCsv(csv, &txns, &result);
    try std.testing.expectEqual(@as(u32, 3), result.total_rows);
    try std.testing.expectEqual(@as(u32, 2), result.imported);
    try std.testing.expectEqual(@as(u32, 0), result.errors);
    try std.testing.expectEqual(@as(u32, 1), result.skipped_full);
}

test "parseComdirectCsv: CRLF line endings" {
    const csv = "05.03.2026;05.03.2026;Lastschrift;REWE;-42,50\r\n";
    var txns: [10]Transaction = undefined;
    var result: ImportResult = undefined;
    parseComdirectCsv(csv, &txns, &result);
    try std.testing.expectEqual(@as(u32, 1), result.imported);
}

// --- Helper functions ---

test "stripQuotes removes surrounding quotes" {
    try std.testing.expectEqualStrings("hello", stripQuotes("\"hello\""));
}

test "stripQuotes leaves unquoted strings" {
    try std.testing.expectEqualStrings("hello", stripQuotes("hello"));
}

test "stripQuotes leaves single char" {
    try std.testing.expectEqualStrings("a", stripQuotes("a"));
}

test "containsAscii: found" {
    try std.testing.expect(containsAscii("hello world", "world"));
}

test "containsAscii: not found" {
    try std.testing.expect(!containsAscii("hello world", "xyz"));
}

test "containsAscii: empty needle" {
    try std.testing.expect(containsAscii("hello", ""));
}

test "containsAscii: needle longer than haystack" {
    try std.testing.expect(!containsAscii("hi", "hello"));
}

test "looksLikeDateStart: valid German date line" {
    try std.testing.expect(looksLikeDateStart("05.03.2026;foo;bar"));
}

test "looksLikeDateStart: quoted date" {
    try std.testing.expect(looksLikeDateStart("\"05.03.2026\";foo"));
}

test "looksLikeDateStart: non-date" {
    try std.testing.expect(!looksLikeDateStart("Buchungstag;foo"));
}

test "trimCr: removes trailing CR" {
    try std.testing.expectEqualStrings("hello", trimCr("hello\r"));
}

test "trimCr: no CR unchanged" {
    try std.testing.expectEqualStrings("hello", trimCr("hello"));
}

// --- Stress / performance tests ---

/// `s` repeated `n` times, built at comptime (Zig 0.17 dropped the `**` operator).
fn repeatStr(comptime s: []const u8, comptime n: usize) *const [s.len * n]u8 {
    @setEvalBranchQuota(n * 10 + 1000);
    var out: [s.len * n]u8 = undefined;
    for (0..n) |i| @memcpy(out[i * s.len ..][0..s.len], s);
    const final = out;
    return &final;
}

test "parseComdirectCsv: 1000 rows" {
    // Build a 1000-line CSV at comptime
    const header = "Buchungstag;Wertstellung;Vorgang;Buchungstext;Umsatz in EUR\n";
    const row = "15.01.2026;15.01.2026;Lastschrift;REWE Supermarkt Berlin;-23,99\n";
    const csv = header ++ comptime repeatStr(row, 1000);

    var txns: [1000]Transaction = undefined;
    var result: ImportResult = undefined;
    parseComdirectCsv(csv, &txns, &result);

    try std.testing.expectEqual(@as(u32, 1000), result.total_rows);
    try std.testing.expectEqual(@as(u32, 1000), result.imported);
    try std.testing.expectEqual(@as(u32, 0), result.errors);

    // Verify first and last transactions
    try std.testing.expectEqual(@as(i64, -2399), txns[0].amount_cents);
    try std.testing.expectEqual(@as(i64, -2399), txns[999].amount_cents);
    try std.testing.expectEqualStrings("comdirect", txns[500].accountSlice());
}

test "parseTradeRepublicCsv: 1000 rows" {
    const header = "Date,Type,Description,Amount\n";
    const row = "2026-01-15,Purchase,iShares MSCI World,-250.00\n";
    const csv = header ++ comptime repeatStr(row, 1000);

    var txns: [1000]Transaction = undefined;
    var result: ImportResult = undefined;
    const fmt = parseCsv(csv, &txns, &result);

    try std.testing.expectEqual(CsvFormat.trade_republic, fmt);
    try std.testing.expectEqual(@as(u32, 1000), result.imported);
    try std.testing.expectEqual(@as(i64, -25000), txns[0].amount_cents);
}

test "parseScalableCapitalCsv: 1000 rows" {
    const header = "Buchungsdatum;Typ;Beschreibung;Betrag\n";
    const row = "15.01.2026;Sparplan;ETF World;-100,00\n";
    const csv = header ++ comptime repeatStr(row, 1000);

    var txns: [1000]Transaction = undefined;
    var result: ImportResult = undefined;
    const fmt = parseCsv(csv, &txns, &result);

    try std.testing.expectEqual(CsvFormat.scalable_capital, fmt);
    try std.testing.expectEqual(@as(u32, 1000), result.imported);
    try std.testing.expectEqual(@as(i64, -10000), txns[0].amount_cents);
}

test "parseComdirectCsv: 500 rows into buffer of 100 — overflow handled" {
    const row = "01.02.2026;01.02.2026;Lastschrift;ALDI Nord;-15,50\n";
    const csv = comptime repeatStr(row, 500);

    var txns: [100]Transaction = undefined;
    var result: ImportResult = undefined;
    parseComdirectCsv(csv, &txns, &result);

    try std.testing.expectEqual(@as(u32, 500), result.total_rows);
    try std.testing.expectEqual(@as(u32, 100), result.imported);
    try std.testing.expectEqual(@as(u32, 0), result.errors);
    try std.testing.expectEqual(@as(u32, 400), result.skipped_full);

    // Buffer contents are still valid
    try std.testing.expectEqual(@as(i64, -1550), txns[0].amount_cents);
    try std.testing.expectEqual(@as(i64, -1550), txns[99].amount_cents);
}

test "parseComdirectCsv: description truncated at 256 chars" {
    // Description with 300 chars
    const long_desc = &@as([300]u8, @splat('A'));
    const csv = "10.03.2026;10.03.2026;Lastschrift;" ++ long_desc ++ ";-5,00\n";

    var txns: [1]Transaction = undefined;
    var result: ImportResult = undefined;
    parseComdirectCsv(csv, &txns, &result);

    try std.testing.expectEqual(@as(u32, 1), result.imported);
    try std.testing.expectEqual(@as(u16, 256), txns[0].description_len);
    try std.testing.expectEqualStrings(&@as([256]u8, @splat('A')), txns[0].descriptionSlice());
}

test "parseComdirectCsv: mixed valid and invalid rows" {
    const csv =
        "05.03.2026;05.03.2026;Lastschrift;REWE;-10,00\n" ++
        "not a valid row at all\n" ++
        "06.03.2026;06.03.2026;Lastschrift;ALDI;-20,00\n" ++
        "header;row;that;looks;like;meta\n" ++
        "07.03.2026;07.03.2026;Lastschrift;LIDL;-30,00\n";

    var txns: [10]Transaction = undefined;
    var result: ImportResult = undefined;
    parseComdirectCsv(csv, &txns, &result);

    try std.testing.expectEqual(@as(u32, 3), result.total_rows);
    try std.testing.expectEqual(@as(u32, 3), result.imported);
}

test "parseComdirectCsv: various real-world amounts" {
    const csv =
        "01.01.2026;01.01.2026;Gehalt;Arbeitgeber GmbH;3.500,00\n" ++
        "02.01.2026;02.01.2026;Lastschrift;Miete;-1.200,00\n" ++
        "03.01.2026;03.01.2026;Lastschrift;Strom;-89,50\n" ++
        "04.01.2026;04.01.2026;Lastschrift;Netflix;-12,99\n" ++
        "05.01.2026;05.01.2026;Kartenzahlung;Cafe;-4,80\n";

    var txns: [10]Transaction = undefined;
    var result: ImportResult = undefined;
    parseComdirectCsv(csv, &txns, &result);

    try std.testing.expectEqual(@as(u32, 5), result.imported);
    try std.testing.expectEqual(@as(i64, 350000), txns[0].amount_cents); // salary
    try std.testing.expectEqual(@as(i64, -120000), txns[1].amount_cents); // rent
    try std.testing.expectEqual(@as(i64, -8950), txns[2].amount_cents); // electricity
    try std.testing.expectEqual(@as(i64, -1299), txns[3].amount_cents); // netflix
    try std.testing.expectEqual(@as(i64, -480), txns[4].amount_cents); // cafe
}

test "parseComdirectCsv: all hashes unique for different transactions" {
    const csv =
        "01.01.2026;01.01.2026;Gehalt;Firma A;1.000,00\n" ++
        "01.01.2026;01.01.2026;Gehalt;Firma B;1.000,00\n" ++
        "02.01.2026;02.01.2026;Gehalt;Firma A;1.000,00\n" ++
        "01.01.2026;01.01.2026;Gehalt;Firma A;2.000,00\n";

    var txns: [4]Transaction = undefined;
    var result: ImportResult = undefined;
    parseComdirectCsv(csv, &txns, &result);

    try std.testing.expectEqual(@as(u32, 4), result.imported);

    // All 4 transactions have different IDs
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        var j = i + 1;
        while (j < 4) : (j += 1) {
            try std.testing.expect(!std.mem.eql(u8, &txns[i].id, &txns[j].id));
        }
    }
}

test "parseComdirectCsv: too few columns returns error" {
    const csv = "05.03.2026;05.03.2026;only three columns\n";
    var txns: [1]Transaction = undefined;
    var result: ImportResult = undefined;
    parseComdirectCsv(csv, &txns, &result);
    try std.testing.expectEqual(@as(u32, 1), result.total_rows);
    try std.testing.expectEqual(@as(u32, 0), result.imported);
    try std.testing.expectEqual(@as(u32, 1), result.errors);
}

test "parseGermanAmount: large salary amount" {
    try std.testing.expectEqual(@as(i64, 1234567), parseGermanAmount("12.345,67").?);
}

test "parseGermanAmount: very large amount" {
    try std.testing.expectEqual(@as(i64, 10000000), parseGermanAmount("100.000,00").?);
}

test "parseEnglishAmount: large amount" {
    try std.testing.expectEqual(@as(i64, 10000000), parseEnglishAmount("100000.00").?);
}

test "parseCsv: Comdirect fallback for semicolon+German date" {
    const csv = "01.03.2026;foo;bar;Beschreibung;-10,00\n";
    var txns: [1]Transaction = undefined;
    var result: ImportResult = undefined;
    const fmt = parseCsv(csv, &txns, &result);
    // Falls back to comdirect due to semicolons + German dates
    try std.testing.expectEqual(CsvFormat.comdirect, fmt);
    try std.testing.expectEqual(@as(u32, 1), result.imported);
}

// --- 1M-row stress tests (runtime-generated CSV) ---

fn generateCsvRows(allocator: std.mem.Allocator, row: []const u8, count: usize) ![]u8 {
    const total_len = row.len * count;
    const buf = try allocator.alloc(u8, total_len);
    var offset: usize = 0;
    for (0..count) |_| {
        @memcpy(buf[offset .. offset + row.len], row);
        offset += row.len;
    }
    return buf;
}

test "parseComdirectCsv: 1M rows — overflow into 10K buffer" {
    const allocator = std.testing.allocator;
    const row = "15.01.2026;15.01.2026;Lastschrift;REWE Supermarkt Berlin;-23,99\n";
    const csv = try generateCsvRows(allocator, row, 1_000_000);
    defer allocator.free(csv);

    const txns = try allocator.alloc(Transaction, 10_000);
    defer allocator.free(txns);

    var result: ImportResult = undefined;
    parseComdirectCsv(csv, txns, &result);

    try std.testing.expectEqual(@as(u32, 1_000_000), result.total_rows);
    try std.testing.expectEqual(@as(u32, 10_000), result.imported);
    try std.testing.expectEqual(@as(u32, 0), result.errors);
    try std.testing.expectEqual(@as(u32, 990_000), result.skipped_full);

    // First and last imported transactions are valid
    try std.testing.expectEqual(@as(i64, -2399), txns[0].amount_cents);
    try std.testing.expectEqual(@as(i64, -2399), txns[9_999].amount_cents);
    try std.testing.expectEqualStrings("comdirect", txns[0].accountSlice());
    try std.testing.expectEqualStrings("REWE Supermarkt Berlin", txns[5_000].descriptionSlice());
}

test "parseTradeRepublicCsv: 1M rows — overflow into 10K buffer" {
    const allocator = std.testing.allocator;
    // Header needed for format detection, but only first line
    const header = "Date,Type,Description,Amount\n";
    const row = "2026-01-15,Purchase,iShares MSCI World,-250.00\n";

    const header_len = header.len;
    const body_len = row.len * 1_000_000;
    const csv = try allocator.alloc(u8, header_len + body_len);
    defer allocator.free(csv);

    @memcpy(csv[0..header_len], header);
    var offset: usize = header_len;
    for (0..1_000_000) |_| {
        @memcpy(csv[offset .. offset + row.len], row);
        offset += row.len;
    }

    const txns = try allocator.alloc(Transaction, 10_000);
    defer allocator.free(txns);

    var result: ImportResult = undefined;
    const fmt = parseCsv(csv, txns, &result);

    try std.testing.expectEqual(CsvFormat.trade_republic, fmt);
    try std.testing.expectEqual(@as(u32, 1_000_000), result.total_rows);
    try std.testing.expectEqual(@as(u32, 10_000), result.imported);
    try std.testing.expectEqual(@as(u32, 0), result.errors);
    try std.testing.expectEqual(@as(u32, 990_000), result.skipped_full);
    try std.testing.expectEqual(@as(i64, -25000), txns[0].amount_cents);
    try std.testing.expectEqualStrings("trade_republic", txns[0].accountSlice());
}

test "parseScalableCapitalCsv: 1M rows — overflow into 10K buffer" {
    const allocator = std.testing.allocator;
    const header = "Buchungsdatum;Typ;Beschreibung;Betrag\n";
    const row = "15.01.2026;Sparplan;ETF World;-100,00\n";

    const header_len = header.len;
    const body_len = row.len * 1_000_000;
    const csv = try allocator.alloc(u8, header_len + body_len);
    defer allocator.free(csv);

    @memcpy(csv[0..header_len], header);
    var offset: usize = header_len;
    for (0..1_000_000) |_| {
        @memcpy(csv[offset .. offset + row.len], row);
        offset += row.len;
    }

    const txns = try allocator.alloc(Transaction, 10_000);
    defer allocator.free(txns);

    var result: ImportResult = undefined;
    const fmt = parseCsv(csv, txns, &result);

    try std.testing.expectEqual(CsvFormat.scalable_capital, fmt);
    try std.testing.expectEqual(@as(u32, 1_000_000), result.total_rows);
    try std.testing.expectEqual(@as(u32, 10_000), result.imported);
    try std.testing.expectEqual(@as(u32, 0), result.errors);
    try std.testing.expectEqual(@as(u32, 990_000), result.skipped_full);
    try std.testing.expectEqual(@as(i64, -10000), txns[0].amount_cents);
}

test "parseComdirectCsv: 100K rows fully parsed" {
    const allocator = std.testing.allocator;
    const row = "15.01.2026;15.01.2026;Lastschrift;REWE Supermarkt;-23,99\n";
    const csv = try generateCsvRows(allocator, row, 100_000);
    defer allocator.free(csv);

    const txns = try allocator.alloc(Transaction, 100_000);
    defer allocator.free(txns);

    var result: ImportResult = undefined;
    parseComdirectCsv(csv, txns, &result);

    try std.testing.expectEqual(@as(u32, 100_000), result.total_rows);
    try std.testing.expectEqual(@as(u32, 100_000), result.imported);
    try std.testing.expectEqual(@as(u32, 0), result.errors);

    // Spot-check across the range
    try std.testing.expectEqual(@as(i64, -2399), txns[0].amount_cents);
    try std.testing.expectEqual(@as(i64, -2399), txns[49_999].amount_cents);
    try std.testing.expectEqual(@as(i64, -2399), txns[99_999].amount_cents);
    try std.testing.expectEqualStrings("comdirect", txns[99_999].accountSlice());
    try std.testing.expectEqual(@as(u8, 15), txns[50_000].date.day);
}

// ============================================================
// Batch processing tests
// ============================================================

test "parseCsvBatch: Comdirect 1M rows — batch loop processes all" {
    const allocator = std.testing.allocator;
    const row = "15.01.2026;15.01.2026;Lastschrift;REWE Supermarkt Berlin;-23,99\n";
    const csv = try generateCsvRows(allocator, row, 1_000_000);
    defer allocator.free(csv);

    const batch_size = 10_000;
    const txns = try allocator.alloc(Transaction, batch_size);
    defer allocator.free(txns);

    var cursor = ParseCursor{};
    var total_rows: u32 = 0;
    var total_imported: u32 = 0;
    var total_errors: u32 = 0;

    while (cursor.byte_offset < csv.len) {
        var batch_result: ImportResult = undefined;
        parseCsvBatch(csv, &cursor, txns, &batch_result);

        total_rows += batch_result.total_rows;
        total_imported += batch_result.imported;
        total_errors += batch_result.errors;

        if (batch_result.imported == 0 and batch_result.total_rows == 0) break;
    }

    try std.testing.expectEqual(CsvFormat.comdirect, cursor.format);
    try std.testing.expectEqual(@as(u32, 1_000_000), total_rows);
    try std.testing.expectEqual(@as(u32, 1_000_000), total_imported);
    try std.testing.expectEqual(@as(u32, 0), total_errors);
}

test "parseCsvBatch: TR 1M rows — batch loop processes all" {
    const allocator = std.testing.allocator;
    const header = "Date,Type,Description,Amount\n";
    const row = "2026-01-15,Purchase,iShares MSCI World,-250.00\n";

    const csv = try allocator.alloc(u8, header.len + row.len * 1_000_000);
    defer allocator.free(csv);
    @memcpy(csv[0..header.len], header);
    var off: usize = header.len;
    for (0..1_000_000) |_| {
        @memcpy(csv[off .. off + row.len], row);
        off += row.len;
    }

    const batch_size = 10_000;
    const txns = try allocator.alloc(Transaction, batch_size);
    defer allocator.free(txns);

    var cursor = ParseCursor{};
    var total_imported: u32 = 0;

    while (cursor.byte_offset < csv.len) {
        var batch_result: ImportResult = undefined;
        parseCsvBatch(csv, &cursor, txns, &batch_result);
        total_imported += batch_result.imported;
        if (batch_result.imported == 0 and batch_result.total_rows == 0) break;
    }

    try std.testing.expectEqual(CsvFormat.trade_republic, cursor.format);
    try std.testing.expectEqual(@as(u32, 1_000_000), total_imported);
}

test "parseCsvBatch: Scalable 1M rows — batch loop processes all" {
    const allocator = std.testing.allocator;
    const header = "Buchungsdatum;Typ;Beschreibung;Betrag\n";
    const row = "15.01.2026;Sparplan;ETF World;-100,00\n";

    const csv = try allocator.alloc(u8, header.len + row.len * 1_000_000);
    defer allocator.free(csv);
    @memcpy(csv[0..header.len], header);
    var off: usize = header.len;
    for (0..1_000_000) |_| {
        @memcpy(csv[off .. off + row.len], row);
        off += row.len;
    }

    const batch_size = 10_000;
    const txns = try allocator.alloc(Transaction, batch_size);
    defer allocator.free(txns);

    var cursor = ParseCursor{};
    var total_imported: u32 = 0;

    while (cursor.byte_offset < csv.len) {
        var batch_result: ImportResult = undefined;
        parseCsvBatch(csv, &cursor, txns, &batch_result);
        total_imported += batch_result.imported;
        if (batch_result.imported == 0 and batch_result.total_rows == 0) break;
    }

    try std.testing.expectEqual(CsvFormat.scalable_capital, cursor.format);
    try std.testing.expectEqual(@as(u32, 1_000_000), total_imported);
}

test "parseCsvBatch: small batch processes correct count" {
    const csv = "05.03.2026;05.03.2026;Lastschrift;REWE;-10,00\n" ++
        "06.03.2026;06.03.2026;Lastschrift;ALDI;-20,00\n" ++
        "07.03.2026;07.03.2026;Lastschrift;LIDL;-30,00\n";

    var txns: [2]Transaction = undefined;
    var cursor = ParseCursor{};
    var total_imported: u32 = 0;
    var batches: u32 = 0;

    while (cursor.byte_offset < csv.len) {
        var batch_result: ImportResult = undefined;
        parseCsvBatch(csv, &cursor, &txns, &batch_result);
        total_imported += batch_result.imported;
        batches += 1;
        if (batch_result.imported == 0 and batch_result.total_rows == 0) break;
    }

    try std.testing.expectEqual(@as(u32, 3), total_imported);
    try std.testing.expectEqual(@as(u32, 2), batches); // 2 + 1
}

test "parseCsvBatch: empty data" {
    var txns: [10]Transaction = undefined;
    var cursor = ParseCursor{};
    var batch_result: ImportResult = undefined;
    parseCsvBatch("", &cursor, &txns, &batch_result);
    try std.testing.expectEqual(@as(u32, 0), batch_result.imported);
    try std.testing.expectEqual(cursor.byte_offset, 0);
}
