# Any error at sign-in deleted the saved PIN

## What we saw
Quick fetch on Comdirect, three times in a few minutes: "No statement payload from bank (3060: Bitte beachten Sie die enthaltenen Warnungen/Hinweise.)", then "Bank not reachable", then "Sign-in rejected · Please enter your login ID and PIN again". After the last one the bank page said "PIN: not saved". The PIN was right.

## How we measured
Read `wimg_fints_fetch` in `root.zig`: the fetch signs in again ("fetch auth"); `auth_resp.hasError()` (any 9xxx code) returned `"Authentication failed"`, and the app's `isAuthRejected` clears the stored PIN on that word. The bank's codes went to `dbg.print`, which on Android writes to stderr and is lost.

## Cause
Two things hid the real answer and one made it harmful:
- Any 9xxx at sign-in (dialog aborted, message error, maintenance) was reported as a wrong login, so the app deleted a correct PIN.
- When HKKAZ brought no statement, the HKCAZ fallback ran and the error showed only that last answer's first non-success code, here the generic 3060.
- No bank code ever reached the Android log.

## Fix
Only a refused login (PIN/access codes 9340, 9910, 993x, 994x, or an error text naming PIN, Kennung, Anmeldename or "gesperrt") is "Authentication failed"; anything else is "Bank refused the request (Anmeldung 9800: …)" and the PIN stays. Every code of every answer in a fetch is kept with its step; the message names the first error or specific note, skipping general ones (3060, 3050, 3920, 3076, 3040, 3955, 3956). The app logs every bank error with all codes under `wimg-fints` (no PIN, no account data).

## Proof
Tests "no statement: the explaining code wins over general notes, all codes listed" and "sign-in: only a refused login counts as a wrong PIN". The next quick fetch logged the real answer: `HKKAZ 9050 Die Nachricht enthaelt Fehler; HKKAZ 3905 Bitte senden Sie die Anfrage erneut; HKKAZ 9900 Interner Fehler aufgetreten; HKCAZ … 3010 Kontonummer ist ungültig`. A Comdirect-side error, so with 3905 the CAMT fallback is skipped and the app retries once. The `root.zig` tests were not in `zig build test` at all (three old ones crashed once added, on uninitialised test data); they run now.

## Lesson
A destructive reaction (forgetting a credential, cancelling a schedule) needs a specific signal, never "some error happened". And an error message has to carry the bank's own words from the step that failed, or nobody can tell a hiccup from a rejection.
