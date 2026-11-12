const std = @import("std");
const booking = @import("booking.zig");
const db_mod = @import("db.zig");
const c = @import("sqlite_c.zig");

const Db = db_mod.Db;
const DbError = db_mod.DbError;

// --- Merchant normalization ---

/// Known merchant mappings (uppercase pattern → display name)
const KnownMerchant = struct {
    pattern: []const u8,
    name: []const u8,
};

const known_merchants = [_]KnownMerchant{
    .{ .pattern = "NETFLIX", .name = "Netflix" },
    .{ .pattern = "SPOTIFY", .name = "Spotify" },
    .{ .pattern = "AMAZON PRIME", .name = "Amazon Prime" },
    .{ .pattern = "AMAZON", .name = "Amazon" },
    .{ .pattern = "APPLE.COM", .name = "Apple" },
    .{ .pattern = "GOOGLE", .name = "Google" },
    .{ .pattern = "DISNEY", .name = "Disney+" },
    .{ .pattern = "REWE", .name = "REWE" },
    .{ .pattern = "EDEKA", .name = "EDEKA" },
    .{ .pattern = "LIDL", .name = "Lidl" },
    .{ .pattern = "ALDI", .name = "Aldi" },
    .{ .pattern = "DM DROGERIE", .name = "dm" },
    .{ .pattern = "PAYPAL", .name = "PayPal" },
    .{ .pattern = "MIETE", .name = "Miete" },
    .{ .pattern = "STADTWERKE", .name = "Stadtwerke" },
    .{ .pattern = "VODAFONE", .name = "Vodafone" },
    .{ .pattern = "TELEKOM", .name = "Telekom" },
    .{ .pattern = "O2", .name = "o2" },
    .{ .pattern = "KLARNA", .name = "Klarna" },
    .{ .pattern = "CHECK24", .name = "Check24" },
    .{ .pattern = "GEZ", .name = "Rundfunkbeitrag" },
    .{ .pattern = "RUNDFUNK", .name = "Rundfunkbeitrag" },
    .{ .pattern = "BEITRAGSSERVICE", .name = "Rundfunkbeitrag" },
    .{ .pattern = "YOUTUBE", .name = "YouTube" },
    .{ .pattern = "CHATGPT", .name = "ChatGPT" },
    .{ .pattern = "OPENAI", .name = "OpenAI" },
    .{ .pattern = "GITHUB", .name = "GitHub" },
    .{ .pattern = "HETZNER", .name = "Hetzner" },
    .{ .pattern = "IONOS", .name = "IONOS" },
    .{ .pattern = "CLEVER FIT", .name = "clever fit" },
    .{ .pattern = "MCFIT", .name = "McFit" },
    .{ .pattern = "FIT STAR", .name = "FitStar" },
    .{ .pattern = "FITX", .name = "FitX" },
};

/// Suffixes to strip from merchant names
const strip_suffixes = [_][]const u8{
    ".COM",         ".DE",      ".SE",     ".NL",   " GMBH", " SAGT DANKE", " AG", " SE",
    " DEUTSCHLAND", " GERMANY", " EUROPE", " SARL", " LTD",  " INC",
};

/// Normalize a transaction description to a merchant name.
/// Returns the number of bytes written into out_buf.
pub fn normalizeMerchant(desc: []const u8, out_buf: []u8) ?usize {
    if (desc.len == 0) return null;

    // Uppercase into temp buffer
    var upper: [512]u8 = undefined;
    const upper_len = @min(desc.len, upper.len);
    for (desc[0..upper_len], 0..) |ch, i| {
        upper[i] = asciiUpper(ch);
    }
    var working: []const u8 = upper[0..upper_len];

    // Check known merchants first
    for (known_merchants) |km| {
        if (containsSubstring(working, km.pattern)) {
            if (km.name.len > out_buf.len) return null;
            @memcpy(out_buf[0..km.name.len], km.name);
            return km.name.len;
        }
    }

    // Strip suffixes
    for (strip_suffixes) |suffix| {
        if (working.len > suffix.len) {
            const tail = working[working.len - suffix.len ..];
            if (std.mem.eql(u8, tail, suffix)) {
                working = working[0 .. working.len - suffix.len];
            }
        }
    }

    // FinTS statements (Comdirect) put the booking type in front of every
    // description: "LASTSCHRIFT / BELASTUNG <payee text>", "ÜBERTRAG / ÜBERWEISUNG
    // <purpose>". Without stripping it every direct debit lands in one bucket
    // called "LASTSCHRIFT" and nothing looks recurring.
    working = booking.stripPrefix(working);

    // The SEPA reference tail is different on every booking.
    if (std.mem.indexOf(u8, working, "END-TO-END-REF")) |idx| {
        if (idx > 0) working = working[0..idx];
    }

    // Take first meaningful token (skip leading numbers/dates)
    var start: usize = 0;
    // Skip date-like prefixes (e.g. "2026-03-01 " or "01.03.2026 ")
    if (working.len > 10) {
        var digits_or_sep: usize = 0;
        for (working) |ch| {
            if ((ch >= '0' and ch <= '9') or ch == '-' or ch == '.' or ch == '/') {
                digits_or_sep += 1;
            } else break;
        }
        if (digits_or_sep >= 6 and digits_or_sep < working.len and working[digits_or_sep] == ' ') {
            start = digits_or_sep;
        }
    }

    // Keep up to three tokens, stopping at a separator. Long digit runs (invoice
    // or booking numbers) change every month, so they are not part of the key.
    var out_len: usize = 0;
    var kept: usize = 0;
    var pos = start;
    while (pos < working.len and kept < 3) {
        while (pos < working.len and working[pos] == ' ') : (pos += 1) {}
        const tok_start = pos;
        var hit_separator = false;
        while (pos < working.len and working[pos] != ' ') : (pos += 1) {
            if (working[pos] == '/' or working[pos] == '\\' or working[pos] == ',' or working[pos] == ';') {
                hit_separator = true;
                break;
            }
        }
        const tok = working[tok_start..pos];
        if (tok.len > 0 and !isLongNumber(tok)) {
            const need = tok.len + @as(usize, if (out_len > 0) 1 else 0);
            if (out_len + need > out_buf.len) return null;
            if (out_len > 0) {
                out_buf[out_len] = ' ';
                out_len += 1;
            }
            @memcpy(out_buf[out_len .. out_len + tok.len], tok);
            out_len += tok.len;
            kept += 1;
        }
        if (hit_separator) break;
    }

    if (out_len == 0) return null;
    return out_len;
}

