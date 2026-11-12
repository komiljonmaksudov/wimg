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

/// The description without its booking type, or the description itself.
pub fn stripPrefix(text: []const u8) []const u8 {
    return if (match(text)) |m| m.rest else text;
}

/// Row title: the text after the booking type, trimmed. Never empty.
pub fn displayTitle(text: []const u8) []const u8 {
    if (match(text)) |m| return m.rest;
    const t = std.mem.trim(u8, text, " ");
    return if (t.len == 0) text else t;
}

/// Booking type label ("Lastschrift", "Karte", …), or "" when there is none
/// (CSV imports usually carry no booking type).
pub fn kind(text: []const u8) []const u8 {
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
