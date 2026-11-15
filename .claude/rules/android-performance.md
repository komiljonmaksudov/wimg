# Android performance — how to judge and measure smoothness

## Judge smoothness only on a release-like build

Debug builds are debuggable, so Android runs them uncompiled
(`compilation-filter=run-from-apk` in a trace). Compose is several times
slower there. Measured on the Poco (14 Nov 2026), Übersicht ⇄ Umsätze 3×:

| Build | slow frames (≥ 40 ms) total | frames ≥ 100 ms | worst |
| --- | --- | --- | --- |
| debug, before fixes | ~5,900 ms | 18 | 448 ms |
| debug, after fixes | 2,518 ms | 9 | 190 ms |
| `bench` (release code) | 200 ms | 0 | 55 ms |

`bench` build type (`app/build.gradle.kts`): release setup (R8, not
debuggable) signed with the debug key, so it installs over a debug build and
keeps the data. Build: `gradle assembleBench -x lintVitalAnalyzeBench
-x lintVitalReportBench -x lintVitalBench` (lint crashes on JDK 25).
While it is installed, `run-as` doesn't work: back up the data with the
debug build first if you need to read the DB.

## Measuring

- **Frame log** (`FrameWatch` in `MainActivity.kt`, on while `files/frames-on`
  exists): every frame ≥ 25 ms with its phases (`wait` = main thread busy
  before the frame, `anim` = Compose recomposition, `draw`), the page and the
  ms since it opened. Tag `wimg-frame`. A big `wait` right after a big frame is
  that frame's overrun, not separate work.
- **Driving the phone**: `adb shell input tap` through the place menu, same
  sequence each run, two rounds and count the second (the first after a
  restart is always slower).
- **CPU trace** (debug builds only, flag `files/trace-on`): the app records a
  20 s sampling trace into `files/wimg.trace` (pull with `run-as … cat`).
  Writing it blocks the main thread → an ANR dialog, expected. Main thread is
  thread id 3 inside the trace. Parse the dmtrace v3 format (text header,
  `SLOW` magic, 14-byte records: tid u16, method|action u32, cpu u32, wall u32).
- `simpleperf` and `am profile` don't work on HyperOS (no perf events; the
  shell-owned file stays empty).

## What was slow, and the rules that came out of it

- **`AnimatedContent` per character** (the rolling amount) was the most
  expensive thing on Übersicht and Umsätze, and after one roll it stopped
  reporting the text baseline, so digits dropped a line. Rule: animate
  characters with a `graphicsLayer` offset on plain `Text`; give the baseline
  from the font (`TextMeasurer.firstBaseline`), never read it from an animated
  container.
- **List work in composition**: filtering, grouping and running sums of 3,000+
  transactions ran on the main thread on every page open. Rule: precompute in
  the IO loader (`TxView` in `loadTx`), filter in `produceState` on
  `Dispatchers.Default`, and never scan the whole list per scroll frame
  (prefix sums + id → index map).
- **libwimg's lock** never blocked the main thread in practice (watched for a
  session). Keep it that way: no `LibWimg` call in composition or a
  `LaunchedEffect` without `withContext(Dispatchers.IO)`.
- **A global `Changes.bump()`** reloads every list in the app. Settings that
  only affect one derived thing (period mode) reload just that
  (`PeriodState.setMode`).
- **"Not loaded" is not "empty"**: a page opened with nothing cached (cold
  start from a notification or widget, a past month) used to draw its empty
  state ("keine Umsätze") for a few frames. Rule: first state from
  `ScreenCache`; with no entry, load it once synchronously in `remember`
  (Rückblick: 120–180 ms on the Poco, hidden in the app start) and keep
  later loads on `Dispatchers.IO`. Same for `PeriodState` on first use.
