# A white flash and the wrong bar on every "back"

## What we saw
"When I tap the back button, e.g. on my bank's page, I see a white screen for a brief moment." And: "it shortly shows the Übersicht floating bar".

## How we measured
`adb shell screenrecord` on the phone (bench build), then every frame the phone actually drew (`ffmpeg -fps_mode passthrough`), tiled into one sheet; the bar cropped at full size. Taps by text through `uiautomator dump`, and a guard that only presses back while wimg is in front (an unguarded run once pressed back in another app the user had opened).

## Cause
1. Back faded the leaving page out (100 ms) while the page below faded in (150 ms). For ~4 frames both were half transparent and the light window background showed through: the dark band turned pale grey.
2. The bar followed the back stack's current entry. On back it moves one frame before the page below is composed and has registered its bar; for that frame the bar used a stand-in whose route is not a place, and the place label fell back to the first place, Übersicht (then crossfaded to the right one).

## Fix
Page changes are instant (no enter/exit transitions in the NavHost). The bar's owner is the page that most recently came on screen (set when it registers its bar), so page and bar change in the same frame. Commit 21cc575.

## Proof
Frame sheets before/after for the bank page, a recurring payment, Einstellungen › Konten, search and a transaction: no pale frame, no Übersicht bar.

## Lesson
Two layers fading at the same time are each see-through; fade one over the other, or don't fade. And let UI chrome follow what is drawn, not the navigation state, which runs a frame ahead.
