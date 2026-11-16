# TODO

Open work only, grouped by area; finished work moves to [CHANGELOG.md](CHANGELOG.md). How the pieces fit in [CLAUDE.md](CLAUDE.md) and `.claude/rules/`; lessons in [docs/field-notes/](docs/field-notes/README.md). Only the next one to two weeks of work.

## Before launch
- [x] **One schema, v1 (user, 2026-11-14)**: done 2026-11-15 (`db.zig` `migrate()`, meta key `schema`). The Poco was at 23 and is relabelled.

## Manual entries (user, 2026-11-14)
- [x] Marked (`transactions.source = 'manual'`, v22/v23), editable and deletable on Android with real deletion across devices (`deleted_transactions` markers), left out of salary detection, "Von Hand" filter in Umsätze. Done 2026-11-14; edit form and filter not tried on the phone yet.
- [ ] iOS: the same (edit, delete, filter) once Android is settled.

## FinTS (from the Comdirect analysis, 2026-11-16)
- [ ] Task reference (HITAN) and challenge text: read with `readElement`, unescape, JSON-escape the challenge; task reference buffer 36 bytes.
- [ ] HITAB medium names: escape-aware split (names with escaped characters are cut today).
- [ ] `isEscaped` checks only the previous byte (`??+` reads as escaped); count the run of '?'.
- [ ] Encode outgoing text as ISO-8859-1 like python-fints (we send UTF-8); escape Kunden-ID in HNSHK/HNVSK key names.
- [ ] Keep the system id per connection instead of a fresh one each connect (python-fints, hbci4java do).
- [ ] Drop the `_debug_*` fields from the connect JSON.

## Android
- [ ] Notification tap: not reproducible on the emulator anymore (foreground and background, 2026-11-15); confirm with a real notification on the phone.
