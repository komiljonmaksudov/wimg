const std = @import("std");
const dbg = @import("dbg.zig");
const builtin = @import("builtin");
const is_wasm = builtin.cpu.arch == .wasm32;
const banks_mod = if (!is_wasm) @import("banks.zig") else struct {
    pub const BankFamily = enum(u8) { standard = 0, deutsche_bank = 1, postbank = 2, norisbank = 3 };
};

pub const FintsError = error{
    BufferTooSmall,
    InvalidResponse,
    AuthFailed,
    TanRequired,
    DialogFailed,
    ProtocolError,
    InvalidSegment,
};

/// FinTS 3.0 session state. Tracks dialog lifecycle and TAN flow.
pub const FintsSession = struct {
    blz: [8]u8,
    url: [128]u8,
    url_len: u8,
    user_id: [64]u8,
    user_id_len: u8,
    account_ktv: [96]u8, // Kontoverbindung (Ktonr:Unterkonto:280:BLZ) from HIUPD
    account_ktv_len: u8,
    pin: [64]u8,
    pin_len: u8,

    system_id: [32]u8,
    system_id_len: u8,
    dialog_id: [32]u8,
    dialog_id_len: u8,

    msg_num: u16,
    product_id: [25]u8,
    product_id_len: u8,
    bpd_version: u16,
    upd_version: u16,

    hitan_version: u8,
    hikaz_version: u8,
    supports_camt: bool,
    camt_format: [128]u8,
    camt_format_len: u8,
    // Selected TAN security function (e.g. "902" for photoTAN, "901" for mobileTAN)
    tan_sec_func: [4]u8,
    tan_sec_func_len: u8,
    tan_medium_name: [32]u8,
    tan_medium_name_len: u8,
    tan_description_required: u8, // 0=must_not, 1=may, 2=must
    tan_supported_media_number: u8,
    tan_medium_required: bool,
    tan_response_hhd_uc_required: bool,
    decoupled_max_poll_number: u8,
    wait_before_first_poll: u8,
    wait_before_next_poll: u8,
    automated_polling_allowed: bool,
    challenge: [512]u8,
    challenge_len: u16,
    challenge_hhduc: [8192]u8, // photoTAN PNG image (Base64 or binary)
    challenge_hhduc_len: u16,
    challenge_ref: [32]u8,
    challenge_ref_len: u8,

    has_pending_tan: bool,
    has_active_dialog: bool, // auth dialog is open (post-TAN)
    decoupled: bool,
    bank_family: banks_mod.BankFamily,

    pub fn init(blz: []const u8, url: []const u8, user_id: []const u8, pin: []const u8) FintsSession {
        var s: FintsSession = undefined;
        @memset(&s.blz, '0');
        @memset(&s.url, 0);
        @memset(&s.user_id, 0);
        @memset(&s.account_ktv, 0);
        @memset(&s.pin, 0);
        @memset(&s.system_id, 0);
        @memset(&s.dialog_id, 0);
        @memset(&s.product_id, 0);
        @memset(&s.tan_medium_name, 0);
        @memset(&s.challenge, 0);
        @memset(&s.challenge_hhduc, 0);
        @memset(&s.challenge_ref, 0);

        const blz_len = @min(blz.len, 8);
        @memcpy(s.blz[0..blz_len], blz[0..blz_len]);

        const url_len = @min(url.len, 128);
        @memcpy(s.url[0..url_len], url[0..url_len]);
        s.url_len = @intCast(url_len);

        const uid_len = @min(user_id.len, 64);
        @memcpy(s.user_id[0..uid_len], user_id[0..uid_len]);
        s.user_id_len = @intCast(uid_len);
        s.account_ktv_len = 0;

        const pin_l = @min(pin.len, 64);
        @memcpy(s.pin[0..pin_l], pin[0..pin_l]);
        s.pin_len = @intCast(pin_l);

        s.system_id_len = 1;
        s.system_id[0] = '0'; // initial system_id = "0"
        s.dialog_id_len = 1;
        s.dialog_id[0] = '0';
        s.msg_num = 1;
        // 0 = unknown; builders fall back to v6 until HITANS is parsed from BPD.
        s.hitan_version = 0;
        // HKKAZ defaults to v5 unless bank BPD advertises higher versions.
        s.hikaz_version = 5;
        s.supports_camt = false;
        @memset(&s.camt_format, 0);
        s.camt_format_len = 0;
        // Start in one-step mode (999). Upgrade to two-step after parsing bank capabilities.
        @memcpy(s.tan_sec_func[0..3], "999");
        s.tan_sec_func_len = 3;
        s.tan_medium_name_len = 0;
        s.tan_description_required = 0;
        s.tan_supported_media_number = 0;
        s.tan_medium_required = false;
        s.tan_response_hhd_uc_required = false;
        // Reasonable defaults if bank does not publish decoupled timings.
        s.decoupled_max_poll_number = 10;
        s.wait_before_first_poll = 4;
        s.wait_before_next_poll = 2;
        s.automated_polling_allowed = true;
        s.has_pending_tan = false;
        s.has_active_dialog = false;
        s.decoupled = false;
        s.bank_family = if (!is_wasm) banks_mod.detectBankFamily(url) else .standard;
        s.challenge_len = 0;
        s.challenge_hhduc_len = 0;
        s.challenge_ref_len = 0;
        s.product_id_len = 0;
        s.bpd_version = 0;
        s.upd_version = 0;

        return s;
    }

    pub fn urlSlice(self: *const FintsSession) []const u8 {
        return self.url[0..self.url_len];
    }

    pub fn userIdSlice(self: *const FintsSession) []const u8 {
        return self.user_id[0..self.user_id_len];
    }

    pub fn pinSlice(self: *const FintsSession) []const u8 {
        return self.pin[0..self.pin_len];
    }

    pub fn accountKtvSlice(self: *const FintsSession) []const u8 {
        return self.account_ktv[0..self.account_ktv_len];
    }

    pub fn systemIdSlice(self: *const FintsSession) []const u8 {
        return self.system_id[0..self.system_id_len];
    }

    pub fn dialogIdSlice(self: *const FintsSession) []const u8 {
        return self.dialog_id[0..self.dialog_id_len];
    }

    pub fn productIdSlice(self: *const FintsSession) []const u8 {
        return self.product_id[0..self.product_id_len];
    }

    pub fn tanSecFuncSlice(self: *const FintsSession) []const u8 {
        return self.tan_sec_func[0..self.tan_sec_func_len];
    }

    pub fn camtFormatSlice(self: *const FintsSession) []const u8 {
        return self.camt_format[0..self.camt_format_len];
    }

    pub fn clearPin(self: *FintsSession) void {
        @memset(&self.pin, 0);
        self.pin_len = 0;
    }

    /// Reset dialog state for a new dialog (keeps credentials + product_id).
    pub fn resetDialog(self: *FintsSession) void {
        self.dialog_id_len = 1;
        self.dialog_id[0] = '0';
        self.msg_num = 1;
        self.has_pending_tan = false;
        self.has_active_dialog = false;
        self.decoupled = false;
        self.challenge_len = 0;
        self.challenge_hhduc_len = 0;
        self.challenge_ref_len = 0;
    }
};

/// FinTS response code.
pub const ResponseCode = struct {
    code: [4]u8,
    reference: [7]u8,
    reference_len: u8,
    text: [128]u8,
    text_len: u8,
    parameter: [64]u8,
    parameter_len: u8,

    pub fn codeSlice(self: *const ResponseCode) []const u8 {
        return &self.code;
    }

    pub fn textSlice(self: *const ResponseCode) []const u8 {
        return self.text[0..self.text_len];
    }

    pub fn referenceSlice(self: *const ResponseCode) []const u8 {
        return self.reference[0..self.reference_len];
    }

    pub fn parameterSlice(self: *const ResponseCode) []const u8 {
        return self.parameter[0..self.parameter_len];
    }

    pub fn isSuccess(self: *const ResponseCode) bool {
        return self.code[0] == '0'; // 0xxx = success
    }

    pub fn isTanRequired(self: *const ResponseCode) bool {
        return std.mem.eql(u8, &self.code, "0030") or std.mem.eql(u8, &self.code, "3920");
    }

    pub fn isError(self: *const ResponseCode) bool {
        return self.code[0] == '9'; // 9xxx = error
    }
};

/// Parsed response from a FinTS message exchange.
pub const ParsedResponse = struct {
    codes: [16]ResponseCode,
    code_count: u8,
    dialog_id: [32]u8,
    dialog_id_len: u8,
    system_id: [32]u8,
    system_id_len: u8,
    mt940_data: [32768]u8, // up to 32 KB of MT940 data
    mt940_len: u16,
    camt_data: [65536]u8, // up to 64 KB of CAMT XML data
    camt_len: u16,
    challenge: [512]u8,
    challenge_len: u16,
    challenge_hhduc: [8192]u8, // photoTAN image data
    challenge_hhduc_len: u16,
    challenge_ref: [32]u8,
    challenge_ref_len: u8,
    has_tan_request: bool,
    decoupled: bool,
    tan_media: [8]TanMedium,
    tan_media_count: u8,

    pub fn init() ParsedResponse {
        var r: ParsedResponse = undefined;
        r.code_count = 0;
        r.dialog_id_len = 0;
        r.system_id_len = 0;
        r.mt940_len = 0;
        r.camt_len = 0;
        r.challenge_len = 0;
        r.challenge_hhduc_len = 0;
        r.challenge_ref_len = 0;
        r.has_tan_request = false;
        r.decoupled = false;
        r.tan_media_count = 0;
        @memset(&r.mt940_data, 0);
        @memset(&r.camt_data, 0);
        @memset(&r.dialog_id, 0);
        @memset(&r.system_id, 0);
        @memset(&r.challenge, 0);
        @memset(&r.challenge_ref, 0);
        return r;
    }

    pub fn hasError(self: *const ParsedResponse) bool {
        for (self.codes[0..self.code_count]) |*c| {
            if (c.isError()) return true;
        }
        return false;
    }
};

fn clampHktanVersion(v: u8) u8 {
    return switch (v) {
        2, 3, 5, 6, 7 => v,
        else => 6,
    };
}

fn clampHikazVersion(v: u8) u8 {
    return switch (v) {
        5, 6, 7 => v,
        else => 5,
    };
}

fn buildHktanProcess4(session: *const FintsSession, buf: []u8, offset: usize, num: u16, segment_ref: []const u8) ?usize {
    const hktan_ver = clampHktanVersion(session.hitan_version);
    return switch (hktan_ver) {
        // v2/v3 do not carry segment_type
        2 => writeSegment(buf, offset, "HKTAN", num, 2, &.{
            "4",
        }),
        3 => writeSegment(buf, offset, "HKTAN", num, 3, &.{
            "4",
        }),
        // v5+ carry segment_type and optional fields afterwards
        5 => writeSegment(buf, offset, "HKTAN", num, 5, &.{
            "4",
            segment_ref,
        }),
        6, 7 => writeHktanProcess4V6Like(session, buf, offset, num, hktan_ver, segment_ref),
        else => null,
    };
}

fn writeHktanProcess4V6Like(session: *const FintsSession, buf: []u8, offset: usize, num: u16, ver: u8, segment_ref: []const u8) ?usize {
    var pos: usize = offset;
    if (buf.len - pos < 128) return null;

    // Manual writer to preserve DEG delimiters (:) for parameter_challenge_class.
    const prefix = "HKTAN:";
    @memcpy(buf[pos .. pos + prefix.len], prefix);
    pos += prefix.len;
    pos += writeUint(buf[pos..], num) orelse return null;
    buf[pos] = ':';
    pos += 1;
    pos += writeUint(buf[pos..], ver) orelse return null;

    // de1 tan_process
    buf[pos] = '+';
    pos += 1;
    buf[pos] = '4';
    pos += 1;
    // de2 segment_type
    buf[pos] = '+';
    pos += 1;
    @memcpy(buf[pos .. pos + segment_ref.len], segment_ref);
    pos += segment_ref.len;

    // de3..de9 empty optional fields
    for (0..7) |_| {
        buf[pos] = '+';
        pos += 1;
    }

    // de10 parameter_challenge_class (DEG).
    // For HKTAN v6/v7 process-4, strict banks expect an explicit empty DEG (":").
    buf[pos] = '+';
    pos += 1;
    buf[pos] = ':';
    pos += 1;

    // de11 tan_medium_name: python-fints sends this for process 4 when required.
    if (session.tan_medium_name_len > 0 or session.tan_medium_required) {
        buf[pos] = '+';
        pos += 1;
        if (session.tan_medium_name_len > 0) {
            const tm = session.tan_medium_name[0..session.tan_medium_name_len];
            pos += escapeFintsValue(buf[pos..], tm) orelse return null;
        }
    }

    // Segment terminator
    buf[pos] = '\'';
    pos += 1;
    return pos - offset;
}

fn buildHktanProcessSubmit(session: *const FintsSession, tan_process: []const u8, buf: []u8, offset: usize, num: u16, task_ref: []const u8) ?usize {
    const hktan_ver = clampHktanVersion(session.hitan_version);
    return switch (hktan_ver) {
        // v2/v3: set task_reference and further_tan_follows=false ("N") like python-fints
        2 => writeSegment(buf, offset, "HKTAN", num, 2, &.{
            tan_process, // tan_process ("2" submit or "S" decoupled status)
            "", // task_hash_value
            task_ref, // task_reference
            "", // tan_list_number
            "N", // further_tan_follows
        }),
        3 => writeSegment(buf, offset, "HKTAN", num, 3, &.{
            tan_process,
            "", // task_hash_value
            task_ref,
            "", // tan_list_number
            "N", // further_tan_follows
        }),
        // v5 includes tan_list_number between task_reference and further_tan_follows
        5 => writeSegment(buf, offset, "HKTAN", num, 5, &.{
            tan_process, // tan_process ("2" submit or "S" decoupled status)
            "", // segment_type
            "", // account
            "", // task_hash_value
            task_ref, // task_reference
            "", // tan_list_number
            "N", // further_tan_follows
        }),
        // v6/v7: no tan_list_number, but same process semantics
        6, 7 => writeSegment(buf, offset, "HKTAN", num, hktan_ver, &.{
            tan_process, // tan_process ("2" submit or "S" decoupled status)
            "", // segment_type
            "", // account
            "", // task_hash_value
            task_ref, // task_reference
            "N", // further_tan_follows
        }),
        else => null,
    };
}

