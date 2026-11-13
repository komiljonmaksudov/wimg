const std = @import("std");
const types = @import("types.zig");
const c = @import("sqlite_c.zig");

const Category = types.Category;

/// Match a transaction description against categorization rules in the database.
/// Returns the highest-priority matching category, or .uncategorized if no match.
pub fn matchRules(handle: *c.sqlite3, description: []const u8) Category {
    const sql = "SELECT pattern, category FROM rules ORDER BY priority DESC;";

    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(handle, sql, -1, &stmt, null);
    if (rc != c.SQLITE_OK or stmt == null) return .uncategorized;
    defer _ = c.sqlite3_finalize(stmt.?);

    const s = stmt.?;
    while (c.sqlite3_step(s) == c.SQLITE_ROW) {
        const pat_ptr = c.sqlite3_column_text(s, 0) orelse continue;
        const pat_len: usize = @intCast(c.sqlite3_column_bytes(s, 0));
        const cat_val = c.sqlite3_column_int(s, 1);

        if (pat_len == 0) continue;

        if (containsIgnoreCase(description, pat_ptr[0..pat_len])) {
            return Category.fromInt(@intCast(cat_val));
        }
    }

    return .uncategorized;
}

/// Case-insensitive substring search (ASCII only).
pub fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    return std.ascii.findIgnoreCase(haystack, needle) != null;
}

fn toLowerAscii(ch: u8) u8 {
    if (ch >= 'A' and ch <= 'Z') return ch + 32;
    return ch;
}

fn eqlIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ac, bc| {
        if (toLowerAscii(ac) != toLowerAscii(bc)) return false;
    }
    return true;
}

/// Extract a merchant keyword from a German banking transaction description.
/// Strips common prefixes (LASTSCHRIFT, KARTENZAHLUNG, etc.), skips short words,
/// numbers, and filler words. Returns the first meaningful word, or null.
pub fn extractKeyword(desc: []const u8) ?[]const u8 {
    const skip_prefixes = [_][]const u8{
        "LASTSCHRIFT", "KARTENZAHLUNG",    "SEPA",
        "ÜBERWEISUNG",
        "GUTSCHRIFT",  "VISA",             "MASTERCARD",
        "ABRECHNUNG",  "DAUERAUFTRAG",     "EINZAHLUNG",
        "AUSZAHLUNG",  "BARGELD",          "FOLGENR",
        "VERRECHNUNG", "BASISLASTSCHRIFT", "ECHTZEIT",
        "PAYPAL",
    };
    const skip_filler = [_][]const u8{
        "GMBH", "UG",    "AG",     "KG",   "OHG", "GBR", "INC", "LTD",   "LLC",
        "SAGT", "DANKE", "VIELEN", "DANK", "NR",  "REF", "END", "KARTE",
    };

    var i: usize = 0;
    while (i < desc.len) {
        // skip whitespace and common separators
        while (i < desc.len and (desc[i] == ' ' or desc[i] == '/' or desc[i] == '*' or desc[i] == '-')) : (i += 1) {}
        if (i >= desc.len) break;

        const start = i;
        while (i < desc.len and desc[i] != ' ' and desc[i] != '/' and desc[i] != '*') : (i += 1) {}
        const word = desc[start..i];

        if (word.len < 3) continue;
        if (word[0] >= '0' and word[0] <= '9') continue;

        var is_skip = false;
        for (skip_prefixes) |pfx| {
            if (eqlIgnoreCase(word, pfx)) {
                is_skip = true;
                break;
            }
        }
        if (is_skip) continue;

        for (skip_filler) |filler| {
            if (eqlIgnoreCase(word, filler)) {
                is_skip = true;
                break;
            }
        }
        if (is_skip) continue;

        return word;
    }
    return null;
}

// ============================================================
// Tests
// ============================================================

test "containsIgnoreCase: exact match" {
    try std.testing.expect(containsIgnoreCase("REWE", "REWE"));
}

test "containsIgnoreCase: case mismatch" {
    try std.testing.expect(containsIgnoreCase("REWE Supermarkt", "rewe"));
}

test "containsIgnoreCase: needle uppercase, haystack lowercase" {
    try std.testing.expect(containsIgnoreCase("rewe supermarkt", "REWE"));
}

test "containsIgnoreCase: not found" {
    try std.testing.expect(!containsIgnoreCase("REWE Supermarkt", "ALDI"));
}

test "containsIgnoreCase: empty needle" {
    try std.testing.expect(containsIgnoreCase("hello", ""));
}

test "containsIgnoreCase: needle longer than haystack" {
    try std.testing.expect(!containsIgnoreCase("hi", "hello world"));
}

test "containsIgnoreCase: substring in middle" {
    try std.testing.expect(containsIgnoreCase("Lastschrift REWE 1234", "rewe"));
}

test "containsIgnoreCase: both empty" {
    try std.testing.expect(containsIgnoreCase("", ""));
}

test "extractKeyword: strips LASTSCHRIFT prefix" {
    const kw = extractKeyword("LASTSCHRIFT REWE MARKT BERLIN");
    try std.testing.expectEqualStrings("REWE", kw.?);
}

test "extractKeyword: strips KARTENZAHLUNG prefix" {
    const kw = extractKeyword("KARTENZAHLUNG AMAZON.DE");
    try std.testing.expectEqualStrings("AMAZON.DE", kw.?);
}

test "extractKeyword: skips numbers and short words" {
    const kw = extractKeyword("LASTSCHRIFT 12345 AN SPOTIFY AB");
    try std.testing.expectEqualStrings("SPOTIFY", kw.?);
}

test "extractKeyword: strips GMBH filler" {
    // word "GMBH" skipped, returns merchant before it
    const kw = extractKeyword("SEPA SOMEMERCHANT GMBH BERLIN");
    try std.testing.expectEqualStrings("SOMEMERCHANT", kw.?);
}

test "extractKeyword: PayPal separator" {
    const kw = extractKeyword("PAYPAL *NETFLIX");
    try std.testing.expectEqualStrings("NETFLIX", kw.?);
}

test "extractKeyword: returns null for empty" {
    try std.testing.expect(extractKeyword("") == null);
}

test "extractKeyword: returns null for only prefixes" {
    try std.testing.expect(extractKeyword("LASTSCHRIFT 123") == null);
}
