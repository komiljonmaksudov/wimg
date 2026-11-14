//! Gehaltsmonat: what "a month" is. Calendar months (the default), a fixed
//! start day ("Fester Tag", e.g. the 15th to the 14th), or salary to salary.
//!
//! Salary detection: incomes are grouped by payer (same key as recurring
//! detection). A payer whose incomes arrive about monthly (two or more, 20–40
//! days apart) is a candidate; the one with the largest typical amount wins.
//! The user confirms it ("Ist das dein Gehalt?"), says no, or picks another
//! payer. Confirmed and rejected payers live in the synced `settings` table.
//!
//! Every platform asks `wimg_get_periods` and renders what comes back.

const std = @import("std");
const c = @import("sqlite_c.zig");
const db_mod = @import("db.zig");
const recurring = @import("recurring.zig");
const booking = @import("booking.zig");

const Db = db_mod.Db;
const Day = recurring.DateTriple;

pub const Mode = enum { calendar, salary, day };

const MAX_INCOMES = 1024;
const MAX_EVENTS = 64;
const MAX_PAYERS = 64;
const KEY_LEN = 64;
const TITLE_LEN = 72;
/// Incomes of one payer this close together count as one salary.
const MERGE_DAYS = 7;
/// Below this a monthly income is not taken for a salary (refunds, interest).
const MIN_SALARY_CENTS = 30000;

const Income = struct {
    jd: i32,
    cents: i64,
    id: [32]u8,
    key: [KEY_LEN]u8,
    key_len: u8,
    title: [TITLE_LEN]u8,
    title_len: u8,

    fn keySlice(self: *const Income) []const u8 {
        return self.key[0..self.key_len];
    }
    fn titleSlice(self: *const Income) []const u8 {
        return self.title[0..self.title_len];
    }
};

const Event = struct { jd: i32, cents: i64 };

const Payer = struct {
    key: []const u8,
    title: []const u8,
    count: u32 = 0,
    median_cents: i64 = 0,
    last_jd: i32 = 0,
    monthly: bool = false,
};

// Static: too big for a 1 MB Android worker-thread stack (libwimg is single-threaded).
var income_store: [MAX_INCOMES]Income = undefined;

pub fn jd(d: Day) i32 {
    return recurring.julianDay(d);
}

pub fn fromJd(v: i32) Day {
    return recurring.fromRataDie(v);
}

pub fn fromYmd(ymd: u32) Day {
    return .{ .year = @intCast(ymd / 10000), .month = @intCast((ymd / 100) % 100), .day = @intCast(ymd % 100) };
}

fn monthLen(year: i32, month: i32) i32 {
    const next = if (month == 12) Day{ .year = year + 1, .month = 1, .day = 1 } else Day{ .year = year, .month = month + 1, .day = 1 };
    return jd(next) - jd(.{ .year = year, .month = month, .day = 1 });
}

/// Day [day] of the given month, or its last day when the month is shorter.
fn clampedDay(year: i32, month: i32, day: i32) Day {
    return .{ .year = year, .month = month, .day = @min(day, monthLen(year, month)) };
}

fn addMonths(d: Day, n: i32) Day {
    const idx = d.year * 12 + (d.month - 1) + n;
    return .{ .year = @divFloor(idx, 12), .month = @mod(idx, 12) + 1, .day = d.day };
}

/// When the next salary is due after one on [last]: the first [typical] day of
/// a month that is at least 20 days later.
pub fn expectedAfter(last: i32, typical: i32) i32 {
    const start = fromJd(last + 20);
    var m = Day{ .year = start.year, .month = start.month, .day = 1 };
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        const cand = clampedDay(m.year, m.month, typical);
        if (jd(cand) >= last + 20) return jd(cand);
        m = addMonths(m, 1);
    }
    return last + 30;
}