fn fillCurrentDateTime(date_buf: *[8]u8, time_buf: *[6]u8) void {
    if (is_wasm) {
        @memcpy(date_buf[0..8], "19700101");
        @memcpy(time_buf[0..6], "000000");
        return;
    }

    var tv: std.c.timeval = undefined;
    _ = std.c.gettimeofday(&tv, null);
    const now_secs: i64 = tv.sec;
    const epoch_secs = std.time.epoch.EpochSeconds{ .secs = @intCast(@max(now_secs, 0)) };
    const epoch_day = epoch_secs.getEpochDay();
    const day_secs = epoch_secs.getDaySeconds();
    const yd = epoch_day.calculateYearDay();
    const md = yd.calculateMonthDay();

    writeFixedWidthUnsigned(date_buf[0..4], yd.year);
    writeFixedWidthUnsigned(date_buf[4..6], md.month.numeric());
    writeFixedWidthUnsigned(date_buf[6..8], @as(u6, md.day_index) + 1);

    writeFixedWidthUnsigned(time_buf[0..2], day_secs.getHoursIntoDay());
    writeFixedWidthUnsigned(time_buf[2..4], day_secs.getMinutesIntoHour());
    writeFixedWidthUnsigned(time_buf[4..6], day_secs.getSecondsIntoMinute());
}

fn writeFixedWidthUnsigned(buf: []u8, value: anytype) void {
    var n: u64 = @intCast(value);
    var i: usize = buf.len;
    while (i > 0) {
        i -= 1;
        buf[i] = @intCast('0' + (n % 10));
        n /= 10;
    }
}

fn generateSecurityReference(out: *[7]u8) []const u8 {
    var tv: std.c.timeval = undefined;
    _ = std.c.gettimeofday(&tv, null);
    const seed: u64 = @as(u64, @bitCast(@as(i64, tv.sec))) ^
        (@as(u64, @bitCast(@as(i64, tv.usec))) << 20);
    var prng = std.Random.DefaultPrng.init(seed);
    const n = prng.random().intRangeAtMost(u32, 1_000_000, 9_999_999);
    writeFixedWidthUnsigned(out[0..7], n);
    return out[0..7];
}

// ============================================================
// Message Building
// ============================================================

/// Build anonymous initialization message (no credentials).
/// Used to fetch BPD (bank parameter data).
pub fn buildAnonInit(session: *const FintsSession, buf: []u8) ?usize {
    var inner_buf: [4096]u8 = undefined;
    var inner_pos: usize = 0;

    // HKIDN — Identification (anonymous: user_id=9999999999 per FinTS spec, system_id=0)
    // Kreditinstitutskennung is a DEG: 280:BLZ (colon must NOT be escaped)
    // Segment numbers start at 2 (1 = HNHBK, no security envelope in anonymous mode)
    inner_pos += writeHkidn(&inner_buf, inner_pos, 2, &session.blz, "9999999999", "0", "0") orelse return null;

    // HKVVB — BPD request
    inner_pos += writeSegment(&inner_buf, inner_pos, "HKVVB", 3, 3, &.{
        "0", // BPD version unknown in anonymous bootstrap
        "0", // UPD version unknown in anonymous bootstrap
        "1", // language DE
        session.productIdSlice(),
        "5.0.0", // python-fints product version
    }) orelse return null;

    return writeEnvelope(session, buf, inner_buf[0..inner_pos]);
}

/// Build anonymous initialization wrapped in HNVSK/HNVSD security envelope.
/// Required by Deutsche Bank, Postbank, and norisbank which reject bare anonymous init with 9110.
/// Uses dummy encryption (PIN:1, sec_func=998), user_id=9999999999, system_id=0.
pub fn buildAnonInitWithEnvelope(session: *const FintsSession, buf: []u8) ?usize {
    var inner_buf: [4096]u8 = undefined;
    var inner_pos: usize = 0;

    // HKIDN — anonymous identification inside envelope (seg 3, after HNVSK=998 and HNVSD=999)
    inner_pos += writeHkidn(&inner_buf, inner_pos, 3, &session.blz, "9999999999", "0", "0") orelse return null;

    // HKVVB — BPD request
    inner_pos += writeSegment(&inner_buf, inner_pos, "HKVVB", 4, 3, &.{
        "0",
        "0",
        "1",
        session.productIdSlice(),
        "5.0.0",
    }) orelse return null;

    // Wrap in HNVSK/HNVSD envelope using sec_func=998 (dummy encryption for anonymous)
    // Uses "9999999999" as user_id in key_name, system_id=0
    return writeAnonAuthEnvelope(session, buf, inner_buf[0..inner_pos], 4);
}

/// Write HNVSK/HNVSD envelope for anonymous init (no real credentials).
/// Similar to writeAuthEnvelope but uses anonymous identifiers.
fn writeAnonAuthEnvelope(session: *const FintsSession, buf: []u8, inner: []const u8, last_inner_seg: u16) ?usize {
    var sec_buf: [8192]u8 = undefined;
    var sec_pos: usize = 0;

    // HNVSK:998:3 — dummy encryption header for anonymous mode
    var hnvsk_buf: [256]u8 = undefined;
    var vsk_pos: usize = 0;

    const vsk_h1 = "HNVSK:998:3+PIN:1+998+1+2::0+1:";
    @memcpy(hnvsk_buf[vsk_pos .. vsk_pos + vsk_h1.len], vsk_h1);
    vsk_pos += vsk_h1.len;

    var date_buf: [8]u8 = undefined;
    var time_buf: [6]u8 = undefined;
    fillCurrentDateTime(&date_buf, &time_buf);

    @memcpy(hnvsk_buf[vsk_pos .. vsk_pos + 8], &date_buf);
    vsk_pos += 8;
    hnvsk_buf[vsk_pos] = ':';
    vsk_pos += 1;
    @memcpy(hnvsk_buf[vsk_pos .. vsk_pos + 6], &time_buf);
    vsk_pos += 6;
    const vsk_enc = "+2:2:13:@8@";
    @memcpy(hnvsk_buf[vsk_pos .. vsk_pos + vsk_enc.len], vsk_enc);
    vsk_pos += vsk_enc.len;

    // 8 null bytes (dummy encryption key)
    @memset(hnvsk_buf[vsk_pos .. vsk_pos + 8], 0);
    vsk_pos += 8;

    // Key name with anonymous user_id
    const vsk_key = ":5:1+280:";
    @memcpy(hnvsk_buf[vsk_pos .. vsk_pos + vsk_key.len], vsk_key);
    vsk_pos += vsk_key.len;
    @memcpy(hnvsk_buf[vsk_pos .. vsk_pos + 8], &session.blz);
    vsk_pos += 8;
    const vsk_anon_suffix = ":9999999999:V:0:0+0'";
    @memcpy(hnvsk_buf[vsk_pos .. vsk_pos + vsk_anon_suffix.len], vsk_anon_suffix);
    vsk_pos += vsk_anon_suffix.len;

    @memcpy(sec_buf[sec_pos .. sec_pos + vsk_pos], hnvsk_buf[0..vsk_pos]);
    sec_pos += vsk_pos;

    // HNVSD:999:1+@len@inner_data'
    const hnvsd_prefix = "HNVSD:999:1+@";
    @memcpy(sec_buf[sec_pos .. sec_pos + hnvsd_prefix.len], hnvsd_prefix);
    sec_pos += hnvsd_prefix.len;

    sec_pos += writeUint(sec_buf[sec_pos..], @intCast(inner.len)) orelse return null;

    sec_buf[sec_pos] = '@';
    sec_pos += 1;

    if (sec_pos + inner.len + 1 >= sec_buf.len) return null;
    @memcpy(sec_buf[sec_pos .. sec_pos + inner.len], inner);
    sec_pos += inner.len;

    sec_buf[sec_pos] = '\'';
    sec_pos += 1;

    return writeEnvelopeWithNum(session, buf, sec_buf[0..sec_pos], last_inner_seg + 1);
}

/// Build synchronization dialog init (sec_func=999, HKSYN to get system_id).
/// Used as first step in connect — fetches BPD and system_id.
pub fn buildSyncInit(session: *const FintsSession, buf: []u8) ?usize {
    var inner_buf: [4096]u8 = undefined;
    var inner_pos: usize = 0;

    var sec_ref_buf: [7]u8 = undefined;
    const sec_ref = generateSecurityReference(&sec_ref_buf);

    // HNSHK — sec_func=999 (one-step, allowed for sync only)
    inner_pos += writeSignatureHeader(&inner_buf, inner_pos, 2, session, sec_ref, "999") orelse return null;

    // HKIDN — Identification (system_id=0 for sync)
    inner_pos += writeHkidn(&inner_buf, inner_pos, 3, &session.blz, session.userIdSlice(), "0", "1") orelse return null;

    // HKVVB — BPD request
    inner_pos += writeSegment(&inner_buf, inner_pos, "HKVVB", 4, 3, &.{
        if (session.bpd_version == 0) "0" else blk: {
            var b: [8]u8 = undefined;
            const l = writeUint(&b, session.bpd_version) orelse return null;
            break :blk b[0..l];
        },
        if (session.upd_version == 0) "0" else blk: {
            var b: [8]u8 = undefined;
            const l = writeUint(&b, session.upd_version) orelse return null;
            break :blk b[0..l];
        },
        "1", // dialog language = DE (python-fints Language2.DE)
        session.productIdSlice(),
        "5.0.0", // python-fints product version
    }) orelse return null;

    // HKSYN — Synchronization (mode 0 = new system ID)
    inner_pos += writeSegment(&inner_buf, inner_pos, "HKSYN", 5, 3, &.{
        "0",
    }) orelse return null;

    // HNSHA — Signature footer (contains PIN)
    inner_pos += writeSignatureFooter(&inner_buf, inner_pos, 6, sec_ref, session.pinSlice(), "") orelse return null;

    return writeAuthEnvelope(session, "999", buf, inner_buf[0..inner_pos], 6);
}

/// Build authenticated initialization message for business dialogs.
/// Uses real TAN security function (e.g. 902 for photoTAN).
pub fn buildAuthInit(session: *const FintsSession, buf: []u8) ?usize {
    var inner_buf: [4096]u8 = undefined;
    var inner_pos: usize = 0;

    var sec_ref_buf: [7]u8 = undefined;
    const sec_ref = generateSecurityReference(&sec_ref_buf);
    const sec_func = session.tanSecFuncSlice();

    // HNSHK — with real TAN method
    inner_pos += writeSignatureHeader(&inner_buf, inner_pos, 2, session, sec_ref, sec_func) orelse return null;

    // HKIDN — Identification (with real system_id from sync)
    inner_pos += writeHkidn(&inner_buf, inner_pos, 3, &session.blz, session.userIdSlice(), session.systemIdSlice(), "1") orelse return null;

    // HKVVB — BPD request
    inner_pos += writeSegment(&inner_buf, inner_pos, "HKVVB", 4, 3, &.{
        if (session.bpd_version == 0) "0" else blk: {
            var b: [8]u8 = undefined;
            const l = writeUint(&b, session.bpd_version) orelse return null;
            break :blk b[0..l];
        },
        if (session.upd_version == 0) "0" else blk: {
            var b: [8]u8 = undefined;
            const l = writeUint(&b, session.upd_version) orelse return null;
            break :blk b[0..l];
        },
        "1", // dialog language = DE (python-fints Language2.DE)
        session.productIdSlice(),
        "5.0.0", // python-fints product version
    }) orelse return null;

    const is_one_step = std.mem.eql(u8, sec_func, "999");
    if (!is_one_step) {
        // HKTAN process-4 init for two-step auth flows.
        inner_pos += buildHktanProcess4(session, &inner_buf, inner_pos, 5, "HKIDN") orelse return null;

        // HNSHA — Signature footer (contains PIN)
        inner_pos += writeSignatureFooter(&inner_buf, inner_pos, 6, sec_ref, session.pinSlice(), "") orelse return null;
        return writeAuthEnvelope(session, sec_func, buf, inner_buf[0..inner_pos], 6);
    }

    // One-step init (python-fints bootstrap style) without HKTAN.
    inner_pos += writeSignatureFooter(&inner_buf, inner_pos, 5, sec_ref, session.pinSlice(), "") orelse return null;
    return writeAuthEnvelope(session, sec_func, buf, inner_buf[0..inner_pos], 5);
}

