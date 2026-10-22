const std = @import("std");

pub const Category = enum(u8) {
    uncategorized = 0,
    groceries = 1,
    dining = 2,
    transport = 3,
    housing = 4,
    utilities = 5,
    entertainment = 6,
    shopping = 7,
    health = 8,
    insurance = 9,
    income = 10,
    transfer = 11,
    cash = 12,
    subscriptions = 13,
    travel = 14,
    education = 15,
    other = 255,

    pub fn name(self: Category) []const u8 {
        return switch (self) {
            .uncategorized => "Uncategorized",
            .groceries => "Groceries",
            .dining => "Dining",
            .transport => "Transport",
            .housing => "Housing",
            .utilities => "Utilities",
            .entertainment => "Entertainment",
            .shopping => "Shopping",
            .health => "Health",
            .insurance => "Insurance",
            .income => "Income",
            .transfer => "Transfer",
            .cash => "Cash",
            .subscriptions => "Subscriptions",
            .travel => "Travel",
            .education => "Education",
            .other => "Other",
        };
    }

    pub fn germanName(self: Category) []const u8 {
        return switch (self) {
            .uncategorized => "Unkategorisiert",
            .groceries => "Lebensmittel",
            .dining => "Essen gehen",
            .transport => "Transport",
            .housing => "Wohnen",
            .utilities => "Nebenkosten",
            .entertainment => "Unterhaltung",
            .shopping => "Shopping",
            .health => "Gesundheit",
            .insurance => "Versicherung",
            .income => "Einkommen",
            .transfer => "Umbuchung",
            .cash => "Bargeld",
            .subscriptions => "Abonnements",
            .travel => "Reisen",
            .education => "Bildung",
            .other => "Sonstiges",
        };
    }

    pub fn color(self: Category) []const u8 {
        return switch (self) {
            .uncategorized => "#d4d4d4",
            .groceries => "#525252",
            .dining => "#737373",
            .transport => "#6b7280",
            .housing => "#57534e",
            .utilities => "#78716c",
            .entertainment => "#9ca3af",
            .shopping => "#a3a3a3",
            .health => "#64748b",
            .insurance => "#94a3b8",
            .income => "#22c55e",
            .transfer => "#b8b8b8",
            .cash => "#a1a1aa",
            .subscriptions => "#71717a",
            .travel => "#8b8b8b",
            .education => "#858585",
            .other => "#d4d4d4",
        };
    }

    pub fn icon(self: Category) []const u8 {
        return switch (self) {
            .uncategorized => "?",
            .groceries => "\xf0\x9f\x9b\x92", // 🛒
            .dining => "\xf0\x9f\x8d\xbd\xef\xb8\x8f", // 🍽️
            .transport => "\xf0\x9f\x9a\x86", // 🚆
            .housing => "\xf0\x9f\x8f\xa0", // 🏠
            .utilities => "\xe2\x9a\xa1", // ⚡
            .entertainment => "\xf0\x9f\x8e\xac", // 🎬
            .shopping => "\xf0\x9f\x9b\x8d\xef\xb8\x8f", // 🛍️
            .health => "\xf0\x9f\x92\x8a", // 💊
            .insurance => "\xf0\x9f\x9b\xa1\xef\xb8\x8f", // 🛡️
            .income => "\xf0\x9f\x92\xb0", // 💰
            .transfer => "\xf0\x9f\x94\x84", // 🔄
            .cash => "\xf0\x9f\x92\xb5", // 💵
            .subscriptions => "\xf0\x9f\x93\xb1", // 📱
            .travel => "\xe2\x9c\x88\xef\xb8\x8f", // ✈️
            .education => "\xf0\x9f\x8e\x93", // 🎓
            .other => "\xf0\x9f\x93\xa6", // 📦
        };
    }

    pub fn fromInt(val: u8) Category {
        return std.enums.fromInt(Category, val) orelse .uncategorized;
    }
};

pub const Date = struct {
    year: u16,
    month: u8,
    day: u8,

    pub fn order(self: Date) u32 {
        return @as(u32, self.year) * 10000 + @as(u32, self.month) * 100 + @as(u32, self.day);
    }

    pub fn eql(a: Date, b: Date) bool {
        return a.year == b.year and a.month == b.month and a.day == b.day;
    }
};

