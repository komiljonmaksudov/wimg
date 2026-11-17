//! The import seam: every source (FinTS, statement files) hands its booked
//! transactions to `apply`, which skips what is already here, inserts the rest
//! and categorizes them by rule. Plus statement files: MT940 (.sta, .mt940,
//! .txt) and CAMT (.xml, camt.052/053), recognized by content.

const std = @import("std");
const types = @import("types.zig");
const db_mod = @import("db.zig");
const categories = @import("categories.zig");
const banks = @import("banks.zig");
const mt940 = @import("mt940.zig");
const camt = @import("camt.zig");

const Transaction = types.Transaction;
const Db = db_mod.Db;

/// How a booking counts as already here.
pub const TwinRule = enum {
    /// Same id (same date, text and amount): one source fetched again.
    same_id,
    /// Same account, day and amount, counted (two equal coffees on one day both
    /// stay): another format of the same bookings, whose texts and so ids differ
    /// (CAMT next to MT940 history, a statement file next to fetched bookings).
    day_and_amount,
};

pub const Applied = struct { imported: u32 = 0, duplicates: u32 = 0 };

/// Marks each booking whose twin is already in the database (`twin[i]`).
/// Counted before anything is inserted.
pub fn markTwins(db: *Db, txns: []const Transaction, twin: []bool) void {
    for (txns, 0..) |*t, i| {
        var same_before: i64 = 0;
        for (txns[0..i]) |*u| {
            if (u.date.year == t.date.year and u.date.month == t.date.month and u.date.day == t.date.day and u.amount_cents == t.amount_cents) same_before += 1;
        }
        const here = db.countSameBooking(t.accountSlice(), t.date.year, t.date.month, t.date.day, t.amount_cents);
        twin[i] = same_before < here;
    }
}

/// Inserts `txns` (booked only) and categorizes the new ones by rule. `scratch`
/// needs `txns.len` entries for `.day_and_amount`.
pub fn apply(db: *Db, txns: []Transaction, twins: TwinRule, scratch: []bool) Applied {
    var out = Applied{};
    const twin = scratch[0..if (twins == .day_and_amount) txns.len else 0];
    if (twins == .day_and_amount) markTwins(db, txns, twin);
    for (txns, 0..) |*txn, i| {
        if (twins == .day_and_amount and twin[i]) {
            out.duplicates += 1;
            continue;
        }
        const inserted = db.insertTransaction(txn) catch continue;
        if (!inserted) {
            out.duplicates += 1;
            continue;
        }
        out.imported += 1;
        if (txn.category == .uncategorized) {
            const matched = categories.matchRules(db.handle, txn.descriptionSlice());
            if (matched != .uncategorized) db.setCategoryById(&txn.id, matched) catch {};
        }
    }
    return out;
}

// ---------------------------------------------------------------------------
// Statement files
// ---------------------------------------------------------------------------

pub const Format = enum {
    mt940,
    camt,

    pub fn name(self: Format) []const u8 {
        return switch (self) {
            .mt940 => "mt940",
            .camt => "camt",
        };
    }
};

/// MT940 or CAMT, by content; null for anything else (a CSV, say).
pub fn detect(data: []const u8) ?Format {
    const head = data[0..@min(data.len, 4096)];
    if (std.mem.indexOf(u8, head, "<BkToCstmrStmt") != null or std.mem.indexOf(u8, head, "<BkToCstmrAcctRpt") != null or
        std.mem.indexOf(u8, data, "<BkToCstmrStmt") != null or std.mem.indexOf(u8, data, "<BkToCstmrAcctRpt") != null) return .camt;
    if (std.mem.indexOf(u8, data, ":61:") != null and
        (std.mem.indexOf(u8, data, ":25:") != null or std.mem.indexOf(u8, data, ":20:") != null)) return .mt940;
    return null;
}

/// The bank code (BLZ) of the statement's account: MT940 `:25:` as
/// "BLZ/Konto" or a German IBAN, CAMT the first German `<IBAN>`.
pub fn blzOf(data: []const u8, fmt: Format) ?[8]u8 {
    const field: []const u8 = switch (fmt) {
        .mt940 => blk: {
            const at = std.mem.indexOf(u8, data, ":25:") orelse return null;
            const rest = data[at + 4 ..];
            const end = std.mem.indexOfAny(u8, rest, "\r\n@") orelse rest.len;
            break :blk std.mem.trim(u8, rest[0..end], " ");
        },
        .camt => blk: {
            const at = std.mem.indexOf(u8, data, "<IBAN>") orelse return null;
            const rest = data[at + 6 ..];
            const end = std.mem.indexOfScalar(u8, rest, '<') orelse return null;
            break :blk std.mem.trim(u8, rest[0..end], " ");
        },
    };
    var blz: [8]u8 = undefined;
    // German IBAN: DE + 2 check digits + 8-digit BLZ + 10-digit account.
    if (field.len >= 22 and std.ascii.startsWithIgnoreCase(field, "DE") and allDigits(field[4..12])) {
        @memcpy(&blz, field[4..12]);
        return blz;
    }
    // "20041133/1234567890"
    if (field.len >= 9 and field[8] == '/' and allDigits(field[0..8])) {
        @memcpy(&blz, field[0..8]);
        return blz;
    }
    return null;
}

