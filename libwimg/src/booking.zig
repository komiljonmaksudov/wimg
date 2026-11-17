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

/// The description without its booking type, or the description itself.
pub fn stripPrefix(text: []const u8) []const u8 {
    return if (match(text)) |m| m.rest else text;
}

/// Row title: the text after the booking type, trimmed. Never empty.
pub fn displayTitle(text: []const u8) []const u8 {
    const base = if (match(text)) |m| m.rest else std.mem.trim(u8, text, " ");
    if (cardMerchant(base)) |name| return name;
    return if (base.len == 0) text else base;
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
