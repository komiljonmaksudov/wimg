# C ABI — libwimg Public API

The exact `export fn` list in `libwimg/src/root.zig` (header:
`libwimg/include/libwimg.h`). Swift calls it directly, Android through the JNI
shim `wimg-android/app/src/main/cpp/wimg_jni.c`, the sync server links it
natively (MCP), the rollback Worker loads it as WASM.

Pointer returns are length-prefixed JSON: 4-byte little-endian `u32` length,
then the bytes. Free with `wimg_free`. `null` / negative `i32` = error, details
via `wimg_get_error`.

```zig
// Lifecycle
export fn wimg_init(path: [*:0]const u8) i32
export fn wimg_close() void
export fn wimg_free(ptr: [*]const u8, len: u32) void
export fn wimg_alloc(size: u32) ?[*]u8
export fn wimg_get_error() ?[*]const u8

// Import
export fn wimg_parse_csv(data: [*]const u8, len: u32) ?[*]const u8
export fn wimg_import_csv(data: [*]const u8, len: u32) ?[*]const u8

// Transactions
export fn wimg_get_transactions() ?[*]const u8
export fn wimg_get_transactions_filtered(acct: [*]const u8, acct_len: u32) ?[*]const u8
export fn wimg_get_pending(acct: [*]const u8, acct_len: u32) ?[*]const u8   // "Vorgemerkt": device-only, never summed
export fn wimg_set_category(id: [*]const u8, id_len: u32, category: u8) i32
export fn wimg_set_excluded(id: [*]const u8, id_len: u32, excluded: u8) i32
export fn wimg_auto_categorize() i32
export fn wimg_get_categories() ?[*]const u8
export fn wimg_add_manual_transaction(date_ptr: [*]const u8, date_len: u32, desc_ptr: [*]const u8, desc_len: u32, amount_cents: i64, category: u8, acct_ptr: [*]const u8, acct_len: u32) i32

// Rules (Einstellungen › Gelernte Regeln)
export fn wimg_get_rules() ?[*]const u8                  // [{id, pattern, category, priority}]
export fn wimg_delete_rule(id: i64, reset: u8) i32

// Summaries, recurring, snapshots
export fn wimg_get_summary_filtered(year: u32, month: u32, acct: [*]const u8, acct_len: u32) ?[*]const u8
export fn wimg_detect_recurring() i32
export fn wimg_get_recurring() ?[*]const u8
export fn wimg_get_recurring_payments(id_ptr: [*]const u8, id_len: u32) ?[*]const u8
export fn wimg_set_recurring_hidden(id: [*]const u8, id_len: u32, hidden: u8) i32
export fn wimg_edit_recurring(id: [*]const u8, id_len: u32, name: [*]const u8, name_len: u32, category: i32, interval: [*]const u8, interval_len: u32, fixed_cents: i64) i32  // empty / <0 / minInt(i64) = as detected
export fn wimg_accept_recurring_price(id: [*]const u8, id_len: u32) i32
export fn wimg_set_recurring_oneoff(pattern_id: [*]const u8, pattern_len: u32, tx_id: [*]const u8, tx_len: u32, oneoff: u8) i32
export fn wimg_take_snapshot(year: u32, month: u32) i32
export fn wimg_get_snapshots() ?[*]const u8

// Accounts
export fn wimg_get_accounts() ?[*]const u8
export fn wimg_add_account(data: [*]const u8, len: u32) i32
export fn wimg_update_account(data: [*]const u8, len: u32) i32
export fn wimg_delete_account(id: [*]const u8, id_len: u32) i32
export fn wimg_set_account_hidden(id: [*]const u8, id_len: u32, hidden: u8) i32   // hidden: out of "Alle Konten" (filtered/pending/summary with empty account); wimg_get_transactions keeps it (search)

// Undo/Redo
export fn wimg_undo() ?[*]const u8
export fn wimg_redo() ?[*]const u8

// Sync + E2E crypto
export fn wimg_get_changes(since_ts: i64) ?[*]const u8
export fn wimg_apply_changes(data: [*]const u8, len: u32) i32
export fn wimg_derive_key(sync_key_ptr: [*]const u8, sync_key_len: u32) ?[*]const u8
export fn wimg_encrypt_field(pt_ptr: [*]const u8, pt_len: u32, key_ptr: [*]const u8, nonce_ptr: [*]const u8) ?[*]const u8
export fn wimg_decrypt_field(ct_ptr: [*]const u8, ct_len: u32, key_ptr: [*]const u8) ?[*]const u8

// Gehaltsmonat (period.zig). Dates YYYYMMDD. Periods JSON:
// {"mode","chosen","day","today","salary":{"key","title","amount","day","count","confirmed","last","next","overdue_days"}?,
//  "periods":[{"from","to","days","current","salary"?,"early_days"}] (newest first),
//  "other_income":[{"id","date","amount","title","key"}], "payers":[{"key","title","amount","count","last"}]}
export fn wimg_get_periods(today_ymd: u32, count: u32) ?[*]const u8
export fn wimg_get_summary_range(from_ymd: u32, to_ymd: u32, acct: [*]const u8, acct_len: u32) ?[*]const u8
export fn wimg_set_period_mode(mode_ptr: [*]const u8, mode_len: u32, day: u32) i32   // "calendar" | "salary" | "day"
export fn wimg_salary_answer(key_ptr: [*]const u8, key_len: u32, answer: u8) i32     // 1 yes, 0 no, 2 only this payer

// wimg Sync devices (board 21)
export fn wimg_touch_device(data: [*]const u8, len: u32) i32      // {"id","name","kind"} → 0 ok, 1 removed by another device, -1 error
export fn wimg_get_devices() ?[*]const u8                         // [{"id","name","kind","last_seen"}]
export fn wimg_remove_device(id: [*]const u8, id_len: u32) i32

// Export + raw SQL (MCP `query`)
export fn wimg_export_csv() ?[*]const u8
export fn wimg_export_db() ?[*]const u8
export fn wimg_query(sql_ptr: [*]const u8, sql_len: u32) ?[*]const u8

// Debts + goals — no platform calls these (UI removed 2026-05-14)
export fn wimg_get_debts() ?[*]const u8
export fn wimg_add_debt(data: [*]const u8, len: u32) i32
export fn wimg_mark_debt_paid(id: [*]const u8, id_len: u32, amount_cents: i64) i32
export fn wimg_delete_debt(id: [*]const u8, id_len: u32) i32
export fn wimg_get_goals() ?[*]const u8
export fn wimg_add_goal(data: [*]const u8, len: u32) i32
export fn wimg_contribute_goal(id: [*]const u8, id_len: u32, amount_cents: i64) i32
export fn wimg_delete_goal(id: [*]const u8, id_len: u32) i32

// FinTS — native only, @export'ed in a `comptime { if (!is_wasm) ... }` block
fn wimg_set_http_callback(cb: fints_http_mod.HttpCallback) callconv(.c) void
fn wimg_fints_connect(data: [*]const u8, len: u32) callconv(.c) ?[*]const u8         // {"blz","user","pin","product"}
fn wimg_fints_send_tan(data: [*]const u8, len: u32) callconv(.c) ?[*]const u8        // {"tan":"..."}
fn wimg_fints_fetch(data: [*]const u8, len: u32) callconv(.c) ?[*]const u8           // {"from":"...","to":"..."}
fn wimg_fints_get_banks() callconv(.c) ?[*]const u8
fn wimg_fints_get_tan_media() callconv(.c) ?[*]const u8                               // HKTAB → media JSON
fn wimg_fints_set_tan_medium(data: [*]const u8, len: u32) callconv(.c) ?[*]const u8  // {"name":"..."}
```

## WASM (compact only)

`scripts/build-wasm.sh` → `wimg-sync/libwimg-compact.wasm`, used only by the
rollback Worker. `-Dcompact` defaults to `true`. Budget: 16 MB FBA (`root.zig`)
+ 4 × 8 MB VFS files (`wasm_vfs.c`) + 8 MB heap (`libc_shim.c`) + 1 MB stack.