/// Calendar month or "Fester Tag" period that contains [day]; returns from/to (inclusive).
pub fn fixedPeriod(day: Day, start_day: i32) [2]i32 {
    const sd = if (start_day < 1) 1 else @min(start_day, 28);
    const this_start = clampedDay(day.year, day.month, sd);
    const from = if (jd(day) >= jd(this_start)) this_start else blk: {
        const p = addMonths(.{ .year = day.year, .month = day.month, .day = 1 }, -1);
        break :blk clampedDay(p.year, p.month, sd);
    };
    const n = addMonths(.{ .year = from.year, .month = from.month, .day = 1 }, 1);
    return .{ jd(from), jd(clampedDay(n.year, n.month, sd)) - 1 };
}

fn lineIn(list: []const u8, key: []const u8) bool {
    var it = std.mem.splitScalar(u8, list, '\n');
    while (it.next()) |l| if (l.len > 0 and std.mem.eql(u8, l, key)) return true;
    return false;
}

/// Loads incomes (newest last) from visible accounts.
fn loadIncomes(database: *Db) usize {
    const sql = "SELECT date_year, date_month, date_day, amount_cents, id, description FROM transactions " ++
        "WHERE amount_cents > 0 AND excluded = 0 AND " ++ db_mod.visible_accounts ++
        " ORDER BY date_year DESC, date_month DESC, date_day DESC, rowid DESC LIMIT 1024;";
    var st: ?*c.sqlite3_stmt = null;
    if (c.sqlite3_prepare_v2(database.handle, sql, -1, &st, null) != c.SQLITE_OK or st == null) return 0;
    defer _ = c.sqlite3_finalize(st.?);
    var n: usize = 0;
    while (c.sqlite3_step(st.?) == c.SQLITE_ROW and n < MAX_INCOMES) {
        const desc_ptr = c.sqlite3_column_text(st.?, 5) orelse continue;
        const desc = desc_ptr[0..@intCast(c.sqlite3_column_bytes(st.?, 5))];
        var inc = &income_store[n];
        inc.jd = jd(.{ .year = c.sqlite3_column_int(st.?, 0), .month = c.sqlite3_column_int(st.?, 1), .day = c.sqlite3_column_int(st.?, 2) });
        inc.cents = c.sqlite3_column_int64(st.?, 3);
        inc.id = @splat('0');
        if (c.sqlite3_column_text(st.?, 4)) |idp| {
            const l: usize = @min(32, @as(usize, @intCast(c.sqlite3_column_bytes(st.?, 4))));
            @memcpy(inc.id[0..l], idp[0..l]);
        }
        const kl = recurring.normalizeMerchant(desc, &inc.key) orelse continue;
        inc.key_len = @intCast(kl);
        const t = booking.displayTitle(desc);
        const tl = @min(t.len, TITLE_LEN);
        @memcpy(inc.title[0..tl], t[0..tl]);
        inc.title_len = @intCast(tl);
        n += 1;
    }
    std.mem.reverse(Income, income_store[0..n]);
    return n;
}

/// Salary events of the payers in [keys] (or the one [key]), oldest first.
fn eventsOf(incomes: []const Income, keys: []const u8, single: ?[]const u8, out: *[MAX_EVENTS]Event) usize {
    var n: usize = 0;
    for (incomes) |*inc| {
        const k = inc.keySlice();
        const match = if (single) |s| std.mem.eql(u8, s, k) else lineIn(keys, k);
        if (!match) continue;
        if (n > 0 and inc.jd - out[n - 1].jd < MERGE_DAYS) {
            out[n - 1].cents += inc.cents;
            continue;
        }
        if (n == MAX_EVENTS) {
            std.mem.copyForwards(Event, out[0 .. MAX_EVENTS - 1], out[1..MAX_EVENTS]);
            n -= 1;
        }
        out[n] = .{ .jd = inc.jd, .cents = inc.cents };
        n += 1;
    }
    return n;
}

