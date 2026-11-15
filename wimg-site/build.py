#!/usr/bin/env python3
"""Build the wimg landing page into public/.

src/index.html + src/site.js are the page (Brief 18, direction "Schreibtisch",
from the design canvas; every amount, merchant and bank on it is invented).
static/ (fonts, icons, QR code, Datenschutz) is copied as-is. No dependencies.

Usage: python3 wimg-site/build.py
"""
import pathlib, shutil

ROOT = pathlib.Path(__file__).resolve().parent
SRC, OUT = ROOT / "src", ROOT / "public"

if OUT.exists():
    shutil.rmtree(OUT)
shutil.copytree(ROOT / "static", OUT)
for name in ("index.html", "site.js"):
    shutil.copy(SRC / name, OUT / name)
size = sum(p.stat().st_size for p in (OUT / "index.html", OUT / "site.js"))
print(f"built {OUT} (page + script {size // 1024} KB before compression)")