/// Build HKKAZ (fetch bank statements) message.
/// Uses HNVSK/HNVSD security envelope with PIN in HNSHA.
pub fn buildFetchStatements(session: *const FintsSession, from: []const u8, to: []const u8, touchdown: []const u8, buf: []u8) ?usize {
    var inner_buf: [4096]u8 = undefined;
    var inner_pos: usize = 0;

    var sec_ref_buf: [7]u8 = undefined;
    const sec_ref = generateSecurityReference(&sec_ref_buf);

    // HNSHK — Signature header (always seg 2 inside HNVSD)
    inner_pos += writeSignatureHeader(&inner_buf, inner_pos, 2, session, sec_ref, session.tanSecFuncSlice()) orelse return null;

    const hikaz_ver = clampHikazVersion(session.hikaz_version);

    // HKKAZ — Account statements MT940 (seg 3)
    // Kontoverbindung DEG = Ktonr:Unterkonto:Laenderkennung:BLZ
    var acct_buf: [128]u8 = undefined;
    var acct_pos: usize = 0;
    if (session.account_ktv_len > 0) {
        const ktv = session.accountKtvSlice();
        @memcpy(acct_buf[acct_pos .. acct_pos + ktv.len], ktv);
        acct_pos += ktv.len;
    } else {
        const uid = session.userIdSlice();
        @memcpy(acct_buf[acct_pos .. acct_pos + uid.len], uid);
        acct_pos += uid.len;
        const acct_suffix = ":0:280:";
        @memcpy(acct_buf[acct_pos .. acct_pos + acct_suffix.len], acct_suffix);
        acct_pos += acct_suffix.len;
        @memcpy(acct_buf[acct_pos .. acct_pos + 8], &session.blz);
        acct_pos += 8;
    }

    // Write HKKAZ manually (DEG colons must not be escaped).
    // v5(Account2)/v6(Account3): account:subaccount:280:BLZ
    // v7(KTI1): iban+bic+account+subaccount+280:BLZ
    var kaz_buf: [256]u8 = undefined;
    var kaz_pos: usize = 0;
    const kaz_header = switch (hikaz_ver) {
        6 => "HKKAZ:3:6+",
        7 => "HKKAZ:3:7+",
        else => "HKKAZ:3:5+",
    };
    @memcpy(kaz_buf[kaz_pos .. kaz_pos + kaz_header.len], kaz_header);
    kaz_pos += kaz_header.len;
    if (hikaz_ver == 7) {
        const ktv = acct_buf[0..acct_pos];
        if (splitAccountKtv(ktv)) |parts| {
            // We usually do not have IBAN/BIC in HIUPD yet, so keep both empty.
            @memcpy(kaz_buf[kaz_pos .. kaz_pos + 2], "++");
            kaz_pos += 2;
            @memcpy(kaz_buf[kaz_pos .. kaz_pos + parts.account.len], parts.account);
            kaz_pos += parts.account.len;
            kaz_buf[kaz_pos] = '+';
            kaz_pos += 1;
            @memcpy(kaz_buf[kaz_pos .. kaz_pos + parts.subaccount.len], parts.subaccount);
            kaz_pos += parts.subaccount.len;
            @memcpy(kaz_buf[kaz_pos .. kaz_pos + 5], "+280:");
            kaz_pos += 5;
            @memcpy(kaz_buf[kaz_pos .. kaz_pos + parts.blz.len], parts.blz);
            kaz_pos += parts.blz.len;
        } else {
            // Fallback if we cannot split account components.
            @memcpy(kaz_buf[kaz_pos .. kaz_pos + acct_pos], acct_buf[0..acct_pos]);
            kaz_pos += acct_pos;
        }
    } else {
        @memcpy(kaz_buf[kaz_pos .. kaz_pos + acct_pos], acct_buf[0..acct_pos]);
        kaz_pos += acct_pos;
    }
    @memcpy(kaz_buf[kaz_pos .. kaz_pos + 3], "+N+");
    kaz_pos += 3;
    @memcpy(kaz_buf[kaz_pos .. kaz_pos + from.len], from);
    kaz_pos += from.len;
    kaz_buf[kaz_pos] = '+';
    kaz_pos += 1;
    @memcpy(kaz_buf[kaz_pos .. kaz_pos + to.len], to);
    kaz_pos += to.len;
    if (touchdown.len > 0) {
        @memcpy(kaz_buf[kaz_pos .. kaz_pos + 2], "++");
        kaz_pos += 2;
        @memcpy(kaz_buf[kaz_pos .. kaz_pos + touchdown.len], touchdown);
        kaz_pos += touchdown.len;
        kaz_buf[kaz_pos] = '\'';
        kaz_pos += 1;
    } else {
        @memcpy(kaz_buf[kaz_pos .. kaz_pos + 3], "++'");
        kaz_pos += 3;
    }

    @memcpy(inner_buf[inner_pos .. inner_pos + kaz_pos], kaz_buf[0..kaz_pos]);
    inner_pos += kaz_pos;

    const is_one_step = std.mem.eql(u8, session.tanSecFuncSlice(), "999");
    if (!is_one_step) {
        // HKTAN process-4 for the concrete business segment (two-step methods only).
        inner_pos += buildHktanProcess4(session, &inner_buf, inner_pos, 4, "HKKAZ") orelse return null;
        // HNSHA (seg 5)
        inner_pos += writeSignatureFooter(&inner_buf, inner_pos, 5, sec_ref, session.pinSlice(), "") orelse return null;
        return writeAuthEnvelope(session, session.tanSecFuncSlice(), buf, inner_buf[0..inner_pos], 5);
    }

    // One-step mode does not use HKTAN around business segments.
    // Segment numbering: HNSHK=2, HKKAZ=3, HNSHA=4.
    inner_pos += writeSignatureFooter(&inner_buf, inner_pos, 4, sec_ref, session.pinSlice(), "") orelse return null;
    return writeAuthEnvelope(session, session.tanSecFuncSlice(), buf, inner_buf[0..inner_pos], 4);
}

/// Build HKCAZ (fetch bank statements CAMT XML) message.
/// Uses HNVSK/HNVSD security envelope with PIN in HNSHA.
pub fn buildFetchStatementsCamt(session: *const FintsSession, from: []const u8, to: []const u8, touchdown: []const u8, buf: []u8) ?usize {
    var inner_buf: [4096]u8 = undefined;
    var inner_pos: usize = 0;

    var sec_ref_buf: [7]u8 = undefined;
    const sec_ref = generateSecurityReference(&sec_ref_buf);

    // HNSHK — Signature header (always seg 2 inside HNVSD)
    inner_pos += writeSignatureHeader(&inner_buf, inner_pos, 2, session, sec_ref, session.tanSecFuncSlice()) orelse return null;

    // Account reference in KTI1-compatible shape.
    var acct_buf: [160]u8 = undefined;
    var acct_pos: usize = 0;
    if (session.account_ktv_len > 0) {
        if (splitAccountKtv(session.accountKtvSlice())) |parts| {
            @memcpy(acct_buf[acct_pos .. acct_pos + 2], "++");
            acct_pos += 2;
            @memcpy(acct_buf[acct_pos .. acct_pos + parts.account.len], parts.account);
            acct_pos += parts.account.len;
            acct_buf[acct_pos] = '+';
            acct_pos += 1;
            @memcpy(acct_buf[acct_pos .. acct_pos + parts.subaccount.len], parts.subaccount);
            acct_pos += parts.subaccount.len;
            @memcpy(acct_buf[acct_pos .. acct_pos + 5], "+280:");
            acct_pos += 5;
            @memcpy(acct_buf[acct_pos .. acct_pos + parts.blz.len], parts.blz);
            acct_pos += parts.blz.len;
        } else {
            // Fallback for malformed/unknown account data.
            @memcpy(acct_buf[acct_pos .. acct_pos + 2], "++");
            acct_pos += 2;
            const uid = session.userIdSlice();
            @memcpy(acct_buf[acct_pos .. acct_pos + uid.len], uid);
            acct_pos += uid.len;
            @memcpy(acct_buf[acct_pos .. acct_pos + 7], "+0+280:");
            acct_pos += 7;
            @memcpy(acct_buf[acct_pos .. acct_pos + 8], &session.blz);
            acct_pos += 8;
        }
    } else {
        @memcpy(acct_buf[acct_pos .. acct_pos + 2], "++");
        acct_pos += 2;
        const uid = session.userIdSlice();
        @memcpy(acct_buf[acct_pos .. acct_pos + uid.len], uid);
        acct_pos += uid.len;
        @memcpy(acct_buf[acct_pos .. acct_pos + 7], "+0+280:");
        acct_pos += 7;
        @memcpy(acct_buf[acct_pos .. acct_pos + 8], &session.blz);
        acct_pos += 8;
    }

    var camt_buf: [1024]u8 = undefined;
    var camt_pos: usize = 0;
    const header = "HKCAZ:3:1+";
    @memcpy(camt_buf[camt_pos .. camt_pos + header.len], header);
    camt_pos += header.len;
    @memcpy(camt_buf[camt_pos .. camt_pos + acct_pos], acct_buf[0..acct_pos]);
    camt_pos += acct_pos;

    // Supported CAMT message type list (DEG). Keep first supported format from HICAZS.
    camt_buf[camt_pos] = '+';
    camt_pos += 1;
    const default_fmt = "urn?:iso?:std?:iso?:20022?:tech?:xsd?:camt.052.001.02";
    const camt_fmt = if (session.camt_format_len > 0) session.camtFormatSlice() else default_fmt;
    @memcpy(camt_buf[camt_pos .. camt_pos + camt_fmt.len], camt_fmt);
    camt_pos += camt_fmt.len;

    @memcpy(camt_buf[camt_pos .. camt_pos + 3], "+N+");
    camt_pos += 3;
    @memcpy(camt_buf[camt_pos .. camt_pos + from.len], from);
    camt_pos += from.len;
    camt_buf[camt_pos] = '+';
    camt_pos += 1;
    @memcpy(camt_buf[camt_pos .. camt_pos + to.len], to);
    camt_pos += to.len;

    if (touchdown.len > 0) {
        @memcpy(camt_buf[camt_pos .. camt_pos + 2], "++");
        camt_pos += 2;
        @memcpy(camt_buf[camt_pos .. camt_pos + touchdown.len], touchdown);
        camt_pos += touchdown.len;
        camt_buf[camt_pos] = '\'';
        camt_pos += 1;
    } else {
        @memcpy(camt_buf[camt_pos .. camt_pos + 3], "++'");
        camt_pos += 3;
    }

    @memcpy(inner_buf[inner_pos .. inner_pos + camt_pos], camt_buf[0..camt_pos]);
    inner_pos += camt_pos;

    const is_one_step = std.mem.eql(u8, session.tanSecFuncSlice(), "999");
    if (!is_one_step) {
        // HKTAN process-4 for the concrete business segment (two-step methods only).
        inner_pos += buildHktanProcess4(session, &inner_buf, inner_pos, 4, "HKCAZ") orelse return null;
        // HNSHA (seg 5)
        inner_pos += writeSignatureFooter(&inner_buf, inner_pos, 5, sec_ref, session.pinSlice(), "") orelse return null;
        return writeAuthEnvelope(session, session.tanSecFuncSlice(), buf, inner_buf[0..inner_pos], 5);
    }

    // One-step mode does not use HKTAN around business segments.
    // Segment numbering: HNSHK=2, HKCAZ=3, HNSHA=4.
    inner_pos += writeSignatureFooter(&inner_buf, inner_pos, 4, sec_ref, session.pinSlice(), "") orelse return null;
    return writeAuthEnvelope(session, session.tanSecFuncSlice(), buf, inner_buf[0..inner_pos], 4);
}

/// Build HKTAB message to fetch available TAN media for the user.
/// The bank responds with HITAB containing TAN medium names.
/// HKTAB:seg:4+0+A' — request all TAN media, listing mode.
pub fn buildFetchTanMedia(session: *const FintsSession, buf: []u8) ?usize {
    var inner_buf: [4096]u8 = undefined;
    var inner_pos: usize = 0;

    var sec_ref_buf: [7]u8 = undefined;
    const sec_ref = generateSecurityReference(&sec_ref_buf);

    // HNSHK (seg 2)
    inner_pos += writeSignatureHeader(&inner_buf, inner_pos, 2, session, sec_ref, session.tanSecFuncSlice()) orelse return null;

    // HKTAB:3:4+0+A' — fetch all TAN media
    inner_pos += writeSegment(&inner_buf, inner_pos, "HKTAB", 3, 4, &.{
        "0", // tan_media_type: 0 = all
        "A", // tan_media_class: A = all
    }) orelse return null;

    // HNSHA (seg 4)
    inner_pos += writeSignatureFooter(&inner_buf, inner_pos, 4, sec_ref, session.pinSlice(), "") orelse return null;

    return writeAuthEnvelope(session, session.tanSecFuncSlice(), buf, inner_buf[0..inner_pos], 4);
}

/// TAN medium entry parsed from HITAB response.
pub const TanMedium = struct {
    name: [64]u8,
    name_len: u8,
    media_class: [16]u8, // "M" = mobileTAN, "P" = photoTAN, etc.
    media_class_len: u8,
    status: u8, // 1 = active, 0 = inactive

    pub fn nameSlice(self: *const TanMedium) []const u8 {
        return self.name[0..self.name_len];
    }
};

/// Parse HITAB segment to extract TAN media names.
/// Returns number of media found. Media written to out_media array.
pub fn parseHitab(segment: []const u8, out_media: []TanMedium) u8 {
    // HITAB:seg:ver+field1+field2+...
    // Each TAN medium is a colon-separated DEG within the segment body.
    // HITAB v4 format per field (after first '+'): tan_media_type : tan_media_class : status : ... : media_name : ...
    // The exact field positions vary by HITAB version. We look for name-like tokens.

    var count: u8 = 0;
    if (out_media.len == 0) return 0;

    // Skip segment header (everything before first '+')
    var pos: usize = 0;
    while (pos < segment.len and segment[pos] != '+') : (pos += 1) {}
    if (pos >= segment.len) return 0;
    pos += 1; // skip '+'

    // Parse fields separated by '+'
    while (pos < segment.len and count < out_media.len) {
        // Find end of this field
        var field_end = pos;
        while (field_end < segment.len and segment[field_end] != '+' and segment[field_end] != '\'') : (field_end += 1) {}

        const field = segment[pos..field_end];

        // Each TAN medium group is colon-separated. Look for groups that
        // contain a name (typically field index depends on HITAB version).
        // HITAB v4: the medium entries start at field index 1+.
        // Entry structure: media_class:status:card_number:card_seq:... :name:phone:...
        // We parse colon-separated tokens and pick the name heuristically.
        if (field.len > 3) {
            var media: TanMedium = undefined;
            @memset(&media.name, 0);
            @memset(&media.media_class, 0);
            media.name_len = 0;
            media.media_class_len = 0;
            media.status = 0;

            var tok_idx: u8 = 0;
            var tok_start: usize = 0;
            var best_name: ?[]const u8 = null;
            var cp: usize = 0;
            while (cp <= field.len) : (cp += 1) {
                if (cp == field.len or field[cp] == ':') {
                    const tok = field[tok_start..cp];
                    if (tok_idx == 0) {
                        // media_class (A=all, L=list, M=mobile, P=pushTAN, etc.)
                        const mc_len = @min(tok.len, media.media_class.len);
                        @memcpy(media.media_class[0..mc_len], tok[0..mc_len]);
                        media.media_class_len = @intCast(mc_len);
                    } else if (tok_idx == 1 and tok.len == 1 and tok[0] >= '0' and tok[0] <= '9') {
                        // status: 1=active
                        media.status = tok[0] - '0';
                    }

                    // Heuristic: the longest alphanumeric token with length >= 3
                    // that is not purely numeric is likely the medium name.
                    if (tok.len >= 3 and !isAllDigits(tok)) {
                        if (best_name == null or tok.len > best_name.?.len) {
                            best_name = tok;
                        }
                    }

                    tok_start = cp + 1;
                    tok_idx += 1;
                }
            }

            if (best_name) |name| {
                const n_len = @min(name.len, media.name.len);
                @memcpy(media.name[0..n_len], name[0..n_len]);
                media.name_len = @intCast(n_len);
                out_media[count] = media;
                count += 1;
            }
        }

        pos = field_end;
        if (pos < segment.len) pos += 1; // skip '+' or '\''
    }

    return count;
}