fn isLongNumber(tok: []const u8) bool {
    if (tok.len < 8) return false;
    for (tok) |ch| {
        if (ch < '0' or ch > '9') return false;
    }
    return true;
}

fn asciiUpper(ch: u8) u8 {
    return if (ch >= 'a' and ch <= 'z') ch - 32 else ch;
}

fn containsSubstring(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    const limit = haystack.len - needle.len + 1;
    for (0..limit) |i| {
        if (std.mem.eql(u8, haystack[i .. i + needle.len], needle)) return true;
    }
    return false;
}

// --- Date arithmetic ---

const DateTriple = struct {
    year: i32,
    month: i32,
    day: i32,
};

fn daysBetween(a: DateTriple, b: DateTriple) i32 {
    return julianDay(b) - julianDay(a);
}

/// Days since 1970-01-01 (Howard Hinnant's days_from_civil). Only differences
/// and round trips through `fromRataDie` matter; the epoch is arbitrary.
fn julianDay(d: DateTriple) i32 {
    const y: i32 = if (d.month <= 2) d.year - 1 else d.year;
    const era: i32 = @divFloor(y, 400);
    const yoe: i32 = y - era * 400; // [0, 399]
    const mp: i32 = @mod(d.month + 9, 12); // March = 0
    const doy: i32 = @divFloor(153 * mp + 2, 5) + d.day - 1; // [0, 365]
    const doe: i32 = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    return era * 146097 + doe - 719468;
}

fn addDays(d: DateTriple, days: i32) DateTriple {
    return fromRataDie(julianDay(d) + days);
}

/// Exact inverse of `julianDay` (civil_from_days). The previous version mixed
/// two different day-count algorithms, so addDays() landed in the wrong month
/// and year (3 Nov 2026 + 30 days came out as 1 Feb 2026).
fn fromRataDie(days: i32) DateTriple {
    const z: i32 = days + 719468;
    const era: i32 = @divFloor(z, 146097);
    const doe: i32 = z - era * 146097; // [0, 146096]
    const yoe: i32 = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
    const doy: i32 = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
    const mp: i32 = @divFloor(5 * doy + 2, 153);
    const day: i32 = doy - @divFloor(153 * mp + 2, 5) + 1;
    const month: i32 = if (mp < 10) mp + 3 else mp - 9;
    const year: i32 = yoe + era * 400 + @as(i32, if (month <= 2) 1 else 0);
    return .{ .year = year, .month = month, .day = day };
}

fn formatDateStr(buf: []u8, d: DateTriple) ?usize {
    if (buf.len < 10) return null;
    const y: u32 = @intCast(d.year);
    const m: u32 = @intCast(d.month);
    const da: u32 = @intCast(d.day);
    buf[0] = '0' + @as(u8, @intCast(y / 1000));
    buf[1] = '0' + @as(u8, @intCast((y / 100) % 10));
    buf[2] = '0' + @as(u8, @intCast((y / 10) % 10));
    buf[3] = '0' + @as(u8, @intCast(y % 10));
    buf[4] = '-';
    buf[5] = '0' + @as(u8, @intCast(m / 10));
    buf[6] = '0' + @as(u8, @intCast(m % 10));
    buf[7] = '-';
    buf[8] = '0' + @as(u8, @intCast(da / 10));
    buf[9] = '0' + @as(u8, @intCast(da % 10));
    return 10;
}

// --- Interval classification ---

const Interval = enum {
    weekly,
    monthly,
    quarterly,
    annual,
    unknown,

    pub fn label(self: Interval) []const u8 {
        return switch (self) {
            .weekly => "weekly",
            .monthly => "monthly",
            .quarterly => "quarterly",
            .annual => "annual",
            .unknown => "unknown",
        };
    }

    pub fn typicalDays(self: Interval) i32 {
        return switch (self) {
            .weekly => 7,
            .monthly => 30,
            .quarterly => 91,
            .annual => 365,
            .unknown => 0,
        };
    }
};

fn classifyInterval(median_days: i32) Interval {
    if (median_days >= 5 and median_days <= 9) return .weekly;
    if (median_days >= 25 and median_days <= 35) return .monthly;
    if (median_days >= 85 and median_days <= 100) return .quarterly;
    if (median_days >= 350 and median_days <= 380) return .annual;
    return .unknown;
}