fn medianCents(events: []const Event) i64 {
    var tmp: [MAX_EVENTS]i64 = undefined;
    for (events, 0..) |e, i| tmp[i] = e.cents;
    std.mem.sort(i64, tmp[0..events.len], {}, std.sort.asc(i64));
    return if (events.len == 0) 0 else tmp[events.len / 2];
}

/// Most common day of the month among the last few salaries (ties: the latest).
fn typicalDay(events: []const Event) i32 {
    const from = if (events.len > 6) events.len - 6 else 0;
    var days: [6]i32 = undefined;
    var k: usize = 0;
    for (events[from..]) |e| {
        days[k] = fromJd(e.jd).day;
        k += 1;
    }
    std.mem.sort(i32, days[0..k], {}, std.sort.asc(i32));
    return if (k == 0) 1 else days[k / 2];
}

fn isMonthly(events: []const Event) bool {
    if (events.len < 2) return false;
    var i: usize = 1;
    while (i < events.len) : (i += 1) {
        const gap = events[i].jd - events[i - 1].jd;
        if (gap >= 20 and gap <= 40) return true;
    }
    return false;
}

/// Distinct payers of the last 200 days, largest typical amount first.
fn collectPayers(incomes: []const Income, today: i32, out: *[MAX_PAYERS]Payer) usize {
    var n: usize = 0;
    var i: usize = incomes.len;
    while (i > 0) {
        i -= 1;
        const inc = &incomes[i];
        if (today - inc.jd > 200) break;
        const k = inc.keySlice();
        var seen = false;
        for (out[0..n]) |p| if (std.mem.eql(u8, p.key, k)) {
            seen = true;
            break;
        };
        if (seen or n == MAX_PAYERS) continue;
        var ev: [MAX_EVENTS]Event = undefined;
        const en = eventsOf(incomes, "", k, &ev);
        out[n] = .{ .key = k, .title = inc.titleSlice(), .count = @intCast(en), .median_cents = medianCents(ev[0..en]), .last_jd = inc.jd, .monthly = isMonthly(ev[0..en]) };
        n += 1;
    }
    std.mem.sort(Payer, out[0..n], {}, struct {
        fn lt(_: void, a: Payer, b: Payer) bool {
            return a.median_cents > b.median_cents;
        }
    }.lt);
    return n;
}

const Out = struct {
    buf: []u8,
    pos: usize = 0,
    ok: bool = true,

    fn s(self: *Out, v: []const u8) void {
        if (!self.ok or self.pos + v.len > self.buf.len) {
            self.ok = false;
            return;
        }
        @memcpy(self.buf[self.pos .. self.pos + v.len], v);
        self.pos += v.len;
    }
    fn str(self: *Out, v: []const u8) void {
        self.s("\"");
        if (!self.ok) return;
        const n = db_mod.jsonEscapeString(self.buf[self.pos..], v) orelse {
            self.ok = false;
            return;
        };
        self.pos += n;
        self.s("\"");
    }
    fn int(self: *Out, v: i64) void {
        if (!self.ok) return;
        const n = db_mod.formatSignedInt(self.buf[self.pos..], v) orelse {
            self.ok = false;
            return;
        };
        self.pos += n;
    }
    fn amount(self: *Out, cents: i64) void {
        if (!self.ok) return;
        const n = db_mod.formatAmount(self.buf[self.pos..], cents) orelse {
            self.ok = false;
            return;
        };
        self.pos += n;
    }
    fn date(self: *Out, v: i32) void {
        var b: [10]u8 = undefined;
        const d = fromJd(v);
        _ = std.fmt.bufPrint(&b, "{d:0>4}-{d:0>2}-{d:0>2}", .{ @as(u32, @intCast(d.year)), @as(u32, @intCast(d.month)), @as(u32, @intCast(d.day)) }) catch return;
        self.str(&b);
    }
};

