# TODO

Open work only, grouped by area; finished work moves to [CHANGELOG.md](CHANGELOG.md). How the pieces fit in [CLAUDE.md](CLAUDE.md) and `.claude/rules/`; lessons in [docs/field-notes/](docs/field-notes/README.md). Only the next one to two weeks of work.

## Before launch
- [x] **One schema, v1 (user, 2026-11-14)**: done 2026-11-15 (`db.zig` `migrate()`, meta key `schema`). The Poco was at 23 and is relabelled.

## Manual entries (user, 2026-11-14)
- [x] Marked (`transactions.source = 'manual'`, v22/v23), editable and deletable on Android with real deletion across devices (`deleted_transactions` markers), left out of salary detection, "Von Hand" filter in Umsätze. Done 2026-11-14; checked on the phone by the user 2026-11-17.
- [ ] iOS: the same (edit, delete, filter) once Android is settled.

## FinTS (from the Comdirect analysis, 2026-11-16)
- [x] Task reference (HITAN) and challenge text: unescaped, challenge JSON-escaped for the app, task reference buffer 40 bytes (2026-11-16).
- [x] HITAB medium names: escape-aware split, unescaped (2026-11-16).
- [x] `isEscaped` counts the run of '?' (2026-11-16).
- [x] Kunden-ID escaped in HNSHK/HNVSK key names and the fallback account (2026-11-16).
- [ ] Encode outgoing text as ISO-8859-1 like python-fints (we send UTF-8): matters for names/TAN media with umlauts.
- [x] System id kept per connection (`BankConnection.systemId`, connect without HKSYN, fresh sync if the bank refuses it) (2026-11-16). Two ↻ on Comdirect work (user, 2026-11-17).
- [x] `_debug_*` fields gone from the connect JSON (2026-11-16).

## Bank sources (decided 2026-11-16, not started)
- [x] (2026-11-17, `import.zig`: `apply` with `TwinRule`, used by the FinTS fetch and statement files; pending, balance and CSV still in their callers) One import seam in libwimg: every source (FinTS, CSV, file import, later bunq/Fio) hands over a `Batch` (account, booked, pending, balance, twin rule) and one `import.apply(db, batch)` does duplicates/twins, pending, categories and balance. Plain data + functions, no plugin system, no login framework (sign-in stays inside each source). Sketch:
  `pub const Batch = struct { account: []const u8, booked: []const Transaction, pending: []const Transaction, balance: ?Balance, twins: TwinRule };` (`.same_id` normally, `.day_and_amount` for CAMT next to MT940 history) and `pub fn apply(db: *Db, batch: Batch) ImportResult`. Moves today's twin check, pending replace, rule categorizing and balance out of `wimg_fints_fetch` and the CSV import. Background: `.claude/rules/banking-aggregators.md` (update 2026-11-16).
- [x] CAMT/MT940 file import next to CSV (2026-11-17): `wimg_parse_statement` / `wimg_import_statement`, account from the BLZ/IBAN (same as FinTS), twins skipped, balance set; Android Import screen. iOS UI not yet. Not handled: ZIP archives of several CAMT files.
- [ ] CAMT by default where the bank advertises HICAZS, MT940 as legacy fallback.
- [ ] Enable Banking: support ticket 452772778232 sent 2026-11-16 (personal-use apps inside a public app, shared https redirect, non-commercial option). Auto-reply: without an agreement, tickets are "processed in automated way and you may not hear back". If nothing comes back, ask sales (info@enablebanking.com, per their FAQ). Until a written yes: don't build. Only ever as a labelled extra, Enable Banking sees bookings in transit.
- [ ] Direct bank connectors (bunq, Fio, comdirect REST) only on user demand; comdirect REST needs a TAN per session, FinTS doesn't.

