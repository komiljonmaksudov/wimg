#ifndef LIBWIMG_H
#define LIBWIMG_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// All functions returning pointers return length-prefixed JSON strings:
// first 4 bytes = uint32_t length (little-endian), then the string data.
// Caller must call wimg_free() on the returned pointer when done.

// --- Lifecycle ---

// Initialize the database at the given path. Returns 0 on success, -1 on error.
int32_t wimg_init(const char *db_path);

// Close the database and free resources.
void wimg_close(void);

// Free a pointer previously returned by other wimg_ functions.
void wimg_free(const uint8_t *ptr, uint32_t len);

// Get the last error message (length-prefixed string), or NULL if no error.
const uint8_t *wimg_get_error(void);

// --- Import ---

// Parse a CSV file without importing (preview only). Auto-detects format.
// Returns pointer to length-prefixed JSON: {"format":"...","total_rows":N,"transactions":[...]}
// Each transaction: {"id":"...","date":"YYYY-MM-DD","description":"...","amount":X.XX,"currency":"EUR","category":N}
// Returns NULL on error.
const uint8_t *wimg_parse_csv(const uint8_t *data, uint32_t len);

// Import a CSV file. Auto-detects format (Comdirect, Trade Republic, Scalable).
// Returns pointer to length-prefixed JSON: {"total_rows":N,"imported":N,"skipped_duplicates":N,"errors":N,"format":"...","categorized":N}
// Returns NULL on error.
const uint8_t *wimg_import_csv(const uint8_t *data, uint32_t len);

// Statement files (MT940 .sta/.mt940, CAMT .xml), recognized by content.
// Preview: {"format","account","total_rows","duplicates","transactions":[…]};
// NULL with the error "not a statement" for anything else (try CSV then).
const uint8_t *wimg_parse_statement(const uint8_t *data, uint32_t len);
// Import into the bank's account (BLZ from :25: or the IBAN); skips bookings whose
// twin (account, day, amount) is already here. Same JSON as wimg_import_csv.
const uint8_t *wimg_import_statement(const uint8_t *data, uint32_t len);

// --- Transactions ---

// Get all transactions as a length-prefixed JSON array.
const uint8_t *wimg_get_transactions(void);

// Set the category for a transaction by ID. Returns 0 on success, -1 on error.
int32_t wimg_set_category(const uint8_t *id, uint32_t id_len, uint8_t category);

// Set the excluded flag for a transaction. excluded=1 hides from summaries, excluded=0 restores.
int32_t wimg_set_excluded(const uint8_t *id, uint32_t id_len, uint8_t excluded);

// Re-run auto-categorization on all uncategorized transactions.
// Returns number of newly categorized, or -1 on error.
int32_t wimg_auto_categorize(void);

// --- Summaries ---


// --- Debts ---

// Get all debts as a length-prefixed JSON array.
const uint8_t *wimg_get_debts(void);

// Add a debt. Input is JSON: {"id":"...","name":"...","total":N,"monthly":N}
// Amounts are decimal (e.g. 1234.56), converted to cents internally.
int32_t wimg_add_debt(const uint8_t *data, uint32_t len);

// Mark a debt as partially paid. amount_cents is in cents.
int32_t wimg_mark_debt_paid(const uint8_t *id, uint32_t id_len, int64_t amount_cents);

// Delete a debt by ID.
int32_t wimg_delete_debt(const uint8_t *id, uint32_t id_len);

// --- Savings Goals ---

// Get all savings goals as a length-prefixed JSON array.
const uint8_t *wimg_get_goals(void);

// Add a savings goal. Input is JSON: {"id":"...","name":"...","icon":"...","target":N,"deadline":"YYYY-MM-DD"}
int32_t wimg_add_goal(const uint8_t *data, uint32_t len);

// Contribute to a savings goal. amount_cents is in cents.
int32_t wimg_contribute_goal(const uint8_t *id, uint32_t id_len, int64_t amount_cents);

// Delete a savings goal by ID.
int32_t wimg_delete_goal(const uint8_t *id, uint32_t id_len);

// --- Accounts ---

// Get all accounts as a length-prefixed JSON array.
const uint8_t *wimg_get_accounts(void);

// Add an account. Input is JSON: {"id":"...","name":"...","color":"#..."}
int32_t wimg_add_account(const uint8_t *data, uint32_t len);

// Update an account. Input is JSON: {"id":"...","name":"...","color":"#..."}
int32_t wimg_update_account(const uint8_t *data, uint32_t len);

// Hide (1) or show (0) an account: hidden ones leave "Alle Konten" lists and
// sums (get_transactions_filtered/get_pending/get_summary with empty account).
int32_t wimg_set_account_hidden(const uint8_t *id, uint32_t id_len, uint8_t hidden);

