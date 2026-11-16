# Comdirect stopped delivering: a '+' in a random id, then a failing MT940 side

## What we saw
From the morning of 2026-11-16 every Comdirect fetch failed, with changing codes: "Sync failed", sign-in `9050/9800/9130 kein Binaerfeld gefunden`, `9110 Unbekannter Aufbau`, and on HKKAZ `9050 + 3905 Bitte senden Sie die Anfrage erneut + 9900 Interner Fehler`. The day before, the same code had fetched fine.

## How we measured
`scripts/fints-dump.ts` (real libwimg in the terminal, curl transport) printed the parsed ids: `HISYN … +vc?+xyXOn5KEBAACeOPWCFQWCCgQA` became `system_id='vc?' (len=3)`. The app logs every bank error with all codes (`adb logcat -s wimg-fints`) plus the HKKAZ/HKTAN segments (no PIN, account digits masked). New dump options `--until N` and `--camt` split "recent booking" from "MT940 side": MT940 failed for 17.10.–11.11. too (fetched fine the day before), and CAMT for the same account delivered.

## Cause
Two separate things:
- The system id (HISYN) and dialog id (HNHBK) are random per dialog and can contain '+'. They arrive escaped (`?+`); the parsers cut at the escaped '+', and HNSHK/HNVSK/HNHBK wrote the ids raw. Broken whenever an id contained '+'. A fresh id every connect made it come and go.
- Separately, Comdirect's MT940 path (HKKAZ) failed internally for this account (HIRMS points at the HKKAZ segment, so the request was parsed) while HKCAZ worked. Most likely part of the MT940 → CAMT move; the cause is on the bank's side.

On top of that, our own retries signed in without a PIN (libwimg wipes it after a fetch), producing more 9130/9110, and any sign-in error used to delete the saved PIN (see the note of the same day).

## Fix
Escape-aware `readElement` for system id and dialog id; escaping wherever they are written; `@` added to the escaped characters. The app falls back quietly to the other statement format on a bank-side error and remembers the working one per connection; CAMT next to MT940 history is value-dated, starts 3 days before the newest stored booking and skips twins (account, day, amount, counted).

## Proof
Tests for both ids with the real `vc?+xyXO…` value, value-dated CAMT, twin counts. Terminal: sign-in passes with an id containing '+', CAMT delivered 39 bookings. Poco: ↻ fetched via CAMT, no duplicates (user, 2026-11-16).

## Lesson
Every value a bank sends is FinTS-escaped text, even "technical" ids that look like base64: read it with the escape rules, write it escaped. A bug that depends on random data looks like a bank outage; a terminal harness that prints parsed values finds it in one run.