fn isAllDigits(s: []const u8) bool {
    for (s) |c| {
        if (c < '0' or c > '9') return false;
    }
    return true;
}

/// Build TAN submission message.
/// Uses HNVSK/HNVSD security envelope.
pub fn buildTanResponse(session: *const FintsSession, tan: []const u8, buf: []u8) ?usize {
    var inner_buf: [4096]u8 = undefined;
    var inner_pos: usize = 0;

    var sec_ref_buf: [7]u8 = undefined;
    const sec_ref = generateSecurityReference(&sec_ref_buf);

    // HNSHK (seg 2)
    inner_pos += writeSignatureHeader(&inner_buf, inner_pos, 2, session, sec_ref, session.tanSecFuncSlice()) orelse return null;

    // HKTAN submit:
    // - process "2" for regular TAN submit
    // - process "S" for decoupled status polling
    const tan_process = if (session.decoupled) "S" else "2";
    inner_pos += buildHktanProcessSubmit(session, tan_process, &inner_buf, inner_pos, 3, session.challenge_ref[0..session.challenge_ref_len]) orelse return null;

    // HNSHA (seg 4)
    const tan_payload = if (session.decoupled) "" else tan;
    inner_pos += writeSignatureFooter(&inner_buf, inner_pos, 4, sec_ref, session.pinSlice(), tan_payload) orelse return null;

    return writeAuthEnvelope(session, session.tanSecFuncSlice(), buf, inner_buf[0..inner_pos], 4);
}

/// Build dialog end message with security envelope.
pub fn buildDialogEndWithSecFunc(session: *const FintsSession, sec_func: []const u8, buf: []u8) ?usize {
    var inner_buf: [4096]u8 = undefined;
    var inner_pos: usize = 0;

    var sec_ref_buf: [7]u8 = undefined;
    const sec_ref = generateSecurityReference(&sec_ref_buf);

    // HNSHK (seg 2)
    inner_pos += writeSignatureHeader(&inner_buf, inner_pos, 2, session, sec_ref, sec_func) orelse return null;

    // HKEND (seg 3)
    inner_pos += writeSegment(&inner_buf, inner_pos, "HKEND", 3, 1, &.{
        session.dialogIdSlice(),
    }) orelse return null;

    // HNSHA (seg 4)
    inner_pos += writeSignatureFooter(&inner_buf, inner_pos, 4, sec_ref, session.pinSlice(), "") orelse return null;

    return writeAuthEnvelope(session, sec_func, buf, inner_buf[0..inner_pos], 4);
}

/// Build dialog end message with current TAN security function.
pub fn buildDialogEnd(session: *const FintsSession, buf: []u8) ?usize {
    return buildDialogEndWithSecFunc(session, session.tanSecFuncSlice(), buf);
}

/// Parse a FinTS response message, updating session state.
pub fn parseResponse(session: *FintsSession, data: []const u8, out: *ParsedResponse) void {
    // Split by unescaped segment delimiter '
    var seg_iter = SegmentIterator{ .data = data, .pos = 0 };
    while (seg_iter.next()) |segment| {
        if (segment.len < 5) continue;

        // Parse segment header: ID:NUM:VER
        if (startsWith(segment, "HNHBK")) {
            // Extract dialog ID from HNHBK:1:3+SIZE+300+DIALOG_ID+MSG_NUM
            // Fields (after segment header): [0]=size, [1]=hbci_ver, [2]=dialog_id, [3]=msg_num
            var field_idx: u8 = 0;
            var fpos: usize = 0;
            // Skip segment header (up to first +)
            while (fpos < segment.len and segment[fpos] != '+') : (fpos += 1) {}
            fpos += 1; // skip the +
            var field_start = fpos;
            while (fpos <= segment.len) : (fpos += 1) {
                if (fpos == segment.len or segment[fpos] == '+' or segment[fpos] == '\'') {
                    if (field_idx == 2) { // dialog_id
                        const did = segment[field_start..fpos];
                        const dlen = @min(did.len, out.dialog_id.len);
                        @memcpy(out.dialog_id[0..dlen], did[0..dlen]);
                        out.dialog_id_len = @intCast(dlen);
                        break;
                    }
                    field_idx += 1;
                    field_start = fpos + 1;
                }
            }
        } else if (startsWith(segment, "HNVSD")) {
            // Security envelope contains inner segments
            if (extractEnvelopeContent(segment)) |inner| {
                if (!is_wasm) {
                    const plen = @min(inner.len, 120);
                    dbg.print("[FinTS Zig] HNVSD inner[0..{d}]='{s}'\n", .{ plen, inner[0..plen] });
                    dbg.print("[FinTS Zig] HNVSD inner.len={d}, segment.len={d}\n", .{ inner.len, segment.len });
                }
                parseResponse(session, inner, out);
            } else {
                if (!is_wasm) dbg.print("[FinTS Zig] HNVSD: extractEnvelopeContent returned null!\n", .{});
            }
        } else if (startsWith(segment, "HIRMG") or startsWith(segment, "HIRMS")) {
            // Response codes
            parseResponseCodes(segment, out);
        } else if (startsWith(segment, "HNVSK")) {
            // Security header — skip
        } else if (startsWith(segment, "HISYN")) {
            // System ID response
            if (!is_wasm) {
                const plen = @min(segment.len, 80);
                dbg.print("[FinTS Zig] HISYN segment='{s}'\n", .{segment[0..plen]});
            }
            extractSystemId(segment, out);
        } else if (startsWith(segment, "HITANS:")) {
            // TAN method params (version advertised by bank). Track highest seen version.
            var c: usize = 0;
            var colon_count: u8 = 0;
            var ver: u8 = 0;
            while (c < segment.len) : (c += 1) {
                if (segment[c] == ':') {
                    colon_count += 1;
                    if (colon_count == 2) {
                        c += 1;
                        while (c < segment.len and segment[c] >= '0' and segment[c] <= '9') : (c += 1) {
                            ver = ver * 10 + @as(u8, segment[c] - '0');
                        }
                        break;
                    }
                }
            }
            if (ver >= 2 and ver <= 7 and (session.hitan_version == 0 or ver > session.hitan_version)) {
                session.hitan_version = ver;
            }
            // Parse twostep_parameters groups for selected sec_func (e.g. 902) to drive HKTAN optionals.
            // HITANS payload fields are '+' separated; twostep parameter entries are colon-separated DEGs.
            var fp: usize = 0;
            while (fp < segment.len and segment[fp] != '+') : (fp += 1) {}
            if (fp < segment.len) fp += 1;
            var field_start = fp;
            while (fp <= segment.len) : (fp += 1) {
                if (fp == segment.len or segment[fp] == '+' or segment[fp] == '\'') {
                    const field = segment[field_start..fp];
                    // candidate twostep parameter begins with "ddd:p:" where ddd is sec_func and p is tan_process.
                    if (field.len >= 7 and
                        field[0] >= '0' and field[0] <= '9' and
                        field[1] >= '0' and field[1] <= '9' and
                        field[2] >= '0' and field[2] <= '9' and
                        field[3] == ':' and field[5] == ':')
                    {
                        const sf = field[0..3];
                        const tp = field[4];
                        if (std.mem.eql(u8, sf, session.tanSecFuncSlice()) and tp == '2') {
                            // TwoStepParameters field offsets by HITANS version:
                            // v5: description_required=19, supported_media_number=20
                            // v6/v7: description_required=17, response_hhd_uc_required=18, supported_media_number=19
                            const desc_idx: u8 = if (ver >= 6) 17 else 19;
                            const hhd_uc_idx: u8 = if (ver >= 6) 18 else 255;
                            const media_idx: u8 = if (ver >= 6) 19 else 20;
                            var description_required: u8 = 0;
                            var supported_media_number: u8 = 0;
                            var response_hhd_uc_required = false;
                            var decoupled_max_poll_number: u8 = 0;
                            var wait_before_first_poll: u8 = 0;
                            var wait_before_next_poll: u8 = 0;
                            var automated_polling_allowed = true;
                            var idx: u8 = 0;
                            var cp: usize = 0;
                            var token_start: usize = 0;
                            while (cp <= field.len) : (cp += 1) {
                                if (cp == field.len or field[cp] == ':') {
                                    const tok = field[token_start..cp];
                                    if (idx == desc_idx and tok.len > 0 and tok[0] >= '0' and tok[0] <= '2') {
                                        description_required = tok[0] - '0';
                                    } else if (idx == hhd_uc_idx and tok.len > 0) {
                                        response_hhd_uc_required = (tok[0] == 'J');
                                    } else if (idx == media_idx and tok.len > 0 and tok[0] >= '0' and tok[0] <= '9') {
                                        supported_media_number = std.fmt.parseInt(u8, tok, 10) catch 0;
                                    } else if (ver >= 7 and tok.len > 0 and tok[0] >= '0' and tok[0] <= '9') {
                                        // Some banks shift v7 token positions; support both observed layouts:
                                        // canonical: max=21, first_wait=22, next_wait=23, auto=25
                                        // shifted:   max=20, first_wait=21, next_wait=22, auto=24
                                        if (idx == 20 or idx == 21) {
                                            const parsed = std.fmt.parseInt(u8, tok, 10) catch 0;
                                            if (parsed > 0 and decoupled_max_poll_number == 0) decoupled_max_poll_number = parsed;
                                        } else if (idx == 22) {
                                            const parsed = std.fmt.parseInt(u8, tok, 10) catch 0;
                                            if (parsed > 0 and wait_before_first_poll == 0) wait_before_first_poll = parsed;
                                        } else if (idx == 23) {
                                            const parsed = std.fmt.parseInt(u8, tok, 10) catch 0;
                                            if (parsed > 0 and wait_before_next_poll == 0) wait_before_next_poll = parsed;
                                        }
                                    } else if (ver >= 7 and (idx == 24 or idx == 25) and tok.len > 0) {
                                        // "J" = automatic polling allowed, "N" = disallow.
                                        automated_polling_allowed = (tok[0] != 'N');
                                    }
                                    token_start = cp + 1;
                                    idx += 1;
                                }
                            }
                            session.tan_description_required = description_required;
                            session.tan_supported_media_number = supported_media_number;
                            session.tan_response_hhd_uc_required = response_hhd_uc_required;
                            session.tan_medium_required = (supported_media_number > 1 and description_required == 2);
                            if (decoupled_max_poll_number > 0) session.decoupled_max_poll_number = decoupled_max_poll_number;
                            if (wait_before_first_poll > 0) session.wait_before_first_poll = wait_before_first_poll;
                            if (wait_before_next_poll > 0) session.wait_before_next_poll = wait_before_next_poll;
                            session.automated_polling_allowed = automated_polling_allowed;
                            break;
                        }
                    }
                    field_start = fp + 1;
                }
            }
        } else if (startsWith(segment, "HITAN:")) {
            // TAN challenge / TAN submit feedback segment
            extractTanChallenge(segment, out);
        } else if (startsWith(segment, "HIBPA")) {
            // HIBPA:...+bpd_version+...
            var p: usize = 0;
            while (p < segment.len and segment[p] != '+') : (p += 1) {}
            if (p < segment.len) {
                p += 1;
                const start = p;
                while (p < segment.len and segment[p] >= '0' and segment[p] <= '9') : (p += 1) {}
                if (p > start) {
                    const parsed = std.fmt.parseInt(u16, segment[start..p], 10) catch 0;
                    if (parsed > 0) session.bpd_version = parsed;
                }
            }
        } else if (startsWith(segment, "HIUPA")) {
            // HIUPA:...+upd_version+...
            var p: usize = 0;
            while (p < segment.len and segment[p] != '+') : (p += 1) {}
            if (p < segment.len) {
                p += 1;
                const start = p;
                while (p < segment.len and segment[p] >= '0' and segment[p] <= '9') : (p += 1) {}
                if (p > start) {
                    const parsed = std.fmt.parseInt(u16, segment[start..p], 10) catch 0;
                    session.upd_version = parsed;
                }
            }
        } else if (startsWith(segment, "HIUPD")) {
            // Account data; extract Kontoverbindung (Ktonr:Unterkonto:280:BLZ) for HKKAZ parity.
            extractAccountKtvFromHiupd(session, segment);
        } else if (startsWith(segment, "HIKAZS:")) {
            // Statement parameter segment. Keep highest advertised HIKAZS/HKKAZ version.
            var c: usize = 0;
            var colon_count: u8 = 0;
            var ver: u8 = 0;
            while (c < segment.len) : (c += 1) {
                if (segment[c] == ':') {
                    colon_count += 1;
                    if (colon_count == 2) {
                        c += 1;
                        while (c < segment.len and segment[c] >= '0' and segment[c] <= '9') : (c += 1) {
                            ver = ver * 10 + @as(u8, segment[c] - '0');
                        }
                        break;
                    }
                }
            }
            if (ver >= 5 and ver <= 7 and ver > session.hikaz_version) {
                session.hikaz_version = ver;
            }
        } else if (startsWith(segment, "HICAZS:")) {
            // CAMT statement parameter segment. If present, bank supports HKCAZ/HICAZ.
            session.supports_camt = true;
            extractCamtFormatFromHicazs(session, segment);
        } else if (startsWith(segment, "HITAB")) {
            // TAN media list response — parse TAN medium names.
            const remaining = out.tan_media.len - out.tan_media_count;
            if (remaining > 0) {
                const found = parseHitab(segment, out.tan_media[out.tan_media_count..]);
                out.tan_media_count += found;
            }
        } else if (startsWith(segment, "HIKAZ")) {
            // Account statements (MT940 data)
            extractMt940(segment, out);
        } else if (startsWith(segment, "HICAZ")) {
            // Account statements (CAMT XML data)
            extractCamtXml(segment, out);
        }
    }

    // Update session from response
    if (out.dialog_id_len > 0) {
        const len = out.dialog_id_len;
        @memcpy(session.dialog_id[0..len], out.dialog_id[0..len]);
        session.dialog_id_len = len;
    }
    if (out.system_id_len > 0) {
        const len = out.system_id_len;
        @memcpy(session.system_id[0..len], out.system_id[0..len]);
        session.system_id_len = len;
    }
    if (out.has_tan_request) {
        session.has_pending_tan = true;
        session.decoupled = out.decoupled;
        // Reset previous TAN payload first, then copy what is present in this response.
        session.challenge_len = 0;
        session.challenge_hhduc_len = 0;
        session.challenge_ref_len = 0;
        if (out.challenge_len > 0) {
            @memcpy(session.challenge[0..out.challenge_len], out.challenge[0..out.challenge_len]);
            session.challenge_len = out.challenge_len;
        }
        if (out.challenge_hhduc_len > 0) {
            @memcpy(session.challenge_hhduc[0..out.challenge_hhduc_len], out.challenge_hhduc[0..out.challenge_hhduc_len]);
            session.challenge_hhduc_len = out.challenge_hhduc_len;
        }
        if (out.challenge_ref_len > 0) {
            @memcpy(session.challenge_ref[0..out.challenge_ref_len], out.challenge_ref[0..out.challenge_ref_len]);
            session.challenge_ref_len = out.challenge_ref_len;
        }
    } else {
        // No TAN request in this response; clear stale challenge state.
        session.has_pending_tan = false;
        session.decoupled = false;
        session.challenge_len = 0;
        session.challenge_hhduc_len = 0;
    }
}