// --- Detection algorithm ---

const MAX_TX_PER_MERCHANT = 64;
const MAX_MERCHANTS = 256;
const MIN_OCCURRENCES = 3;

const TxEntry = struct {
    date: DateTriple,
    amount: i64,
    category: i32,
};

const MerchantBucket = struct {
    name: [128]u8 = undefined,
    name_len: usize = 0,
    entries: [MAX_TX_PER_MERCHANT]TxEntry = undefined,
    entry_count: usize = 0,
    used: bool = false,
};

/// Detect recurring patterns from transaction history.
/// Returns the number of patterns detected.
pub fn detectRecurring(database: *Db) DbError!i32 {
    // Clear existing patterns
    try database.clearRecurring();

    const sql =
        \\SELECT description, amount_cents, date_year, date_month, date_day, category
        \\FROM transactions WHERE excluded = 0
        \\ORDER BY date_year ASC, date_month ASC, date_day ASC;
    ;

    var stmt: ?*c.sqlite3_stmt = null;
    if (c.sqlite3_prepare_v2(database.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt.?);
    const s = stmt.?;

    // Hash map: normalized merchant → entries (bounded, linear probing)
    var buckets: [MAX_MERCHANTS]MerchantBucket = @splat(MerchantBucket{});
    var bucket_count: usize = 0;

    // Global max date across all transactions. Used as the "as-of" reference
    // for staleness checks: a pattern whose `last_seen` lags far behind this
    // date is no longer active in the user's life.
    var max_date: DateTriple = .{ .year = 0, .month = 0, .day = 0 };
    var max_julian: i32 = std.math.minInt(i32);

    while (c.sqlite3_step(s) == c.SQLITE_ROW) {
        const desc_ptr = c.sqlite3_column_text(s, 0) orelse continue;
        const desc_len: usize = @intCast(c.sqlite3_column_bytes(s, 0));
        const amount = c.sqlite3_column_int64(s, 1);
        const year = c.sqlite3_column_int(s, 2);
        const month = c.sqlite3_column_int(s, 3);
        const day = c.sqlite3_column_int(s, 4);
        const category = c.sqlite3_column_int(s, 5);

        const row_date: DateTriple = .{ .year = year, .month = month, .day = day };
        const row_julian = julianDay(row_date);
        if (row_julian > max_julian) {
            max_julian = row_julian;
            max_date = row_date;
        }

        // Normalize merchant
        var norm_buf: [128]u8 = undefined;
        const norm_len = normalizeMerchant(desc_ptr[0..desc_len], &norm_buf) orelse continue;
        const norm = norm_buf[0..norm_len];

        // Find or create bucket for this merchant
        const slot = findOrCreateBucket(&buckets, &bucket_count, norm) orelse continue;
        const b = &buckets[slot];

        // Add entry (sorted by date since query is ORDER BY date ASC)
        if (b.entry_count < MAX_TX_PER_MERCHANT) {
            b.entries[b.entry_count] = .{
                .date = row_date,
                .amount = amount,
                .category = category,
            };
            b.entry_count += 1;
        }
    }

    // Process all merchant groups
    var detected: i32 = 0;
    for (&buckets) |*b| {
        if (!b.used or b.entry_count < MIN_OCCURRENCES) continue;
        const entries = b.entries[0..b.entry_count];
        if (processGroup(database, b.name[0..b.name_len], entries, max_julian) catch false) {
            detected += 1;
            continue;
        }
        // The group as a whole is not regular. It may still hide one fixed payment
        // among unrelated bookings that share the same text, e.g. a monthly rent
        // transfer next to other transfers with the same purpose line. Retry with
        // only the bookings around the most frequent amount.
        var cluster: [MAX_TX_PER_MERCHANT]TxEntry = undefined;
        const n = mostFrequentAmountCluster(entries, &cluster);
        if (n >= MIN_OCCURRENCES and n < entries.len) {
            if (processGroup(database, b.name[0..b.name_len], cluster[0..n], max_julian) catch false) {
                detected += 1;
            }
        }
    }

    return detected;
}

/// Copy the entries whose amount is within ±15% of the most frequent exact amount
/// (same sign) into `out`, keeping date order. Returns how many were copied.
fn mostFrequentAmountCluster(entries: []const TxEntry, out: *[MAX_TX_PER_MERCHANT]TxEntry) usize {
    var best_amount: i64 = 0;
    var best_count: usize = 0;
    for (entries) |e| {
        var count: usize = 0;
        for (entries) |other| {
            if (other.amount == e.amount) count += 1;
        }
        if (count > best_count) {
            best_count = count;
            best_amount = e.amount;
        }
    }
    if (best_count < MIN_OCCURRENCES or best_amount == 0) return 0;

    const abs_mode: i64 = if (best_amount < 0) -best_amount else best_amount;
    const lo = @divTrunc(abs_mode * RECENT_AMOUNT_BAND_LO, 100);
    const hi = @divTrunc(abs_mode * RECENT_AMOUNT_BAND_HI, 100);
    var n: usize = 0;
    for (entries) |e| {
        if ((e.amount < 0) != (best_amount < 0)) continue;
        const a: i64 = if (e.amount < 0) -e.amount else e.amount;
        if (a >= lo and a <= hi) {
            out[n] = e;
            n += 1;
        }
    }
    return n;
}

/// Simple hash for merchant name (FNV-1a)
fn merchantHash(name: []const u8) u32 {
    var h: u32 = 2166136261;
    for (name) |byte| {
        h ^= byte;
        h *%= 16777619;
    }
    return h;
}

/// Find existing bucket or create new one. Returns slot index or null if full.
fn findOrCreateBucket(buckets: *[MAX_MERCHANTS]MerchantBucket, count: *usize, name: []const u8) ?usize {
    const start = merchantHash(name) % MAX_MERCHANTS;
    var idx = start;
    while (true) {
        const b = &buckets[idx];
        if (b.used and b.name_len == name.len and std.mem.eql(u8, b.name[0..b.name_len], name)) {
            return idx; // Found existing
        }
        if (!b.used) {
            if (count.* >= MAX_MERCHANTS - 1) return null; // Table full
            b.used = true;
            @memcpy(b.name[0..name.len], name);
            b.name_len = name.len;
            b.entry_count = 0;
            count.* += 1;
            return idx; // Created new
        }
        idx = (idx + 1) % MAX_MERCHANTS;
        if (idx == start) return null; // Wrapped around, table full
    }
}

/// Required number of recent entries within the canonical-amount band for the
/// "amount consistency" check. Cheaper than scanning the entire history: subs
/// often have intro pricing followed by a steady-state price, and only the
/// steady-state matters for "is this currently a recurring charge".
const RECENT_AMOUNT_WINDOW: usize = 4;

/// ±15% band around the recent-window median.
const RECENT_AMOUNT_BAND_LO: i64 = 85;
const RECENT_AMOUNT_BAND_HI: i64 = 115;

/// Returns true if the last `RECENT_AMOUNT_WINDOW` (or fewer) entries are
/// consistent enough that we trust the most recent amount as the canonical
/// charge. Required share inside the band is ceil(2/3) — for n=3 → 2, n=4 → 3.
fn recentAmountsConsistent(entries: []const TxEntry) bool {
    const n = @min(entries.len, RECENT_AMOUNT_WINDOW);
    if (n == 0) return false;

    var recent: [RECENT_AMOUNT_WINDOW]i64 = undefined;
    const start = entries.len - n;
    for (entries[start..], 0..) |e, i| {
        recent[i] = if (e.amount < 0) -e.amount else e.amount;
    }

    // Selection sort over the small window.
    for (0..n) |i| {
        var min_idx = i;
        for (i + 1..n) |j| {
            if (recent[j] < recent[min_idx]) min_idx = j;
        }
        const tmp = recent[i];
        recent[i] = recent[min_idx];
        recent[min_idx] = tmp;
    }

    const median = recent[n / 2];
    if (median == 0) return false;
    const lo = @divTrunc(median * RECENT_AMOUNT_BAND_LO, 100);
    const hi = @divTrunc(median * RECENT_AMOUNT_BAND_HI, 100);

    var in_range: usize = 0;
    for (recent[0..n]) |a| {
        if (a >= lo and a <= hi) in_range += 1;
    }
    // Threshold: n=1 → 1, n=2 → 2, n=3 → 2, n=4 → 3. Approximates ceil(2n/3)
    // but written as a switch so the compiler does not need to prove the
    // arithmetic does not overflow at the call site.
    const required: usize = switch (n) {
        0 => return false,
        1 => 1,
        2 => 2,
        3 => 2,
        4 => 3,
        else => (n + (n + 2) / 3),
    };
    return in_range >= required;
}

/// A pattern is "active" only if its `last_seen` is recent relative to the
/// global max transaction date. We allow up to 2× the typical interval of
/// silence before declaring the sub dead. Without this, a subscription that
/// ended a year ago lingers forever as "500T überfällig".
fn isPatternActive(last_seen_julian: i32, global_max_julian: i32, interval: Interval) bool {
    if (global_max_julian == std.math.minInt(i32)) return true;
    const gap = global_max_julian - last_seen_julian;
    const threshold = interval.typicalDays() * 2;
    return gap <= threshold;
}

fn processGroup(database: *Db, merchant: []const u8, entries: []const TxEntry, global_max_julian: i32) DbError!bool {
    if (entries.len < MIN_OCCURRENCES) return false;

    // Calculate intervals between consecutive dates
    var intervals: [MAX_TX_PER_MERCHANT]i32 = undefined;
    var interval_count: usize = 0;
    for (1..entries.len) |i| {
        const days = daysBetween(entries[i - 1].date, entries[i].date);
        if (days > 0) {
            intervals[interval_count] = days;
            interval_count += 1;
        }
    }

    if (interval_count < 2) return false;

    // Find median interval
    // Simple selection sort on first interval_count elements
    var sorted: [MAX_TX_PER_MERCHANT]i32 = undefined;
    @memcpy(sorted[0..interval_count], intervals[0..interval_count]);
    for (0..interval_count) |i| {
        var min_idx = i;
        for (i + 1..interval_count) |j| {
            if (sorted[j] < sorted[min_idx]) min_idx = j;
        }
        const tmp = sorted[i];
        sorted[i] = sorted[min_idx];
        sorted[min_idx] = tmp;
    }
    const median = sorted[interval_count / 2];

    // Classify interval
    const interval = classifyInterval(median);
    if (interval == .unknown) return false;

    // Check consistency: ≥60% of intervals within range
    var in_range: usize = 0;
    const lo: i32 = switch (interval) {
        .weekly => 5,
        .monthly => 25,
        .quarterly => 85,
        .annual => 350,
        .unknown => 0,
    };
    const hi: i32 = switch (interval) {
        .weekly => 9,
        .monthly => 35,
        .quarterly => 100,
        .annual => 380,
        .unknown => 0,
    };
    for (intervals[0..interval_count]) |iv| {
        if (iv >= lo and iv <= hi) in_range += 1;
    }
    if (in_range * 100 < interval_count * 60) return false;

    // Amount consistency: check only the most recent window. A sub with intro
    // pricing or a one-time hike still counts if its *current* price is
    // stable. The previous full-history check rejected bimodal pricing and
    // made half-year-old subs disappear once new patterns showed up.
    if (!recentAmountsConsistent(entries)) return false;

    // Compute values
    const last_entry = entries[entries.len - 1];
    const prev_entry = entries[entries.len - 2];
    const last_amount = last_entry.amount;
    const prev_amount_val = prev_entry.amount;
    const category = last_entry.category;

    // Price change detection: >50 cents difference
    const prev_amount: ?i64 = if (entries.len >= 2)
        prev_amount_val
    else
        null;

    // Calculate next_due
    const next_due_date = addDays(last_entry.date, interval.typicalDays());

    // Activity check: if last_seen is too stale relative to the user's most
    // recent transaction, mark the pattern inactive so it won't show as
    // "500T überfällig" in the UI. Still inserted so detection is stable
    // across reruns and resurfaces if new payments arrive.
    const active: i32 = if (isPatternActive(julianDay(last_entry.date), global_max_julian, interval)) 1 else 0;

    // Generate deterministic ID from merchant hash
    var id_buf: [32]u8 = undefined;
    hashMerchantId(merchant, &id_buf);

    // Format last_seen date
    var ls_buf: [10]u8 = undefined;
    const ls_len = formatDateStr(&ls_buf, last_entry.date) orelse return false;

    // Format next_due date
    var nd_buf: [10]u8 = undefined;
    const nd_len = formatDateStr(&nd_buf, next_due_date) orelse return false;

    const intv_label = interval.label();

    try database.insertOrUpdateRecurring(
        &id_buf,
        32,
        merchant.ptr,
        @intCast(merchant.len),
        last_amount,
        intv_label.ptr,
        @intCast(intv_label.len),
        category,
        &ls_buf,
        @intCast(ls_len),
        &nd_buf,
        @intCast(nd_len),
        prev_amount,
        active,
    );

    return active == 1;
}

/// Payments that belong to one recurring pattern, newest first:
/// `[{"id":"…","date":"YYYY-MM-DD","amount":-10.99}, …]`.
/// A payment belongs to the pattern when its description normalizes to the
/// same merchant (the pattern id is the hash of that merchant) and its sign
/// matches the pattern's. Unknown ids give `[]`.
pub fn paymentsJson(database: *Db, pattern_id: []const u8, buf: [*]u8, buf_len: usize) DbError!?usize {
    if (buf_len < 2) return null;
    var pos: usize = 0;
    buf[pos] = '[';
    pos += 1;

    // The pattern's sign (expense or income).
    var sign: i64 = 0;
    {
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(database.handle, "SELECT amount FROM recurring_patterns WHERE id = ?1;", -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);
        if (c.sqlite3_bind_text(stmt.?, 1, pattern_id.ptr, @intCast(pattern_id.len), c.SQLITE_STATIC) != c.SQLITE_OK) return DbError.BindFailed;
        if (c.sqlite3_step(stmt.?) == c.SQLITE_ROW) {
            const a = c.sqlite3_column_int64(stmt.?, 0);
            sign = if (a < 0) -1 else 1;
        }
    }
    if (sign != 0) {
        const sql =
            \\SELECT id, date_year, date_month, date_day, amount_cents, description
            \\FROM transactions WHERE excluded = 0
            \\ORDER BY date_year DESC, date_month DESC, date_day DESC, rowid DESC;
        ;
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(database.handle, sql, -1, &stmt, null) != c.SQLITE_OK or stmt == null) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt.?);
        const s = stmt.?;
        var first = true;
        while (c.sqlite3_step(s) == c.SQLITE_ROW) {
            const amount = c.sqlite3_column_int64(s, 4);
            if ((amount < 0) != (sign < 0) or amount == 0) continue;
            const desc_ptr = c.sqlite3_column_text(s, 5) orelse continue;
            const desc_len: usize = @intCast(c.sqlite3_column_bytes(s, 5));
            var norm_buf: [128]u8 = undefined;
            const norm_len = normalizeMerchant(desc_ptr[0..desc_len], &norm_buf) orelse continue;
            var hid: [32]u8 = undefined;
            hashMerchantId(norm_buf[0..norm_len], &hid);
            if (!std.mem.eql(u8, &hid, pattern_id)) continue;

            const id_ptr = c.sqlite3_column_text(s, 0) orelse continue;
            const id_len: usize = @intCast(c.sqlite3_column_bytes(s, 0));
            const out = buf[0..buf_len];
            const need = id_len + 64;
            if (pos + need > buf_len) return null;
            if (!first) {
                out[pos] = ',';
                pos += 1;
            }
            first = false;
            const p1 = "{\"id\":\"";
            @memcpy(out[pos .. pos + p1.len], p1);
            pos += p1.len;
            @memcpy(out[pos .. pos + id_len], id_ptr[0..id_len]);
            pos += id_len;
            const p2 = "\",\"date\":\"";
            @memcpy(out[pos .. pos + p2.len], p2);
            pos += p2.len;
            pos += formatDateStr(out[pos..], .{
                .year = c.sqlite3_column_int(s, 1),
                .month = c.sqlite3_column_int(s, 2),
                .day = c.sqlite3_column_int(s, 3),
            }) orelse return null;
            const p3 = "\",\"amount\":";
            @memcpy(out[pos .. pos + p3.len], p3);
            pos += p3.len;
            pos += db_mod.formatAmount(out[pos..], amount) orelse return null;
            if (pos >= buf_len) return null;
            out[pos] = '}';
            pos += 1;
        }
    }
    if (pos >= buf_len) return null;
    buf[pos] = ']';
    pos += 1;
    return pos;
}

