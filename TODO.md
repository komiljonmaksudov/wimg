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
- [ ] One import seam in libwimg: every source (FinTS, CSV, file import, later bunq/Fio) hands over a `Batch` (account, booked, pending, balance, twin rule) and one `import.apply(db, batch)` does duplicates/twins, pending, categories and balance. Plain data + functions, no plugin system, no login framework (sign-in stays inside each source). Sketch:
  `pub const Batch = struct { account: []const u8, booked: []const Transaction, pending: []const Transaction, balance: ?Balance, twins: TwinRule };` (`.same_id` normally, `.day_and_amount` for CAMT next to MT940 history) and `pub fn apply(db: *Db, batch: Batch) ImportResult`. Moves today's twin check, pending replace, rule categorizing and balance out of `wimg_fints_fetch` and the CSV import. Background: `.claude/rules/banking-aggregators.md` (update 2026-11-16).
- [ ] CAMT/MT940 file import next to CSV (parsers exist), on top of the seam: private, free, any bank with exports.
- [ ] CAMT by default where the bank advertises HICAZS, MT940 as legacy fallback.
- [ ] Enable Banking: support ticket 452772778232 sent 2026-11-16 (personal-use apps inside a public app, shared https redirect, non-commercial option). Auto-reply: without an agreement, tickets are "processed in automated way and you may not hear back". If nothing comes back, ask sales (info@enablebanking.com, per their FAQ). Until a written yes: don't build. Only ever as a labelled extra, Enable Banking sees bookings in transit.
- [ ] Direct bank connectors (bunq, Fio, comdirect REST) only on user demand; comdirect REST needs a TAN per session, FinTS doesn't.

## Android
- [ ] Notification tap: not reproducible on the emulator anymore (foreground and background, 2026-11-15); confirm with a real notification on the phone.
- [x] Price-change notification (2026-11-17, `BackgroundRefresh.notifyPriceRise`, switch "Preis gestiegen", on by default). Runs recurring detection after a background import first.
- [x] Recurring detection runs in libwimg after every fetch or CSV import that added bookings (2026-11-17).
- [ ] Merchant names: card payments show raw bank text ("PAYSEND, Dublin IE Karte Nr. …", "KD.1210843747 WIR SAGEN"). Clean them up in libwimg `booking.zig` once the user sends full payment references.
- [x] Squirrel: the band dims to evening and today's stitch is sewn in during "Tag ohne Ausgaben" (2026-11-17).
- [x] Squirrel: "Gehalt ist da" refills the ring (2026-11-17). Moments wait for the launch animation since 2026-11-17 (they used to play underneath it).
- [x] Minus periods get the Rückblick cards that are true (quiet days, a caught price), decided by the user 2026-11-17.
- [ ] On the Poco: Monat widget at 2×2 (compact layout) and an empty account keeping the switch (both fixed 2026-11-17, not seen on a phone yet).