// ============================================================
// Internal: Segment Writing
// ============================================================

/// Write HKIDN segment with proper DEG for Kreditinstitutskennung (280:BLZ).
/// The colon in the DEG must NOT be escaped (it's a structural group separator).
fn writeHkidn(buf: []u8, offset: usize, num: u16, blz: []const u8, kunden_id: []const u8, system_id: []const u8, system_status: []const u8) ?usize {
    var pos: usize = offset;
    if (buf.len - pos < 100) return null;

    // HKIDN:num:2+280:BLZ+kunden_id+system_id+system_status'
    const header = "HKIDN:";
    @memcpy(buf[pos .. pos + header.len], header);
    pos += header.len;
    pos += writeUint(buf[pos..], num) orelse return null;
    const ver = ":2+280:";
    @memcpy(buf[pos .. pos + ver.len], ver);
    pos += ver.len;
    // BLZ (8 digits, no escaping needed)
    const blz_len = @min(blz.len, 8);
    @memcpy(buf[pos .. pos + blz_len], blz[0..blz_len]);
    pos += blz_len;
    // +kunden_id
    buf[pos] = '+';
    pos += 1;
    pos += escapeFintsValue(buf[pos..], kunden_id) orelse return null;
    // +system_id
    buf[pos] = '+';
    pos += 1;
    pos += escapeFintsValue(buf[pos..], system_id) orelse return null;
    // +system_status
    buf[pos] = '+';
    pos += 1;
    pos += escapeFintsValue(buf[pos..], system_status) orelse return null;
    // Segment terminator
    buf[pos] = '\'';
    pos += 1;

    return pos - offset;
}

/// Write a FinTS segment: ID:NUM:VER+DE1+DE2+...+'
fn writeSegment(buf: []u8, offset: usize, id: []const u8, num: u16, ver: u8, des: []const []const u8) ?usize {
    var pos: usize = offset;
    const remaining = buf.len - pos;
    if (remaining < id.len + 10) return null;

    // Header: ID:NUM:VER
    @memcpy(buf[pos .. pos + id.len], id);
    pos += id.len;
    buf[pos] = ':';
    pos += 1;
    pos += writeUint(buf[pos..], num) orelse return null;
    buf[pos] = ':';
    pos += 1;
    pos += writeUint(buf[pos..], ver) orelse return null;

    // Data elements
    for (des) |de| {
        if (pos >= buf.len) return null;
        buf[pos] = '+';
        pos += 1;
        pos += escapeFintsValue(buf[pos..], de) orelse return null;
    }

    // Segment terminator
    if (pos >= buf.len) return null;
    buf[pos] = '\'';
    pos += 1;

    return pos - offset;
}

/// Write HNHBK...HNHBS envelope around inner segments.
/// hnhbs_num: explicit HNHBS segment number. If 0, auto-calculated from inner segment count.
fn writeEnvelopeWithNum(session: *const FintsSession, buf: []u8, inner: []const u8, hnhbs_num: u16) ?usize {
    // HNHBK header: HNHBK:1:3+MSGSIZE+300+DIALOG_ID+MSG_NUM'
    // HNHBS trailer: HNHBS:N:1+MSG_NUM'

    // Build trailer first to know its size
    var trailer_buf: [64]u8 = undefined;
    const seg_num = if (hnhbs_num > 0) hnhbs_num else 2 + countSegments(inner);
    var msg_num_buf: [6]u8 = undefined;
    const msg_num_len = writeUint(&msg_num_buf, session.msg_num) orelse return null;
    const trailer_len = writeSegment(&trailer_buf, 0, "HNHBS", seg_num, 1, &.{
        msg_num_buf[0..msg_num_len],
    }) orelse return null;

    // Build header placeholder — we'll patch the size
    var header_buf: [128]u8 = undefined;
    // Total message size = header + inner + trailer
    // Header has fixed 12-digit size field
    const estimated_header_len = 30 + session.dialog_id_len; // rough estimate
    const total_size = estimated_header_len + inner.len + trailer_len;

    var size_str: [12]u8 = undefined;
    formatFixedWidth(&size_str, total_size);

    var header_pos: usize = 0;
    const header_seg = "HNHBK:1:3+" ++ "";
    @memcpy(header_buf[header_pos .. header_pos + header_seg.len], header_seg);
    header_pos += header_seg.len;
    @memcpy(header_buf[header_pos .. header_pos + 12], &size_str);
    header_pos += 12;
    header_buf[header_pos] = '+';
    header_pos += 1;
    // HBCI version
    const ver = "300";
    @memcpy(header_buf[header_pos .. header_pos + ver.len], ver);
    header_pos += ver.len;
    header_buf[header_pos] = '+';
    header_pos += 1;
    // Dialog ID
    const did = session.dialogIdSlice();
    @memcpy(header_buf[header_pos .. header_pos + did.len], did);
    header_pos += did.len;
    header_buf[header_pos] = '+';
    header_pos += 1;
    // Message number (python-fints renders this as plain numeric, not zero-padded)
    header_pos += writeUint(header_buf[header_pos..], session.msg_num) orelse return null;
    header_buf[header_pos] = '\'';
    header_pos += 1;

    // Recalculate with actual header size
    const actual_total = header_pos + inner.len + trailer_len;
    formatFixedWidth(&size_str, actual_total);
    // Patch size in header (starts at position 10 = after "HNHBK:1:3+")
    @memcpy(header_buf[10 .. 10 + 12], &size_str);

    // Assemble
    if (buf.len < actual_total) return null;
    var pos: usize = 0;
    @memcpy(buf[pos .. pos + header_pos], header_buf[0..header_pos]);
    pos += header_pos;
    @memcpy(buf[pos .. pos + inner.len], inner);
    pos += inner.len;
    @memcpy(buf[pos .. pos + trailer_len], trailer_buf[0..trailer_len]);
    pos += trailer_len;

    return pos;
}

/// Write HNHBK...HNHBS envelope (auto segment numbering for bare messages).
fn writeEnvelope(session: *const FintsSession, buf: []u8, inner: []const u8) ?usize {
    return writeEnvelopeWithNum(session, buf, inner, 0);
}

/// Write HNSHK (signature header) segment for PIN/TAN.
/// Fields per python-fints: security_profile, security_function, security_reference,
/// security_application_area, security_role, security_identification_details,
/// security_reference_number, security_datetime, hash_algorithm, signature_algorithm, key_name.
fn writeSignatureHeader(buf: []u8, offset: usize, num: u16, session: *const FintsSession, sec_ref: []const u8, sec_func: []const u8) ?usize {
    var pos: usize = offset;
    const remaining = buf.len - pos;
    if (remaining < 256) return null;

    // HNSHK:num:4+PIN:1+sec_func+sec_ref+1+1+2::sys_id+1+1:DATE:TIME+1:999:1+6:10:16+280:BLZ:user:S:0:0'
    const header = "HNSHK:";
    @memcpy(buf[pos .. pos + header.len], header);
    pos += header.len;
    pos += writeUint(buf[pos..], num) orelse return null;

    // HNSHK always uses PIN:1 (signature header). Only HNVSK uses PIN:2.
    const part1a = ":4+PIN:1+";
    @memcpy(buf[pos .. pos + part1a.len], part1a);
    pos += part1a.len;

    // Security function (999 for sync, 902 for photoTAN, etc.)
    @memcpy(buf[pos .. pos + sec_func.len], sec_func);
    pos += sec_func.len;

    buf[pos] = '+';
    pos += 1;

    // Security reference
    @memcpy(buf[pos .. pos + sec_ref.len], sec_ref);
    pos += sec_ref.len;

    // +SHM+ISS+ident(MS::system_id)+ref_num+datetime+hash+sig+key_name
    // security_identification_details = IdentifiedRole.MS (2) + system_id
    const part2a = "+1+1+2::";
    @memcpy(buf[pos .. pos + part2a.len], part2a);
    pos += part2a.len;

    // System ID (0 for sync, real ID after sync)
    const sid = session.systemIdSlice();
    @memcpy(buf[pos .. pos + sid.len], sid);
    pos += sid.len;

    var date_buf: [8]u8 = undefined;
    var time_buf: [6]u8 = undefined;
    fillCurrentDateTime(&date_buf, &time_buf);

    const part2b = "+1+1:";
    @memcpy(buf[pos .. pos + part2b.len], part2b);
    pos += part2b.len;
    @memcpy(buf[pos .. pos + 8], &date_buf);
    pos += 8;
    buf[pos] = ':';
    pos += 1;
    @memcpy(buf[pos .. pos + 6], &time_buf);
    pos += 6;
    const part2c = "+1:999:1+6:10:16+280:";
    @memcpy(buf[pos .. pos + part2c.len], part2c);
    pos += part2c.len;

    // BLZ
    @memcpy(buf[pos .. pos + 8], &session.blz);
    pos += 8;
    buf[pos] = ':';
    pos += 1;

    // user_id
    const uid = session.userIdSlice();
    @memcpy(buf[pos .. pos + uid.len], uid);
    pos += uid.len;

    // :S:0:0'
    const part3 = ":S:0:0'";
    @memcpy(buf[pos .. pos + part3.len], part3);
    pos += part3.len;

    return pos - offset;
}

/// Write HNSHA (signature footer) segment with PIN and optional TAN.
fn writeSignatureFooter(buf: []u8, offset: usize, num: u16, sec_ref: []const u8, pin: []const u8, tan: []const u8) ?usize {
    var pos: usize = offset;
    const remaining = buf.len - pos;
    if (remaining < 128) return null;

    // HNSHA:num:2+sec_ref++pin(:tan)?'
    const header = "HNSHA:";
    @memcpy(buf[pos .. pos + header.len], header);
    pos += header.len;
    pos += writeUint(buf[pos..], num) orelse return null;

    const part1 = ":2+";
    @memcpy(buf[pos .. pos + part1.len], part1);
    pos += part1.len;

    @memcpy(buf[pos .. pos + sec_ref.len], sec_ref);
    pos += sec_ref.len;

    // ++PIN
    @memcpy(buf[pos .. pos + 2], "++");
    pos += 2;

    @memcpy(buf[pos .. pos + pin.len], pin);
    pos += pin.len;

    // :TAN (if provided)
    if (tan.len > 0) {
        buf[pos] = ':';
        pos += 1;
        @memcpy(buf[pos .. pos + tan.len], tan);
        pos += tan.len;
    }

    buf[pos] = '\'';
    pos += 1;

    return pos - offset;
}

/// Wrap inner segments (which include HNSHK/HNSHA) in HNVSK + HNVSD envelope.
/// last_inner_seg: the segment number of the last segment inside HNVSD (e.g. HNSHA).
/// HNHBS will be last_inner_seg + 1.
fn writeAuthEnvelope(session: *const FintsSession, sec_func: []const u8, buf: []u8, inner: []const u8, last_inner_seg: u16) ?usize {
    var sec_buf: [8192]u8 = undefined;
    var sec_pos: usize = 0;

    // HNVSK:998:3 — Security header (dummy encryption for PIN/TAN)
    // Fields: security_profile(PIN:1) + security_function(998) + security_role(1) +
    //         security_identification(1::0) + security_datetime(1:DATE:TIME) +
    //         encryption_algorithm(2:2:13:@8@\0\0\0\0\0\0\0\0:5:1) +
    //         key_name(280:BLZ:user:V:0:0) + compression(0)
    var hnvsk_buf: [256]u8 = undefined;
    var vsk_pos: usize = 0;

    // python-fints parity: one-step (999) uses profile PIN:1, two-step methods use PIN:2.
    const pin_ver: []const u8 = if (std.mem.eql(u8, sec_func, "999")) "1" else "2";

    // Part before system_id in security_identification
    const vsk_h1 = "HNVSK:998:3+PIN:";
    @memcpy(hnvsk_buf[vsk_pos .. vsk_pos + vsk_h1.len], vsk_h1);
    vsk_pos += vsk_h1.len;
    @memcpy(hnvsk_buf[vsk_pos .. vsk_pos + pin_ver.len], pin_ver);
    vsk_pos += pin_ver.len;
    // security_identification_details = IdentifiedRole.MS (2) + system_id
    const vsk_h2 = "+998+1+2::";
    @memcpy(hnvsk_buf[vsk_pos .. vsk_pos + vsk_h2.len], vsk_h2);
    vsk_pos += vsk_h2.len;

    // System ID in security_identification (0 for sync, real after sync)
    const sid = session.systemIdSlice();
    @memcpy(hnvsk_buf[vsk_pos .. vsk_pos + sid.len], sid);
    vsk_pos += sid.len;

    var date_buf: [8]u8 = undefined;
    var time_buf: [6]u8 = undefined;
    fillCurrentDateTime(&date_buf, &time_buf);

    const vsk_part1 = "+1:";
    @memcpy(hnvsk_buf[vsk_pos .. vsk_pos + vsk_part1.len], vsk_part1);
    vsk_pos += vsk_part1.len;
    @memcpy(hnvsk_buf[vsk_pos .. vsk_pos + 8], &date_buf);
    vsk_pos += 8;
    hnvsk_buf[vsk_pos] = ':';
    vsk_pos += 1;
    @memcpy(hnvsk_buf[vsk_pos .. vsk_pos + 6], &time_buf);
    vsk_pos += 6;
    const vsk_part1b = "+2:2:13:@8@";
    @memcpy(hnvsk_buf[vsk_pos .. vsk_pos + vsk_part1b.len], vsk_part1b);
    vsk_pos += vsk_part1b.len;

    // 8 null bytes (encryption key value — dummy for PIN/TAN)
    @memset(hnvsk_buf[vsk_pos .. vsk_pos + 8], 0);
    vsk_pos += 8;

    // Part after binary key value, up to BLZ
    const vsk_part2 = ":5:1+280:";
    @memcpy(hnvsk_buf[vsk_pos .. vsk_pos + vsk_part2.len], vsk_part2);
    vsk_pos += vsk_part2.len;

    // BLZ
    @memcpy(hnvsk_buf[vsk_pos .. vsk_pos + 8], &session.blz);
    vsk_pos += 8;
    hnvsk_buf[vsk_pos] = ':';
    vsk_pos += 1;

    // user_id
    const uid = session.userIdSlice();
    @memcpy(hnvsk_buf[vsk_pos .. vsk_pos + uid.len], uid);
    vsk_pos += uid.len;

    const vsk_suffix = ":V:0:0+0'";
    @memcpy(hnvsk_buf[vsk_pos .. vsk_pos + vsk_suffix.len], vsk_suffix);
    vsk_pos += vsk_suffix.len;

    @memcpy(sec_buf[sec_pos .. sec_pos + vsk_pos], hnvsk_buf[0..vsk_pos]);
    sec_pos += vsk_pos;

    // HNVSD:999:1+@len@inner_data'
    const hnvsd_prefix = "HNVSD:999:1+@";
    @memcpy(sec_buf[sec_pos .. sec_pos + hnvsd_prefix.len], hnvsd_prefix);
    sec_pos += hnvsd_prefix.len;

    // Write length as decimal
    sec_pos += writeUint(sec_buf[sec_pos..], @intCast(inner.len)) orelse return null;

    sec_buf[sec_pos] = '@';
    sec_pos += 1;

    // Write the inner data
    if (sec_pos + inner.len + 1 >= sec_buf.len) return null;
    @memcpy(sec_buf[sec_pos .. sec_pos + inner.len], inner);
    sec_pos += inner.len;

    sec_buf[sec_pos] = '\'';
    sec_pos += 1;

    return writeEnvelopeWithNum(session, buf, sec_buf[0..sec_pos], last_inner_seg + 1);
}

