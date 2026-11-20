# A first CAMT fetch didn't fit, and the iPhone said "Anmeldung fehlgeschlagen"

## What we saw
On a freshly installed iPhone (no bookings yet) every Comdirect sign-in ended in
"Anmeldung fehlgeschlagen", later "Verbindungsproblem" or "etwas ist schiefgelaufen".
The Poco, with its history already stored, fetched fine.

## How we measured
The app's console over `xcrun devicectl device process launch --console` while the
user signed in (FinTS previews never contain the signature, so no PIN in the log).

## Cause
Four things in a row, each hiding the next:
1. The locally built app linked a libwimg from before "CAMT first" (14:19 vs. 14:46
   on 2026-11-19), so it asked in MT940, which Comdirect refuses since 2026-11-16.
   The sign-in itself worked (3076); iOS labelled the fetch error as a sign-in error.
2. A double tap sent the TAN twice in one dialog: 9120 (wrong message number), 9800.
3. The CAMT answer for months of history was 458 KB base64 / 334 KB XML. The HTTP
   buffer held 256 KB, the decoded store 192 KB, the CAMT part 64 KB: thrown away,
   reported as a connection problem.
4. The fetch kept two `[2000]Transaction` arrays (~800 KB each) on the 2 MB FinTS
   thread stack. A small change in frame layout overflowed it: SIGBUS.

## Fix
Rebuilt libwimg; one TAN message at a time; buffers 5 MB (HTTP), 4 MB (decoded),
3 MB CAMT in a shared static store; the transaction array static.

## Proof
iPhone 11, Comdirect, 2026-11-20: 204 bookings from one 334 KB CAMT answer, no errors.
341 libwimg tests pass.

## Lesson
Before testing a bank fetch on a phone, check the date of the linked libwimg. And
big FinTS buffers belong in static memory, never on the FinTS thread's stack.
