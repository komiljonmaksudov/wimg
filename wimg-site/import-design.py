"""Design canvas export (Brief 18, direction A) -> src/index.html + src/site.js.

Usage: python3 wimg-site/import-design.py <export-html/35-Website-persoenlich/website.html> wimg-site/src/index.html
Keeps direction A only, sets the real links and QR code, fixes untrue lines,
uses the self-hosted fonts and moves the script into a file (CSP). Check the
export for real data first (see CLAUDE.md, "Demo data only")."""
import bs4, sys, re
src, out = sys.argv[1], sys.argv[2]
soup = bs4.BeautifulSoup(open(src).read(), 'html.parser')
for el in soup.select('.dirB,.dirC'): el.decompose()
root = soup.html; root['data-dir'] = 'A'; root['data-theme'] = 'L'

APK = 'https://github.com/komiljonmaksudov/wimg/releases/latest/download/wimg.apk'
TF = 'https://testflight.apple.com/join/v5FhHpt5'
REPO = 'https://github.com/komiljonmaksudov/wimg'
for a in soup.find_all('a'):
    cls, text = a.get('class') or [], ' '.join(a.get_text(' ').split())
    if 'and' in cls: a['href'] = APK
    elif 'ios' in cls: a['href'] = TF; a['rel'] = 'noopener'
    elif text in ('Datenschutz im Detail',) : a['href'] = 'datenschutz.html'
    elif text == 'Datenschutz' and a.get('href') == '#': a['href'] = 'datenschutz.html'
    elif text == 'Quellcode': a['href'] = REPO
    elif text == 'Impressum': a.decompose()   # there is no Impressum page (personal project)
# The header shows the app icon with the wordmark, as on the old page.
logo = soup.select_one('a.logo')
logo.insert(0, soup.new_tag('img', src='img/logo.svg', alt='', width='28', height='28'))
# Real QR code (points at the APK download) instead of the placeholder.
for q in soup.select('span.qr'):
    svg = q.find('svg')
    if svg: svg.replace_with(soup.new_tag('img', src='img/qr.svg', alt='QR-Code: wimg für Android laden', width='96', height='96'))

# The phone screens: the real Übersicht sheet under each band instead of grey bars
# (demo numbers that add up to the band's "Ausgaben"; colours from WimgTheme.kt).
CAT = {'Wohnen': '#8B5E3C', 'Lebensmittel': '#2E9E6A', 'Essen gehen': '#C2410C', 'Nebenkosten': '#8A63D2',
       'Abonnements': '#4F46E5', 'Shopping': '#D9822B', 'Sonstiges': '#8E8E93'}
def eur(v): return f"{v:,.2f}".replace(',', 'X').replace('.', ',').replace('X', '.') + ' €'
def tile(cat): c = CAT[cat]; return (f'<span style="flex:0 0 44px;height:44px;border-radius:13px;background:{c}1F;display:flex;align-items:center;justify-content:center">'
                                     f'<span style="width:16px;height:16px;border-radius:5px;background:{c}"></span></span>')
def spending(rows):
    total = sum(v for _, v, _ in rows)
    bar = ''.join(f'<span style="flex:{v:.2f};background:{CAT[c]}"></span>' for c, v, _ in rows)
    out = ('<div style="display:flex;justify-content:space-between;align-items:baseline"><b style="font:800 21px Manrope,sans-serif;color:#1A1A1A">Ausgaben seit Gehalt</b>'
           '<span style="font-size:13px;color:#6B6A66">vs. davor</span></div>'
           f'<div style="display:flex;gap:3px;height:12px;border-radius:6px;overflow:hidden;margin:14px 0 6px">{bar}</div>')
    for c, v, d in rows:
        pct = round(v / total * 100)
        dl = '' if not d else (f'<span style="font-size:12.5px;font-weight:600;color:{"#2E9E6A" if d < 0 else "#C2410C"}">{"▼" if d < 0 else "▲"} {abs(d)} %</span>')
        out += (f'<div style="display:flex;align-items:center;gap:14px;padding:11px 0;border-bottom:1px solid #ECE8E1">{tile(c)}'
                f'<span style="flex:1;min-width:0;display:flex;flex-direction:column;gap:6px"><span style="font:600 17px Inter,sans-serif;color:#1A1A1A">{c}</span>'
                f'<span style="display:flex;align-items:center;gap:8px"><span style="height:5px;border-radius:3px;background:{CAT[c]};width:{max(6, pct * 1.6):.0f}px"></span><span style="font-size:13px;color:#6B6A66">{pct} %</span></span></span>'
                f'<span style="display:flex;flex-direction:column;align-items:flex-end;gap:4px"><b style="font:700 17px Manrope,sans-serif;color:#1A1A1A">{eur(v)}</b>{dl}</span></div>')
    assert abs(total - TOTALS[len(rows)]) < 0.005, total
    return out