// ============================================================
// Internal: Response Parsing
// ============================================================

/// Iterator that splits FinTS message by unescaped ' delimiter.
/// Handles @len@ binary data blocks (skips over them without splitting).
const SegmentIterator = struct {
    data: []const u8,
    pos: usize,

    fn next(self: *SegmentIterator) ?[]const u8 {
        if (self.pos >= self.data.len) return null;

        const start = self.pos;
        while (self.pos < self.data.len) {
            // Skip @len@ binary data blocks
            if (self.data[self.pos] == '@' and !isEscaped(self.data, self.pos)) {
                if (self.parseBinaryLen()) |bin_len| {
                    self.pos += bin_len; // skip binary content
                    continue;
                }
            }
            if (self.data[self.pos] == '\'' and !isEscaped(self.data, self.pos)) {
                const segment = self.data[start..self.pos];
                self.pos += 1;
                if (segment.len > 0) return segment;
                return self.next();
            }
            self.pos += 1;
        }

        // Remaining data (no trailing ')
        if (start < self.data.len) return self.data[start..];
        return null;
    }

    /// Parse @len@ and advance pos past the closing @. Returns the binary length to skip.
    fn parseBinaryLen(self: *SegmentIterator) ?usize {
        var p = self.pos + 1; // skip opening @
        var len: usize = 0;
        var has_digits = false;
        while (p < self.data.len and self.data[p] >= '0' and self.data[p] <= '9') : (p += 1) {
            len = len * 10 + (self.data[p] - '0');
            has_digits = true;
        }
        if (!has_digits or p >= self.data.len or self.data[p] != '@') return null;
        // Advance past closing @ and the binary data
        self.pos = p + 1; // past closing @
        return len;
    }
};

fn isEscaped(data: []const u8, pos: usize) bool {
    if (pos == 0) return false;
    return data[pos - 1] == '?';
}

fn parseResponseCodes(segment: []const u8, out: *ParsedResponse) void {
    // Format: HIRMG:2:2+CODE:TEXT+CODE:TEXT+...
    // or HIRMS:3:2:REF+CODE:TEXT+...
    // Find the first + to skip the header
    var pos: usize = 0;
    while (pos < segment.len and segment[pos] != '+') : (pos += 1) {}
    if (pos >= segment.len) return;
    pos += 1;

    // Parse each code group (separated by +)
    while (pos < segment.len) {
        // Read one response group first (until next unescaped '+').
        const group_start = pos;
        while (pos < segment.len) {
            if (segment[pos] == '+' and !isEscaped(segment, pos)) break;
            pos += 1;
        }
        const group = segment[group_start..pos];
        if (group.len < 4) {
            if (pos < segment.len and segment[pos] == '+') pos += 1;
            continue;
        }
        if (out.code_count >= 16) break;

        var code = &out.codes[out.code_count];
        @memset(&code.code, 0);
        @memset(&code.reference, 0);
        @memset(&code.text, 0);
        @memset(&code.parameter, 0);
        code.reference_len = 0;
        code.text_len = 0;
        code.parameter_len = 0;

        // Split group by unescaped ':' into up to 4 parts:
        // - HIRMG style: code:text
        // - HIRMS style: code:reference:text:parameter
        var part_start: usize = 0;
        var parts: [4][]const u8 = .{ "", "", "", "" };
        var part_count: u8 = 0;
        var gp: usize = 0;
        while (gp <= group.len and part_count < 4) : (gp += 1) {
            if (gp == group.len or (group[gp] == ':' and !isEscaped(group, gp))) {
                parts[part_count] = group[part_start..gp];
                part_count += 1;
                part_start = gp + 1;
            }
        }

        const code_src = parts[0];
        if (code_src.len < 4) {
            if (pos < segment.len and segment[pos] == '+') pos += 1;
            continue;
        }
        @memcpy(code.code[0..4], code_src[0..4]);

        if (part_count >= 3) {
            // code:reference:text(:parameter)
            const ref_len = @min(parts[1].len, code.reference.len);
            @memcpy(code.reference[0..ref_len], parts[1][0..ref_len]);
            code.reference_len = @intCast(ref_len);

            const text_len = @min(parts[2].len, code.text.len);
            @memcpy(code.text[0..text_len], parts[2][0..text_len]);
            code.text_len = @intCast(text_len);

            if (part_count >= 4) {
                const param_len = @min(parts[3].len, code.parameter.len);
                @memcpy(code.parameter[0..param_len], parts[3][0..param_len]);
                code.parameter_len = @intCast(param_len);
            }
        } else if (part_count >= 2) {
            // code:text
            const text_len = @min(parts[1].len, code.text.len);
            @memcpy(code.text[0..text_len], parts[1][0..text_len]);
            code.text_len = @intCast(text_len);
        }

        out.code_count += 1;

        // Check for dialog_id in certain response codes
        if (std.mem.eql(u8, &code.code, "0020")) {
            // Dialog-ID is usually in HNHBK, but extract from HIRMG if present
        }

        if (pos < segment.len and segment[pos] == '+') pos += 1;
    }
}

fn extractSystemId(segment: []const u8, out: *ParsedResponse) void {
    // HISYN:N:V+system_id'
    var pos: usize = 0;
    while (pos < segment.len and segment[pos] != '+') : (pos += 1) {}
    if (pos >= segment.len) return;
    pos += 1;

    const start = pos;
    while (pos < segment.len and segment[pos] != '+' and segment[pos] != '\'') : (pos += 1) {}
    const id = segment[start..pos];
    const len = @min(id.len, 32);
    @memcpy(out.system_id[0..len], id[0..len]);
    out.system_id_len = @intCast(len);
}

fn extractTanChallenge(segment: []const u8, out: *ParsedResponse) void {
    // HITAN:N:V+... (field mapping depends on HITAN version)
    out.has_tan_request = true;

    // Parse HITAN version from header (HITAN:<num>:<ver>...)
    var hitan_ver: u8 = 0;
    var c: usize = 0;
    var colon_count: u8 = 0;
    while (c < segment.len) : (c += 1) {
        if (segment[c] == ':') {
            colon_count += 1;
            if (colon_count == 2) {
                c += 1;
                while (c < segment.len and segment[c] >= '0' and segment[c] <= '9') : (c += 1) {
                    hitan_ver = hitan_ver * 10 + @as(u8, segment[c] - '0');
                }
                break;
            }
        }
    }

    // python-fints mapping:
    // HITAN6/7: field2=task_hash_value, field3=task_reference, field4=challenge, field5=challenge_hhduc
    // older HITAN variants: field2=task_reference, field4=challenge, field5=challenge_hhduc
    const ref_field_num: u8 = if (hitan_ver >= 6) 3 else 2;
    const challenge_field_num: u8 = 4;
    const hhduc_field_num: u8 = 5;

    // Split by + to find challenge fields
    var field_num: u8 = 0;
    var pos: usize = 0;

    // Skip segment header
    while (pos < segment.len and segment[pos] != '+') : (pos += 1) {}
    if (pos >= segment.len) return;
    pos += 1;
    field_num = 1;

    while (pos < segment.len) {
        const field_start = pos;
        var parsed_binary_field = false;

        // FinTS binary fields are encoded as @len@<raw-bytes>. Those bytes may contain
        // '+' or '\'' and must be consumed by length, not delimiter scanning.
        if (segment[pos] == '@') {
            var p = pos + 1;
            var bin_len: usize = 0;
            var has_digits = false;
            while (p < segment.len and segment[p] >= '0' and segment[p] <= '9') : (p += 1) {
                has_digits = true;
                bin_len = (bin_len * 10) + @as(usize, segment[p] - '0');
            }
            if (has_digits and p < segment.len and segment[p] == '@') {
                const data_start = p + 1;
                if (data_start <= segment.len and bin_len <= (segment.len - data_start)) {
                    pos = data_start + bin_len;
                    parsed_binary_field = true;
                }
            }
        }

        if (!parsed_binary_field) {
            // Find next unescaped '+' or segment terminator.
            while (pos < segment.len) {
                if ((segment[pos] == '+' or segment[pos] == '\'') and !isEscaped(segment, pos)) break;
                pos += 1;
            }
        }
        const field = segment[field_start..pos];

        if (field_num == 1) {
            // Process variant — check for "S" (decoupled)
            if (std.mem.eql(u8, field, "S")) {
                out.decoupled = true;
            }
        } else if (field_num == ref_field_num) {
            // Challenge reference
            const ref_len = @min(field.len, 32);
            @memcpy(out.challenge_ref[0..ref_len], field[0..ref_len]);
            out.challenge_ref_len = @intCast(ref_len);
        } else if (field_num == challenge_field_num) {
            // Challenge text
            const chal_len = @min(field.len, 512);
            @memcpy(out.challenge[0..chal_len], field[0..chal_len]);
            out.challenge_len = @intCast(chal_len);
        } else if (field_num == hhduc_field_num) {
            // Challenge HHDUC — photoTAN image data
            // May be prefixed with @len@ binary marker
            if (std.mem.indexOf(u8, field, "@")) |at_pos| {
                const after = field[at_pos + 1 ..];
                if (std.mem.indexOf(u8, after, "@")) |end_at| {
                    const data_start = at_pos + 1 + end_at + 1;
                    if (data_start < field.len) {
                        const data = field[data_start..];
                        const copy_len = @min(data.len, 8192);
                        @memcpy(out.challenge_hhduc[0..copy_len], data[0..copy_len]);
                        out.challenge_hhduc_len = @intCast(copy_len);
                    }
                }
            } else if (field.len > 0) {
                // Raw data without @len@ prefix
                const copy_len = @min(field.len, 8192);
                @memcpy(out.challenge_hhduc[0..copy_len], field[0..copy_len]);
                out.challenge_hhduc_len = @intCast(copy_len);
            }
        }

        field_num += 1;
        if (pos < segment.len and segment[pos] == '+') pos += 1 else break;
    }
}

fn extractMt940(segment: []const u8, out: *ParsedResponse) void {
    // HIKAZ can contain multiple binary fields; append the one(s) that look like MT940.
    var pos: usize = 0;
    while (pos < segment.len and segment[pos] != '+') : (pos += 1) {}
    if (pos >= segment.len) return;
    pos += 1; // first field after segment header

    var appended_any = false;
    var first_binary: []const u8 = "";

    while (pos < segment.len) {
        // Binary field: @len@<raw bytes>
        if (segment[pos] == '@' and !isEscaped(segment, pos)) {
            var p = pos + 1;
            var bin_len: usize = 0;
            var has_digits = false;
            while (p < segment.len and segment[p] >= '0' and segment[p] <= '9') : (p += 1) {
                has_digits = true;
                bin_len = bin_len * 10 + (segment[p] - '0');
            }
            if (has_digits and p < segment.len and segment[p] == '@') {
                const data_start = p + 1;
                if (data_start <= segment.len) {
                    const available = segment.len - data_start;
                    const raw = segment[data_start .. data_start + @min(bin_len, available)];
                    if (first_binary.len == 0) first_binary = raw;
                    if (looksLikeMt940(raw)) {
                        appendMt940(out, raw);
                        appended_any = true;
                    }
                    pos = data_start + @min(bin_len, available);
                    if (pos < segment.len and segment[pos] == '+' and !isEscaped(segment, pos)) {
                        pos += 1;
                    }
                    continue;
                }
            }
        }

        // Non-binary field: skip to next unescaped +.
        while (pos < segment.len) : (pos += 1) {
            if (segment[pos] == '+' and !isEscaped(segment, pos)) {
                pos += 1;
                break;
            }
        }
    }

    // If nothing matched MT940 heuristics, keep old behavior and use the first binary block.
    if (!appended_any and first_binary.len > 0) {
        appendMt940(out, first_binary);
    }
}