fn hashMerchantId(merchant: []const u8, out: *[32]u8) void {
    // Simple hash → hex string for deterministic ID
    var hash: u64 = 5381;
    for (merchant) |ch| {
        hash = hash *% 33 +% ch;
    }
    const hex_chars = "0123456789abcdef";
    // Fill 32-char ID: repeat hash bytes as hex
    var h = hash;
    for (0..16) |i| {
        out[i * 2] = hex_chars[@intCast((h >> 4) & 0x0F)];
        out[i * 2 + 1] = hex_chars[@intCast(h & 0x0F)];
        h = h *% 2654435761 +% @as(u64, @intCast(i));
    }
}

// --- Tests ---

fn testNormalize(desc: []const u8, buf: *[128]u8) []const u8 {
    const n = normalizeMerchant(desc, buf) orelse return "";
    return buf[0..n];
}

test "normalizeMerchant strips FinTS booking-type prefixes" {
    var buf: [128]u8 = undefined;
    try std.testing.expectEqualStrings("KTO. 12345 678", testNormalize("LASTSCHRIFT / BELASTUNG KTO. 12345 678 KD MUSTERMANN RNR 2603 44025 DATUM 01.11.2026", &buf));
    // Latin-1 umlauts as stored from MT940, instant transfer variant, SEPA tail cut off.
    try std.testing.expectEqualStrings("MAX MUSTERMANN", testNormalize("\xDCBERTRAG / \xDCBERWEISUNG - ECHTZEIT MAX MUSTERMANN END-TO-END-REF.: NICHT ANGEGEBEN Ref. 4D2C/5", &buf));
    try std.testing.expectEqualStrings("MAX MUSTERMANN", testNormalize("ÜBERTRAG / ÜBERWEISUNG MAX MUSTERMANN END-TO-END-REF.: NICHT ANGEGEBEN", &buf));
    try std.testing.expectEqualStrings("BAECKEREI KAMPS", testNormalize("KARTENVERFÜGUNG BAECKEREI KAMPS, SOLINGEN DE", &buf));
}

