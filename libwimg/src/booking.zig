//! Booking types that FinTS banks put in front of the description
//! ("LASTSCHRIFT / BELASTUNG REWE …"). Shared by recurring detection (to find
//! the merchant) and the transaction JSON (`title` + `kind` for list rows), so
//! every platform shows the same row title.

const std = @import("std");

const Prefix = struct {
    /// Matched by its ASCII part so UTF-8 and Latin-1 umlauts both work
    /// ("ÜBERWEISUNG" arrives as either).
    text: []const u8,
    /// Short German label for the booking type; translated by the platforms.
    kind: []const u8,
};

const prefixes = [_]Prefix{
    .{ .text = "LASTSCHRIFT / BELASTUNG ", .kind = "Lastschrift" },
    .{ .text = "BERWEISUNG - ECHTZEIT ", .kind = "Echtzeitüberweisung" },
    .{ .text = "BERWEISUNG ", .kind = "Überweisung" },
    .{ .text = "KARTENVERF", .kind = "Karte" },
    .{ .text = "DAUERAUFTRAG ", .kind = "Dauerauftrag" },
    .{ .text = "GUTSCHRIFT ", .kind = "Gutschrift" },
    .{ .text = "AUSZAHLUNG ", .kind = "Auszahlung" },
};

const Match = struct { rest: []const u8, kind: []const u8 };

fn match(text: []const u8) ?Match {
    for (prefixes) |p| {
        const idx = std.mem.indexOf(u8, text, p.text) orelse continue;
        if (idx > 14) continue; // only at the very start ("ÜBERTRAG / " precedes "BERWEISUNG")
        var rest = text[idx + p.text.len ..];
        // Prefixes given without a trailing space end mid-word: skip to the next word.
        if (p.text[p.text.len - 1] != ' ') {
            const sp = std.mem.indexOfScalar(u8, rest, ' ') orelse return null;
            rest = rest[sp + 1 ..];
        }
        rest = std.mem.trim(u8, rest, " ");
        if (rest.len == 0) return null;
        return .{ .rest = rest, .kind = p.kind };
    }
    return null;
}

/// Card payments (Comdirect and others): "MERCHANT, City  CC Karte Nr. 4871 78XX
/// … Kartenzahlung … Visa-Debitkarte 2026-11-13 00:00:00 Ref. …", in any case and,
/// once booked, cut into 27-character pieces ("WUPP ERTAL"). The merchant is what
/// comes before the first comma; without a comma, everything before "Karte Nr.".
fn cardMerchant(text: []const u8) ?[]const u8 {
    const k = std.ascii.findIgnoreCase(text, "karte nr.") orelse return null;
    const head = text[0..k];
    const end = std.mem.indexOfScalar(u8, head, ',') orelse head.len;
    const name = std.mem.trim(u8, head[0..end], " ");
    return if (name.len == 0) null else name;
}

/// Pending card payments (CAMT, Comdirect) end with the payment time:
/// "EDK*EDEKA Musterladen Musterstadt DEU    20 26-11-16T19:08:03" (the bank
/// may break the year with a space). Returns the text without it.
fn stripTrailingTime(text: []const u8) []const u8 {
    const t = std.mem.trimEnd(u8, text, " ");
    // "HH:MM:SS" at the very end, after a 'T'.
    if (t.len < 9) return text;
    const time = t[t.len - 8 ..];
    for (time, 0..) |ch, i| {
        const want_colon = i == 2 or i == 5;
        if (want_colon != (ch == ':') or (!want_colon and !std.ascii.isDigit(ch))) return text;
    }
    if (t[t.len - 9] != 'T') return text;
    // Then the date: up to 8 digits, '-' and spaces, nothing else (the
    // merchant's own letters stay, even a "T" ending a word).
    var i = t.len - 9;
    var digits: usize = 0;
    while (i > 0) {
        const ch = t[i - 1];
        if (std.ascii.isDigit(ch)) {
            if (digits == 8) break;
            digits += 1;
        } else if (ch != '-' and ch != ' ') break;
        i -= 1;
    }
    if (digits < 6) return text;
    const rest = std.mem.trimEnd(u8, t[0..i], " ");
    return if (rest.len == 0) text else rest;
}

/// The description without its booking type, or the description itself.
pub fn stripPrefix(text: []const u8) []const u8 {
    return if (match(text)) |m| m.rest else text;
}

/// Row title: the text after the booking type, trimmed. Never empty.
pub fn displayTitle(text: []const u8) []const u8 {
    const base = if (match(text)) |m| m.rest else std.mem.trim(u8, text, " ");
    if (cardMerchant(base)) |name| return name;
    if (base.len == 0) return text;
    return stripTrailingTime(base);
}

/// Booking type label ("Lastschrift", "Karte", …), or "" when there is none
/// (CSV imports usually carry no booking type).
pub fn kind(text: []const u8) []const u8 {
    // Booked card payments arrive as "Lastschrift": call them what they are.
    if (cardMerchant(text) != null) return "Karte";
    return if (match(text)) |m| m.kind else "";
}

