# Maestro flows (wimg Android)

End-to-end journeys on the emulator with **wimg Test** (`com.wimg.app.tester`, the `preview`
build: release code, its own app, starts empty). Same Maestro and rules as Eigenheim.

```
scripts/maestro flow                     # build + install wimg Test, run every flow here
scripts/maestro flow .maestro/filter.yaml
scripts/maestro mcp                      # Maestro MCP for Claude Code (.mcp.json)
```

Screenshots and logs land in `$TMPDIR/wimg-maestro/` (one folder per flow and run).

## Rules

- **Few flows, journeys only**: onboarding, the filter panel, a category change with Undo,
  Back. Logic belongs in libwimg's unit tests, which take seconds.
- **Wait for a state, never for a time**: `extendedWaitUntil` visible / notVisible, no sleeps.
- **Check states, not numbers**: demo data is random (`DemoDataService`), so never assert a
  count or an amount; check that a booking is there or gone.
- **Run a new flow 3 times** before adding it. A flow that fails twice with no known cause moves
  to `pending/` with a date, and is fixed or deleted within 30 days.
- **Labels are English** (the emulator's language). Text matches the whole element; use
  `.*` for part of a sentence.
- **Emulator only**, never the Poco or any phone with real data.
- **Shared emulator**: `scripts/maestro` holds `/tmp/eh-emulator.lock` while it runs and
  refuses to start when Eigenheim holds it.
- **Privacy**: `scripts/maestro` turns Maestro's analytics and update check off and blocks its
  outgoing HTTPS. Never `maestro login`, never the cloud commands.
- **Exploring**: Maestro MCP, `inspect_screen` first (the accessibility tree), screenshots
  second. A path that works is saved as a flow.