test "normalizeMerchant leaves changing invoice numbers out of the key" {
    var buf: [128]u8 = undefined;
    try std.testing.expectEqualStrings("B VK MUSTERSTR", testNormalize("LASTSCHRIFT / BELASTUNG B 8319997724 VK 3014261600 MUSTERSTR . 1 / STROM ABS", &buf));
    try std.testing.expectEqualStrings("B VK MUSTERSTR", testNormalize("LASTSCHRIFT / BELASTUNG B 8440181080 VK 3014261600 MUSTERSTR . 1 / STROM ABS", &buf));
    // A description that is only a booking number gives no usable key.
    try std.testing.expectEqualStrings("", testNormalize("LASTSCHRIFT / BELASTUNG 1049180470184/PP.6831.PP/. , IHR EINKAUF BEI", &buf));
}

test "mostFrequentAmountCluster isolates a fixed payment among mixed transfers" {
    const d = struct {
        fn e(month: i32, day: i32, amount: i64) TxEntry {
            return .{ .date = .{ .year = 2026, .month = month, .day = day }, .amount = amount, .category = 0 };
        }
    };
    const entries = [_]TxEntry{
        d.e(6, 10, -76000), d.e(6, 22, -35000), d.e(6, 25, -20000), d.e(7, 1, -35000),
        d.e(7, 4, -90000),  d.e(8, 3, -35000),  d.e(8, 20, -10000), d.e(9, 1, -35000),
        d.e(9, 15, 35000),  d.e(10, 1, -35000),
    };
    var out: [MAX_TX_PER_MERCHANT]TxEntry = undefined;
    const n = mostFrequentAmountCluster(&entries, &out);
    try std.testing.expectEqual(@as(usize, 5), n); // the five -350.00 debits, not the +350.00 credit
    for (out[0..n]) |x| try std.testing.expectEqual(@as(i64, -35000), x.amount);
}

