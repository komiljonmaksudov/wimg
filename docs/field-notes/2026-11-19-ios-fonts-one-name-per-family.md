# iOS would have loaded one weight of each font

## What we saw
The iOS redesign bundles the same Manrope, Inter and JetBrains Mono files Android uses. Before
registering them, CoreText read their names: all four Manrope files called themselves
`Manrope-ExtraLight`, all four Inter files `Inter-Regular`, both JetBrains Mono files
`JetBrainsMono-Regular`.

## How we measured
A small Swift script with `CTFontManagerCreateFontDescriptorsFromURL` printed PostScript name,
family, style and weight for each file in `wimg-android/app/src/main/res/font/`.

## Cause
The files were cut from the Google Fonts variable fonts with the fontTools instancer. The
instancer set the weight (`usWeightClass`) but kept the name table of the variable font's
default instance. Android doesn't care: `FontFamily(Font(R.font.x, FontWeight.Bold))` maps by
file. iOS registers fonts from `UIAppFonts` by PostScript name, so a second file with the
same name is dropped and `Font.custom("Manrope-Bold", …)` would have found nothing.

## Fix
`scripts/ios-fonts.py` writes a copy of each file with its own family, style, full and
PostScript name (`Manrope-Bold`, `Inter-SemiBold`, …) into `wimg-ios/wimg/Fonts/`;
`Components/Wimg.swift` (`WimgFont`) uses those names.

## Proof
The same CoreText script on the new files lists ten distinct names with the right weights.
In the simulator the Mehr page shows Manrope ExtraBold for the title and Inter for the rows,
light and dark.

## Lesson
A font file's name is part of its identity on Apple platforms. Check what the system reads
from a file before shipping it, not what the file is called.
