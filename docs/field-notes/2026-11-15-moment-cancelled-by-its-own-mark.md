# The squirrel's moment cancelled itself halfway: it was keyed on what it changed

## What we saw
On the Poco the band's line said "Knapp" but the squirrel stayed in the normal pose; it only switched when tapped. The Knapp moment (once per period) never played, and later moments would have been marked as played without being seen.

## How we measured
Screen recordings of the band (`screenrecord`, frames tiled with ffmpeg) on the Poco, with a debug-only switch (`files/moment`) that forces one moment per app start.

## Cause
`pendingMoment()` picks the first moment not yet marked in SharedPreferences. The player ran in `LaunchedEffect(moment?.key)` and marked the moment as played at its start. The next recomposition asked again, got the next candidate (or none), the key changed, and Compose cancelled the running effect before it reset `playing`. With `playing` stuck at true the figure never followed the real pose again. A second, related gap: before the data loaded, an empty summary (0,00 €) looked like "Leer" and could have used up the Leer moment.

## Fix
The moment is chosen once per visit (`chosen` state) and the effect is keyed on that; `playing` is reset in `finally`. No pose, stitches or moment until `HomeData` is loaded. The start pose is shown before the 500 ms pause, not after it.

## Proof
All five moments (Gehalt, Leer, Knapp, Preiserhöhung, Tag ohne Ausgaben) recorded end to end on the Poco, each ending with its bubble; cold start no longer shows the Leer squirrel.

## Lesson
An effect must not be keyed on a value that its own side effect changes. Pin the decision in state first, then key the effect on the pinned value; and decide "once" things only from loaded data, never from a loading placeholder.