pub const Transaction = struct {
    id: [32]u8, // hex-encoded hash
    date: Date,
    description: [256]u8,
    description_len: u16,
    amount_cents: i64, // stored as cents to avoid float issues
    currency: [3]u8, // "EUR"
    category: Category,
    account: [64]u8,
    account_len: u8,

    pub fn descriptionSlice(self: *const Transaction) []const u8 {
        return self.description[0..self.description_len];
    }

    pub fn accountSlice(self: *const Transaction) []const u8 {
        return self.account[0..self.account_len];
    }

    pub fn amountFloat(self: *const Transaction) f64 {
        return @as(f64, @floatFromInt(self.amount_cents)) / 100.0;
    }
};

pub const ImportResult = struct {
    total_rows: u32,
    imported: u32,
    skipped_duplicates: u32,
    errors: u32,
    skipped_full: u32 = 0,
};

// ============================================================
// Tests
// ============================================================

test "Category.name returns correct English names" {
    try std.testing.expectEqualStrings("Groceries", Category.groceries.name());
    try std.testing.expectEqualStrings("Other", Category.other.name());
    try std.testing.expectEqualStrings("Uncategorized", Category.uncategorized.name());
    try std.testing.expectEqualStrings("Income", Category.income.name());
    try std.testing.expectEqualStrings("Transport", Category.transport.name());
}

test "Category.germanName returns correct German names" {
    try std.testing.expectEqualStrings("Lebensmittel", Category.groceries.germanName());
    try std.testing.expectEqualStrings("Sonstiges", Category.other.germanName());
    try std.testing.expectEqualStrings("Unkategorisiert", Category.uncategorized.germanName());
    try std.testing.expectEqualStrings("Einkommen", Category.income.germanName());
    try std.testing.expectEqualStrings("Wohnen", Category.housing.germanName());
}

test "Category.germanName all values non-empty" {
    const all = [_]Category{
        .uncategorized, .groceries,     .dining,        .transport,
        .housing,       .utilities,     .entertainment, .shopping,
        .health,        .insurance,     .income,        .transfer,
        .cash,          .subscriptions, .travel,        .education,
        .other,
    };
    for (all) |cat| {
        try std.testing.expect(cat.germanName().len > 0);
    }
}

test "Category.color starts with # and has length 7" {
    const all = [_]Category{
        .uncategorized, .groceries,     .dining,        .transport,
        .housing,       .utilities,     .entertainment, .shopping,
        .health,        .insurance,     .income,        .transfer,
        .cash,          .subscriptions, .travel,        .education,
        .other,
    };
    for (all) |cat| {
        const c = cat.color();
        try std.testing.expect(c.len == 7);
        try std.testing.expect(c[0] == '#');
    }
}

test "Category.color specific values" {
    try std.testing.expectEqualStrings("#525252", Category.groceries.color());
    try std.testing.expectEqualStrings("#22c55e", Category.income.color());
}

test "Category.icon uncategorized is ?" {
    try std.testing.expectEqualStrings("?", Category.uncategorized.icon());
}

test "Category.icon groceries is multi-byte UTF-8" {
    try std.testing.expect(Category.groceries.icon().len > 1);
}

test "Category.icon all values non-empty" {
    const all = [_]Category{
        .uncategorized, .groceries,     .dining,        .transport,
        .housing,       .utilities,     .entertainment, .shopping,
        .health,        .insurance,     .income,        .transfer,
        .cash,          .subscriptions, .travel,        .education,
        .other,
    };
    for (all) |cat| {
        try std.testing.expect(cat.icon().len > 0);
    }
}

test "Category.fromInt valid values" {
    try std.testing.expectEqual(Category.groceries, Category.fromInt(1));
    try std.testing.expectEqual(Category.other, Category.fromInt(255));
    try std.testing.expectEqual(Category.income, Category.fromInt(10));
    try std.testing.expectEqual(Category.uncategorized, Category.fromInt(0));
}

test "Category.fromInt invalid value falls back to uncategorized" {
    try std.testing.expectEqual(Category.uncategorized, Category.fromInt(99));
    try std.testing.expectEqual(Category.uncategorized, Category.fromInt(200));
    try std.testing.expectEqual(Category.uncategorized, Category.fromInt(17));
}

test "Date.order computes YYYYMMDD integer" {
    const d = Date{ .year = 2026, .month = 3, .day = 5 };
    try std.testing.expectEqual(@as(u32, 20260305), d.order());
}

test "Date.order with single-digit month/day" {
    const d = Date{ .year = 2026, .month = 1, .day = 1 };
    try std.testing.expectEqual(@as(u32, 20260101), d.order());
}