test "normalizeMerchant: known merchants" {
    var buf: [128]u8 = undefined;

    const len1 = normalizeMerchant("NETFLIX.COM/BILL", &buf).?;
    try std.testing.expectEqualStrings("Netflix", buf[0..len1]);

    const len2 = normalizeMerchant("Spotify AB Stockholm", &buf).?;
    try std.testing.expectEqualStrings("Spotify", buf[0..len2]);

    const len3 = normalizeMerchant("REWE SAGT DANKE 1234", &buf).?;
    try std.testing.expectEqualStrings("REWE", buf[0..len3]);

    const len4 = normalizeMerchant("RUNDFUNK ARD ZDF", &buf).?;
    try std.testing.expectEqualStrings("Rundfunkbeitrag", buf[0..len4]);
}

test "normalizeMerchant: generic merchants" {
    var buf: [128]u8 = undefined;

    const len1 = normalizeMerchant("MUELLER DROGERIE GMBH", &buf).?;
    // Should strip GMBH
    try std.testing.expect(len1 > 0);
    // Result should be uppercase (since it's not a known merchant)
    try std.testing.expect(buf[0] == 'M');
}

test "classifyInterval" {
    try std.testing.expectEqual(Interval.weekly, classifyInterval(7));
    try std.testing.expectEqual(Interval.monthly, classifyInterval(30));
    try std.testing.expectEqual(Interval.monthly, classifyInterval(31));
    try std.testing.expectEqual(Interval.quarterly, classifyInterval(91));
    try std.testing.expectEqual(Interval.annual, classifyInterval(365));
    try std.testing.expectEqual(Interval.unknown, classifyInterval(15));
    try std.testing.expectEqual(Interval.unknown, classifyInterval(200));
}

