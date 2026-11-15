# TODO

Open work only, grouped by area; finished work moves to [CHANGELOG.md](CHANGELOG.md). How the pieces fit in [CLAUDE.md](CLAUDE.md) and `.claude/rules/`; lessons in [docs/field-notes/](docs/field-notes/README.md). Only the next one to two weeks of work.

## Before launch
- [ ] **One schema, v1 (user, 2026-11-14)**: libwimg carries 22 migration steps (`db.zig`, `version < N`). Before the first public release, fold them into one `schema_sql` at version 1 and drop the steps. Before that: the user's phone (and any test device) must be on the last migrated version, then either keep a single "anything older than v1 → export, wipe, re-import" path or reinstall from a backup. The sync server stores ciphertext rows by table/id, so it is unaffected as long as the row JSON keeps its fields.

## Manual entries (user, 2026-11-14)
- [x] Marked (`transactions.source = 'manual'`, v22/v23), editable and deletable on Android with real deletion across devices (`deleted_transactions` markers), left out of salary detection, "Von Hand" filter in Umsätze. Done 2026-11-14; edit form and filter not tried on the phone yet.
- [ ] iOS: the same (edit, delete, filter) once Android is settled.

## Android
- [ ] Notification tap: not reproducible on the emulator anymore (foreground and background, 2026-11-15); confirm with a real notification on the phone.
