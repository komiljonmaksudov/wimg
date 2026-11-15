# One cash entry crashed the app on start: negative numbers were written as nothing

## What we saw
"wimg gets crashed now – cannot open it", right after the build that gives a cash account ("Bargeld") a balance of its own.

## How we measured
`adb logcat -b crash`: `Unexpected JSON token … Expected numeric literal at path: $[0].balance_cents`, input `"balance_cents":,"balance_date":"2026-11-14"`.

## Cause
The accounts list wrote `balance_cents` with `formatInt`, which loops `while (val > 0)` and so writes nothing for a negative value. Bank balances had always been positive, so it never showed. The new cash balance was the first negative one (−9 €). An overdrawn bank account would have crashed the app the same way.

## Fix
`formatSignedInt` for the balance; the sync path already used it.

## Proof
Test "accounts JSON: a negative balance is written (cash, overdraft)"; the app starts and shows "Kontostand · alle Konten" with bank + cash.

## Lesson
A number formatter that takes `anytype` should refuse what it can't write, not write nothing; and an app shouldn't be able to crash on one malformed field of a list (the Kotlin side decodes the whole list or nothing).