test "Date.eql same dates" {
    const a = Date{ .year = 2026, .month = 3, .day = 5 };
    const b = Date{ .year = 2026, .month = 3, .day = 5 };
    try std.testing.expect(a.eql(b));
}

test "Date.eql different dates" {
    const a = Date{ .year = 2026, .month = 3, .day = 5 };
    const b = Date{ .year = 2026, .month = 3, .day = 6 };
    try std.testing.expect(!a.eql(b));
}

test "Date.eql different year" {
    const a = Date{ .year = 2025, .month = 3, .day = 5 };
    const b = Date{ .year = 2026, .month = 3, .day = 5 };
    try std.testing.expect(!a.eql(b));
}

test "Transaction.descriptionSlice returns correct slice" {
    var txn: Transaction = undefined;
    const desc = "REWE Supermarkt";
    @memcpy(txn.description[0..desc.len], desc);
    txn.description_len = desc.len;
    try std.testing.expectEqualStrings("REWE Supermarkt", txn.descriptionSlice());
}

test "Transaction.accountSlice returns correct slice" {
    var txn: Transaction = undefined;
    const acct = "comdirect";
    @memcpy(txn.account[0..acct.len], acct);
    txn.account_len = acct.len;
    try std.testing.expectEqualStrings("comdirect", txn.accountSlice());
}

test "Transaction.amountFloat converts cents to float" {
    var txn: Transaction = undefined;
    txn.amount_cents = 12345;
    try std.testing.expectApproxEqAbs(@as(f64, 123.45), txn.amountFloat(), 0.001);
}

test "Transaction.amountFloat negative cents" {
    var txn: Transaction = undefined;
    txn.amount_cents = -4250;
    try std.testing.expectApproxEqAbs(@as(f64, -42.50), txn.amountFloat(), 0.001);
}

test "Transaction.amountFloat zero" {
    var txn: Transaction = undefined;
    txn.amount_cents = 0;
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), txn.amountFloat(), 0.001);
}

// --- Stress / edge case tests ---

test "Transaction: max-length description (256 chars)" {
    var txn: Transaction = undefined;
    const desc = &@as([256]u8, @splat('X'));
    @memcpy(txn.description[0..256], desc);
    txn.description_len = 256;
    try std.testing.expectEqual(@as(usize, 256), txn.descriptionSlice().len);
    try std.testing.expectEqualStrings(desc, txn.descriptionSlice());
}

test "Transaction: max-length account (64 chars)" {
    var txn: Transaction = undefined;
    const acct = &@as([64]u8, @splat('A'));
    @memcpy(txn.account[0..64], acct);
    txn.account_len = 64;
    try std.testing.expectEqual(@as(usize, 64), txn.accountSlice().len);
    try std.testing.expectEqualStrings(acct, txn.accountSlice());
}

test "Transaction: empty description" {
    var txn: Transaction = undefined;
    txn.description_len = 0;
    try std.testing.expectEqual(@as(usize, 0), txn.descriptionSlice().len);
}

test "Transaction: empty account" {
    var txn: Transaction = undefined;
    txn.account_len = 0;
    try std.testing.expectEqual(@as(usize, 0), txn.accountSlice().len);
}

test "Transaction.amountFloat large salary" {
    var txn: Transaction = undefined;
    txn.amount_cents = 350000; // 3500.00 EUR
    try std.testing.expectApproxEqAbs(@as(f64, 3500.0), txn.amountFloat(), 0.001);
}

test "Transaction.amountFloat very large amount" {
    var txn: Transaction = undefined;
    txn.amount_cents = 99999999; // 999,999.99 EUR
    try std.testing.expectApproxEqAbs(@as(f64, 999999.99), txn.amountFloat(), 0.01);
}

test "Transaction.amountFloat single cent" {
    var txn: Transaction = undefined;
    txn.amount_cents = 1;
    try std.testing.expectApproxEqAbs(@as(f64, 0.01), txn.amountFloat(), 0.001);
}

test "Date.order boundary: year 9999" {
    const d = Date{ .year = 9999, .month = 12, .day = 31 };
    try std.testing.expectEqual(@as(u32, 99991231), d.order());
}

test "Category.fromInt all valid enum values roundtrip" {
    const all = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 255 };
    for (all) |val| {
        const cat = Category.fromInt(val);
        try std.testing.expectEqual(val, @backingInt(cat));
    }
}