## Android
- [ ] GitHub APK: CI now builds the `github` build type (release code, not debuggable, its own permanent key `~/wimg-apk.p12`, separate from the Play upload key). Key made, secrets set and backed up 2026-11-17. Left: check the first CI APK, and tell GitHub users in the release notes: one last uninstall/reinstall (Sync or backup file first).
- [ ] Play test updates: 2–3 during the 16 days, each with release notes from `docs/play-store-test-log.md`; paste the new store descriptions (`docs/play-store-listing.md`) with the first one.
- [x] Filter panel on Umsätze, option A from brief 19 (built 2026-11-18, checked on the Poco with real data; the closed panel shows a plain line "22 Umsätze · Sonstiges · seit 29.10." instead of tag pills, which looked heavy on the phone; dark mode checked on the Poco, 360 dp on the emulator 2026-11-18: panel fits; in English the filter button drops its count there, by the bar rule "a label that doesn't fit is left out", the band line still names the filters) (`~/Desktop/wimg-redesign/export/36-Filter-Panel/`, boards 02–04, 07–09; decided 2026-11-17):
  - four rows Art · Konto · Zeitraum · Kategorie, each with its current value on the right (light background when not "Alle"); a row opens a short list in the same panel, with a back arrow;
  - Kategorie lists only the categories in the period, sorted by spending, with the amount, then "Mehr (n)"; Zeitraum stacked vertically (no cut-off row);
  - closed panel: small tags under the sum in the band, a count on the filter button;
  - filtered "Summe der Treffer" is the total and stands still while scrolling; it rolls once only when the data changes;
  - without a filter, keep the bank balance following the scroll (the balance on the topmost row's day);
  - left out for now: the sticky "November bis hier" line (day totals already orient), options B and C.
- [ ] Play upload from CI, like TestFlight (before the next test update): after every tag, upload `app-release.aab` to the closed track "Alpha" with the "What's new" text from files in the repo (e.g. `docs/play-whats-new/de-DE.txt`, `en-US.txt`). Play Developer API (edits: insert → bundles.upload → tracks.update → commit), a short script, no third-party Action (it would see the secrets). Needs from the user once: a Google Cloud service account with a JSON key, invited in Play Console › Users and permissions with "Release to testing tracks" for wimg only; the key as one GitHub secret. Until then: download `wimg-android-play` from the run and upload by hand.
- [ ] Android walk-through test (when there's time): a script that goes through the whole app like a person, opening every place, tapping and swiping (filter panel and its lists, changing a category and Undo, Settings switches, the places menu, back), with a screenshot or short recording per step, on demo data. Every change can then be checked the same way, instead of tapping by hand and missing things (2026-11-18: the panel closing on a tap on its empty part, and the Design switch that always showed "System", were found by hand). Start from what exists: `adb shell input` taps as in the frame log runs (`android-performance.md`), or a Compose UI test.
- [ ] Notification tap: not reproducible on the emulator anymore (foreground and background, 2026-11-15); confirm with a real notification on the phone.
- [x] Price-change notification (2026-11-17, `BackgroundRefresh.notifyPriceRise`, switch "Preis gestiegen", on by default). Runs recurring detection after a background import first.
- [x] Recurring detection runs in libwimg after every fetch or CSV import that added bookings (2026-11-17).
- [ ] Merchant names: card payments show raw bank text ("PAYSEND, Dublin IE Karte Nr. …", "KD.1210843747 WIR SAGEN"). Clean them up in libwimg `booking.zig` once the user sends full payment references.
- [x] Squirrel: the band dims to evening and today's stitch is sewn in during "Tag ohne Ausgaben" (2026-11-17).
- [x] Squirrel: "Gehalt ist da" refills the ring (2026-11-17). Moments wait for the launch animation since 2026-11-17 (they used to play underneath it).
- [x] Minus periods get the Rückblick cards that are true (quiet days, a caught price), decided by the user 2026-11-17.
- [ ] On the Poco: Monat widget at 2×2 (compact layout) and an empty account keeping the switch (both fixed 2026-11-17, not seen on a phone yet).
