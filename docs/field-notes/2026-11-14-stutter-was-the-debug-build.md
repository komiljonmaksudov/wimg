# The stutter was the debug build: 18 slow frames per round, none in release

## What we saw
"Navigating between pages just feels buggy… small stops… like it loads slowly." Android, Poco phone, every page switch through the floating bar.

## How we measured
- A frame log (`FrameMetrics` listener) that writes every frame ≥ 25 ms with its phases, the page and the ms since it opened.
- adb taps through the place menu: Übersicht ⇄ Umsätze 3×, same sequence each run, two rounds, the second counted.
- A sampling trace recorded by the app itself (`Debug.startMethodTracingSampling`), parsed with a 40-line script. `simpleperf` and `am profile` didn't work on HyperOS.
- A watch on libwimg's lock: no main-thread call waited even 8 ms. The Zig core was never the problem.

| Build | slow frames total | frames ≥ 100 ms | worst |
| --- | --- | --- | --- |
| debug, before | ~5,900 ms | 18 | 448 ms |
| debug, after code fixes | 2,518 ms | 9 | 190 ms |
| release code (`bench`) | 200 ms | 0 | 55 ms |

## Cause
The trace header said `compilation-filter=run-from-apk`: a debuggable app runs uncompiled, and Compose does a lot of small calls (snapshot maps, slot table, null checks) that are cheap only when compiled. Within that, two real costs: the rolling amount (see its note) and filtering/grouping 3,205 transactions in composition on every open.

## Fix
- `bench` build type: release (R8, not debuggable) signed with the debug key, installs over a debug build and keeps the data.
- Rolling amount rebuilt; Umsätze filters in the background and keeps prefix sums instead of summing per scroll frame.

## Proof
The table above.

## Lesson
Never judge smoothness on a debug build of a Compose app; measure the release code on the real phone first, then optimise what is still slow there.