// Gehaltsmonat. Periods JSON (see .claude/rules/c-abi.md); today/from/to = YYYYMMDD.
const uint8_t *wimg_get_periods(uint32_t today_ymd, uint32_t count);
const uint8_t *wimg_get_summary_range(uint32_t from_ymd, uint32_t to_ymd, const uint8_t *acct, uint32_t acct_len);
int32_t wimg_set_period_mode(const uint8_t *mode, uint32_t mode_len, uint32_t day); // "calendar" | "salary" | "day"
int32_t wimg_salary_answer(const uint8_t *key, uint32_t key_len, uint8_t answer);   // 1 yes, 0 no, 2 only this one

// wimg Sync devices. touch: {"id","name","kind"} -> 0 ok, 1 removed by another
// device (stop syncing), -1 error. get: [{"id","name","kind","last_seen"}].
int32_t wimg_touch_device(const uint8_t *data, uint32_t len);
const uint8_t *wimg_get_devices(void);
int32_t wimg_remove_device(const uint8_t *id, uint32_t id_len);

// Delete an account by ID.
int32_t wimg_delete_account(const uint8_t *id, uint32_t id_len);

// Get transactions filtered by account (empty string = all).
const uint8_t *wimg_get_transactions_filtered(const uint8_t *acct, uint32_t acct_len);
/* Not-yet-booked ("vorgemerkt") transactions from the last bank fetch. Same JSON
   shape as wimg_get_transactions_filtered; device-only, never counted in totals. */
const uint8_t *wimg_get_pending(const uint8_t *acct, uint32_t acct_len);

// Get summary filtered by account.
const uint8_t *wimg_get_summary_filtered(uint32_t year, uint32_t month, const uint8_t *acct, uint32_t acct_len);

// --- Recurring ---

// Detect recurring payment patterns from transaction history.
// Clears existing patterns and re-detects. Returns count of patterns found, or -1 on error.
int32_t wimg_detect_recurring(void);

// Get all active recurring patterns as a length-prefixed JSON array.
// Each entry: {"id":"...","merchant":"...","amount":X.XX,"interval":"monthly","category":N,
//   "last_seen":"YYYY-MM-DD","next_due":"YYYY-MM-DD","active":1,"prev_amount":X.XX,"price_change":X.XX}
const uint8_t *wimg_get_recurring(void);

// Payments that belong to one recurring pattern (by pattern id), newest first,
// as a length-prefixed JSON array: [{"id":"...","date":"YYYY-MM-DD","amount":X.XX}].
// Unknown ids give [].
const uint8_t *wimg_get_recurring_payments(const uint8_t *id, uint32_t id_len);

// --- Categories ---

// Get all category metadata as a length-prefixed JSON array (static, no DB needed).
const uint8_t *wimg_get_categories(void);

// --- Snapshots ---

// Take a monthly snapshot for the given year/month. Returns 0 on success, -1 on error.
int32_t wimg_take_snapshot(uint32_t year, uint32_t month);

// Get all snapshots as a length-prefixed JSON array.
const uint8_t *wimg_get_snapshots(void);

// --- Export ---

// Export all transactions as CSV. Returns length-prefixed CSV string.
const uint8_t *wimg_export_csv(void);

// Export the full database as JSON (all tables). Returns length-prefixed JSON string.
const uint8_t *wimg_export_db(void);

// --- Undo/Redo ---

// Undo the last action. Returns length-prefixed JSON with undo info, or NULL.
// Recurring patterns: user decisions. Empty name / category < 0 / empty
// interval = as detected; fixed_cents == INT64_MIN = automatic amount.
int32_t wimg_set_recurring_hidden(const uint8_t *id, uint32_t id_len, uint8_t hidden);
int32_t wimg_edit_recurring(const uint8_t *id, uint32_t id_len, const uint8_t *name, uint32_t name_len, int32_t category,
                            const uint8_t *interval, uint32_t interval_len, int64_t fixed_cents);
int32_t wimg_accept_recurring_price(const uint8_t *id, uint32_t id_len);
int32_t wimg_set_recurring_oneoff(const uint8_t *pattern_id, uint32_t pattern_len, const uint8_t *tx_id, uint32_t tx_len, uint8_t oneoff);

// Rules (JSON [{id, pattern, category, priority}]) and deleting one; reset != 0
// makes the transactions it sorted uncategorised again.
const uint8_t *wimg_get_rules(void);
int32_t wimg_delete_rule(int64_t id, uint8_t reset);

// A transaction entered by hand (e.g. cash). date "YYYY-MM-DD", amount signed cents.
int32_t wimg_add_manual_transaction(const uint8_t *date, uint32_t date_len, const uint8_t *desc, uint32_t desc_len,
                                    int64_t amount_cents, uint8_t category, const uint8_t *acct, uint32_t acct_len);
