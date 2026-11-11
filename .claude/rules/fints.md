# FinTS 3.0 Technical Notes

Purpose: protocol-level reference for `libwimg` FinTS implementation.
Audience: engineers touching `libwimg/src/fints.zig`, `root.zig`, `mt940.zig`, `camt.zig`.

## Scope

- Native-only FinTS (`iOS`), no WASM transport.
- Protocol implemented in Zig, transport provided by iOS callback (`URLSession`).
- Current verified bank: Comdirect (`BLZ 20041177`).
- Top-bank matrix validates 8 major banks via anonymous init probing.

## End-to-End Flow (Current)

1. Sync init (bootstrap, sec func `999`), parse BPD/UPD/HITANS/HIKAZS/HICAZS.
2. Select TAN mechanism from `3920` (prefer two-step, e.g. `902`).
3. If `tan_medium_required` (description_required=2, supported_media_number>1):
   - Send HKTAB to fetch TAN media list.
   - Parse HITAB response for medium names.
   - User selects medium → stored in session `tan_medium_name`.
4. Auth init (HKTAN process-4 for `HKIDN` when two-step mode).
5. If challenge:
   - `nochallenge`/empty -> continue automatically.
   - Decoupled (HITAN process variant `S`) -> auto-poll via HKTAN process-S.
   - photoTAN/TAN challenge -> return to UI.
6. Fetch statements (`HKKAZ`/`HKCAZ` version negotiated from BPD + process-4 `HKTAN`).
   - HKKAZ v5 (Account2), v6 (Account3), v7 (KTI1) — version from `HIKAZS`.
   - Transparent MT940 → CAMT fallback when `HIKAZS` absent but `HICAZS` present.
7. If TAN required for fetch:
   - Submit via HKTAN process-2 with `task_reference`.
8. Parse `HIKAZ` (MT940) or `HICAZ` (CAMT XML) response(s), insert transactions.
9. Follow touchdown pagination via structured `3040` parameter extraction.
10. End dialog (`HKEND`), clear sensitive state.

## Critical Wire-Format Rules

- `HNHBK` size must match final message length exactly.
- `dialog_id`/`system_id` must be preserved across recursive `HNVSD` parsing.
- Segment numbering must be contiguous.
- DEG colons in account/group fields must remain structural (`:`), not escaped.
- FinTS binary fields are `@len@<raw-bytes>` and may contain delimiters.
  Parsers must be length-aware, not delimiter-only.
- `HITANS` and `HITAN` must be dispatched separately (`HITANS:` first).

## TAN-Specific Rules

- `HKTAN` process-2 (submit) must include `task_reference` from prior `HITAN`.
- Wrong/missing reference typically yields `9120`/`9110`.
- TAN submit request must still include correct signature footer content
  (`PIN:TAN` shape as required by current envelope/signature builder).
- On successful response with statement payload, clear stale TAN state immediately.
- TAN method selection: read the allowed methods from the `3920` parameters
  (`3920::text:910:911:923`), keep only ones defined in `HITANS` with process 2,
  prefer a decoupled (app approval) method. Text scan is only a fallback.
- HKTAN version = the `HITANS` version that defines the selected method, not the
  highest advertised (Sparkasse: chipTAN in v6, pushTAN 2.0 in v7).
- `HITANS` layout: `+J:N:0:` prefix, then fixed-width entries (v6 = 21 tokens,
  v7 = 26). `parseHitansMethods` fills `session.tan_methods`.
- Decoupled is signalled by response code `3955` on the challenge and `3956` on a
  status poll that is still pending. The HITAN echoes the request's process, and a
  status reply may have no challenge text or task reference (keep the original).
- The TAN medium picker is only required for typed-TAN methods. Decoupled methods
  send no medium name even when `description_required=2` (python-fints: Sparkasse
  accepts an empty name for pushTAN).
- Decoupled TAN (process-S): empty TAN payload, no PIN in signature, poll loop
  with BPD-derived timings (`decoupled_max_poll_number`, `wait_before_first_poll`,
  `wait_before_next_poll`, `automated_polling_allowed`).

## TAN Medium Selection (HKTAB/HITAB)

- Banks with `description_required=2` and `supported_media_number>1` require
  explicit TAN medium selection before business segments (HKKAZ etc.).
- C ABI: `wimg_fints_get_tan_media` opens its own dialog (HKIDN + HKVVB + HKTAN
  process 4 with segment reference `HKTAB`, which needs no TAN), sends
  `HKTAB:3:<v>+0+A'` in it (v = highest of 4/5 from `HITABS`), closes the dialog
  and returns the parsed HITAB media names as JSON array. HKTAB outside a
  dialog is invalid.
- HITAB name = first text token after class and status; the masked phone number
  and a debit IBAN come later and can be longer.
- C ABI: `wimg_fints_set_tan_medium` stores selected name in session
  `tan_medium_name` for inclusion in HKTAN process-4.
- iOS: `FinTSView` shows `.tanMediumSelect` stage after connect if
  `tan_medium_required=true` in connect response.

## HKKAZ Version Negotiation