fn writePeriod(o: *Out, first: *bool, from: i32, to: i32, current: bool, salary_cents: ?i64, early: i32) void {
    if (!first.*) o.s(",");
    first.* = false;
    o.s("{\"from\":");
    o.date(from);
    o.s(",\"to\":");
    o.date(to);
    o.s(",\"days\":");
    o.int(to - from + 1);
    o.s(if (current) ",\"current\":true" else ",\"current\":false");
    if (salary_cents) |sc| {
        o.s(",\"salary\":");
        o.amount(sc);
    }
    o.s(",\"early_days\":");
    o.int(early);
    o.s("}");
}

/// The periods JSON (see c-abi.md). [count] periods, newest first.
pub fn periodsJson(database: *Db, today_ymd: u32, count: u32, buf: []u8) ?usize {
    const today = jd(fromYmd(today_ymd));
    var mode_buf: [16]u8 = undefined;
    const chosen_str = database.getSetting("period_mode", &mode_buf) orelse "calendar";
    const chosen: Mode = std.meta.stringToEnum(Mode, chosen_str) orelse .calendar;
    var day_buf: [8]u8 = undefined;
    const fixed_day: i32 = std.fmt.parseInt(i32, database.getSetting("period_day", &day_buf) orelse "1", 10) catch 1;
    var payers_buf: [1024]u8 = undefined;
    const confirmed = database.getSetting("salary_payers", &payers_buf) orelse "";
    var rejected_buf: [1024]u8 = undefined;
    const rejected = database.getSetting("salary_rejected", &rejected_buf) orelse "";

    const n_inc = loadIncomes(database);
    const incomes = income_store[0..n_inc];

    var payers: [MAX_PAYERS]Payer = undefined;
    const n_payers = collectPayers(incomes, today, &payers);

    // The salary: what the user confirmed, else the best monthly candidate.
    var events: [MAX_EVENTS]Event = undefined;
    var n_events: usize = 0;
    var is_confirmed = false;
    var cand: ?Payer = null;
    if (confirmed.len > 0) {
        n_events = eventsOf(incomes, confirmed, null, &events);
        is_confirmed = n_events > 0;
        // Title for the first confirmed payer still seen.
        for (payers[0..n_payers]) |p| if (lineIn(confirmed, p.key)) {
            cand = p;
            break;
        };
    }
    if (!is_confirmed) {
        for (payers[0..n_payers]) |p| {
            if (!p.monthly or p.median_cents < MIN_SALARY_CENTS or lineIn(rejected, p.key)) continue;
            cand = p;
            n_events = eventsOf(incomes, "", p.key, &events);
            break;
        }
    }
    const ev = events[0..n_events];
    const has_salary = n_events >= 2 or (is_confirmed and n_events >= 1);
    const mode: Mode = switch (chosen) {
        .salary => if (has_salary) .salary else .calendar,
        else => chosen,
    };

    var o = Out{ .buf = buf };
    o.s("{\"mode\":");
    o.str(@tagName(mode));
    o.s(",\"chosen\":");
    o.str(@tagName(chosen));
    o.s(",\"day\":");
    o.int(fixed_day);
    o.s(",\"today\":");
    o.date(today);

    var typical: i32 = 1;
    var next: i32 = 0;
    if (has_salary) {
        typical = typicalDay(ev);
        const last = ev[n_events - 1].jd;
        next = expectedAfter(last, typical);
        o.s(",\"salary\":{\"key\":");
        o.str(if (cand) |p| p.key else "");
        o.s(",\"title\":");
        o.str(if (cand) |p| p.title else "");
        o.s(",\"amount\":");
        o.amount(medianCents(ev));
        o.s(",\"day\":");
        o.int(typical);
        o.s(",\"count\":");
        o.int(@intCast(n_events));
        o.s(if (is_confirmed) ",\"confirmed\":true" else ",\"confirmed\":false");
        o.s(",\"last\":");
        o.date(last);
        o.s(",\"next\":");
        o.date(next);
        o.s(",\"overdue_days\":");
        o.int(@max(0, today - next));
        o.s("}");
    }

    // Periods, newest first.
    o.s(",\"periods\":[");
    var first = true;
    var written: u32 = 0;
    switch (mode) {
        .salary => {
            var i: usize = n_events;
            while (i > 0 and written < count) {
                i -= 1;
                const from = ev[i].jd;
                const current = i == n_events - 1;
                // The running period ends the day before the next salary; when it is
                // late, the period simply goes on until it arrives.
                const to = if (current) @max(next - 1, today) else ev[i + 1].jd - 1;
                const early: i32 = if (i > 0) @max(0, expectedAfter(ev[i - 1].jd, typical) - from) else 0;
                writePeriod(&o, &first, from, to, current, ev[i].cents, early);
                written += 1;
            }
        },
        .calendar, .day => {
            const sd: i32 = if (mode == .calendar) 1 else fixed_day;
            var p = fixedPeriod(fromJd(today), sd);
            while (written < count) : (written += 1) {
                writePeriod(&o, &first, p[0], p[1], written == 0, null, 0);
                p = fixedPeriod(fromJd(p[0] - 1), sd);
            }
        },
    }
    o.s("]");

    // Other incomes since the salary: they never start a period.
    o.s(",\"other_income\":[");
    if (has_salary) {
        const since = ev[n_events - 1].jd;
        var n: usize = 0;
        var i: usize = n_inc;
        first = true;
        while (i > 0 and n < 5) {
            i -= 1;
            const inc = &incomes[i];
            if (inc.jd < since) break;
            const k = inc.keySlice();
            const is_salary = if (is_confirmed) lineIn(confirmed, k) else (cand != null and std.mem.eql(u8, cand.?.key, k));
            if (is_salary) continue;
            if (!first) o.s(",");
            first = false;
            o.s("{\"id\":");
            o.str(&inc.id);
            o.s(",\"date\":");
            o.date(inc.jd);
            o.s(",\"amount\":");
            o.amount(inc.cents);
            o.s(",\"title\":");
            o.str(inc.titleSlice());
            o.s(",\"key\":");
            o.str(k);
            o.s("}");
            n += 1;
        }
    }
    o.s("]");

    // Payers to choose from ("Gehalt selbst auswählen").
    o.s(",\"payers\":[");
    first = true;
    var shown: usize = 0;
    for (payers[0..n_payers]) |p| {
        if (shown == 6) break;
        if (!first) o.s(",");
        first = false;
        o.s("{\"key\":");
        o.str(p.key);
        o.s(",\"title\":");
        o.str(p.title);
        o.s(",\"amount\":");
        o.amount(p.median_cents);
        o.s(",\"count\":");
        o.int(p.count);
        o.s(",\"last\":");
        o.date(p.last_jd);
        o.s("}");
        shown += 1;
    }
    o.s("]}");
    return if (o.ok) o.pos else null;
}