// Manual entries only. 0 ok, 1 not a manual entry, -1 error.
int32_t wimg_delete_transaction(const uint8_t *id, uint32_t id_len);
int32_t wimg_update_manual_transaction(const uint8_t *id, uint32_t id_len, const uint8_t *date, uint32_t date_len,
                                       const uint8_t *desc, uint32_t desc_len, int64_t amount_cents, uint8_t category,
                                       const uint8_t *acct, uint32_t acct_len);

const uint8_t *wimg_undo(void);

// Redo the last undone action. Returns length-prefixed JSON, or NULL.
const uint8_t *wimg_redo(void);

// --- Sync ---

// Get all rows changed since `since_ts` (unix ms). Returns length-prefixed JSON.
// Format: {"rows":[{"table":"...","id":"...","data":{...},"updated_at":N},...]}
const uint8_t *wimg_get_changes(int64_t since_ts);

// Apply incoming sync changes (JSON). Returns count of applied rows, or -1 on error.
// Input: {"rows":[{"table":"...","id":"...","data":{...},"updated_at":N},...]}
int32_t wimg_apply_changes(const uint8_t *data, uint32_t len);

// --- Crypto (E2E encryption for sync) ---

// Derive a 32-byte encryption key from a sync key using HKDF-SHA256.
// Returns length-prefixed 32-byte key, or NULL on error.
const uint8_t *wimg_derive_key(const uint8_t *sync_key, uint32_t sync_key_len);

// Encrypt plaintext using XChaCha20-Poly1305.
// key must be 32 bytes. nonce must be 24 bytes.
// Returns length-prefixed base64(nonce + ciphertext + tag), or NULL on error.
const uint8_t *wimg_encrypt_field(const uint8_t *plaintext, uint32_t plaintext_len,
                                  const uint8_t *key, const uint8_t *nonce);

// Decrypt base64-encoded ciphertext using XChaCha20-Poly1305.
// key must be 32 bytes.
// Returns length-prefixed plaintext, or NULL on error.
const uint8_t *wimg_decrypt_field(const uint8_t *ciphertext, uint32_t ciphertext_len,
                                  const uint8_t *key);

// --- FinTS ---

// Set HTTP callback for platform-native HTTPS.
// On iOS, this should be set to a function using URLSession.
// Signature: int callback(url, url_len, body, body_len, out, out_len)
// Returns bytes written to out, or -1 on error.
typedef int32_t (*wimg_http_callback_t)(
    const uint8_t *url, uint32_t url_len,
    const uint8_t *body, uint32_t body_len,
    uint8_t *out, uint32_t out_len
);
void wimg_set_http_callback(wimg_http_callback_t callback);

// Connect to a bank via FinTS 3.0.
// Input JSON: {"blz":"20041133","user":"...","pin":"...","product":"..."}
// Returns length-prefixed JSON:
//   {"status":"ok"} on success
//   {"status":"tan_required","challenge":"..."} if TAN needed
//   {"status":"error","message":"..."} on failure
const uint8_t *wimg_fints_connect(const uint8_t *data, uint32_t len);

// Submit a TAN for the current FinTS dialog.
// Input JSON: {"tan":"123456"}
// Returns length-prefixed JSON: {"status":"ok"} or {"status":"error","message":"..."}
const uint8_t *wimg_fints_send_tan(const uint8_t *data, uint32_t len);

// Fetch bank statements via FinTS.
// Input JSON: {"from":"2026-01-01","to":"2026-03-01"}
// Fetches MT940 statements, parses them, and inserts into DB.
// Returns length-prefixed JSON: {"imported":N,"duplicates":N}
// May return {"status":"tan_required","challenge":"..."} if TAN is needed.
const uint8_t *wimg_fints_fetch(const uint8_t *data, uint32_t len);

// Get list of supported banks as JSON array.
// Each entry: {"blz":"...","name":"...","url":"..."}
const uint8_t *wimg_fints_get_banks(void);

// Fetch available TAN media from the bank (HKTAB).
// Requires active session (call wimg_fints_connect first).
// Returns length-prefixed JSON array: [{"name":"...","status":1},...]
// Returns "[]" if bank does not require TAN medium selection.
const uint8_t *wimg_fints_get_tan_media(void);

// Set the selected TAN medium name for subsequent requests.
// Input JSON: {"name":"iPhone von Max"}
// Must be called before wimg_fints_fetch if bank requires medium selection.
const uint8_t *wimg_fints_set_tan_medium(const uint8_t *data, uint32_t len);



#ifdef __cplusplus
}
#endif

#endif // LIBWIMG_H
