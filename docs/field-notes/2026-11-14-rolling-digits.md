# The rolling amount: the most expensive composable, and digits a line too low

## What we saw
The big amount on Übersicht read "59 , €" with "+ 1 94" on a line below. On Wiederkehrend "9 , €" over "19 31". Separately: page switches stuttered.

## How we measured
- Screenshots: the characters were not wrapping; some sat exactly one line lower at their correct horizontal place.
- Sampling trace of page switches: `RollingAmount` was about 2.8 s of the 6.5 s spent in all wimg composables, more than any screen's own content.

## Cause
Every character was its own `AnimatedContent` (transition, size transform, clip). That is heavy to compose and measure ×10 characters ×2 screens. And after a character had rolled once, its `AnimatedContent` no longer reported the child's text baseline, so the `Row(alignByBaseline)` put it by its top edge: one line lower. The first fix (measuring at natural width) aimed at the wrong cause.

## Fix
One plain `Text` per character inside a clipped box; during a roll the old and new character move by a `graphicsLayer` translation driven by one `Animatable` (no recomposition per frame). The baseline comes from the font (`TextMeasurer.firstBaseline`), not from the child.

## Proof
The digits stay on one line after rolls; the composable no longer shows up near the top of the trace.

## Lesson
Don't put an `AnimatedContent` per character, and never read an alignment line from an animated container: compute it from the font.
