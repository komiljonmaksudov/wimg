const std = @import("std");
const types = @import("types.zig");
const c = @import("sqlite_c.zig");
const booking = @import("booking.zig");

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
        // A rule on a booking word ("BELASTUNG") would hit every direct debit.
        if (isGenericWord(pat_ptr[0..pat_len])) continue;

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
/// Words that never name a shop: booking types, SEPA fields, legal forms,
/// filler. Learned from them, a rule hits every booking of that kind (a learned
/// "BELASTUNG" put 1,899 direct debits into one category). Banks send "Ü" in
/// Latin-1, so a word is also compared without its leading non-ASCII bytes.
pub fn isGenericWord(word_raw: []const u8) bool {
    const exact = [_][]const u8{
        "LASTSCHRIFT",      "KARTENZAHLUNG", "SEPA",
        "ÜBERWEISUNG",
        "UEBERWEISUNG",     "BERWEISUNG",    "GUTSCHRIFT",
        "VISA",             "MASTERCARD",    "ABRECHNUNG",
        "DAUERAUFTRAG",     "EINZAHLUNG",    "AUSZAHLUNG",
        "BARGELD",          "FOLGENR",       "VERRECHNUNG",
        "BASISLASTSCHRIFT", "ECHTZEIT",      "PAYPAL",
        "BELASTUNG",
        "ÜBERTRAG",
        "UEBERTRAG",        "BERTRAG",
        "KARTENVERFÜGUNG",
        "KARTENVERFUEGUNG", "GELDAUTOMAT",   "ENTGELT",
        "ZINSEN",           "EREF",          "MREF",
        "CRED",             "SVWZ",          "ABWA",
        "ABWE",             "IBAN",          "BIC",
        "KTO",              "KD",            "KDNR",
        "RECHNUNG",         "DEBITKARTE",    "KREDITKARTE",
        "GMBH",             "UG",            "AG",
        "KG",               "OHG",           "GBR",
        "INC",              "LTD",           "LLC",
        "SAGT",             "DANKE",         "VIELEN",
        "DANK",             "NR",            "REF",
        "END",              "KARTE",         "ONLINE",
    };
    const word = std.mem.trim(u8, word_raw, " .,:;-/*\"'");
    var ascii_start: usize = 0;
    while (ascii_start < word.len and word[ascii_start] >= 0x80) : (ascii_start += 1) {}
    const tail = word[ascii_start..];
    for (exact) |w| {
        if (eqlIgnoreCase(word, w) or (ascii_start > 0 and eqlIgnoreCase(tail, w))) return true;
    }
    // Cut or re-encoded forms: "KARTENVERF\xDCGUNG", "KARTENVERF..."
    if (std.ascii.startsWithIgnoreCase(word, "KARTENVERF")) return true;
    if (word.len < 3) return true;
    return false;
}

/// The merchant word to learn a rule from: the first word of the row's title
/// (booking type and card text already gone, see booking.zig) that isn't
/// generic and doesn't start with a digit.
pub fn extractKeyword(desc: []const u8) ?[]const u8 {
    const title = booking.displayTitle(desc);
    var i: usize = 0;
    while (i < title.len) {
        while (i < title.len and (title[i] == ' ' or title[i] == '/' or title[i] == '*' or title[i] == '-' or title[i] == ',')) : (i += 1) {}
        if (i >= title.len) break;
        const start = i;
        while (i < title.len and title[i] != ' ' and title[i] != '/' and title[i] != '*' and title[i] != ',') : (i += 1) {}
        const word = title[start..i];
        if (word.len < 3) continue;
        if (word[0] >= '0' and word[0] <= '9') continue;
        if (isGenericWord(word)) continue;
        return word;
    }
    return null;
}

test "extractKeyword skips booking types and card text" {
    try std.testing.expectEqualStrings("MUSTERSTREAM", extractKeyword("LASTSCHRIFT / BELASTUNG MUSTERSTREAM ABO").?);
    try std.testing.expectEqualStrings("Musterladen", extractKeyword("KARTENVERFÜGUNG Musterladen, Musterstadt DE Karte Nr. 1234").?);
    try std.testing.expectEqualStrings("Musterladen", extractKeyword("Musterladen, Musterstadt  D E Karte Nr. 1234 56XX XXXX 7890 Kartenzahlung").?);
    try std.testing.expectEqualStrings("MUSTERMANN", extractKeyword("\xDCBERTRAG / \xDCBERWEISUNG MUSTERMANN GMBH").?);
    try std.testing.expect(extractKeyword("LASTSCHRIFT / BELASTUNG") == null);
}

test "isGenericWord: booking words, Latin-1 forms, real shops" {
    try std.testing.expect(isGenericWord("BELASTUNG"));
    try std.testing.expect(isGenericWord("KARTENVERFÜGUNG"));
    try std.testing.expect(isGenericWord("KARTENVERF\xDCGUNG"));
    try std.testing.expect(isGenericWord("\xDCBERWEISUNG"));
    try std.testing.expect(!isGenericWord("ALDI"));
    try std.testing.expect(!isGenericWord("Netflix"));
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