fn appendMt940(out: *ParsedResponse, chunk: []const u8) void {
    if (chunk.len == 0) return;
    const offset: usize = out.mt940_len;
    if (offset >= out.mt940_data.len) return;
    const copy_len = @min(chunk.len, out.mt940_data.len - offset);
    @memcpy(out.mt940_data[offset .. offset + copy_len], chunk[0..copy_len]);
    out.mt940_len = @intCast(offset + copy_len);
}

fn appendCamt(out: *ParsedResponse, chunk: []const u8) void {
    if (chunk.len == 0) return;
    const offset: usize = out.camt_len;
    if (offset >= out.camt_data.len) return;
    const copy_len = @min(chunk.len, out.camt_data.len - offset);
    @memcpy(out.camt_data[offset .. offset + copy_len], chunk[0..copy_len]);
    out.camt_len = @intCast(offset + copy_len);
}

fn looksLikeMt940(data: []const u8) bool {
    if (data.len == 0) return false;
    // Trim leading whitespace/newlines before checking markers.
    var start: usize = 0;
    while (start < data.len and (data[start] == '\r' or data[start] == '\n' or data[start] == ' ' or data[start] == '\t')) : (start += 1) {}
    if (start >= data.len) return false;
    const s = data[start..];

    if (std.mem.startsWith(u8, s, ":20:")) return true;
    if (std.mem.indexOf(u8, s, "\n:20:") != null) return true;
    if (std.mem.indexOf(u8, s, "\r:20:") != null) return true;
    // Some banks omit :20: in fragments, but :61: still indicates statement body.
    if (std.mem.startsWith(u8, s, ":61:")) return true;
    if (std.mem.indexOf(u8, s, "\n:61:") != null) return true;
    if (std.mem.indexOf(u8, s, "\r:61:") != null) return true;
    return false;
}

fn looksLikeCamtXml(data: []const u8) bool {
    if (data.len == 0) return false;
    if (std.mem.indexOf(u8, data, "<Document") != null) return true;
    if (std.mem.indexOf(u8, data, "<BkToCstmrStmt") != null) return true;
    if (std.mem.indexOf(u8, data, "<BkToCstmrAcctRpt") != null) return true;
    if (std.mem.indexOf(u8, data, "camt.052") != null) return true;
    if (std.mem.indexOf(u8, data, "camt.053") != null) return true;
    return false;
}

fn extractCamtXml(segment: []const u8, out: *ParsedResponse) void {
    // HICAZ includes multiple binary fields; append the one(s) that look like XML.
    var pos: usize = 0;
    while (pos < segment.len and segment[pos] != '+') : (pos += 1) {}
    if (pos >= segment.len) return;
    pos += 1;

    var appended_any = false;
    var first_binary: []const u8 = "";

    while (pos < segment.len) {
        if (segment[pos] == '@' and !isEscaped(segment, pos)) {
            var p = pos + 1;
            var bin_len: usize = 0;
            var has_digits = false;
            while (p < segment.len and segment[p] >= '0' and segment[p] <= '9') : (p += 1) {
                has_digits = true;
                bin_len = bin_len * 10 + (segment[p] - '0');
            }
            if (has_digits and p < segment.len and segment[p] == '@') {
                const data_start = p + 1;
                if (data_start <= segment.len) {
                    const available = segment.len - data_start;
                    const raw = segment[data_start .. data_start + @min(bin_len, available)];
                    if (first_binary.len == 0) first_binary = raw;
                    if (looksLikeCamtXml(raw)) {
                        appendCamt(out, raw);
                        appended_any = true;
                    }
                    pos = data_start + @min(bin_len, available);
                    if (pos < segment.len and segment[pos] == '+' and !isEscaped(segment, pos)) {
                        pos += 1;
                    }
                    continue;
                }
            }
        }

        while (pos < segment.len) : (pos += 1) {
            if (segment[pos] == '+' and !isEscaped(segment, pos)) {
                pos += 1;
                break;
            }
        }
    }

    if (!appended_any and first_binary.len > 0) {
        appendCamt(out, first_binary);
    }
}

fn extractCamtFormatFromHicazs(session: *FintsSession, segment: []const u8) void {
    // Keep first supported CAMT format token that contains "camt.".
    var pos: usize = 0;
    while (pos < segment.len and segment[pos] != '+') : (pos += 1) {}
    if (pos >= segment.len) return;
    pos += 1;

    var field_start = pos;
    while (pos <= segment.len) : (pos += 1) {
        if (pos == segment.len or ((segment[pos] == '+' or segment[pos] == '\'') and !isEscaped(segment, pos))) {
            const field = segment[field_start..pos];
            if (field.len > 0 and std.mem.indexOf(u8, field, "camt.") != null) {
                var token_start: usize = 0;
                var fp: usize = 0;
                while (fp <= field.len) : (fp += 1) {
                    if (fp == field.len or (field[fp] == ':' and !isEscaped(field, fp))) {
                        const tok = field[token_start..fp];
                        if (tok.len > 0 and std.mem.indexOf(u8, tok, "camt.") != null) {
                            const copy_len = @min(tok.len, session.camt_format.len);
                            @memcpy(session.camt_format[0..copy_len], tok[0..copy_len]);
                            session.camt_format_len = @intCast(copy_len);
                            return;
                        }
                        token_start = fp + 1;
                    }
                }
            }
            field_start = pos + 1;
        }
    }
}

fn extractAccountKtvFromHiupd(session: *FintsSession, segment: []const u8) void {
    // Find a field like "Ktonr:Unterkonto:280:BLZ" and keep it for HKKAZ requests.
    var pos: usize = 0;
    while (pos < segment.len and segment[pos] != '+') : (pos += 1) {}
    if (pos >= segment.len) return;
    pos += 1;

    var field_start = pos;
    while (pos <= segment.len) : (pos += 1) {
        if (pos == segment.len or (segment[pos] == '+' and !isEscaped(segment, pos))) {
            const field = segment[field_start..pos];
            if (std.mem.indexOf(u8, field, ":280:")) |country_pos| {
                if (country_pos > 0 and country_pos + 13 <= field.len) {
                    const blz = field[country_pos + 5 .. country_pos + 13];
                    if (std.mem.eql(u8, blz, &session.blz) and std.mem.indexOfScalar(u8, field[0..country_pos], ':') != null) {
                        const candidate = field[0 .. country_pos + 13];
                        const copy_len = @min(candidate.len, session.account_ktv.len);
                        @memcpy(session.account_ktv[0..copy_len], candidate[0..copy_len]);
                        session.account_ktv_len = @intCast(copy_len);
                        return;
                    }
                }
            }
            field_start = pos + 1;
        }
    }
}

const AccountKtvParts = struct {
    account: []const u8,
    subaccount: []const u8,
    blz: []const u8,
};

fn splitAccountKtv(ktv: []const u8) ?AccountKtvParts {
    // Expected format: account:subaccount:280:BLZ
    var first_colon: ?usize = null;
    var second_colon: ?usize = null;
    var third_colon: ?usize = null;

    for (ktv, 0..) |ch, i| {
        if (ch != ':') continue;
        if (first_colon == null) {
            first_colon = i;
        } else if (second_colon == null) {
            second_colon = i;
        } else {
            third_colon = i;
            break;
        }
    }

    if (first_colon == null or second_colon == null or third_colon == null) return null;
    const c1 = first_colon.?;
    const c2 = second_colon.?;
    const c3 = third_colon.?;
    if (c2 <= c1 or c3 <= c2 + 1) return null;
    if (!std.mem.eql(u8, ktv[c2 + 1 .. c3], "280")) return null;

    const account = ktv[0..c1];
    const subaccount = ktv[c1 + 1 .. c2];
    const blz = ktv[c3 + 1 ..];
    if (blz.len == 0) return null;

    return .{
        .account = account,
        .subaccount = subaccount,
        .blz = blz,
    };
}

fn extractEnvelopeContent(segment: []const u8) ?[]const u8 {
    // Find @len@ marker in HNVSD segment and return exactly len bytes
    if (std.mem.indexOf(u8, segment, "@")) |at_pos| {
        var p = at_pos + 1;
        var len: usize = 0;
        var has_digits = false;
        while (p < segment.len and segment[p] >= '0' and segment[p] <= '9') : (p += 1) {
            len = len * 10 + (segment[p] - '0');
            has_digits = true;
        }
        if (!has_digits or p >= segment.len or segment[p] != '@') return null;
        const data_start = p + 1; // after closing @
        if (data_start + len <= segment.len) {
            return segment[data_start .. data_start + len];
        }
        // Fallback: return everything after @len@
        if (data_start < segment.len) {
            return segment[data_start..];
        }
    }
    return null;
}

// ============================================================
// Internal: Helpers
// ============================================================

/// Escape FinTS special characters: ? before +, :, ', ?
fn escapeFintsValue(buf: []u8, value: []const u8) ?usize {
    var pos: usize = 0;
    for (value) |c| {
        if (c == '?' or c == '+' or c == ':' or c == '\'') {
            if (pos + 2 > buf.len) return null;
            buf[pos] = '?';
            pos += 1;
        } else {
            if (pos + 1 > buf.len) return null;
        }
        buf[pos] = c;
        pos += 1;
    }
    return pos;
}

/// Unescape FinTS value: remove ? before +, :, ', ?
pub fn unescapeFintsValue(buf: []u8, value: []const u8) usize {
    var pos: usize = 0;
    var i: usize = 0;
    while (i < value.len) {
        if (i + 1 < value.len and value[i] == '?') {
            const next = value[i + 1];
            if (next == '?' or next == '+' or next == ':' or next == '\'') {
                if (pos < buf.len) {
                    buf[pos] = next;
                    pos += 1;
                }
                i += 2;
                continue;
            }
        }
        if (pos < buf.len) {
            buf[pos] = value[i];
            pos += 1;
        }
        i += 1;
    }
    return pos;
}

fn writeUint(buf: []u8, val: usize) ?usize {
    var tmp: [20]u8 = undefined;
    var n = val;
    var len: usize = 0;

    if (n == 0) {
        if (buf.len == 0) return null;
        buf[0] = '0';
        return 1;
    }

    while (n > 0) : (len += 1) {
        tmp[len] = @intCast('0' + (n % 10));
        n /= 10;
    }

    if (len > buf.len) return null;

    // Reverse
    for (0..len) |i| {
        buf[i] = tmp[len - 1 - i];
    }
    return len;
}

fn formatFixedWidth(buf: *[12]u8, val: usize) void {
    var n = val;
    var i: usize = 12;
    while (i > 0) {
        i -= 1;
        buf[i] = @intCast('0' + (n % 10));
        n /= 10;
    }
}

fn countSegments(data: []const u8) u16 {
    var count: u16 = 0;
    for (data) |c| {
        if (c == '\'') count += 1;
    }
    return count;
}

fn startsWith(haystack: []const u8, prefix: []const u8) bool {
    return std.mem.startsWith(u8, haystack, prefix);
}

/// Encode data as Base64.
pub fn base64Encode(buf: []u8, data: []const u8) ?usize {
    const encoder = std.base64.standard.Encoder;
    const needed = encoder.calcSize(data.len);
    if (needed > buf.len) return null;
    const encoded = encoder.encode(buf, data);
    return encoded.len;
}

/// Decode Base64 data.
pub fn base64Decode(buf: []u8, data: []const u8) ?usize {
    const decoder = std.base64.standard.Decoder;
    const size = decoder.calcSizeForSlice(data) catch return null;
    if (size > buf.len) return null;
    decoder.decode(buf, data) catch return null;
    return size;
}

// ============================================================
// Tests
// ============================================================

test "FintsSession.init sets fields correctly" {
    const s = FintsSession.init("20041133", "https://fints.comdirect.de/fints", "testuser", "12345");
    try std.testing.expectEqualStrings("20041133", &s.blz);
    try std.testing.expectEqualStrings("https://fints.comdirect.de/fints", s.urlSlice());
    try std.testing.expectEqualStrings("testuser", s.userIdSlice());
    try std.testing.expectEqualStrings("12345", s.pinSlice());
    try std.testing.expectEqualStrings("0", s.systemIdSlice());
    try std.testing.expectEqualStrings("0", s.dialogIdSlice());
    try std.testing.expectEqual(@as(u16, 1), s.msg_num);
}

test "FintsSession.clearPin zeros the PIN" {
    var s = FintsSession.init("20041133", "https://x.de/f", "user", "secretPIN");
    try std.testing.expectEqualStrings("secretPIN", s.pinSlice());
    s.clearPin();
    try std.testing.expectEqual(@as(u8, 0), s.pin_len);
    // Verify memory is zeroed
    for (s.pin[0..9]) |b| {
        try std.testing.expectEqual(@as(u8, 0), b);
    }
}

test "escapeFintsValue escapes special characters" {
    var buf: [64]u8 = undefined;
    const len = escapeFintsValue(&buf, "Hello+World:Test?End'Done") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("Hello?+World?:Test??End?'Done", buf[0..len]);
}

test "escapeFintsValue no escaping needed" {
    var buf: [64]u8 = undefined;
    const len = escapeFintsValue(&buf, "plain text 123") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("plain text 123", buf[0..len]);
}

test "unescapeFintsValue removes escape chars" {
    var buf: [64]u8 = undefined;
    const len = unescapeFintsValue(&buf, "Hello?+World?:Test??End?'Done");
    try std.testing.expectEqualStrings("Hello+World:Test?End'Done", buf[0..len]);
}

test "base64 roundtrip" {
    var enc_buf: [128]u8 = undefined;
    var dec_buf: [128]u8 = undefined;
    const original = "HNHBK:1:3+000000000095+300+0+1'";
    const enc_len = base64Encode(&enc_buf, original) orelse return error.TestUnexpectedResult;
    const dec_len = base64Decode(&dec_buf, enc_buf[0..enc_len]) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings(original, dec_buf[0..dec_len]);
}

test "writeSegment basic" {
    var buf: [256]u8 = undefined;
    const len = writeHkidn(&buf, 0, 3, "20041133", "testuser", "0", "1") orelse return error.TestUnexpectedResult;
    const seg = buf[0..len];
    try std.testing.expect(startsWith(seg, "HKIDN:3:2+"));
    try std.testing.expect(seg[seg.len - 1] == '\'');
    try std.testing.expect(std.mem.indexOf(u8, seg, "20041133") != null);
    try std.testing.expect(std.mem.indexOf(u8, seg, "testuser") != null);
}