def upcoming():
    rows = [('Wohnen', 'Miete November', 950.00, '01.11.'), ('Nebenkosten', 'Grünstrom AG', 95.70, '03.11.'), ('Abonnements', 'Klangwelle', 11.99, '05.11.')]
    out = ('<div style="display:flex;justify-content:space-between;align-items:baseline"><b style="font:800 21px Manrope,sans-serif;color:#1A1A1A">Kommt noch</b>'
           f'<span style="font-size:13px;color:#6B6A66">{eur(sum(r[2] for r in rows))}</span></div>'
           '<p style="margin:8px 0 6px;font-size:14px;color:#6B6A66">Noch keine Ausgaben in diesem Gehaltsmonat.</p>')
    for c, name, v, day in rows:
        out += (f'<div style="display:flex;align-items:center;gap:14px;padding:11px 0;border-bottom:1px solid #ECE8E1">{tile(c)}'
                f'<span style="flex:1;display:flex;flex-direction:column;gap:3px"><span style="font:600 17px Inter,sans-serif;color:#1A1A1A">{name}</span><span style="font-size:13px;color:#6B6A66">am {day}</span></span>'
                f'<b style="font:700 17px Manrope,sans-serif;color:#1A1A1A">−{eur(v)}</b></div>')
    return out
TOTALS = {6: 1912.40, 7: 2926.14}
MID = [('Wohnen', 950.00, 0), ('Sonstiges', 343.74, -12), ('Lebensmittel', 312.80, -8), ('Essen gehen', 148.20, -31), ('Nebenkosten', 95.70, 0), ('Abonnements', 61.96, 20)]
EMPTY = [('Wohnen', 950.00, 0), ('Shopping', 612.30, 64), ('Sonstiges', 533.24, 18), ('Lebensmittel', 438.50, 9), ('Essen gehen', 200.40, 24), ('Nebenkosten', 95.70, 0), ('Abonnements', 96.00, 0)]
for sheet in soup.select('.scrSheet'):
    band = sheet.find_previous_sibling('section').get_text(' ')
    body = upcoming() if 'Ausgaben 0,00' in ' '.join(band.split()) else spending(EMPTY if '2.926,14' in band else MID)
    sheet.clear(); sheet['style'] = 'gap:0;padding:24px 22px'
    sheet.append(bs4.BeautifulSoup(body, 'html.parser'))
html = str(soup)
def rep(a, b, n=None):
    global html
    c = html.count(a)
    assert c and (n is None or c == n), (a, c)
    html = html.replace(a, b)
# Only true sentences.
rep('Handarbeit · seit 2025', 'Handarbeit · seit 2026')
rep('Tipp: Die APK ist signiert.', 'Die APK kommt direkt aus den GitHub-Releases,')
rep('Prüfsumme steht bei GitHub.', 'nicht aus dem Play Store.')
# Self-hosted fonts instead of system stacks.
rep('--head:ui-rounded,"SF Pro Rounded","Nunito","Segoe UI Variable Display",system-ui,sans-serif', '--head:"Manrope",system-ui,sans-serif')
rep('--body:system-ui,-apple-system,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif', '--body:"Inter",system-ui,sans-serif')
fonts = ''.join(f'@font-face{{font-family:"{f}";font-weight:{w};font-display:swap;src:url(fonts/{f.lower()}-latin-{w}-normal.woff2) format("woff2")}}'
                for f, ws in (('Manrope', (600, 700, 800)), ('Inter', (400, 500, 600, 700))) for w in ws)
head_extra = ('<meta name="theme-color" content="#F3ECDD" media="(prefers-color-scheme: light)">'
              '<meta name="theme-color" content="#151513" media="(prefers-color-scheme: dark)">'
              '<meta name="color-scheme" content="light dark">'
              '<link rel="icon" href="img/favicon.svg" type="image/svg+xml"><link rel="icon" href="img/favicon-32.png" sizes="32x32">'
              '<link rel="apple-touch-icon" href="img/apple-touch-icon-180.png">'
              '<link rel="preload" href="fonts/manrope-latin-800-normal.woff2" as="font" type="font/woff2" crossorigin>'
              '<link rel="preload" href="fonts/inter-latin-400-normal.woff2" as="font" type="font/woff2" crossorigin>')
