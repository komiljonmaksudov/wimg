# Correcting a booking's category moved only that booking

## What we saw
After the BELASTUNG fix, Übersicht showed "Sonstiges 83 %". The user corrected bookings to
teach wimg their merchants: "nothing recategorized when I clicked on it". Each correction
changed one row; the same merchant's other bookings stayed in Sonstiges.

## How we measured
On the developer's phone (bench build over the user's data): Sonstiges list for the salary
period, one CHICOFFEE booking set to Essen gehen, list and Übersicht read again.

## Cause
`setCategory` updated one row and learned a rule silently. The rule only ever ran in
`wimg_auto_categorize`, which touches `category = 0` rows and runs on import or from
Einstellungen. So a correction had no visible effect beyond the row itself. Also: Übersicht
and the lists call category 0 "Sonstiges", the picker calls it "Unkategorisiert" and has a
separate "Andere" (255), so it looked like the bookings sat in a real category.

## Fix
`setCategory` moves the merchant's other bookings that are 0 or 255 (the learned keyword,
same match as `matchRules`) together with the tapped one, never a booking in a real category,
and records them as one undo step (op 4: `[[id, old category], …]`). `wimg_set_category`
returns how many others moved; the Dock says "Essen gehen · +4 weitere".

## Proof
Tests in `db.zig`: the merchant's 0 and 255 bookings move, one in a real category and another
merchant's stay, one undo restores each old category, redo applies again; a booking without a
merchant word changes alone. On the phone: Dock "Essen gehen · +4 …", Sonstiges for the period
27 → 23 bookings, Essen gehen 31,89 € on Übersicht.

## Lesson
A learned rule nobody sees work isn't learning. Apply what was learned at the moment the user
teaches it, scoped to what nobody has decided yet, and make it one undo.