/// "Ist das dein Gehalt?": 1 = yes (adds the payer), 0 = no (never asked
/// again), 2 = this payer only ("Ändern" / "Gehalt selbst auswählen").
pub fn answerSalary(database: *Db, key: []const u8, answer: u8) db_mod.DbError!void {
    var buf: [1024]u8 = undefined;
    var out: [1100]u8 = undefined;
    const name = if (answer == 0) "salary_rejected" else "salary_payers";
    const current = if (answer == 2) "" else (database.getSetting(name, &buf) orelse "");
    if (lineIn(current, key)) return;
    // Oldest entries drop off when the list gets long.
    var keep = current;
    while (keep.len + key.len + 1 > 1000) {
        const nl = std.mem.indexOfScalar(u8, keep, '\n') orelse break;
        keep = keep[nl + 1 ..];
    }
    const v = std.fmt.bufPrint(&out, "{s}{s}{s}", .{ keep, if (keep.len > 0) "\n" else "", key }) catch return db_mod.DbError.ExecFailed;
    try database.setSetting(name, v);
    // A "yes" takes the payer off the rejected list.
    if (answer != 0) {
        var rb: [1024]u8 = undefined;
        const rej = database.getSetting("salary_rejected", &rb) orelse "";
        if (lineIn(rej, key)) {
            var nb: [1024]u8 = undefined;
            var w: usize = 0;
            var it = std.mem.splitScalar(u8, rej, '\n');
            while (it.next()) |l| {
                if (l.len == 0 or std.mem.eql(u8, l, key)) continue;
                if (w > 0) {
                    nb[w] = '\n';
                    w += 1;
                }
                @memcpy(nb[w .. w + l.len], l);
                w += l.len;
            }
            try database.setSetting("salary_rejected", nb[0..w]);
        }
    }
}

