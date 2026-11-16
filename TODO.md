# TODO

Open work only, grouped by area; finished work moves to [CHANGELOG.md](CHANGELOG.md). How the pieces fit in [CLAUDE.md](CLAUDE.md) and `.claude/rules/`; lessons in [docs/field-notes/](docs/field-notes/README.md). Only the next one to two weeks of work.

## Before launch
- [x] **One schema, v1 (user, 2026-11-14)**: done 2026-11-15 (`db.zig` `migrate()`, meta key `schema`). The Poco was at 23 and is relabelled.

## Manual entries (user, 2026-11-14)
- [x] Marked (`transactions.source = 'manual'`, v22/v23), editable and deletable on Android with real deletion across devices (`deleted_transactions` markers), left out of salary detection, "Von Hand" filter in Umsätze. Done 2026-11-14; edit form and filter not tried on the phone yet.
- [ ] iOS: the same (edit, delete, filter) once Android is settled.

## FinTS (from the Comdirect analysis, 2026-11-16)
- [x] Task reference (HITAN) and challenge text: unescaped, challenge JSON-escaped for the app, task reference buffer 40 bytes (2026-11-16).
- [x] HITAB medium names: escape-aware split, unescaped (2026-11-16).
- [x] `isEscaped` counts the run of '?' (2026-11-16).
- [x] Kunden-ID escaped in HNSHK/HNVSK key names and the fallback account (2026-11-16).
- [ ] Encode outgoing text as ISO-8859-1 like python-fints (we send UTF-8): matters for names/TAN media with umlauts.
- [x] System id kept per connection (`BankConnection.systemId`, connect without HKSYN, fresh sync if the bank refuses it) (2026-11-16). Not yet tried against a bank.
- [x] `_debug_*` fields gone from the connect JSON (2026-11-16).

## Bank sources (decided 2026-11-16, not started)
- [ ] One import seam in libwimg: every source (FinTS, CSV, file import, later bunq/Fio) hands over a `Batch` (account, booked, pending, balance, twin rule) and one `import.apply(db, batch)` does duplicates/twins, pending, categories and balance. Plain data + functions, no plugin system. Sketch and reasons: `.claude/rules/banking-aggregators.md` (update 2026-11-16).
- [ ] CAMT/MT940 file import next to CSV (parsers exist), on top of the seam: private, free, any bank with exports.
- [ ] CAMT by default where the bank advertises HICAZS, MT940 as legacy fallback.
- [ ] Enable Banking: ticket sent by the user (personal-use apps inside a public app, shared https redirect, non-commercial option). Decide after their answer; only as a labelled extra, Enable Banking sees bookings in transit.
- [ ] Direct bank connectors (bunq, Fio, comdirect REST) only on user demand; comdirect REST needs a TAN per session, FinTS doesn't.

- [ ] Notification tap: not reproducible on the emulator anymore (foreground and background, 2026-11-15); confirm with a real notification on the phone.
