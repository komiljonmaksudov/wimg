#!/usr/bin/env python3
"""Build the wimg landing page into public/.

src/components/<Name>.html + <Name>.js are the page's components (exported
from the design canvas, data replaced with invented demo data). runtime.js
renders them. static/ is copied as-is. No dependencies.

Usage: python3 wimg-site/build.py
"""
import json, pathlib, shutil

ROOT = pathlib.Path(__file__).resolve().parent
SRC, OUT = ROOT / "src", ROOT / "public"

F = {}
for tpl in sorted((SRC / "components").glob("*.html")):
    F[tpl.stem] = {"tpl": tpl.read_text(), "code": tpl.with_suffix(".js").read_text()}

if OUT.exists():
    shutil.rmtree(OUT)
shutil.copytree(ROOT / "static", OUT)
app = 'const TOP="Landing";\nconst F=' + json.dumps(F, ensure_ascii=False) + ";\n" + (SRC / "runtime.js").read_text()
(OUT / "app.js").write_text(app)
(OUT / "index.html").write_text((SRC / "head.html").read_text())
print(f"built {OUT} ({len(F)} components, app.js {len(app) // 1024} KB)")