// --- Tests -----------------------------------------------------------------

fn testDb() !Db {
    var db = try Db.init(":memory:");
    db.exec("DELETE FROM rules;") catch {};
    return db;
}

var test_seq: u32 = 0;

fn addTx(db: *Db, ymd: []const u8, desc: []const u8, cents: i64) !void {
    var sql: [512]u8 = undefined;
    test_seq += 1;
    const q = try std.fmt.bufPrintSentinel(&sql, "INSERT INTO transactions (id, date_year, date_month, date_day, description, amount_cents) VALUES ('{d:0>32}', {s}, {s}, {s}, '{s}', {d});", .{ test_seq, ymd[0..4], ymd[5..7], ymd[8..10], desc, cents }, 0);
    try db.exec(q);
}

fn periods(db: *Db, today: u32) ![]const u8 {
    const S = struct {
        var buf: [16384]u8 = undefined;
    };
    const n = periodsJson(db, today, 4, &S.buf) orelse return error.TestUnexpectedResult;
    return S.buf[0..n];
}

fn has(json: []const u8, part: []const u8) !void {
    if (std.mem.indexOf(u8, json, part) == null) {
        std.debug.print("missing {s} in\n{s}\n", .{ part, json });
        return error.TestUnexpectedResult;
    }
}

test "calendar is the default and unchanged" {
    var db = try testDb();
    defer db.close();
    const j = try periods(&db, 20261114);
    try has(j, "\"mode\":\"calendar\",\"chosen\":\"calendar\"");
    try has(j, "{\"from\":\"2026-11-01\",\"to\":\"2026-11-30\",\"days\":30,\"current\":true");
    try has(j, "{\"from\":\"2026-10-01\",\"to\":\"2026-10-31\",\"days\":31,\"current\":false");
}

test "fester Tag: the 15th to the 14th" {
    var db = try testDb();
    defer db.close();
    try db.setSetting("period_mode", "day");
    try db.setSetting("period_day", "15");
    const j = try periods(&db, 20261114);
    try has(j, "{\"from\":\"2026-10-15\",\"to\":\"2026-11-14\",\"days\":31,\"current\":true");
    try has(j, "{\"from\":\"2026-09-15\",\"to\":\"2026-10-14\"");
    const k = try periods(&db, 20261115);
    try has(k, "{\"from\":\"2026-11-15\",\"to\":\"2026-12-14\"");
}

test "salary not yet detected with one salary: calendar, no candidate" {
    var db = try testDb();
    defer db.close();
    try db.setSetting("period_mode", "salary");
    try addTx(&db, "2026-10-27", "MUSTER GMBH GEHALT", 284000);
    const j = try periods(&db, 20261114);
    try has(j, "\"mode\":\"calendar\",\"chosen\":\"salary\"");
    try std.testing.expect(std.mem.indexOf(u8, j, "\"salary\":{") == null);
}

