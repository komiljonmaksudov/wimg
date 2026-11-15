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
# Real QR code (points at the APK download) instead of the placeholder.
for q in soup.select('span.qr'):
    svg = q.find('svg')
    if svg: svg.replace_with(soup.new_tag('img', src='img/qr.svg', alt='QR-Code: wimg für Android laden', width='96', height='96'))

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
open(out.replace('index.html', 'site.js'), 'w').write(m.group(1).strip() + '\n')
html = html[:m.start()] + '<script src="site.js" defer></script>' + html[m.end():]
open(out, 'w').write(html)
print('script moved,', len(m.group(1)), 'chars')