test "buildAnonInit produces valid envelope with 9999999999 customer_id" {
    var s = FintsSession.init("20041133", "https://x.de/f", "user", "pin");
    s.product_id_len = 25;
    @memcpy(s.product_id[0..25], "F7C4049477F6136957A46EC28");

    var buf: [4096]u8 = undefined;
    const len = buildAnonInit(&s, &buf) orelse return error.TestUnexpectedResult;
    const msg = buf[0..len];

    // Must start with HNHBK and end with HNHBS
    try std.testing.expect(startsWith(msg, "HNHBK:1:3+"));
    // Must contain HKIDN and HKVVB
    try std.testing.expect(std.mem.indexOf(u8, msg, "HKIDN") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "HKVVB") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "HNHBS") != null);
    // Must use 9999999999 as anonymous customer_id (FinTS spec)
    try std.testing.expect(std.mem.indexOf(u8, msg, "9999999999") != null);
    // Must NOT contain HNVSK (bare envelope for standard banks)
    try std.testing.expect(std.mem.indexOf(u8, msg, "HNVSK") == null);
}

test "buildAnonInitWithEnvelope wraps in HNVSK/HNVSD" {
    var s = FintsSession.init("10070000", "https://fints.deutsche-bank.de/", "user", "pin");
    s.product_id_len = 25;
    @memcpy(s.product_id[0..25], "F7C4049477F6136957A46EC28");

    var buf: [8192]u8 = undefined;
    const len = buildAnonInitWithEnvelope(&s, &buf) orelse return error.TestUnexpectedResult;
    const msg = buf[0..len];

    // Must start with HNHBK
    try std.testing.expect(startsWith(msg, "HNHBK:1:3+"));
    // Must contain security envelope segments
    try std.testing.expect(std.mem.indexOf(u8, msg, "HNVSK:998:3+PIN:1+998") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "HNVSD:999:1+@") != null);
    // Must contain HKIDN and HKVVB inside envelope
    try std.testing.expect(std.mem.indexOf(u8, msg, "HKIDN") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "HKVVB") != null);
    // Must use 9999999999 as anonymous user
    try std.testing.expect(std.mem.indexOf(u8, msg, "9999999999") != null);
    // Size field must match actual message length
    const size_str = msg[10..22];
    const declared_size = std.fmt.parseInt(usize, size_str, 10) catch return error.TestUnexpectedResult;
    try std.testing.expectEqual(len, declared_size);
}

test "FintsSession detects bank_family from URL" {
    const s1 = FintsSession.init("10070000", "https://fints.deutsche-bank.de/", "u", "p");
    try std.testing.expectEqual(banks_mod.BankFamily.deutsche_bank, s1.bank_family);

    const s2 = FintsSession.init("10010010", "https://hbci.postbank.de/banking/hbci.do", "u", "p");
    try std.testing.expectEqual(banks_mod.BankFamily.postbank, s2.bank_family);

    const s3 = FintsSession.init("20041133", "https://fints.comdirect.de/fints", "u", "p");
    try std.testing.expectEqual(banks_mod.BankFamily.standard, s3.bank_family);
}

test "writeEnvelope size field is correct" {
    var s = FintsSession.init("12345678", "https://x.de/f", "u", "p");
    var buf: [4096]u8 = undefined;
    const inner = "HKIDN:3:2+12345678+0+0+1'";
    const len = writeEnvelope(&s, &buf, inner) orelse return error.TestUnexpectedResult;

    // Extract size from header (after "HNHBK:1:3+", 12 digits)
    const size_start = 10;
    const size_str = buf[size_start .. size_start + 12];
    const declared_size = std.fmt.parseInt(usize, size_str, 10) catch return error.TestUnexpectedResult;
    try std.testing.expectEqual(len, declared_size);
}

test "formatFixedWidth pads to 12 digits" {
    var buf: [12]u8 = undefined;
    formatFixedWidth(&buf, 95);
    try std.testing.expectEqualStrings("000000000095", &buf);
}

test "parseResponse extracts response codes" {
    var s = FintsSession.init("12345678", "https://x.de/f", "u", "p");
    var resp = ParsedResponse.init();
    const data = "HIRMG:2:2+0010:Nachricht entgegengenommen+0100:Dialog initialisiert'";
    parseResponse(&s, data, &resp);

    try std.testing.expectEqual(@as(u8, 2), resp.code_count);
    try std.testing.expectEqualStrings("0010", resp.codes[0].codeSlice());
    try std.testing.expect(resp.codes[0].isSuccess());
}

test "parseResponse extracts HIRMS reference and parameter" {
    var s = FintsSession.init("12345678", "https://x.de/f", "u", "p");
    var resp = ParsedResponse.init();
    const data = "HIRMS:3:2:4+3040:4:Weitere Daten folgen:TD_TOKEN_123'";
    parseResponse(&s, data, &resp);

    try std.testing.expectEqual(@as(u8, 1), resp.code_count);
    try std.testing.expectEqualStrings("3040", resp.codes[0].codeSlice());
    try std.testing.expectEqualStrings("4", resp.codes[0].referenceSlice());
    try std.testing.expectEqualStrings("Weitere Daten folgen", resp.codes[0].textSlice());
    try std.testing.expectEqualStrings("TD_TOKEN_123", resp.codes[0].parameterSlice());
}

test "parseResponse detects error codes" {
    var s = FintsSession.init("12345678", "https://x.de/f", "u", "p");
    var resp = ParsedResponse.init();
    const data = "HIRMG:2:2+9800:Nicht erlaubt'";
    parseResponse(&s, data, &resp);

    try std.testing.expectEqual(@as(u8, 1), resp.code_count);
    try std.testing.expect(resp.codes[0].isError());
}

test "parseResponse extracts dialog_id from HNHBK with HNVSK binary data" {
    var s = FintsSession.init("20041177", "https://x.de/f", "u", "p");
    var resp = ParsedResponse.init();

    // Build data with HNHBK + HNVSK (with @8@ null bytes) + HNHBS
    var data: [512]u8 = undefined;
    var pos: usize = 0;
    const hnhbk = "HNHBK:1:3+000000000200+300+TestDid123+1'";
    @memcpy(data[pos .. pos + hnhbk.len], hnhbk);
    pos += hnhbk.len;
    const vsk_pre = "HNVSK:998:3+PIN:1+998+1+2::0+1+2:2:13:@8@";
    @memcpy(data[pos .. pos + vsk_pre.len], vsk_pre);
    pos += vsk_pre.len;
    @memset(data[pos .. pos + 8], 0);
    pos += 8;
    const vsk_post = ":5:1+280:20041177:u:V:0:0+0'";
    @memcpy(data[pos .. pos + vsk_post.len], vsk_post);
    pos += vsk_post.len;
    const hnhbs = "HNHBS:3:1+1'";
    @memcpy(data[pos .. pos + hnhbs.len], hnhbs);
    pos += hnhbs.len;

    parseResponse(&s, data[0..pos], &resp);
    try std.testing.expectEqualStrings("TestDid123", s.dialogIdSlice());
}

test "parseResponse extracts system ID from HISYN" {
    var s = FintsSession.init("12345678", "https://x.de/f", "u", "p");
    var resp = ParsedResponse.init();
    const data = "HISYN:5:4+mySystemId123'";
    parseResponse(&s, data, &resp);

    try std.testing.expectEqualStrings("mySystemId123", s.systemIdSlice());
}

test "buildAuthInit uses MS role code in HNSHK and HNVSK" {
    var s = FintsSession.init("20041177", "https://x.de/f", "46236380", "191819");
    s.product_id_len = 25;
    @memcpy(s.product_id[0..25], "F7C4049477F6136957A46EC28");
    @memcpy(s.tan_sec_func[0..3], "902");
    s.tan_sec_func_len = 3;
    s.system_id_len = 28;
    @memcpy(s.system_id[0..28], "DEc3N2PD/ZwBAACkKjPRyAWCCgQA");

    var buf: [8192]u8 = undefined;
    const len = buildAuthInit(&s, &buf) orelse return error.TestUnexpectedResult;
    const msg = buf[0..len];

    try std.testing.expect(std.mem.indexOf(u8, msg, "HNVSK:998:3+PIN:2+998+1+2::DEc3N2PD/ZwBAACkKjPRyAWCCgQA") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "HNSHK:2:4+PIN:1+902+") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "+1+1+2::DEc3N2PD/ZwBAACkKjPRyAWCCgQA+1+1:") != null);
}

test "parseResponse extracts TAN challenge" {
    var s = FintsSession.init("12345678", "https://x.de/f", "u", "p");
    var resp = ParsedResponse.init();
    const data = "HITAN:5:7+4++REF123+Bitte TAN eingeben+moredata'";
    parseResponse(&s, data, &resp);

    try std.testing.expect(resp.has_tan_request);
    try std.testing.expect(s.has_pending_tan);
    try std.testing.expectEqualStrings("REF123", s.challenge_ref[0..s.challenge_ref_len]);
}

test "SegmentIterator splits correctly" {
    const data = "SEG1:1:1+data1'SEG2:2:1+data2'SEG3:3:1+data3'";
    var iter = SegmentIterator{ .data = data, .pos = 0 };

    const s1 = iter.next() orelse return error.TestUnexpectedResult;
    try std.testing.expect(startsWith(s1, "SEG1"));

    const s2 = iter.next() orelse return error.TestUnexpectedResult;
    try std.testing.expect(startsWith(s2, "SEG2"));

    const s3 = iter.next() orelse return error.TestUnexpectedResult;
    try std.testing.expect(startsWith(s3, "SEG3"));

    try std.testing.expect(iter.next() == null);
}

test "parseResponse concatenates split HIKAZ mt940 payload" {
    var s = FintsSession.init("20041177", "https://x.de/f", "u", "p");
    var resp = ParsedResponse.init();
    const data = "HIKAZ:1:5+@5@abcde'HIKAZ:2:5+@5@12345'";
    parseResponse(&s, data, &resp);

    try std.testing.expectEqual(@as(u16, 10), resp.mt940_len);
    try std.testing.expectEqualStrings("abcde12345", resp.mt940_data[0..resp.mt940_len]);
}

test "extractMt940 prefers field with MT940 markers" {
    var s = FintsSession.init("20041177", "https://x.de/f", "u", "p");
    var resp = ParsedResponse.init();
    const data = "HIKAZ:1:5+@6@ABCDEF+@14@:20:START\\n:61:'";
    parseResponse(&s, data, &resp);
    try std.testing.expect(std.mem.indexOf(u8, resp.mt940_data[0..resp.mt940_len], ":20:START") != null);
}

test "parseResponse extracts HICAZS camt format token" {
    var s = FintsSession.init("20041177", "https://x.de/f", "u", "p");
    var resp = ParsedResponse.init();
    const data = "HICAZS:2:1+urn?:iso?:std?:iso?:20022?:tech?:xsd?:camt.053.001.02'";
    parseResponse(&s, data, &resp);

    try std.testing.expect(s.supports_camt);
    try std.testing.expect(std.mem.indexOf(u8, s.camtFormatSlice(), "camt.053.001.02") != null);
    try std.testing.expectEqual(@as(u16, 0), resp.camt_len);
}

test "parseResponse extracts HICAZ xml payload" {
    var s = FintsSession.init("20041177", "https://x.de/f", "u", "p");
    var resp = ParsedResponse.init();
    const xml = "<Document><BkToCstmrStmt><Stmt/></BkToCstmrStmt></Document>";

    var msg_buf: [512]u8 = undefined;
    const prefix = "HICAZ:1:1+foo+bar+@";
    @memcpy(msg_buf[0..prefix.len], prefix);
    var pos: usize = prefix.len;
    const len_written = writeUint(msg_buf[pos..], xml.len) orelse return error.TestUnexpectedResult;
    pos += len_written;
    msg_buf[pos] = '@';
    pos += 1;
    @memcpy(msg_buf[pos .. pos + xml.len], xml);
    pos += xml.len;
    msg_buf[pos] = '\'';
    pos += 1;

    parseResponse(&s, msg_buf[0..pos], &resp);
    try std.testing.expectEqual(@as(u16, @intCast(xml.len)), resp.camt_len);
    try std.testing.expect(std.mem.indexOf(u8, resp.camt_data[0..resp.camt_len], "<Document>") != null);
}

test "parseHitab extracts typical TAN media names" {
    const seg = "HITAB:6:4+M:1:12345:0:iPhone von Max:SMS+P:0:00000:0:photoTAN App'";
    var media: [8]TanMedium = undefined;
    const n = parseHitab(seg, &media);
    try std.testing.expectEqual(@as(u8, 2), n);
    try std.testing.expectEqualStrings("iPhone von Max", media[0].nameSlice());
    try std.testing.expectEqual(@as(u8, 1), media[0].status);
    try std.testing.expectEqualStrings("photoTAN App", media[1].nameSlice());
}

test "parseHitab handles reordered tokens and picks best name token" {
    // Name is intentionally the longest non-numeric token in this entry.
    const seg = "HITAB:6:4+P:1:1:2:3:DeviceNameLongerThanOthers:XYZ:123'";
    var media: [8]TanMedium = undefined;
    const n = parseHitab(seg, &media);
    try std.testing.expectEqual(@as(u8, 1), n);
    try std.testing.expectEqualStrings("DeviceNameLongerThanOthers", media[0].nameSlice());
    try std.testing.expectEqual(@as(u8, 1), media[0].status);
}

test "parseHitab supports names with non-ascii bytes" {
    const seg = "HITAB:6:4+M:1:123:0:Ger\xc3\xa4t M\xc3\xbcller'";
    var media: [8]TanMedium = undefined;
    const n = parseHitab(seg, &media);
    try std.testing.expectEqual(@as(u8, 1), n);
    try std.testing.expectEqualStrings("Ger\xc3\xa4t M\xc3\xbcller", media[0].nameSlice());
}

test "ResponseCode classification" {
    var c: ResponseCode = undefined;
    c.code = "0010".*;
    try std.testing.expect(c.isSuccess());
    try std.testing.expect(!c.isError());

    c.code = "9800".*;
    try std.testing.expect(!c.isSuccess());
    try std.testing.expect(c.isError());

    c.code = "0030".*;
    try std.testing.expect(c.isTanRequired());

    c.code = "3920".*;
    try std.testing.expect(c.isTanRequired());
}