test "daysBetween" {
    const d1 = DateTriple{ .year = 2026, .month = 1, .day = 1 };
    const d2 = DateTriple{ .year = 2026, .month = 2, .day = 1 };
    try std.testing.expectEqual(@as(i32, 31), daysBetween(d1, d2));

    const d3 = DateTriple{ .year = 2026, .month = 1, .day = 1 };
    const d4 = DateTriple{ .year = 2026, .month = 1, .day = 8 };
    try std.testing.expectEqual(@as(i32, 7), daysBetween(d3, d4));
}

test "formatDateStr" {
    var buf: [10]u8 = undefined;
    const d = DateTriple{ .year = 2026, .month = 3, .day = 8 };
    const len = formatDateStr(&buf, d).?;
    try std.testing.expectEqual(@as(usize, 10), len);
    try std.testing.expectEqualStrings("2026-03-08", &buf);
}

test "hashMerchantId produces 32 hex chars" {
    var id: [32]u8 = undefined;
    hashMerchantId("Netflix", &id);
    for (id) |ch| {
        try std.testing.expect((ch >= '0' and ch <= '9') or (ch >= 'a' and ch <= 'f'));
    }
}

test "recentAmountsConsistent: stable price passes" {
    const entries = [_]TxEntry{
        .{ .date = .{ .year = 2026, .month = 1, .day = 1 }, .amount = -1000, .category = 0 },
        .{ .date = .{ .year = 2026, .month = 2, .day = 1 }, .amount = -1000, .category = 0 },
        .{ .date = .{ .year = 2026, .month = 3, .day = 1 }, .amount = -1000, .category = 0 },
    };
    try std.testing.expect(recentAmountsConsistent(&entries));
}

test "recentAmountsConsistent: intro pricing then full price passes" {
    // Three months of €5 intro, then three months of €15 full price.
    // Old algorithm rejected this (50% within ±10% of full-history median).
    // New algorithm only inspects the last 4 entries — 3/4 are stable at €15.
    const entries = [_]TxEntry{
        .{ .date = .{ .year = 2026, .month = 1, .day = 1 }, .amount = -500, .category = 0 },
        .{ .date = .{ .year = 2026, .month = 2, .day = 1 }, .amount = -500, .category = 0 },
        .{ .date = .{ .year = 2026, .month = 3, .day = 1 }, .amount = -500, .category = 0 },
        .{ .date = .{ .year = 2026, .month = 4, .day = 1 }, .amount = -1500, .category = 0 },
        .{ .date = .{ .year = 2026, .month = 5, .day = 1 }, .amount = -1500, .category = 0 },
        .{ .date = .{ .year = 2026, .month = 6, .day = 1 }, .amount = -1500, .category = 0 },
    };
    try std.testing.expect(recentAmountsConsistent(&entries));
}

test "recentAmountsConsistent: chaotic recent amounts fail" {
    const entries = [_]TxEntry{
        .{ .date = .{ .year = 2026, .month = 1, .day = 1 }, .amount = -1000, .category = 0 },
        .{ .date = .{ .year = 2026, .month = 2, .day = 1 }, .amount = -3000, .category = 0 },
        .{ .date = .{ .year = 2026, .month = 3, .day = 1 }, .amount = -500, .category = 0 },
        .{ .date = .{ .year = 2026, .month = 4, .day = 1 }, .amount = -8000, .category = 0 },
    };
    try std.testing.expect(!recentAmountsConsistent(&entries));
}

test "isPatternActive: recent monthly sub stays active" {
    // last_seen 25 days ago — well within 2× monthly (60 days).
    const last_seen = DateTriple{ .year = 2026, .month = 4, .day = 6 };
    const max_date = DateTriple{ .year = 2026, .month = 5, .day = 1 };
    try std.testing.expect(isPatternActive(julianDay(last_seen), julianDay(max_date), .monthly));
}