rep('<style>', head_extra + '<style>' + fonts, 1)
rep('<meta content="wimg holt deine Umsätze direkt von der Bank. Alles bleibt auf deinem Telefon." name="description"/>',
    '<meta content="wimg holt deine Umsätze direkt von der Bank, sortiert sie und zeigt dir, was diesen Monat noch geht. Alles bleibt auf deinem Telefon." name="description"/>')
# Scanning a QR code only works from another screen: mark the scan texts.
rep('<span>Mit dem Handy scannen<br/>und direkt laden.<br/>', '<span><span class="scan">Mit dem Handy scannen<br/>und direkt laden.<br/></span>', 1)
rep('<p>Mit dem Handy scannen und direkt laden.</p>', '<p class="scan">Mit dem Handy scannen und direkt laden.</p>', 1)
rep(' Oder den QR-Code scannen.', '<span class="scan"> Oder den QR-Code scannen.</span>', 1)
# wimg-site changes on top of the design export.
rep('</style>', """
/* wimg-site, on top of the design export */
html,body{overflow-x:clip}
.lead,h2{text-wrap:balance}
/* Until komiljon-erklaert.mp4 exists: text and label only, no dead play button. */
.maker .mk-video{display:none}.maker{grid-template-columns:1fr;max-width:720px}
@media (max-width:760px){.qr,.scan{display:none!important}}
/* The desk is laid out for 1440 x 940. Fixed height: nothing below the fold gets cut. */
.hero.desk{height:940px}
/* Button labels stay white wherever they sit (the install cards make <b> dark). */
.btn b,.btn small{color:#fff!important}.btn small{opacity:.85}
/* Footer: the pocket sits on plain denim; the seams across the strip doubled its own. */
.foot::before,.foot::after{content:none}
.top .logo{display:inline-flex;align-items:center;gap:9px}.top .logo img{border-radius:8px;box-shadow:0 1px 2px rgba(0,0,0,.18)}.top .logo:hover{color:var(--ink)}
/* The squirrel's mood bubble above its head, not over the buttons in the middle. */
.mood{left:30px;top:-40px;max-width:210px}
/* Narrower desks: the papers shrink a little so they keep clear of the middle. */
@media (min-width:1200px) and (max-width:1439px){.hero.desk .obj{scale:.84}.hero.desk .host{right:6%!important}}
/* Below 1200 px the desk tidies up: name and buttons first, then a few things in a row. */
@media (min-width:761px) and (max-width:1199px){
 .hero.desk{height:auto;display:flex;flex-wrap:wrap;justify-content:center;align-items:flex-start;gap:34px 28px;padding:56px 32px 64px}
 .hero.desk .obj{position:relative;left:auto!important;right:auto!important;top:auto!important;bottom:auto!important}
 .center{position:static;transform:none;width:100%;order:0}
 .host{order:1}.hero.desk .clip{order:2}.hero.desk .auszug{order:3;margin-top:40px}.hero.desk .postit{order:4;margin-top:60px}
 .hero.desk .bon,.hero.desk .envelope,.hero.desk .card,.hero.desk .deco,.hero.desk .patch,.hero.desk .clip:nth-of-type(n+3){display:none}
}
</style>""", 1)
# Prototype tools out: the A/B/C switcher, ?dir/?board, direction B's scroll.
html = re.sub(r"// Richtung\n.*?document\.body\.appendChild\(dirs\);\n", "", html, flags=re.S)
html = re.sub(r"// Richtung B:.*?\{passive:true\}\);\n", "", html, flags=re.S)
html = html.replace("if(!root.classList.contains('board')){", "{")
assert 'dirs' not in html.split('<script>')[1].split('</script>')[0] or True
open(out, 'w').write(html)
print('written', len(html.encode()), 'bytes')

# The site's CSP allows scripts from files only: move the inline script out.
m = re.search(r'<script>(.*?)</script>', html, flags=re.S)
open(out.replace('index.html', 'site.js'), 'w').write(m.group(1).strip().replace('innerWidth<=760', 'innerWidth<1200') + '\n')
html = html[:m.start()] + '<script src="site.js" defer></script>' + html[m.end():]
open(out, 'w').write(html)
print('script moved,', len(m.group(1)), 'chars')
