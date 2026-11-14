# "Erneut erkennen" lost the current fixed costs: 256 ids and a table filled by 2022

## What we saw
"I played around with the settings in Wiederkehrend and lost all my recurring… only one monthly payment now." Six active monthly payments became one; eleven patterns showed as inactive from 2023–2026.

## How we measured
Built libwimg as a macOS dylib, ran `wimg_detect_recurring` through Python ctypes on a copy of the morning's backup, and bisected against older commits (same result before the board 26 changes). Then a temporary debug print inside `processGroup` for one merchant.

## Cause
Three bugs, all old, hidden until the history got long enough:
1. Detection read transactions oldest first into a table of 256 merchants with 64 bookings each. Four years of history filled it: merchants that started this year got no slot, busy ones kept only their oldest bookings.
2. The fallback "most frequent amount" counted the whole history, so a 549 € transfer from 2024 beat today's 350 € standing order, and similar old amounts broke the monthly rhythm with year-long gaps.
3. The pattern id: a 64-bit hash spread into 32 hex chars by repeated `h = h * k + i`. The low bits of a product depend only on the low bits of its inputs, so every character depended on the lowest byte: 256 possible ids. Two merchants with the same last byte silently overwrote each other.

## Fix
Read newest first (only the oldest history falls off), pick the usual amount from the last 12 bookings and start at its first exact match, ids from two Wyhash seeds (128 bits). One-off marks under an old id move per booking; overrides are copied to the new id.

## Proof
Two new tests (long history + a new merchant; two merchants whose old ids collide). On the copy of the real data all six monthly payments are back, plus a quarterly one that was never found before.

## Lesson
Bounded tables fill with whatever you read first, so read the data you care about first. And when you stretch a hash with multiply-add, check that the output still depends on all of its input bits.
