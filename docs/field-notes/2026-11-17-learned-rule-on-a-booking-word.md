# A learned rule on "BELASTUNG" filed 1,899 bookings as "Essen gehen"

## What we saw
On the developer's phone, Einstellungen › Gelernte Regeln listed two rules: "BELASTUNG"
→ Essen gehen (1,899 bookings) and "KARTENVERFÜGUNG" → Versicherung (115). Übersicht had
shown "Essen gehen" as about half of all spending.

## How we measured
The rules page counts the bookings each rule matches. After the fix, the category split on
Übersicht and the rules page were read again on the same phone (same data).

## Cause
Correcting one booking's category learns a rule from the first "merchant" word of its text
(`categories.extractKeyword`). The skip list knew LASTSCHRIFT, ÜBERWEISUNG and a few more,
but not BELASTUNG or KARTENVERFÜGUNG. For "LASTSCHRIFT / BELASTUNG MUSTERSTREAM" the first
word left was "BELASTUNG", so one correction became a rule for every direct debit. Every new
uncategorized debit after that landed in the same category. A Latin-1 "Ü" (FinTS) also made
"ÜBERWEISUNG" slip past the list.

## Fix
`extractKeyword` starts from the row title the list shows (`booking.displayTitle`: booking
type and card text already removed) and skips `isGenericWord` (booking types, SEPA fields,
legal forms, also compared without a leading Latin-1 byte). `matchRules` ignores generic
patterns, so a bad rule synced from another device does nothing. On start, learned rules on a
generic word are deleted, the bookings they filed go back to no category, and auto-categorize
sorts them again with the remaining rules (the reset rows sync).

## Proof
Tests in `categories.zig` (keyword from "LASTSCHRIFT / BELASTUNG …" is the merchant; Latin-1
forms count as generic) and `root.zig` (start-up drops a "BELASTUNG" rule and resets its
booking). On the phone: Gelernte Regeln shows only the 48 shipped rules; Übersicht went from
"Essen gehen 49 %, Sonstiges 34 %" to "Sonstiges 83 %, Lebensmittel 8 %, …".

## Lesson
A rule learned from one example generalises to everything that shares its key, so the key
must be the most specific word, never a word of the format. Learn from the same cleaned
title the user sees, and keep a stop list for the format's own vocabulary.
