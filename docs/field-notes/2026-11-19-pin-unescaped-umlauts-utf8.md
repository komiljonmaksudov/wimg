# A PIN with "+" broke the bank message, and TAN media with umlauts didn't match

## What we saw
Nothing yet on a phone: found while looking at the TODO "send ISO-8859-1 like python-fints".
Reading `fints.zig` showed two gaps next to each other.

## How we measured
Read the message builders; then unit tests on `escapeFintsValue` and `writeSignatureFooter`
with a PIN `a+b:c'd?e@`, a TAN `12?3` and the name "Mein Gerät ß".

## Cause
- `writeSignatureFooter` copied PIN and TAN into `HNSHA` as they were. Every other value goes
  through `escapeFintsValue`; a PIN containing `+ : ' ? @` ended a data element early, and the
  bank answers with a syntax error (looks like a wrong PIN).
- FinTS text is ISO-8859-1. Names from the bank (HITAB TAN media) reach the app correctly
  (lone high bytes become `\u00XX` in JSON) but came back as UTF-8, so "Gerät" was sent as
  `Ger\xC3\xA4t`, a name the bank doesn't know.

## Fix
`escapeFintsValue` turns UTF-8 for U+0080..U+00FF into its Latin-1 byte (other bytes pass),
and the footer escapes PIN and TAN with it.

## Proof
Three new tests in `fints.zig`; all 1554 libwimg tests pass. Not yet against a real bank.

## Lesson
One escape function is only safe if every value goes through it. The secret ones (PIN, TAN)
are the easiest to forget because nobody logs or looks at them.
