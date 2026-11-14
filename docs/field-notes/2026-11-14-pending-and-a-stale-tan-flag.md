# The bank sent the pending list, and a leftover TAN flag threw it away

## What we saw
"Pending transactions did not get picked up in the latest APK." After a Schnellabfrage, no "Vorgemerkt" rows, although the code for Comdirect's pending list was merged and tested.

## How we measured
libwimg's debug output goes to stderr, which Android drops. So the fetch result got a short diagnosis field (step reached, bank response codes, sizes; no bank data) and the app logged it:
`sent:resp=108750,camt=65536,de4=4605,parsed=0,tan=true,codes=3060 0020 3076`

## Cause
The extra HKCAZ request went out, and Comdirect answered with the pending part (4,605 bytes) and code 3076 (no strong authentication needed). But `has_pending_tan` was still set from earlier in the dialog, and the code treated that as "the bank wants a TAN, so no list".

## Fix
Clear the flag and use the pending part whenever the answer has one. The diagnosis field was removed again.

## Proof
Next fetch: `pending=4`, the rows show greyed at the top of Umsätze.

## Lesson
Session flags outlive the request that set them; decide from what the current answer contains. And when a native library's logs go nowhere on a platform, return a small diagnosis in the result instead.
