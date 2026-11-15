# Field notes

What we learned building wimg, written while it is fresh. One short file per lesson: a bug with a surprising cause, a speed-up and its numbers, code we removed and why, a benchmark, a tool that worked or didn't.

The bar: would another developer (Zig, Kotlin, Swift, the web) learn something from it? A typo fix doesn't qualify. "We measured, and the slow part wasn't where we thought" does.

## How to write one
File name: `YYYY-MM-DD-short-slug.md`. Headings, each a few lines:

- **What we saw**: the symptom, in the user's words if they reported it.
- **How we measured**: the tool (frame log, trace, a bench script) and the numbers.
- **Cause**: what was really going on.
- **Fix**: what changed, with the commit.
- **Proof**: the test or the before/after numbers.
- **Lesson**: one or two sentences for someone else.

Plain words, real numbers, no marketing, no real bank data (amounts and merchants in examples are invented or rounded).

## Security
A note about a security bug stays out of anything public until the fix has shipped to every device, and never shows the exact steps to exploit it.

## Index
- [2026-11-15 · A white flash and the wrong bar on every "back"](2026-11-15-white-flash-on-back.md)
- [2026-11-14 · One cash entry crashed the app on start: negative numbers were written as nothing](2026-11-14-negative-balance-crash.md)
- [2026-11-14 · The stutter was the debug build: 18 slow frames per round, none in release](2026-11-14-stutter-was-the-debug-build.md)
- [2026-11-14 · The rolling amount: the most expensive composable, and digits a line too low](2026-11-14-rolling-digits.md)
- [2026-11-14 · "Erneut erkennen" lost the current fixed costs: 256 ids and a table filled by 2022](2026-11-14-recurring-256-ids.md)
- [2026-11-14 · The bank sent the pending list, and a leftover TAN flag threw it away](2026-11-14-pending-and-a-stale-tan-flag.md)