- Default HKKAZ version is v5.
- `HIKAZS` BPD segment advertises supported versions; keep highest (v5/v6/v7).
- v5: Account2 DEG (Ktonr:Unterkonto:280:BLZ).
- v6: Account3 DEG (same as v5 for current implementation).
- v7: KTI1 DEG (IBAN+BIC+account+subaccount+280:BLZ).
- If no `HIKAZS` but `HICAZS` present → CAMT fallback via `HKCAZ`.

## KTI1 Accounts (HKKAZ v7, HKCAZ)

- KTI1 is ONE data element: `IBAN:BIC:Konto:Unterkonto:280:BLZ`, parts separated
  by `:`. Splitting it with `+` shifts every following field (bank rejects).
- IBAN comes from the data element after the account in `HIUPD`, BIC from the
  bank catalog. Without an IBAN the national form `::Konto:Unterkonto:280:BLZ` is sent.
- python-fints reference: `HKKAZ:3:7+IBAN:BIC+N+from+to`,
  `HKCAZ:3:1+IBAN:BIC+<camt urn>+N+from+to`.

## CAMT-only Banks

- A BPD with `HICAZS` but no `HIKAZS` (Atruvia: Volks-/Raiffeisenbanken, Nov 2026)
  means MT940 is gone. Start with `HKCAZ`; never send `HKKAZ` there.
- `session.supports_mt940` is set from `HIKAZS` v5–v7. Unknown BPD keeps MT940 first.

## CAMT Fallback

- `camt.zig` parser: Ntry extraction, multi-Ustrd concatenation, Amt Ccy parsing.
- Same Transaction model, same DB/categorization pipeline as MT940.
- 112 tests covering CAMT parsing.

## Touchdown Paging

- Response code `3040` carries continuation token.
- Prefer structured `parameter` field from ResponseCode, fallback to `text` field.
- Normalize token: strip whitespace, extract after last `:` or `=`, reject spaces.
- Continue HKKAZ/HKCAZ requests with touchdown field until no `3040` remains.

## HKKAZ and Paging

- Use real account connection (from `HIUPD`), not login user id fallback when available.
- `3040` means more data is available and includes continuation (touchdown) token.
- Continue requesting `HKKAZ` with touchdown field until no `3040` token remains.
- Single page often returns around 100 transactions; this is not "all history".

## MT940 Parsing Learnings

- Banks may split `HIKAZ` across multiple segments; concatenate booked streams.
- Normalize parser input:
  - `@@` -> `\r\n`
  - `-0000` -> `+0000`
- Handle mixed line endings (`\n`, `\r\n`, `\r`).
- `:61:` supports optional funds code char after debit/credit marker.
- Parse should tolerate bank-specific variants before classifying payload as invalid.

## Error Code Cheat Sheet (Observed)

- `0020`: request executed / dialog initialized (context dependent).
- `0030`: TAN required.
- `3040`: additional information/continuation available (touchdown).
- `3050`: UPD out of date (usually informational).
- `3060`: warnings present.
- `3076`: strong customer authentication not required.
- `3920`: available TAN methods listed.
- `3955`: decoupled TAN — approve in the banking app.
- `3956`: decoupled TAN — approval still pending, poll again.
- `9010`: order not processed due to general message errors.
- `9050`: message contains errors.
- `9110`: invalid order message / unknown structure.
- `9120`: invalid order message / initialization missing.
- `9400`: not permitted / access denied (ING anon mode).
- `9800`: dialog aborted.

## Top-Bank Matrix

`scripts/test-bank-matrix.ts` probes 8 target banks with anonymous init:
- Comdirect, Berliner Sparkasse, Deutsche Bank, Commerzbank, Postbank, ING, DKB, Atruvia representative.
- Tests: endpoint reachability, BPD presence, HIKAZS/HICAZS versions, TAN methods, response codes.
- Last result: 8/8 reachable, 3/8 full BPD, 6/8 structural OK.
- Deutsche Bank + Postbank reject with `9110` — likely need security envelope or bank-family-specific init.

## Bank Catalog Drift

`scripts/check-bank-drift.ts` compares official FinTS institute CSV against `banks.zig`:
- Reports: missing banks (in CSV not in catalog), URL changes, removed banks.
- Run manually when new CSV received from registrierung@hbci-zka.de.

## Debugging Playbook

When something fails, log all of:

- Outgoing request preview (`auth`, `fetch`, `send_tan`).
- Response code list (`HIRMG`/`HIRMS`) with text.
- `dialog_id`, `system_id`, `msg_num`.
- TAN state (`has_pending_tan`, challenge len, hhduc len, task_reference).
- `HIKAZ` extraction sizes (`mt940_len`, parsed count, parse errors).
- MT940 preview bytes (first 150-200 chars) after extraction.

If a bank says `9110`:

1. Compare failing message against a known-good library (python-fints).
2. Validate envelope size and segment numbering.
3. Validate TAN segment version/arity and mandatory empty placeholders.
4. Verify binary field parsing is not truncating payloads.

## Background Fetch Constraints (iOS)

- Works automatically only when no interactive TAN is needed (`3076`/`nochallenge`).
- If TAN/photoTAN is required, user interaction is mandatory.
- BG tasks are time-limited; multi-page imports can be interrupted.
- Recommended UX:
  - attempt scheduled background fetch,
  - auto-import if no TAN required,
  - persist pending challenge state and notify user if TAN required.
