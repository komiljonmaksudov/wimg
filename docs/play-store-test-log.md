# Closed test log (Google Play)

Material for the production-access form: what testers did and said, what
changed, and which build shipped it. One line per event. Rules and draft
answers: [play-store-listing.md](play-store-listing.md).

Track "Closed testing – Alpha", testers via Testers Community (15 testers,
Google Group `testers-community@googlegroups.com`, 16-day program), feedback
channel dev@ (Play). Goal: at least 3 updates during the test, each with
release notes that name the change.

## Builds

| Date | Version (code) | What changed | Why |
| --- | --- | --- | --- |
| 2026-11-17 | 0.9.11 (116) | First test build: demo month as a salary month, English throughout (dates, wording), first start without flicker, phone language, 2×2 widget, merchant names for card payments, price-rise notification, squirrel moments, back through places, bank login says it goes straight to the bank | Own pass before the test (developer's phone, emulator, English sweep) |

## Feedback

| Date | From | What they said | What changed (build) |
| --- | --- | --- | --- |
| 2026-11-17 | Tester (friend, WhatsApp) | "Ich habe schon wimg" should read "Ich nutze wimg schon" | Button and Sync texts renamed (next update) |
| 2026-11-17 | Tester (friend, WhatsApp) | Searching "ing" puts ING far down the bank list; sort by how common a bank is | Search ranks name start, then word start, then BLZ, then contains; big banks first, also with an empty search (next update) |
| 2026-11-17 | Tester (friend, WhatsApp) | Wants to import Revolut ("Mit Revolut CSV") | Waiting for a sample export; Revolut has no FinTS (next update or the one after) |

## Pre-launch reports

| Date | Build | Issues | Fixed in |
| --- | --- | --- | --- |