test "isPatternActive: stale monthly sub goes inactive" {
    // last_seen 500 days ago — fixes the "500T überfällig" UI bug.
    const last_seen = DateTriple{ .year = 2024, .month = 12, .day = 18 };
    const max_date = DateTriple{ .year = 2026, .month = 5, .day = 1 };
    try std.testing.expect(!isPatternActive(julianDay(last_seen), julianDay(max_date), .monthly));
}

test "isPatternActive: annual sub tolerates 18-month gap up to threshold" {
    // 700 days ago — within 2× annual (730 days), still active.
    const last_seen = DateTriple{ .year = 2024, .month = 6, .day = 1 };
    const max_date = DateTriple{ .year = 2026, .month = 5, .day = 1 };
    try std.testing.expect(isPatternActive(julianDay(last_seen), julianDay(max_date), .annual));

    // 800 days ago — beyond 2× annual (730 days), inactive.
    const old_last = DateTriple{ .year = 2024, .month = 2, .day = 1 };
    try std.testing.expect(!isPatternActive(julianDay(old_last), julianDay(max_date), .annual));
}

test "addDays crosses months, years and leap days" {
    const D = DateTriple;
    const cases = [_]struct { from: D, add: i32, want: D }{
        .{ .from = .{ .year = 2026, .month = 11, .day = 3 }, .add = 30, .want = .{ .year = 2026, .month = 12, .day = 3 } },
        .{ .from = .{ .year = 2026, .month = 12, .day = 15 }, .add = 30, .want = .{ .year = 2027, .month = 1, .day = 14 } },
        .{ .from = .{ .year = 2028, .month = 2, .day = 28 }, .add = 1, .want = .{ .year = 2028, .month = 2, .day = 29 } },
        .{ .from = .{ .year = 2027, .month = 2, .day = 28 }, .add = 1, .want = .{ .year = 2027, .month = 3, .day = 1 } },
        .{ .from = .{ .year = 2026, .month = 1, .day = 31 }, .add = 91, .want = .{ .year = 2026, .month = 5, .day = 2 } },
        .{ .from = .{ .year = 2026, .month = 3, .day = 1 }, .add = 365, .want = .{ .year = 2027, .month = 3, .day = 1 } },
    };
    for (cases) |tc| {
        const got = addDays(tc.from, tc.add);
        try std.testing.expectEqual(tc.want.year, got.year);
        try std.testing.expectEqual(tc.want.month, got.month);
        try std.testing.expectEqual(tc.want.day, got.day);
    }
}

test "julianDay and fromRataDie round-trip" {
    var d: DateTriple = .{ .year = 2024, .month = 1, .day = 1 };
    var i: i32 = 0;
    while (i < 1200) : (i += 1) {
        const back = fromRataDie(julianDay(d));
        try std.testing.expectEqual(d.year, back.year);
        try std.testing.expectEqual(d.month, back.month);
        try std.testing.expectEqual(d.day, back.day);
        try std.testing.expectEqual(@as(i32, 1), daysBetween(d, addDays(d, 1)));
        d = addDays(d, 1);
    }
    try std.testing.expectEqual(@as(i32, 2027), d.year);
}

test "paymentsJson lists a pattern's payments, newest first" {
    var database = try Db.init(":memory:");
    defer database.close();
    const rows =
        \\INSERT INTO transactions (id, date_year, date_month, date_day, description, amount_cents) VALUES
        \\ ('a1', 2026, 9, 1, 'LASTSCHRIFT / BELASTUNG SPOTIFY AB 123', -1099),
        \\ ('a2', 2026, 10, 1, 'LASTSCHRIFT / BELASTUNG SPOTIFY AB 456', -1099),
        \\ ('a3', 2026, 11, 1, 'LASTSCHRIFT / BELASTUNG SPOTIFY AB 789', -1099),
        \\ ('b1', 2026, 11, 2, 'KARTENVERFUEGUNG REWE MARKT', -2348);
    ;
    try std.testing.expect(c.sqlite3_exec(database.handle, rows, null, null, null) == c.SQLITE_OK);
    _ = try detectRecurring(&database);
    // A refund from the same merchant arrives later: other sign, not a payment.
    const refund = "INSERT INTO transactions (id, date_year, date_month, date_day, description, amount_cents) VALUES ('c1', 2026, 11, 3, 'GUTSCHRIFT SPOTIFY AB ERSTATTUNG', 500);";
    try std.testing.expect(c.sqlite3_exec(database.handle, refund, null, null, null) == c.SQLITE_OK);

    var name_buf: [128]u8 = undefined;
    const n = normalizeMerchant("LASTSCHRIFT / BELASTUNG SPOTIFY AB 123", &name_buf).?;
    var id: [32]u8 = undefined;
    hashMerchantId(name_buf[0..n], &id);

    var out: [1024]u8 = undefined;
    const len = (try paymentsJson(&database, &id, &out, out.len)).?;
    const json = out[0..len];
    // Three debits, newest first; the refund (other sign) and REWE are not part of it.
    try std.testing.expect(std.mem.startsWith(u8, json, "[{\"id\":\"a3\",\"date\":\"2026-11-01\""));
    try std.testing.expect(std.mem.indexOf(u8, json, "\"a1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"b1\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"c1\"") == null);

    const none = (try paymentsJson(&database, "00000000000000000000000000000000", &out, out.len)).?;
    try std.testing.expectEqualStrings("[]", out[0..none]);
}
