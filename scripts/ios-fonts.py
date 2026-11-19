# Give each static weight its own family/style/PostScript name so iOS can
# register all of them (they were cut from variable fonts and kept the default
# instance's names).
import sys, os
from fontTools.ttLib import TTFont
src, dst = sys.argv[1], sys.argv[2]
spec = {  # file: (family, style, psFamily, weight)
 "inter_regular": ("Inter", "Regular", "Inter", 400), "inter_medium": ("Inter", "Medium", "Inter", 500),
 "inter_semibold": ("Inter", "SemiBold", "Inter", 600), "inter_bold": ("Inter", "Bold", "Inter", 700),
 "manrope_medium": ("Manrope", "Medium", "Manrope", 500), "manrope_semibold": ("Manrope", "SemiBold", "Manrope", 600),
 "manrope_bold": ("Manrope", "Bold", "Manrope", 700), "manrope_extrabold": ("Manrope", "ExtraBold", "Manrope", 800),
 "jetbrainsmono_regular": ("JetBrains Mono", "Regular", "JetBrainsMono", 400), "jetbrainsmono_medium": ("JetBrains Mono", "Medium", "JetBrainsMono", 500),
}
for key, (fam, style, psfam, w) in spec.items():
    f = TTFont(os.path.join(src, key + ".ttf"))
    n = f["name"]
    ps = f"{psfam}-{style}"
    legacy_fam = fam if style in ("Regular", "Bold") else f"{fam} {style}"
    legacy_style = style if style in ("Regular", "Bold") else "Regular"
    for rec in list(n.names):
        if rec.nameID in (1, 2, 3, 4, 6, 16, 17, 25):
            n.removeNames(nameID=rec.nameID)
    for pid, eid, lid in ((3, 1, 0x409), (1, 0, 0)):
        n.setName(legacy_fam, 1, pid, eid, lid); n.setName(legacy_style, 2, pid, eid, lid)
        n.setName(f"{ps};wimg", 3, pid, eid, lid); n.setName(f"{fam} {style}", 4, pid, eid, lid)
        n.setName(ps, 6, pid, eid, lid); n.setName(fam, 16, pid, eid, lid); n.setName(style, 17, pid, eid, lid)
    f["OS/2"].usWeightClass = w
    f["OS/2"].fsSelection = (f["OS/2"].fsSelection & ~0b1100001) | (0b100000 if style == "Bold" else 0b1000000 if style == "Regular" else 0)
    f["head"].macStyle = 1 if style == "Bold" else 0
    f.save(os.path.join(dst, ps + ".ttf"))
    print(ps)