fn allDigits(s: []const u8) bool {
    for (s) |ch| if (!std.ascii.isDigit(ch)) return false;
    return s.len > 0;
}

/// The account a statement belongs to: the bank's name, the same id a FinTS
/// connection to that bank uses, so a file and fetched bookings meet (and
/// twins are found). "Kontoauszug" when the bank isn't known.
pub fn accountFor(data: []const u8, fmt: Format) []const u8 {
    const blz = blzOf(data, fmt) orelse return "Kontoauszug";
    const bank = banks.findByBlz(&blz) orelse return "Kontoauszug";
    return bank.nameSlice();
}

pub const Parsed = struct {
    count: u32 = 0,
    errors: u32 = 0,
    balance_cents: i64 = 0,
    balance_date: u32 = 0, // YYYYMMDD, 0 = none
};

/// What the MT940 parser takes at once (it normalizes into a 64 KB buffer).
const mt940_chunk = 60_000;

/// Booked transactions of a statement file. MT940 files of a year exceed the
/// parser's buffer: they're read in pieces cut before a statement (`:20:`) or,
/// inside a long one, before a booking (`:61:`). CAMT is dated by value date,
/// like MT940, so both meet fetched history on the same days.
pub fn parseStatement(data: []const u8, fmt: Format, account: []const u8, out: []Transaction) Parsed {
    var p = Parsed{};
    switch (fmt) {
        .camt => {
            const r = camt.parseCamtValueDated(data, account, out);
            p = .{ .count = r.count, .errors = r.errors, .balance_cents = r.closing_balance, .balance_date = r.closing_balance_date };
        },
        .mt940 => {
            var start: usize = 0;
            while (start < data.len and p.count < out.len) {
                const end = cutMt940(data, start);
                const r = mt940.parseMt940(data[start..end], account, out[p.count..]);
                p.count += r.count;
                p.errors += r.errors;
                if (r.closing_balance_date >= p.balance_date and r.closing_balance_date > 0) {
                    p.balance_date = r.closing_balance_date;
                    p.balance_cents = r.closing_balance;
                }
                start = end;
            }
        },
    }
    return p;
}

/// End of the MT940 piece starting at `start`: the whole rest when it fits,
/// else the last line start with `:20:` (or `:61:`) before the limit.
fn cutMt940(data: []const u8, start: usize) usize {
    if (data.len - start <= mt940_chunk) return data.len;
    const limit = start + mt940_chunk;
    var best20: usize = 0;
    var best61: usize = 0;
    var i = start + 1;
    while (i < limit) : (i += 1) {
        if (data[i - 1] != '\n' and data[i - 1] != '\r') continue;
        if (std.mem.startsWith(u8, data[i..], ":20:")) best20 = i;
        if (std.mem.startsWith(u8, data[i..], ":61:")) best61 = i;
    }
    if (best20 > start) return best20;
    if (best61 > start) return best61;
    return limit; // one line longer than the limit: cut anyway
}

test "detect: MT940, CAMT and anything else" {
    try std.testing.expectEqual(Format.mt940, detect(":20:STARTUMS\r\n:25:20041133/1234567890\r\n:61:2611140201DR12,50NMSC\r\n").?);
    try std.testing.expectEqual(Format.camt, detect("<?xml version=\"1.0\"?><Document><BkToCstmrStmt><Stmt></Stmt></BkToCstmrStmt></Document>").?);
    try std.testing.expect(detect("\"Buchungstag\";\"Umsatz\"\n\"01.11.2026\";\"-1,00\"\n") == null);
}

test "blzOf: MT940 BLZ/Konto, MT940 IBAN, CAMT IBAN" {
    try std.testing.expectEqualStrings("20041133", &blzOf(":20:X\r\n:25:20041133/1234567890\r\n:61:x", .mt940).?);
    try std.testing.expectEqualStrings("37040044", &blzOf(":20:X\r\n:25:DE89370400440532013000\r\n", .mt940).?);
    try std.testing.expectEqualStrings("37040044", &blzOf("<Acct><Id><IBAN>DE89370400440532013000</IBAN></Id></Acct>", .camt).?);
    try std.testing.expect(blzOf(":25:COBADEFFXXX/12\r\n", .mt940) == null);
}

test "cutMt940 cuts before a statement" {
    var big: [130_000]u8 = undefined;
    var n: usize = 0;
    var k: usize = 0;
    while (n + 40 < big.len) : (k += 1) {
        const s = if (k % 50 == 0) ":20:STARTUMS\r\n" else ":61:2611140201DR1,00NMSC\r\n";
        @memcpy(big[n .. n + s.len], s);
        n += s.len;
    }
    const data = big[0..n];
    const end = cutMt940(data, 0);
    try std.testing.expect(end <= mt940_chunk);
    try std.testing.expect(std.mem.startsWith(u8, data[end..], ":20:"));
}