test "salary to salary, a refund does not start a period, salary early" {
    var db = try testDb();
    defer db.close();
    try addTx(&db, "2026-08-27", "MUSTER GMBH GEHALT", 284000);
    try addTx(&db, "2026-09-26", "MUSTER GMBH GEHALT", 284000);
    try addTx(&db, "2026-10-27", "MUSTER GMBH GEHALT", 284000);
    try addTx(&db, "2026-11-03", "MUSTERVERSAND ERSTATTUNG", 4990);
    try addTx(&db, "2026-11-05", "SUPERMARKT", -4815);

    // Detected but not chosen yet: calendar periods, the candidate is offered.
    var j = try periods(&db, 20261114);
    try has(j, "\"mode\":\"calendar\"");
    try has(j, "\"salary\":{\"key\":\"MUSTER GMBH GEHALT\",\"title\":\"MUSTER GMBH GEHALT\",\"amount\":2840.00,\"day\":27,\"count\":3,\"confirmed\":false,\"last\":\"2026-10-27\",\"next\":\"2026-11-27\",\"overdue_days\":0}");

    try db.setSetting("period_mode", "salary");
    try answerSalary(&db, "MUSTER GMBH GEHALT", 1);
    j = try periods(&db, 20261114);
    try has(j, "\"mode\":\"salary\"");
    try has(j, "\"confirmed\":true");
    try has(j, "{\"from\":\"2026-10-27\",\"to\":\"2026-11-26\",\"days\":31,\"current\":true,\"salary\":2840.00,\"early_days\":0}");
    try has(j, "{\"from\":\"2026-09-26\",\"to\":\"2026-10-26\",\"days\":31,\"current\":false,\"salary\":2840.00,\"early_days\":1}");
    try has(j, "\"other_income\":[{\"id\":");
    try has(j, "\"title\":\"MUSTERVERSAND ERSTATTUNG\"");

    // Salary three days early: the old period ends, the new one starts that day.
    try addTx(&db, "2026-11-24", "MUSTER GMBH GEHALT", 284000);
    j = try periods(&db, 20261124);
    try has(j, "{\"from\":\"2026-11-24\",\"to\":\"2026-12-26\",\"days\":33,\"current\":true,\"salary\":2840.00,\"early_days\":3}");
    try has(j, "{\"from\":\"2026-10-27\",\"to\":\"2026-11-23\",\"days\":28,\"current\":false");
    try has(j, "\"other_income\":[]");
}

test "salary overdue: the period goes on until it arrives" {
    var db = try testDb();
    defer db.close();
    try db.setSetting("period_mode", "salary");
    try addTx(&db, "2026-09-27", "MUSTER GMBH GEHALT", 284000);
    try addTx(&db, "2026-10-27", "MUSTER GMBH GEHALT", 284000);
    const j = try periods(&db, 20261130);
    try has(j, "\"overdue_days\":3");
    try has(j, "{\"from\":\"2026-10-27\",\"to\":\"2026-11-30\",\"days\":35,\"current\":true");
}

test "Nein: a rejected payer is not offered again; another can be picked" {
    var db = try testDb();
    defer db.close();
    try addTx(&db, "2026-09-27", "MUSTER GMBH GEHALT", 284000);
    try addTx(&db, "2026-10-27", "MUSTER GMBH GEHALT", 284000);
    try addTx(&db, "2026-10-01", "NEBENJOB MUSTER", 50000);
    try addTx(&db, "2026-11-01", "NEBENJOB MUSTER", 50000);
    try answerSalary(&db, "MUSTER GMBH GEHALT", 0);
    var j = try periods(&db, 20261114);
    try has(j, "\"salary\":{\"key\":\"NEBENJOB MUSTER\"");
    try answerSalary(&db, "MUSTER GMBH GEHALT", 2);
    j = try periods(&db, 20261114);
    try has(j, "\"salary\":{\"key\":\"MUSTER GMBH GEHALT\"");
    try has(j, "\"confirmed\":true");
    var rb: [1024]u8 = undefined;
    try std.testing.expectEqualStrings("", db.getSetting("salary_rejected", &rb).?);
}

test "expectedAfter clamps to short months" {
    const last = jd(.{ .year = 2027, .month = 1, .day = 31 });
    try std.testing.expectEqual(jd(.{ .year = 2027, .month = 2, .day = 28 }), expectedAfter(last, 31));
}