test "displayTitle strips the booking type" {
    try std.testing.expectEqualStrings("REWE MARKT", displayTitle("LASTSCHRIFT / BELASTUNG REWE MARKT"));
    try std.testing.expectEqualStrings("BAECKEREI KAMPS, SOLINGEN DE", displayTitle("KARTENVERFÜGUNG BAECKEREI KAMPS, SOLINGEN DE"));
    try std.testing.expectEqualStrings("MUSTER GMBH GEHALT", displayTitle("ÜBERTRAG / ÜBERWEISUNG MUSTER GMBH GEHALT"));
    // Latin-1 umlaut (0xDC) still matches on the ASCII part
    try std.testing.expectEqualStrings("MUSTER GMBH", displayTitle("\xDCBERTRAG / \xDCBERWEISUNG MUSTER GMBH"));
}

test "displayTitle keeps text without booking type" {
    try std.testing.expectEqualStrings("REWE Markt Köln", displayTitle("REWE Markt Köln"));
    try std.testing.expectEqualStrings("Spotify", displayTitle("  Spotify "));
    // Only the type and nothing after it: show the type rather than nothing
    try std.testing.expectEqualStrings("LASTSCHRIFT / BELASTUNG", displayTitle("LASTSCHRIFT / BELASTUNG "));
    // A booking-type word deep inside the text is not a prefix
    try std.testing.expectEqualStrings("MIETE FUER NOVEMBER GUTSCHRIFT FOLGT", displayTitle("MIETE FUER NOVEMBER GUTSCHRIFT FOLGT"));
}

test "kind names the booking type" {
    try std.testing.expectEqualStrings("Lastschrift", kind("LASTSCHRIFT / BELASTUNG REWE"));
    try std.testing.expectEqualStrings("Karte", kind("KARTENVERFÜGUNG DM DROGERIE"));
    try std.testing.expectEqualStrings("Echtzeitüberweisung", kind("ÜBERTRAG / ÜBERWEISUNG - ECHTZEIT MAX"));
    try std.testing.expectEqualStrings("Überweisung", kind("ÜBERTRAG / ÜBERWEISUNG MAX"));
    try std.testing.expectEqualStrings("", kind("REWE Markt Köln"));
}

test "card payments show the merchant" {
    // Invented merchants and card numbers, shaped like Comdirect's texts.
    try std.testing.expectEqualStrings("Musterladen Discount", displayTitle("Musterladen Discount, Musterstadt  D E Karte Nr. 1234 56XX XXXX 7890 Kartenzahlung comdirect Visa-Debitkarte 2026-11-14 00:00:00"));
    try std.testing.expectEqualStrings("BEISPIEL PAY", displayTitle("BEISPIEL PAY, Dublin  IE Karte Nr. 1234 56XX XXXX 7890 Kartenzahlung comdirect Visa-Debitkarte 2026-11-13 00:00:00"));
    // Booked: upper case, cut into pieces, a reference at the end, behind a booking type.
    try std.testing.expectEqualStrings("MUSTERLADEN DISCOUNT", displayTitle("LASTSCHRIFT / BELASTUNG MUSTERLADEN DISCOUNT, MUST ERSTADT  D E KARTE NR. 1234 56XX XXXX 78 90 KARTENZAHLUNG COMDIRECT VISA-DEBITKARTE 2026-11-11 00:00:00 Ref. 3T2C29KP0Y1ALB6J/47986"));
    try std.testing.expectEqualStrings("BEISPIEL* ABO", displayTitle("BEISPIEL* ABO, DUBL IN 4  IE KARTE NR. 1234 56XX XXXX 78 90 KARTENZAHLUNG"));
    // No comma: everything before "Karte Nr."
    try std.testing.expectEqualStrings("CAFE AM ECK", displayTitle("CAFE AM ECK Karte Nr. 1234 56XX XXXX 7890"));
    try std.testing.expectEqualStrings("Karte", kind("LASTSCHRIFT / BELASTUNG MUSTERLADEN, MUSTERSTADT DE KARTE NR. 1234"));
    // Text that only mentions a card later keeps its title.
    try std.testing.expectEqualStrings("Karte Nr. 1234 gesperrt", displayTitle("Karte Nr. 1234 gesperrt"));
}

test "pending card payments lose the payment time" {
    try std.testing.expectEqualStrings("EDK*EDEKA Musterladen Musterstadt DEU", displayTitle("EDK*EDEKA Musterladen Musterstadt DEU    20 26-11-16T19:08:03"));
    try std.testing.expectEqualStrings("Musterladen Discount Musterstadt DE", displayTitle("Musterladen Discount Musterstadt DE 2026-11-14T15:24:15"));
    // A name ending in T keeps it.
    try std.testing.expectEqualStrings("SUPERMARKT", displayTitle("SUPERMARKT 2026-11-14T15:24:15"));
    // A time without a date, or numbers that only look alike, stay.
    try std.testing.expectEqualStrings("Kurs um T10:00:00", displayTitle("Kurs um T10:00:00"));
    try std.testing.expectEqualStrings("Rechnung 2026-11-14", displayTitle("Rechnung 2026-11-14"));
}
