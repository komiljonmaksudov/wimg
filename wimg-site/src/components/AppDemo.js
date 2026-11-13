// The clickable phone on the landing page: a small copy of the Android app
// (wimg-android/app/src/main/java/com/wimg/app/ui/). Same screens, bar, places
// menu, panels and docked rows; data is invented (see DemoDataService.kt) and
// lives only in this page. Props: start (route to open on), q (search query),
// hint ("0": no pulsing hint), still ("1": a picture, no clicks).

const MONTHS = ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'];
const SHORT = ['Jan', 'Feb', 'März', 'Apr', 'Mai', 'Juni', 'Juli', 'Aug', 'Sept', 'Okt', 'Nov', 'Dez'];
const WD = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'];
const TODAY = '2026-11-12';
const TY = 2026, TM = 11, TD = 12;
const MINUS = '−';

const pad = (n) => String(n).padStart(2, '0');
const iso = (y, m, d) => y + '-' + pad(m) + '-' + pad(d);
const parse = (s) => s.split('-').map(Number);
const dim = (y, m) => new Date(Date.UTC(y, m, 0)).getUTCDate();
const dayNum = (s) => { const [y, m, d] = parse(s); return Date.UTC(y, m - 1, d) / 864e5; };
const daysUntil = (s) => dayNum(s) - dayNum(TODAY);
const addDays = (s, n) => { const t = new Date((dayNum(s) + n) * 864e5); return iso(t.getUTCFullYear(), t.getUTCMonth() + 1, t.getUTCDate()); };
const addMonths = (s, n) => { const [y, m, d] = parse(s); const k = y * 12 + m - 1 + n; const yy = Math.floor(k / 12), mm = k % 12 + 1; return iso(yy, mm, Math.min(d, dim(yy, mm))); };
const dayMonth = (d, m) => d + '. ' + SHORT[m - 1] + '.';
const short = (s) => { const [y, m, d] = parse(s); return dayMonth(d, m) + (y === TY ? '' : ' ' + y); };
const full = (s) => { const [y, m, d] = parse(s); return dayMonth(d, m) + ' ' + y; };
const weekday = (s) => { const [y, m, d] = parse(s); return WD[new Date(Date.UTC(y, m - 1, d)).getUTCDay()] + '.'; };
const dayHeader = (s) => { const b = weekday(s) + ' ' + short(s); const a = -daysUntil(s); return a === 0 ? 'Heute, ' + b : a === 1 ? 'Gestern, ' + b : b; };
const dayLabel = (s) => { const a = -daysUntil(s); return a === 0 ? 'Heute' : a === 1 ? 'Gestern' : weekday(s) + ' ' + short(s); };
const ym = (y, m) => y + '-' + pad(m);

// Amounts in cents: "−1.234" + ",56 €"; income gets an explicit +.
function parts(c, plus) {
  const a = Math.abs(Math.round(c));
  const whole = String(Math.floor(a / 100)).replace(/\B(?=(\d{3})+(?!\d))/g, '.');
  const sign = a === 0 ? '' : c < 0 ? MINUS : plus === false ? '' : '+';
  return [sign + whole, ',' + pad(a % 100) + ' €'];
}
const amt = (c, plus) => parts(c, plus).join('');

// Icons (24 px grid, stroked) for the Material icons the app uses.
const I = {
  home: 'M4 10.5 12 4l8 6.5V20a1 1 0 0 1-1 1h-4.5v-6h-5v6H5a1 1 0 0 1-1-1z',
  list: 'M9 6h11M9 12h11M9 18h11M4.5 6h.01M4.5 12h.01M4.5 18h.01',
  refresh: 'M19.5 12a7.5 7.5 0 1 1-2.2-5.3M19.5 4.5v4h-4',
  calendar: 'M5.5 5h13A1.5 1.5 0 0 1 20 6.5v12a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 4 18.5v-12A1.5 1.5 0 0 1 5.5 5zM4 10h16M8 3v4M16 3v4',
  bank: 'M3 10l9-6 9 6M5 10v8M10 10v8M14 10v8M19 10v8M3 21h18',
  upload: 'M12 16V5M7 10l5-5 5 5M5 20h14',
  settings: 'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z',
  info: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18zM12 11v5M12 8h.01',
  search: 'M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14zM20 20l-4-4',
  plus: 'M12 5v14M5 12h14',
  close: 'M6 6l12 12M18 6 6 18',
  tune: 'M4 7h9M17 7h3M4 17h3M11 17h9M15 5v4M9 15v4',
  back: 'M19 12H5M11 6l-6 6 6 6',
  more: 'M6 12h.01M12 12h.01M18 12h.01',
  edit: 'M4 20h4L19 9a2.1 2.1 0 0 0-3-3L5 17v3zM14 7l3 3',
  block: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18zM5.6 5.6l12.8 12.8',
  tag: 'M20.6 13.4l-7.2 7.2a2 2 0 0 1-2.8 0L3 13V3h10l7.6 7.6a2 2 0 0 1 0 2.8zM7.5 7.5h.01',
  check: 'M5 12.5l4.5 4.5L19 7.5',
  undo: 'M9 14 4 9l5-5M4 9h10.5a5.5 5.5 0 0 1 0 11H11',
  lock: 'M7 11V8a5 5 0 0 1 10 0v3M6 11h12a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1v-8a1 1 0 0 1 1-1z',
  history: 'M3.5 12a8.5 8.5 0 1 0 2.6-6.1M3.5 4v4h4M12 7.5V12l3 2',
  copy: 'M9 9h11v11H9zM15 9V4H4v11h5',
  right: 'M9.5 6l6 6-6 6',
  left: 'M14.5 6l-6 6 6 6',
  up: 'M3 17l6-6 4 4 8-8M15 7h6v6',
  down: 'M3 7l6 6 4-4 8 8M15 17h6v-6',
  sync: 'M4.5 12A7.5 7.5 0 0 1 17.6 7M19.5 4v4h-4M19.5 12A7.5 7.5 0 0 1 6.4 17M4.5 20v-4h4',
  error: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18zM12 7.5v5.5M12 16.5h.01',
  backspace: 'M21 5H9l-6 7 6 7h12zM12 9.5l5 5M17 9.5l-5 5',
  gift: 'M4 11h16v9H4zM3 7h18v4H3zM12 7v13M12 7C10.5 4 7 4 7 6s3 1 5 1c2 0 5 1 5-1s-3.5-2-5 1',
  help: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18zM9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.6.3-1 .9-1 1.6v.6M12 17h.01',
  bug: 'M8 9.5a4 4 0 0 1 8 0V15a4 4 0 0 1-8 0zM4 13h4M16 13h4M5 7l3 2M19 7l-3 2M5 19l3-2M19 19l-3-2',
  shield: 'M12 3l8 3v6c0 4.5-3.4 8.3-8 9-4.6-.7-8-4.5-8-9V6z',
  doc: 'M6 3h8l4 4v14H6zM14 3v4h4M9 12h6M9 16h6',
  ext: 'M7 17 17 7M9 7h8v8',
  minus: 'M5 12h14',
  cart: 'M3 4h2l2.4 11h10.2L20 8H6.2M9 20h.01M17 20h.01',
  dining: 'M7 3v8M5 3v5a2 2 0 0 0 4 0V3M7 11v10M17 3c-2 1-3 3.5-3 6.5V13h3M17 3v18',
  car: 'M5 17h14v-4l-2-5H7l-2 5zM5 13h14M7.5 17v2M16.5 17v2M8 14.5h.01M16 14.5h.01',
  bolt: 'M13 3 5 13h6l-1 8 8-10h-6z',
  game: 'M7 8h10a4 4 0 0 1 4 4v1.5a2.5 2.5 0 0 1-4.5 1.5L15 13H9l-1.5 2A2.5 2.5 0 0 1 3 13.5V12a4 4 0 0 1 4-4zM8 10v4M6 12h4M15.5 11h.01M17.5 13h.01',
  bag: 'M5 8h14l-1 13H6zM9 8V6a3 3 0 0 1 6 0v2',
  heart: 'M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.6-7 10-7 10z',
  income: 'M7 17 17 7M9 7h8v8',
  swap: 'M4 8h14l-3-3M20 16H6l3 3',
  cash: 'M3 7h18v10H3zM12 14.5a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5zM6 10v4M18 10v4',
  subs: 'M4 9h16v11H4zM6 6h12M8 3h8M10.5 12v5l4-2.5z',
  euro: 'M17 6.5A6.5 6.5 0 1 0 17 17.5M4 10.5h9M4 13.5h9',
  plane: 'M10.5 20.5 12 17l7-4-1.5-1.5-5 1.5-4-4.5L10 7 8.5 5.5 5 9l3.5 3.5L7 17l2 1.5z',
  school: 'M3 9l9-5 9 5-9 5zM7 11.5V16c3 2 7 2 10 0v-4.5',
};

// Category colours (light, dark) from WimgTheme.kt; Sonstiges uses text2 and its own bar.
const CAT = {
  0: ['Sonstiges', null, null, 'tag'], 1: ['Lebensmittel', '#2E9E6A', '#5CC992', 'cart'], 2: ['Essen gehen', '#C2410C', '#F07F5A', 'dining'],
  3: ['Transport', '#0E7490', '#4FC3D9', 'car'], 4: ['Wohnen', '#8B5E3C', '#C9A27E', 'home'], 5: ['Nebenkosten', '#8A63D2', '#B39AF0', 'bolt'],
  6: ['Unterhaltung', '#BE185D', '#F078B0', 'game'], 7: ['Shopping', '#D9822B', '#F2A65E', 'bag'], 8: ['Gesundheit', '#D14343', '#F07272', 'heart'],
  9: ['Versicherung', '#3B6FD8', '#7FA6F5', 'shield'], 10: ['Einkommen', '#1B7A43', '#6FD39A', 'income'], 11: ['Umbuchung', '#64748B', '#94A3B8', 'swap'],
  12: ['Bargeld', '#7C8B2E', '#B5C25A', 'cash'], 13: ['Abonnements', '#4F46E5', '#8B8CF5', 'subs'], 14: ['Reisen', '#0284C7', '#5BC0F0', 'plane'],
  15: ['Bildung', '#A16207', '#D9A54A', 'school'], 255: ['Andere', null, null, 'tag'],
};
const PICKER = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 255, 0];
const FILTER_CATS = [1, 2, 3, 7, 6, 9, 5, 4, 13, 8, 10, 0];
const LIGHT = { text2: '#6B6A66', other: '#C9C4BB', dark: false };
const DARK = { text2: '#9A9BA0', other: '#5A5A60', dark: true };
const catName = (id) => (CAT[id] || CAT[0])[0];
const catFg = (P, id) => { const c = CAT[id]; return c && c[1] ? (P.dark ? c[2] : c[1]) : P.text2; };
const catBar = (P, id) => { const c = CAT[id]; return c && c[1] ? (P.dark ? c[2] : c[1]) : P.other; };
const tint = (hex, a) => 'color-mix(in srgb, ' + hex + ' ' + Math.round(a * 100) + '%, transparent)';

const INTERVALS = [['weekly', 'Wöchentlich', 52 / 12], ['monthly', 'Monatlich', 1], ['quarterly', 'Vierteljährlich', 1 / 3], ['annual', 'Jährlich', 1 / 12]];
const ivLabel = (iv) => (INTERVALS.find((x) => x[0] === iv) || [0, iv])[1];
const ivFactor = (iv) => (INTERVALS.find((x) => x[0] === iv) || [0, 0, 1])[2];

const PLACES = [
  ['home', 'Übersicht', 'home'], ['ums', 'Umsätze', 'list'], ['wk', 'Wiederkehrend', 'refresh'], ['review', 'Rückblick', 'calendar'],
  ['banks', 'Banken', 'bank', true], ['import', 'Import', 'upload'], ['settings', 'Einstellungen', 'settings'], ['about', 'Über wimg', 'info'],
];
const PLACE_IDS = PLACES.map((p) => p[0]);

// ---------------------------------------------------------------------------
// Demo data: twelve months up to Thu 12 Nov 2026, merchants from DemoDataService.kt.
// ---------------------------------------------------------------------------

function rng(seed) {
  return () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}

const FIXED = [
  { id: 'gehalt', name: 'Muster GmbH', desc: 'GEHALT {MON} {Y} MUSTER GMBH PERS-NR 10442', kind: 'Gutschrift', cents: 325000, cat: 10, day: 1, iv: 'monthly' },
  { id: 'miete', name: 'Hausverwaltung Musterstadt', desc: 'MIETE {MON} {Y} WHG 3 OG LINKS HAUSVERWALTUNG MUSTERSTADT', kind: 'Dauerauftrag', cents: -95000, cat: 4, day: 1, iv: 'monthly' },
  { id: 'vers', name: 'Muster Versicherung AG', desc: 'MUSTER VERSICHERUNG AG HAUSRAT VS-NR 88-1204-7', kind: 'Lastschrift', cents: -8950, cat: 9, day: 1, iv: 'monthly' },
  { id: 'strom', name: 'Grünstrom AG', desc: 'GRÜNSTROM AG ABSCHLAG STROM KD-NR 4471120 {MON}', kind: 'Lastschrift', cents: -10400, cat: 5, day: 3, iv: 'monthly' },
  { id: 'flimmer', name: 'Flimmerkiste Streaming', desc: 'FLIMMERKISTE STREAMING ABO 19-2207 {MM}/{Y}', kind: 'Lastschrift', cents: -1499, cat: 13, day: 5, iv: 'monthly' },
  { id: 'klang', name: 'Klangwelle Streaming', desc: 'KLANGWELLE STREAMING PREMIUM MITGLIEDSCHAFT {MM}/{Y}', kind: 'Lastschrift', cents: -999, cat: 13, day: 15, iv: 'monthly' },
  { id: 'funk', name: 'Funkline Mobilfunk', desc: 'FUNKLINE MOBILFUNK RG-NR 2026-{MM}-55812', kind: 'Lastschrift', cents: -3999, cat: 5, day: 20, iv: 'monthly' },
  { id: 'rundfunk', name: 'Rundfunkbeitrag', desc: 'RUNDFUNKBEITRAG BEITRAGSNR 492113870 {Q}. QUARTAL', kind: 'Lastschrift', cents: -5508, cat: 5, day: 15, iv: 'quarterly' },
];

const OFTEN = [
  // title, bank text, kind, min, max (cents, negative), times per month [lo, hi], category
  ['Supermarkt am Park', 'SUPERMARKT AM PARK {ID}//MUSTERSTADT/DE', 'Karte', -8500, -1500, 3, 4, 1],
  ['Kornfeld Supermarkt', 'KORNFELD SUPERMARKT FIL. 0{ID3} MUSTERSTADT', 'Karte', -4500, -1200, 2, 3, 1],
  ['Frische Ecke Supermarkt', 'FRISCHE ECKE SUPERMARKT {ID}', 'Karte', -5500, -800, 1, 2, 1],
  ['Musterstadt Verkehrsbetriebe', 'MUSTERSTADT VERKEHRSBETRIEBE TICKET {ID}', 'Karte', -3800, -340, 1, 2, 3],
  ['Drogerie Sonnenschein', 'DROGERIE SONNENSCHEIN {ID}', 'Karte', -2500, -500, 1, 2, 7],
  ['Pizzeria Bella Luna', 'PIZZERIA BELLA LUNA MUSTERSTADT', 'Karte', -3500, -1200, 0, 2, 2],
  ['Kaufhaus Zentrum', 'KAUFHAUS ZENTRUM MUSTERSTADT {ID}', 'Karte', -11900, -1500, 0, 2, 7],
  ['Apotheke am Markt', 'APOTHEKE AM MARKT MUSTERSTADT', 'Karte', -3000, -500, 0, 1, 8],
  ['Geldautomat Musterbank', 'AUSZAHLUNG GELDAUTOMAT MUSTERBANK FIL 12', 'Auszahlung', -10000, -5000, 0, 1, 12],
  ['Kino am Wall', 'KINO AM WALL MUSTERSTADT', 'Karte', -2400, -1100, 0, 1, 6],
  ['Flohmarkt Musterstadt', 'FLOHMARKT MUSTERSTADT STAND 14', 'Karte', -2500, -400, 0, 1, 0],
];
const MON_UP = ['', 'JANUAR', 'FEBRUAR', 'MAERZ', 'APRIL', 'MAI', 'JUNI', 'JULI', 'AUGUST', 'SEPTEMBER', 'OKTOBER', 'NOVEMBER', 'DEZEMBER'];

function makeData() {
  const r = rng(341);
  const int = (a, b) => Math.floor(a + r() * (b - a + 1));
  const txs = [];
  let n = 0;
  const add = (o) => { txs.push(Object.assign({ id: 't' + (++n), excluded: false, account: 'giro' }, o)); };
  const fill = (s, y, m) => s.replace('{MON}', MON_UP[m]).replace('{MM}', pad(m)).replace('{Y}', y).replace('{Q}', Math.ceil(m / 3)).replace('{ID}', int(10000, 99999)).replace('{ID3}', int(100, 999));
  for (let k = 0; k < 12; k++) {
    const y = k === 0 ? 2025 : 2026, m = k === 0 ? 12 : k;
    const cur = y === TY && m === TM;
    const maxDay = cur ? TD - 1 : dim(y, m);
    for (const f of FIXED) {
      if (f.iv === 'quarterly' && m % 3 !== 1) continue;
      if (cur && f.day > TD) continue;
      let cents = f.cents;
      if (f.id === 'flimmer' && cur) cents = -1799;
      if (f.id === 'strom' && y === 2026 && m >= 4) cents = -9800;
      add({ date: iso(y, m, f.day + (f.id === 'gehalt' && m === 11 ? 1 : 0)), title: f.name, desc: fill(f.desc, y, m), kind: f.kind, cents, cat: f.cat, pid: f.id });
    }
    for (const o of OFTEN) {
      const times = int(o[5], o[6]);
      for (let i = 0; i < times; i++) {
        add({ date: iso(y, m, int(2, maxDay)), title: o[0], desc: fill(o[1], y, m), kind: o[2], cents: int(o[3], o[4]), cat: o[7] });
      }
    }
  }
  // Today, so Übersicht has a "Heute".
  add({ date: TODAY, title: 'Supermarkt am Park', desc: 'SUPERMARKT AM PARK 48213//MUSTERSTADT/DE', kind: 'Karte', cents: -2348, cat: 1 });
  add({ date: TODAY, title: 'Musterstadt Verkehrsbetriebe', desc: 'MUSTERSTADT VERKEHRSBETRIEBE TICKET 77120', kind: 'Karte', cents: -340, cat: 3 });
  add({ date: TODAY, title: 'Bäckerei Sonnenkorn', desc: 'BAECKEREI SONNENKORN MUSTERSTADT', kind: 'Karte', cents: -480, cat: 2 });
  txs.sort((a, b) => (a.date < b.date ? 1 : a.date > b.date ? -1 : (+b.id.slice(1)) - (+a.id.slice(1))));
  const pending = [{ id: 'p1', date: TODAY, title: 'Kaufhaus Zentrum', desc: 'KAUFHAUS ZENTRUM MUSTERSTADT 30917', kind: 'Karte', cents: -4990, cat: 7, account: 'giro', excluded: false, pending: true }];
  const patterns = FIXED.map((f) => ({ id: f.id, name: f.name, merchant: f.desc.split(' ').slice(0, 2).join(' '), interval: f.iv, cat: f.cat, hidden: false, accepted: false, oneoff: {}, fixed: null }));
  return { txs, pending, patterns, balance: 241837, n };
}

// ---------------------------------------------------------------------------

class Component extends DCLogic {
  constructor(p) {
    super(p);
    this.uid = 'w' + Math.random().toString(36).slice(2, 8);
    this.still = p.still === '1' || p.still === true;
    // The pulsing "tap here" hint belongs to the big phone only (hint="0" on the others).
    this.hintOn = !this.still && p.hint !== '0';
    this.D = makeData();
    const start = p.start || 'home';
    this.state = {
      stack: start === 'home' ? ['home'] : ['home', start],
      menu: false, add: false, panel: null, hint: this.hintOn, dock: null, theme: 1,
      hy: TY, hm: TM, compare: 'prev', pickYear: TY,
      tf: 'all', tcats: [], period: null, picking: false, compact: false, topRow: 0,
      wkMonths: false, wkExp: true, wkInc: true, wkInactive: false, wkIv: null, wkPicked: TM, hiddenTab: false,
      txId: null, recId: start === 'rec' ? 'flimmer' : null, sel: null,
      q: p.q || '', quick: null, recent: ['klangwelle', 'supermarkt', 'miete'], sFilters: false,
      ry: TY, rm: TM, impOpen: -1,
      expense: true, digits: '', amountStep: true, mDesc: '', mCat: -1, mAcct: 'Bargeld', mDay: 0,
      bg: true, lockOn: true, lockBio: true, lockAfter: 1, secure: true, mask: false, edit: null,
    };
    if (start === 'tx') this.state.txId = this.D.txs[0].id;
    this.scrolls = {};
  }

  componentDidMount() {
    if (this.still) return;
    this.onScroll = (e) => {
      const t = e.target;
      if (!t || !t.classList || !t.classList.contains('w-scroll') || this.route() !== 'ums') return;
      const root = t.closest('.wp');
      if (!root || root.dataset.uid !== this.uid || this.sf) return;
      this.sf = requestAnimationFrame(() => {
        this.sf = 0;
        const compact = t.scrollTop > 48;
        let top = 0;
        for (const r of t.querySelectorAll('[data-i]')) { if (r.offsetTop + r.offsetHeight > t.scrollTop + 1) { top = +r.dataset.i; break; } }
        if (compact !== this.state.compact || top !== this.state.topRow) this.setState({ compact, topRow: top });
      });
    };
    document.addEventListener('scroll', this.onScroll, true);
    // The pulse on the place chip only invites the first tap.
    this.onDown = (e) => { if (this.state.hint && e.target.closest && e.target.closest('.wp[data-uid="' + this.uid + '"]')) this.setState({ hint: false }); };
    document.addEventListener('pointerdown', this.onDown, true);
    this.mq = window.matchMedia ? window.matchMedia('(prefers-color-scheme: dark)') : null;
    if (this.mq && this.mq.addEventListener) this.mq.addEventListener('change', () => { if (this.state.theme === -1) this.forceUpdate(); });
  }

  componentWillUnmount() { document.removeEventListener('scroll', this.onScroll, true); document.removeEventListener('pointerdown', this.onDown, true); clearTimeout(this.dt); clearTimeout(this.dt2); }

  route() { const st = this.state.stack; return st[st.length - 1]; }
  root() { return document.querySelector('.wp[data-uid="' + this.uid + '"]'); }
  scroller() { const r = this.root(); return r && r.querySelector('.w-scroll'); }

  // Navigation: places replace each other (Übersicht stays the root), pages stack.
  nav(stack, extra, restore) {
    const sc = this.scroller();
    if (sc) this.scrolls[this.state.stack.join('/')] = sc.scrollTop;
    this.setState(Object.assign({ stack, menu: false, add: false, panel: null, compact: false, topRow: 0, sFilters: false, edit: null }, extra || {}));
    const key = stack.join('/');
    requestAnimationFrame(() => {
      const el = this.scroller();
      if (el) el.scrollTop = restore ? (this.scrolls[key] || 0) : 0;
      if (restore && this.route() === 'ums') this.onScroll && this.onScroll({ target: el });
      if (stack[stack.length - 1] === 'search' && !this.still) { const inp = this.root() && this.root().querySelector('.w-sinput'); if (inp) inp.focus({ preventScroll: true }); }
    });
  }
  // A place is a fresh page in the app (its remembered month and filters start over).
  goTo(place, extra) {
    const fresh = { hy: TY, hm: TM, tf: 'all', tcats: [], period: null, picking: false, wkMonths: false, wkExp: true, wkInc: true, wkInactive: false, wkIv: null, wkPicked: TM, hiddenTab: false, ry: TY, rm: TM, impOpen: -1 };
    if (place === 'home') fresh.compare = 'prev';
    this.nav(place === 'home' ? ['home'] : ['home', place], Object.assign(fresh, extra || {}));
  }
  push(r, extra) { this.nav(this.state.stack.concat([r]), extra); }
  back() { const st = this.state.stack; if (st.length > 1) this.nav(st.slice(0, -1), null, true); }

  // Dock: one row on top of the bar, newest wins.
  dock(row) {
    clearTimeout(this.dt); clearTimeout(this.dt2);
    const id = (this.dockId = (this.dockId || 0) + 1);
    this.setState({ dock: Object.assign({ id }, row) });
    const ms = row.timeout || (row.kind === 'undo' ? 6000 : row.kind === 'sync' ? 0 : 4000);
    if (ms) this.dt = setTimeout(() => { if (this.state.dock && this.state.dock.id === id) this.setState({ dock: null }); }, ms);
  }
  undo(title, sub, fn) { this.dock({ kind: 'undo', title, sub, action: 'Rückgängig', onAction: fn }); }
  info(title, sub) { this.dock({ kind: 'info', title, sub }); }
  demo(title) { this.dock({ kind: 'prompt', title, sub: 'Geht in der App, nicht in dieser Vorschau', timeout: 3200 }); }
  fetch(title, sub, done) {
    this.dock({ kind: 'sync', title, sub, progress: true });
    this.dt2 = setTimeout(done, 1500);
  }

  // ---- data helpers ----
  tx(id) { return this.D.txs.find((t) => t.id === id) || this.D.pending.find((t) => t.id === id); }
  booked() { return this.D.txs; }
  summary(y, m) {
    const pre = ym(y, m);
    const rows = this.D.txs.filter((t) => t.date.startsWith(pre) && !t.excluded && t.date <= TODAY);
    let income = 0, expenses = 0; const by = {};
    for (const t of rows) {
      if (t.cents > 0) income += t.cents; else { expenses += -t.cents; if (t.cat !== 10) by[t.cat] = (by[t.cat] || 0) + -t.cents; }
    }
    return { income, expenses, count: rows.length, by, rows };
  }
  compareSummary(y, m) {
    const before = (n) => { const k = y * 12 + m - 1 - n; return [Math.floor(k / 12), k % 12 + 1]; };
    if (this.state.compare === 'prev') return this.summary(...before(1));
    if (this.state.compare === 'year') return this.summary(y - 1, m);
    const ms = [1, 2, 3].map((n) => this.summary(...before(n))).filter((x) => x.count > 0);
    if (!ms.length) return null;
    const by = {};
    ms.forEach((x) => Object.keys(x.by).forEach((k) => { by[k] = (by[k] || 0) + x.by[k] / ms.length; }));
    return { income: ms.reduce((a, x) => a + x.income, 0) / ms.length, expenses: 0, count: 1, by };
  }
  payments(p) { return this.D.txs.filter((t) => t.pid === p.id); }
  patternInfo(p) {
    const pays = this.payments(p);
    const counted = pays.filter((t) => !p.oneoff[t.id]);
    const last = counted[0] || pays[0];
    const cents = p.fixed != null ? p.fixed : last ? last.cents : 0;
    const prev = counted[1];
    const step = p.interval === 'quarterly' ? 3 : p.interval === 'annual' ? 12 : 1;
    const next = last ? addMonths(last.date, step) : null;
    const changed = !p.accepted && last && prev && Math.abs(last.cents - prev.cents) > 0;
    return { pays, counted, last, cents, prev: changed ? prev.cents : null, lastSeen: last ? last.date : '', next, changed, active: true };
  }

  // ---------------------------------------------------------------------------
  renderVals() {
    const s = this.state, D = this.D;
    const dark = s.theme === 2 || (s.theme === -1 && this.mq && this.mq.matches);
    const P = dark ? DARK : LIGHT;
    const route = this.route();
    const v = { uid: this.uid, cls: 'wp' + (dark ? ' dark' : '') + (this.still ? ' still' : '') + (s.dock ? ' docked' : ''), is: {}, p: {}, I, inert: this.still, menuExp: s.menu ? 'true' : 'false' };
    v.is[route] = true;
    v.navColor = dark ? 'rgba(255,255,255,.75)' : 'rgba(0,0,0,.75)';
    const open = (id) => () => this.push('tx', { txId: id });
    const setPanel = (p) => () => this.setState({ panel: s.panel === p ? null : p, menu: false, add: false });
    const txRow = (t) => ({ id: t.id, title: t.title, cents: t.cents });

    // ---------- Übersicht ----------
    if (route === 'home') {
      const y = s.hy, m = s.hm, cur = y === TY && m === TM;
      const S = this.summary(y, m), prev = this.compareSummary(y, m);
      const avail = S.income - S.expenses;
      const [w, c] = parts(avail);
      const days = cur ? TD : dim(y, m);
      const prevIncome = prev ? prev.income : 0;
      const ring = S.income > 0 && S.income >= S.expenses && (prevIncome <= 0 || S.income >= prevIncome * 0.1);
      const pct = S.income > 0 ? Math.round((S.income - S.expenses) / S.income * 100) : 0;
      const cats = Object.keys(S.by).map(Number).filter((id) => S.by[id] > 0).sort((a, b) => S.by[b] - S.by[a]);
      const total = cats.reduce((a, id) => a + S.by[id], 0);
      const prevBy = prev && prev.count > 0 ? prev.by : null;
      const hasPrev = prevBy && Object.keys(prevBy).length > 0;
      const pm = (m + 10) % 12 + 1;
      const inMonth = S.rows;
      const lastDate = inMonth.length ? inMonth.reduce((a, t) => (t.date > a ? t.date : a), '') : null;
      const day = lastDate ? inMonth.filter((t) => t.date === lastDate).slice(0, 6) : [];
      const dayRow = (t, pend) => ({
        title: t.title, open: open(t.id), dot: catBar(P, t.cat),
        sub: [dayMonth(parse(t.date)[2], parse(t.date)[1]), catName(t.cat), t.kind, pend ? 'vorgemerkt' : null].filter(Boolean).join(' · '),
        amount: amt(t.cents), color: pend ? 'var(--text3)' : t.cents > 0 ? 'var(--pos)' : 'var(--text)',
      });
      const pending = cur ? D.pending : [];
      v.home = {
        over: 'Verfügbar im ' + MONTHS[m - 1], w, c,
        color: avail > 0 ? 'var(--bandPos)' : avail < 0 ? 'var(--bandNeg)' : '#fff',
        sub: cur ? S.count + ' Umsätze bis ' + dayMonth(TD, m) : S.count + ' Umsätze',
        ring, pct: pct + ' %', dash: (241.9 * Math.max(0, Math.min(100, pct)) / 100).toFixed(1) + ' 241.9',
        inc: amt(S.income), out: amt(-S.expenses), perDay: amt(Math.round(S.expenses / Math.max(1, days)), false),
        hasCats: cats.length > 0, noCats: cats.length === 0,
        cmp: hasPrev ? (s.compare === 'prev' ? 'vs. ' + MONTHS[pm - 1] : s.compare === 'avg' ? 'vs. Ø 3 Monate' : 'vs. ' + SHORT[m - 1] + ' ' + (y - 1)) : '',
        bar: cats.map((id) => ({ flex: Math.max(0.004, S.by[id] / total).toFixed(4), color: catBar(P, id) })),
        cats: cats.map((id) => {
          const p = Math.round(S.by[id] / total * 100);
          const before = prevBy && prevBy[id] > 0 ? prevBy[id] : 0;
          const chg = before ? Math.round((S.by[id] - before) / before * 100) : 0;
          const fg = catFg(P, id);
          return {
            icon: I[(CAT[id] || CAT[0])[3]], fg, bg: tint(fg, dark ? 0.13 : 0.10), label: catName(id), amount: amt(S.by[id], false),
            w: Math.max(4, Math.min(180, p * 2)) + 'px', barc: catBar(P, id), pct: p + ' %',
            hasChg: chg !== 0, chg: Math.min(999, Math.abs(chg)) + ' %', chgColor: chg > 0 ? 'var(--danger)' : 'var(--pos)', arrow: chg > 0 ? 'M7 14l5-5 5 5z' : 'M7 10l5 5 5-5z',
            open: () => this.goTo('ums', { tcats: [id], period: monthPeriod(y, m), tf: 'all' }),
          };
        }),
        hasPending: pending.length > 0, pendTotal: amt(pending.reduce((a, t) => a + t.cents, 0)), pending: pending.map((t) => dayRow(t, true)),
        hasDay: day.length > 0, dayTitle: lastDate ? dayLabel(lastDate) : '', dayTotal: amt(day.reduce((a, t) => a + t.cents, 0)), day: day.map((t) => dayRow(t, false)),
      };
    }

    // ---------- Umsätze ----------
    let ums = null;
    if (route === 'ums') {
      const per = s.period;
      const match = (t) => (s.tf === 'all' || (s.tf === 'out' ? t.cents < 0 : t.cents > 0)) && (!s.tcats.length || s.tcats.includes(t.cat)) && (!per || (t.date >= per.from && t.date <= per.to));
      const list = D.txs.filter((t) => t.date <= TODAY && match(t));
      const pend = D.pending.filter(match);
      const active = s.tf !== 'all' || s.tcats.length > 0 || !!per;
      const anchored = !active;
      const top = Math.min(s.topRow, Math.max(0, list.length - 1));
      const running = anchored ? D.balance - list.slice(0, top).reduce((a, t) => a + t.cents, 0) : list.slice(top).reduce((a, t) => a + t.cents, 0);
      const [w, c] = parts(running, !anchored);
      const groups = []; let g = null;
      const lim = this.still ? 14 : list.length;
      list.slice(0, lim).forEach((t, i) => {
        if (!g || g.date !== t.date) { g = { date: t.date, label: dayHeader(t.date), total: 0, rows: [], first: groups.length === 0 && pend.length === 0 }; groups.push(g); }
        g.total += t.cents;
        g.rows.push(Object.assign(this.txVals(P, t, false), { i }));
      });
      groups.forEach((x) => { x.rows.forEach((r, k) => { r.div = k < x.rows.length - 1; }); x.totalTxt = amt(x.total); x.totalColor = x.total > 0 ? 'var(--pos)' : 'var(--text2)'; x.pad = x.first ? '18px' : '26px'; });
      ums = list;
      v.ums = {
        title: anchored ? 'Kontostand' : active ? 'Summe der Treffer' : 'Summe der Umsätze', w, c, full: !s.compact, compact: s.compact, compactAmt: amt(running, !anchored),
        sub: (anchored ? ['Musterbank', 'Stand ' + short(TODAY)] : []).concat([list.length + ' Umsätze']).join(' · '),
        empty: list.length === 0, groups, hasPending: pend.length > 0, pendHead: 'Vorgemerkt · ' + pend.length, pendTotal: amt(pend.reduce((a, t) => a + t.cents, 0)),
        pending: pend.map((t, k) => Object.assign(this.txVals(P, t, true), { div: k < pend.length - 1 })),
      };
    }

    // ---------- Wiederkehrend ----------
    if (route === 'wk') {
      const month = ym(TY, TM);
      const all = D.patterns.filter((p) => !p.hidden).map((p) => Object.assign({ p }, this.patternInfo(p)));
      const hidden = D.patterns.filter((p) => p.hidden);
      const exp = all.filter((x) => x.cents < 0);
      const perMonth = exp.reduce((a, x) => a + Math.abs(x.cents) * ivFactor(x.p.interval), 0);
      const due = exp.filter((x) => x.lastSeen.startsWith(month) || (x.next || '').startsWith(month) || x.p.interval === 'monthly');
      const paid = due.filter((x) => x.lastSeen.startsWith(month)).reduce((a, x) => a + Math.abs(x.cents), 0);
      const openSum = due.filter((x) => !x.lastSeen.startsWith(month)).reduce((a, x) => a + Math.abs(x.cents), 0);
      const shown = all.filter((x) => ((x.cents < 0 && s.wkExp) || (x.cents > 0 && s.wkInc)) && (!s.wkIv || x.p.interval === s.wkIv));
      const dueDay = (x) => x.lastSeen.startsWith(month) ? parse(x.lastSeen)[2] : (x.next || '').startsWith(month) ? parse(x.next)[2] : null;
      const [w, c] = parts(perMonth, false);
      const sections = [];
      INTERVALS.forEach(([id, label]) => {
        const items = shown.filter((x) => x.cents < 0 && x.p.interval === id).sort((a, b) => ((dueDay(a) || 99) - (dueDay(b) || 99)) || a.p.name.localeCompare(b.p.name));
        if (items.length) sections.push([label, items]);
      });
      const inc = shown.filter((x) => x.cents > 0);
      if (inc.length) sections.push(['Einnahmen', inc]);
      v.wk = {
        w, c, count: exp.length === 1 ? '1 feste Zahlung erkannt' : exp.length + ' feste Zahlungen erkannt',
        hasProg: paid + openSum > 0, prog: (paid / Math.max(1, paid + openSum) * 100).toFixed(1) + '%',
        paidLabel: 'Bezahlt im ' + SHORT[TM - 1] + '.', paid: amt(paid, false), open: amt(openSum, false),
        empty: shown.length === 0, list: !s.wkMonths && shown.length > 0, months: s.wkMonths && shown.length > 0,
        sections: sections.map(([title, items], si) => {
          const total = items.reduce((a, x) => a + x.cents, 0);
          return {
            title, pad: si === 0 ? '18px' : '26px', total: amt(total > 0 ? total : Math.abs(total), total > 0), totalColor: total > 0 ? 'var(--pos)' : 'var(--text2)',
            rows: items.map((x, k) => {
              const income = x.cents > 0, paidNow = x.lastSeen.startsWith(month), d = dueDay(x);
              const next = x.next ? daysUntil(x.next) : null, lab = ivLabel(x.p.interval);
              let sub;
              if (!income && x.prev != null && Math.abs(x.cents) - Math.abs(x.prev) > 50) sub = 'Preis gestiegen · vorher ' + amt(Math.abs(x.prev), false);
              else if (!income && x.prev != null && Math.abs(x.prev) - Math.abs(x.cents) > 50) sub = 'Preis gesunken · vorher ' + amt(Math.abs(x.prev), false);
              else if (income && !paidNow && next != null && next >= 0) sub = lab + ' · erwartet in ' + next + ' Tagen';
              else if (next != null && next > 0 && paidNow) sub = lab + ' · nächste in ' + next + ' Tagen';
              else if (next != null && next > 0) sub = lab + ' · in ' + next + ' Tagen';
              else if (next === 0) sub = lab + ' · heute fällig';
              else sub = lab;
              return {
                hasDay: d != null, noDay: d == null, day: d + '.', mon: SHORT[TM - 1] + '.', name: x.p.name, sub,
                amount: amt(income ? x.cents : Math.abs(x.cents), income), color: income ? 'var(--pos)' : 'var(--text)',
                paid: paidNow, open: !paidNow, dotBg: income ? 'var(--pos)' : 'var(--ink)', div: k < items.length - 1,
                go: () => this.push('rec', { recId: x.p.id }),
              };
            }),
          };
        }),
      };
      if (s.wkMonths) v.wk.year = this.yearVals(exp);
    }

    // ---------- Umsatz-Detail ----------
    if (route === 'tx') {
      const t = this.tx(s.txId) || D.txs[0];
      const [w, c] = parts(t.cents);
      const acct = t.account === 'giro' ? 'Musterbank' : t.account;
      v.tx = {
        over: [t.pending ? 'Vorgemerkt' : null, full(t.date), t.kind].filter(Boolean).join(' · '), w, c, color: t.cents > 0 ? 'var(--bandPos)' : '#fff',
        acct, date: full(t.date), cat: catName(t.cat), dot: catBar(P, t.cat), hasKind: !!t.kind, kind: (t.kind || '').toUpperCase(), desc: t.desc,
        pending: !!t.pending, booked: !t.pending, excluded: t.excluded,
        toggleCls: 'w-toggle' + (t.excluded ? ' on' : ''), toggle: () => this.setExcluded(t, !t.excluded), pickCat: t.pending ? null : setPanel('cat'),
      };
    }

    // ---------- Wiederkehrend-Detail ----------
    if (route === 'rec') {
      const p = D.patterns.find((x) => x.id === s.recId) || D.patterns[0];
      const x = this.patternInfo(p);
      const income = x.cents > 0, a = Math.abs(x.cents);
      const [w, c] = parts(a, income);
      const day = x.lastSeen ? parse(x.lastSeen)[2] : null;
      const newest = x.counted[0], before = x.counted[1];
      const up = x.changed && Math.abs(newest.cents) > Math.abs(before.cents);
      const diff = x.changed ? (Math.abs(newest.cents) - Math.abs(before.cents)) * ivFactor(p.interval) : 0;
      const nd = x.next ? daysUntil(x.next) : null;
      v.rec = {
        over: [ivLabel(p.interval), day ? 'am ' + day + '.' : null].filter(Boolean).join(' · '), w, c, color: income ? 'var(--bandPos)' : '#fff', name: p.name,
        changed: x.changed && !income, up, warnBg: up ? 'var(--warnBg)' : 'var(--accentSoft)', warnFg: up ? 'var(--warn)' : 'var(--accent)', trend: up ? I.up : I.down,
        changeTitle: x.changed ? (up ? 'Preis gestiegen: ' : 'Preis gesunken: ') + amt(Math.abs(before.cents), false) + ' → ' + amt(Math.abs(newest.cents), false) : '',
        changeSub: amt(diff) + ' im Monat · ' + amt(diff * 12) + ' im Jahr',
        oneoff: () => this.markOneoff(p, newest, before), accept: () => this.acceptPrice(p, newest),
        statsPad: x.changed && !income ? '18px' : '0px',
        next: x.next ? short(x.next) : '–', nextSub: nd == null ? '' : nd > 1 ? 'in ' + nd + ' Tagen' : nd === 1 ? 'morgen' : nd === 0 ? 'heute' : 'überfällig',
        year: amt(Math.round(a * 12 * ivFactor(p.interval)), false), sofar: amt(x.counted.reduce((q, t) => q + Math.abs(t.cents), 0), false),
        count: x.counted.length === 1 ? '1 Zahlung' : x.counted.length + ' Zahlungen',
        pays: x.pays.map((t, i) => {
          const one = !!p.oneoff[t.id];
          const ci = x.counted.indexOf(t), older = ci >= 0 ? x.counted[ci + 1] : null;
          const note = one ? 'Einzelzahlung · zählt hier nicht' : !older || older.cents === t.cents ? '' : ci === 0 ? (x.changed ? 'neuer Preis?' : 'neuer Preis') : 'Preis geändert';
          return {
            one, paid: !one, bg: income ? 'var(--pos)' : 'var(--ink)', date: full(t.date), dateColor: one ? 'var(--text2)' : 'var(--text)', note, hasNote: !!note,
            noteColor: one ? 'var(--text2)' : 'var(--warn)', amount: amt(t.cents), amtColor: one ? 'var(--text2)' : income ? 'var(--pos)' : 'var(--text)', deco: one ? 'line-through' : 'none',
            tap: one ? () => this.dock({ kind: 'prompt', title: 'Gehört diese Zahlung dazu?', sub: amt(t.cents), action: 'Ja, zählt dazu', onAction: () => { delete p.oneoff[t.id]; this.forceUpdate(); }, timeout: 8000 }) : null,
          };
        }),
      };
    }

    // ---------- Suche ----------
    if (route === 'search') {
      const q = s.q.trim(), ql = q.toLowerCase();
      const quickM = { 1: (t) => t.cat === 1, 5: (t) => t.cat === 5, 9: (t) => t.cat === 9, 7: (t) => t.cat === 7, u: (t) => t.cat === 0, inc: (t) => t.cents > 0, big: (t) => Math.abs(t.cents) >= 10000, ex: (t) => t.excluded };
      const active = q.length > 0 || s.quick != null;
      const hits = active ? D.txs.filter((t) => t.date <= TODAY && (!q || t.desc.toLowerCase().includes(ql)) && (s.quick == null || quickM[s.quick](t))) : [];
      const quickLabel = { 1: 'Lebensmittel', 5: 'Nebenkosten', 9: 'Versicherung', 7: 'Shopping', u: 'Unkategorisiert', inc: 'Nur Einnahmen', big: 'Über 100 €', ex: 'Ausgeschlossene' };
      const sum = hits.reduce((a, t) => a + t.cents, 0);
      const [w, c] = parts(sum);
      let range = '';
      if (hits.length) {
        const ds = hits.map((t) => t.date).sort(); const [y1, m1] = parse(ds[0]), [y2, m2] = parse(ds[ds.length - 1]);
        range = y1 === y2 && m1 === m2 ? SHORT[m2 - 1] + '. ' + y2 : y1 === y2 ? SHORT[m1 - 1] + '. – ' + SHORT[m2 - 1] + '. ' + y2 : SHORT[m1 - 1] + '. ' + y1 + ' – ' + SHORT[m2 - 1] + '. ' + y2;
      }
      const label = [q ? '„' + q + '“' : null, s.quick != null ? quickLabel[s.quick] : null].filter(Boolean).join(' · ');
      const lim = this.still ? 12 : 200;
      v.search = {
        title: !active || hits.length === 0, result: active && hits.length > 0, start: !active, none: active && hits.length === 0,
        over: [label, hits.length === 1 ? '1 Treffer' : hits.length + ' Treffer', range].join(' · '), w, c, color: sum > 0 ? 'var(--bandPos)' : '#fff',
        avg: hits.length ? 'Ø ' + amt(Math.round(Math.abs(sum) / hits.length), false) + ' pro Umsatz' : '',
        noneTitle: q ? 'Keine Treffer für „' + q + '“' : 'Keine Treffer', hasQ: !!q,
        recent: s.recent.map((r) => { const n = D.txs.filter((t) => t.desc.toLowerCase().includes(r.toLowerCase())).length; return { r, n: n === 1 ? '1 Treffer' : n + ' Treffer', go: () => this.setQuery(r) }; }),
        hasRecent: s.recent.length > 0,
        hits: hits.slice(0, lim).map((t) => ({ segs: highlight(snippet(t, q), q), sub: [full(t.date), 'Musterbank', catName(t.cat)].join(' · '), w: parts(t.cents)[0], c: parts(t.cents)[1], color: t.cents > 0 ? 'var(--pos)' : 'var(--text)', go: () => { if (q) this.remember(q); this.push('tx', { txId: t.id }); } })),
        value: s.q, clear: !!s.q, fbCls: 'w-bicon' + (s.sFilters || s.quick != null ? ' ink' : ''), filters: s.sFilters,
      };
      const quick = [[1, catBar(P, 1)], [5, catBar(P, 5)], [9, catBar(P, 9)], [7, catBar(P, 7)], ['u', null], ['inc', null], ['big', null], ['ex', null]];
      v.search.quick = quick.map(([k, col]) => ({ label: quickLabel[k], on: s.quick === k, cls: 'w-pill' + (s.quick === k ? ' on' : ''), dot: !!col, ring: !col, color: col, go: () => this.setState({ quick: s.quick === k ? null : k, sFilters: false }) }));
      v.search.onInput = (e) => this.setState({ q: e.target.value });
      v.search.onKey = (e) => { if (e.key === 'Enter') { if (s.q.trim()) this.remember(s.q.trim()); e.target.blur(); } };
      v.search.doClear = () => { this.setState({ q: '' }); const inp = this.root().querySelector('.w-sinput'); if (inp) { inp.value = ''; inp.focus({ preventScroll: true }); } };
      v.search.toggleFilters = () => this.setState({ sFilters: !s.sFilters });
      v.search.back = () => this.back();
    }

    // ---------- Rückblick ----------
    if (route === 'review') {
      const y = s.ry, m = s.rm, cur = y === TY && m === TM;
      const S = this.summary(y, m);
      const pk = y * 12 + m - 2, py = Math.floor(pk / 12), pm = pk % 12 + 1;
      const PS = this.summary(py, pm);
      const net = S.income - S.expenses;
      const change = PS.count > 0 && PS.expenses ? Math.round((S.expenses - PS.expenses) / PS.expenses * 100) : null;
      const lastDate = S.rows.length ? S.rows.reduce((a, t) => (t.date > a ? t.date : a), '') : null;
      const biggest = S.rows.filter((t) => t.cents < 0).sort((a, b) => a.cents - b.cents)[0];
      const items = [];
      if (biggest) items.push({ icon: I.euro, fg: '#8B5CF6', over: 'Größte Einzelausgabe', title: biggest.title + ' · ' + short(biggest.date), amount: amt(biggest.cents), go: open(biggest.id) });
      const ch = Object.keys(S.by).map(Number).filter((id) => id !== 0 && PS.by[id]).map((id) => [id, Math.round((S.by[id] - PS.by[id]) / PS.by[id] * 100)]);
      const upC = ch.filter((x) => x[1] > 0).sort((a, b) => b[1] - a[1])[0];
      const downC = ch.filter((x) => x[1] < 0).sort((a, b) => a[1] - b[1])[0];
      if (upC) items.push({ icon: I.up, fg: 'var(--danger)', over: 'Stärkster Anstieg vs. ' + SHORT[pm - 1], title: catName(upC[0]) + ' ▲ ' + upC[1] + ' %', amount: amt(S.by[upC[0]], false) });
      if (downC) items.push({ icon: I.down, fg: 'var(--pos)', over: 'Stärkster Rückgang vs. ' + SHORT[pm - 1], title: catName(downC[0]) + ' ▼ ' + -downC[1] + ' %', amount: amt(S.by[downC[0]], false) });
      if (S.by[0]) items.push({ icon: I.tag, fg: 'var(--text2)', over: 'Noch nicht zugeordnet', title: 'Sonstiges · ' + Math.round(S.by[0] / S.expenses * 100) + ' %', amount: amt(S.by[0], false), go: () => this.goTo('ums', { tcats: [0], period: monthPeriod(y, m), tf: 'all' }) });
      const fixed = D.patterns.filter((p) => !p.hidden).map((p) => Object.assign({ p }, this.patternInfo(p))).filter((x) => x.cents < 0 && x.lastSeen.startsWith(ym(y, m)));
      if (fixed.length) items.push({ icon: I.refresh, fg: 'var(--accent)', over: 'Fixkosten bezahlt', title: fixed.length === 1 ? fixed[0].p.name : fixed.length + ' Zahlungen · ' + fixed.slice(0, 2).map((x) => x.p.name).join(', ') + (fixed.length > 2 ? ' …' : ''), amount: amt(fixed.reduce((a, x) => a + x.cents, 0)), go: () => this.goTo('wk') });
      items.forEach((it, i) => { it.div = i > 0; it.bg = tint(it.fg, 0.1); });
      v.review = {
        over: cur && lastDate ? 'Monatsabschluss · Vorschau mit Daten bis ' + short(lastDate) : 'Monatsabschluss',
        has: S.count > 0, none: S.count === 0, noneText: 'Für ' + MONTHS[m - 1] + ' gibt es noch keine Umsätze.',
        a: 'Dein ' + MONTHS[m - 1] + ': Du hast ', b: amt(Math.abs(net), false), bc: net < 0 ? 'var(--bandNeg)' : 'var(--bandPos)', c: net < 0 ? ' mehr ausgegeben als eingenommen.' : ' mehr eingenommen als ausgegeben.',
        hasChange: change != null && change !== 0, change: change < 0 ? -change + ' % weniger Ausgaben als im ' + MONTHS[pm - 1] + '.' : change + ' % mehr Ausgaben als im ' + MONTHS[pm - 1] + '.',
        inc: amt(S.income), out: amt(-S.expenses), count: String(S.count), items,
      };
    }

    // ---------- Banken ----------
    if (route === 'banks') {
      const [w, c] = parts(D.balance, false);
      v.banks = { w, c, stand: 'Kontostand · Stand ' + short(TODAY), open: () => this.demo('Bank einrichten'), refresh: () => this.fetch('Umsätze laden', 'Musterbank · Schnellabfrage', () => this.info('Alles aktuell', 'Musterbank · keine neuen Umsätze')) };
    }

    // ---------- Import ----------
    if (route === 'import') {
      const SRC = [['Comdirect', 'Girokonto', ['Bei Comdirect im Browser anmelden.', 'Umsätze des Girokontos öffnen und als CSV exportieren.', 'Die Datei hier auswählen. Sie bleibt auf deinem Gerät.']],
        ['Trade Republic', 'Verrechnungskonto', ['In der Trade-Republic-App oder im Browser das Profil öffnen.', 'Unter Transaktionen den Export als CSV anfordern.', 'Die Datei hier auswählen. Sie bleibt auf deinem Gerät.']],
        ['Scalable', 'Verrechnungskonto', ['Bei Scalable Capital im Browser anmelden.', 'Unter Transaktionen die Umsätze als CSV exportieren.', 'Die Datei hier auswählen. Sie bleibt auf deinem Gerät.']]];
      v.imp = { src: SRC.map(([name, acct, steps], i) => ({ name, acct, open: s.impOpen === i, closed: s.impOpen !== i, div: i > 0, bg: s.impOpen === i ? 'var(--accentSoft)' : 'transparent', steps: steps.map((t, k) => ({ n: k + 1 + '.', t })), go: () => this.setState({ impOpen: s.impOpen === i ? -1 : i }) })) };
    }

    // ---------- Umsatz von Hand ----------
    if (route === 'manual') {
      const cents = parseCents(s.digits);
      v.man = {
        segs: [[true, 'Ausgabe'], [false, 'Einnahme']].map(([e, label]) => ({ label, cls: 'w-mseg' + (s.expense === e ? ' on' : ''), go: () => this.setState({ expense: e }) })),
        amount: (s.expense ? MINUS : '+') + formatTyped(s.digits) + ' €', amtColor: cents === 0 ? 'var(--bandSub)' : '#fff', toAmount: () => this.setState({ amountStep: true, panel: null }),
        desc: s.mDesc, onDesc: (e) => this.setState({ mDesc: e.target.value.slice(0, 120) }), focusDesc: () => { if (s.amountStep) this.setState({ amountStep: false }); },
        catNone: s.mCat < 0, catSet: s.mCat >= 0, cat: catName(s.mCat), catDot: catBar(P, s.mCat), pickCat: () => this.setState({ amountStep: false, panel: 'mcat', sel: s.mCat < 0 ? 0 : s.mCat }),
        acct: s.mAcct, pickAcct: () => this.setState({ amountStep: false, panel: 'macct' }), day: mDayLabel(s.mDay), pickDay: () => this.setState({ amountStep: false, panel: 'mday' }),
        keypad: s.amountStep, keys: ['1', '2', '3', '4', '5', '6', '7', '8', '9', ',', '0', '⌫'].map((k) => ({ k, txt: k !== '⌫', del: k === '⌫', go: () => this.key(k) })),
      };
    }

    // ---------- Einstellungen, App-Sperre, Über wimg ----------
    if (route === 'settings') {
      v.set = {
        theme: [['Hell', 1], ['Dunkel', 2], ['System', -1]].map(([label, t]) => ({ label, cls: 'w-sseg' + (s.theme === t ? ' on' : ''), go: () => this.setState({ theme: t }) })),
        bgCls: 'w-toggle' + (s.bg ? ' on' : ''), bg: () => this.setState({ bg: !s.bg }), lockVal: s.lockOn ? 'An' : 'Aus',
        lang: setPanel('lang'), sync: () => this.demo('wimg Sync einrichten'), banks: () => this.push('banks'), lock: () => this.push('lock'),
        auto: () => this.info('Nichts Neues zuzuordnen'), rules: () => this.demo('Gelernte Regeln'), data: () => this.demo('Exportieren und sichern'),
        imp: () => this.push('import'), del: () => this.demo('Alle Daten löschen'), about: () => this.push('about'), faq: () => this.demo('FAQ und Datenschutz'),
      };
    }
    if (route === 'lock') {
      const tg = (k) => () => this.setState({ [k]: !s[k] });
      v.lock = {
        onCls: 'w-toggle' + (s.lockOn ? ' on' : ''), on: tg('lockOn'), bio: s.lockBio, pin: !s.lockBio, bioGo: () => this.setState({ lockBio: true }), pinGo: () => this.setState({ lockBio: false }),
        after: ['Sofort', '1 Min.', '5 Min.', '15 Min.'].map((label, i) => ({ label, cls: 'w-sseg fill' + (s.lockAfter === i ? ' on' : ''), go: () => this.setState({ lockAfter: i }) })),
        secureCls: 'w-toggle' + (s.secure ? ' on' : ''), secure: tg('secure'), maskCls: 'w-toggle' + (s.mask ? ' on' : ''), mask: tg('mask'),
      };
    }
    if (route === 'about') {
      v.about = { news: () => this.demo('Neuigkeiten'), update: () => this.fetch('Suche nach Updates', 'GitHub', () => this.dock({ kind: 'prompt', title: 'Updates prüft die App', sub: 'Diese Vorschau hat keine Version', timeout: 3200 })), faq: () => this.demo('Häufige Fragen'), bug: () => this.demo('Problem melden'), privacy: () => this.demo('So bleiben deine Daten bei dir'), policy: () => { window.location.href = 'datenschutz.html'; } };
    }

    this.barVals(v, P, route, ums);
    this.panelVals(v, P, route);
    this.dockVals(v);
    return v;
  }

  txVals(P, t, pend) {
    const [w, c] = parts(t.cents);
    return {
      title: t.title, titleColor: t.excluded ? 'var(--text3)' : 'var(--text)', dot: catBar(P, t.cat), w, c,
      sub: [catName(t.cat), t.kind, t.excluded ? 'ausgeschlossen' : null, pend ? 'vorgemerkt' : null].filter(Boolean).join(' · '),
      color: t.excluded || pend ? 'var(--text3)' : t.cents > 0 ? 'var(--pos)' : 'var(--text)', go: () => this.push('tx', { txId: t.id }),
    };
  }

  yearVals(exp) {
    const s = this.state;
    const paidIn = (m) => exp.flatMap((x) => x.pays.filter((t) => t.date.startsWith(ym(TY, m)) && !x.p.oneoff[t.id]).map((t) => [x, t]));
    const dueIn = (x, m) => {
      if (!x.next) return false;
      const [ny, nm] = parse(x.next); const diff = (TY - ny) * 12 + (m - nm);
      if (diff < 0) return false;
      return x.p.interval === 'quarterly' ? diff % 3 === 0 : x.p.interval === 'annual' ? diff % 12 === 0 : true;
    };
    const expIn = (m) => exp.filter((x) => dueIn(x, m) && (m > TM || !x.pays.some((t) => t.date.startsWith(ym(TY, m)))));
    let paidTotal = 0, expTotal = 0;
    for (let m = 1; m <= TM; m++) paidTotal += paidIn(m).reduce((a, [, t]) => a - t.cents, 0);
    for (let m = TM; m <= 12; m++) expTotal += expIn(m).reduce((a, x) => a - x.cents, 0);
    const cells = [];
    for (let m = 1; m <= 12; m++) {
      const fut = m > TM, sum = fut ? expIn(m).reduce((a, x) => a - x.cents, 0) : paidIn(m).reduce((a, [, t]) => a - t.cents, 0), sel = m === s.wkPicked;
      cells.push({ name: SHORT[m - 1], sum: sum > 0 ? amt(sum, false) : '–', cls: 'w-ycell' + (sel ? ' sel' : fut ? ' fut' : ''), go: () => this.setState({ wkPicked: m }) });
    }
    const pm = s.wkPicked;
    const paid = paidIn(pm).sort((a, b) => (a[1].date < b[1].date ? -1 : 1));
    const expd = pm >= TM ? expIn(pm).sort((a, b) => parse(a.next)[2] - parse(b.next)[2]) : [];
    const rows = paid.map(([x, t]) => ({ day: parse(t.date)[2] + '.', dc: 'var(--text)', mon: SHORT[pm - 1] + '.', name: x.p.name, sub: ivLabel(x.p.interval) + ' · bezahlt', amount: amt(-t.cents, false), ac: 'var(--text)', go: () => this.push('rec', { recId: x.p.id }) }))
      .concat(expd.map((x) => ({ day: parse(x.next)[2] + '.', dc: 'var(--text3)', mon: SHORT[pm - 1] + '.', name: x.p.name, sub: ivLabel(x.p.interval) + ' · erwartet', amount: amt(-x.cents, false), ac: 'var(--text2)', go: () => this.push('rec', { recId: x.p.id }) })));
    const total = paid.reduce((a, [, t]) => a - t.cents, 0) + expd.reduce((a, x) => a - x.cents, 0);
    return { year: String(TY), totals: amt(paidTotal, false) + ' bezahlt · ' + amt(expTotal, false) + ' erwartet', cells, month: MONTHS[pm - 1], total: amt(total, false), rows };
  }

  // What the bar shows: place bar, back bar or action bar (WimgNavigation.kt).
  barVals(v, P, route, ums) {
    const s = this.state;
    const b = { search: route === 'search' };
    const place = PLACES.find((p) => p[0] === route);
    let detail = null;
    if (route === 'tx') {
      const t = this.tx(s.txId);
      detail = { action: t && t.pending ? null : 'Kategorie wählen', icon: I.tag, onAction: () => this.setState({ panel: s.panel === 'cat' ? null : 'cat', sel: t.cat }), more: () => this.setState({ panel: s.panel === 'more' ? null : 'more' }) };
    } else if (route === 'rec') {
      detail = { action: 'Nicht wiederkehrend', icon: I.block, danger: true, onAction: () => this.hidePattern(), extra: I.edit, onExtra: () => this.setState({ panel: s.panel === 'edit' ? null : 'edit', edit: this.editStart() }) };
    } else if (route === 'manual') {
      detail = { action: s.amountStep ? 'Weiter' : 'Speichern', noSearch: true, onAction: () => { if (s.amountStep) { if (parseCents(s.digits) > 0) this.setState({ amountStep: false }); } else this.saveManual(); } };
    } else if (route === 'import') {
      detail = { action: 'Datei wählen', noSearch: true, onAction: () => this.demo('Datei wählen') };
    } else if (route === 'lock' || route === 'about') {
      detail = { backLabel: 'Einstellungen' };
    }
    b.place = !detail && !b.search;
    b.detail = !!detail;
    if (b.place) {
      const pl = place || PLACES[0];
      b.label = pl[1]; b.icon = I[pl[2]];
      b.chipCls = 'w-bchip' + (s.menu ? ' on' : '') + (s.hint ? ' w-pulse' : '');
      b.unfoldColor = s.menu ? 'var(--inkText)' : 'var(--text2)';
      b.toggleMenu = () => this.setState({ menu: !s.menu, add: false, panel: null, hint: false });
      // Page chip next to the place chip.
      b.hasRing = false; b.hasText = false; b.hasIcon = false;
      if (route === 'home') {
        const cur = s.hy === TY && s.hm === TM, days = dim(s.hy, s.hm), left = days - TD;
        const f = cur ? left / days : 1;
        b.hasRing = true; b.ringText = cur ? String(left) : SHORT[s.hm - 1]; b.ringSize = b.ringText.length > 2 ? '10px' : '12px';
        b.ringDash = (97.4 * f).toFixed(1) + ' 97.4';
        b.ringCls = 'w-bring' + (s.panel === 'month' ? ' on' : '');
        b.ringLabel = cur ? 'Zeitraum: ' + MONTHS[s.hm - 1] + ', noch ' + left + ' Tage' : 'Zeitraum: ' + MONTHS[s.hm - 1] + ' ' + s.hy;
        b.chipGo = () => this.setState({ panel: s.panel === 'month' ? null : 'month', pickYear: s.hy, menu: false, add: false });
      } else if (route === 'ums' || route === 'wk') {
        const active = route === 'ums' ? (s.tf !== 'all' || s.tcats.length > 0 || !!s.period) : (!s.wkExp || !s.wkInc || !!s.wkIv);
        const pn = route === 'ums' ? 'filter' : 'wkfilter';
        b.hasIcon = true; b.chipIcon = route === 'wk' && s.wkMonths ? I.calendar : I.tune;
        b.iconChipCls = 'w-bchip ic' + (s.panel === pn || active ? ' on' : '');
        b.iconLabel = route === 'ums' ? 'Filter' : 'Ansicht und Filter';
        b.chipGo = () => this.setState({ panel: s.panel === pn ? null : pn, picking: false, menu: false, add: false });
      } else if (route === 'review') {
        b.hasText = true; b.text = SHORT[s.rm - 1] + (s.ry !== TY ? ' ' + (s.ry % 100) : '');
        b.textCls = 'w-bchip' + (s.panel === 'month' ? ' on' : '');
        b.chipGo = () => this.setState({ panel: s.panel === 'month' ? null : 'month', pickYear: s.ry, menu: false, add: false });
      }
      b.goSearch = () => this.push('search', { q: '', quick: null });
      b.addOpen = s.add; b.addClosed = !s.add;
      b.addLabel = route === 'banks' ? 'Bank hinzufügen' : 'Hinzufügen';
      b.plus = route === 'banks' ? () => this.demo('Bank hinzufügen') : () => this.setState({ add: !s.add, menu: false, panel: null });
    } else if (detail) {
      b.backOnly = !detail.action; b.withAction = !!detail.action;
      b.backLabel = detail.backLabel || 'Zurück';
      b.goBack = () => this.back();
      b.action = detail.action; b.actionIcon = detail.icon || null;
      // BarAction: one line; when space is short the icon goes first (WimgKit.kt).
      const room = 342 - 48 - (detail.more ? 48 : 0) - (detail.extra || (!detail.noSearch && !detail.extra) ? 48 : 0) - (detail.more || detail.extra || !detail.noSearch ? 13 : 0) - 32;
      b.hasActionIcon = !!detail.icon && (!detail.action || textWidth(detail.action) + 27 <= room);
      b.actionCls = 'w-baction' + (detail.danger ? ' danger' : '');
      b.doAction = detail.onAction;
      b.extra = !!detail.extra; b.extraIcon = detail.extra; b.doExtra = detail.onExtra;
      b.dsearch = !detail.noSearch && !detail.extra; b.goSearch = () => this.push('search', { q: '', quick: null });
      b.more = !!detail.more; b.doMore = detail.more;
      b.divider = b.more || b.dsearch || b.extra;
    }
    b.wide = !!s.dock || (b.detail && b.withAction);
    b.cls = 'w-bar' + (b.wide ? ' wide' : '') + (b.detail && b.withAction ? ' fill' : '');
    v.bar = b;
    v.scrim = s.menu || s.add || !!s.panel || (b.search && s.sFilters);
    v.scrimCls = 'w-scrim' + (v.scrim ? ' on' : '');
    v.closeAll = () => this.setState({ menu: false, add: false, panel: null, sFilters: false, picking: false });
    v.veilCls = 'w-veil' + (b.search ? ' off' : '');
    v.menu = s.menu;
    v.places = PLACES.map(([id, label, icon, gap]) => ({ gap: !!gap, label, icon: I[icon], sel: id === route, cls: 'w-mitem' + (id === route ? ' sel' : ''), go: () => this.goTo(id) }));
    v.add = s.add;
    v.addRows = [['banks', I.bank, 'Bank verbinden', 'Umsätze per FinTS abrufen'], ['import', I.upload, 'CSV importieren', 'Comdirect, Trade Republic, Scalable'], ['manual', I.edit, 'Umsatz von Hand', 'Z. B. Bargeld']]
      .map(([r, icon, title, desc], i) => ({ icon, title, desc, div: i > 0, go: () => this.push(r, r === 'manual' ? { expense: true, digits: '', amountStep: true, mDesc: '', mCat: -1, mAcct: 'Bargeld', mDay: 0 } : null) }));
  }

  panelVals(v, P, route) {
    const s = this.state;
    const pn = s.panel;
    if (!pn) return;
    v.p[pn === 'mcat' ? 'cat' : pn] = true;
    if (pn === 'month' || (pn === 'filter' && s.picking)) {
      if (pn === 'filter') { v.p.filter = false; v.p.month = true; }
      const isHome = route === 'home', isUms = route === 'ums';
      const selY = isHome ? s.hy : isUms ? (s.period && s.period.y) || TY : s.ry;
      const selM = isHome ? s.hm : isUms ? (s.period && s.period.m) || TM : s.rm;
      const py = s.pickYear;
      v.month = {
        year: String(py), canNext: py < TY, nextColor: py < TY ? 'var(--text)' : 'var(--text3)',
        prev: () => this.setState({ pickYear: py - 1 }), next: () => { if (py < TY) this.setState({ pickYear: py + 1 }); },
        cells: SHORT.map((label, i) => {
          const m = i + 1, fut = py > TY || (py === TY && m > TM), sel = py === selY && m === selM;
          return { label, cls: 'w-mcell' + (sel ? ' sel' : fut ? ' fut' : ''), go: fut ? null : () => {
            if (isHome) this.setState({ hy: py, hm: m, panel: null });
            else if (isUms) this.setState({ period: monthPeriod(py, m), picking: false });
            else this.setState({ ry: py, rm: m, panel: null });
          } };
        }),
        compare: isHome, segs: [['prev', 'Vormonat'], ['avg', 'Ø 3 Monate'], ['year', 'Vorjahr']].map(([k, label]) => ({ label, cls: 'w-seg1' + (s.compare === k ? ' on' : ''), go: () => this.setState({ compare: k }) })),
      };
    }
    if (pn === 'filter' && !s.picking) {
      const per = s.period;
      const opts = [[null, 'Immer'], ['this', 'Dieser Monat'], ['last', 'Letzter Monat'], ['3m', '3 Monate'], ['12m', '12 Monate']];
      const make = (k) => k === 'this' ? Object.assign(monthPeriod(TY, TM), { key: 'this' }) : k === 'last' ? Object.assign(monthPeriod(TY, TM - 1), { key: 'last' }) : k === '3m' ? { from: addDays(TODAY, -91), to: TODAY, key: '3m' } : k === '12m' ? { from: addDays(TODAY, -365), to: TODAY, key: '12m' } : null;
      const custom = per && per.key.startsWith('m:') ? per : null;
      const list = this.D.txs.filter((t) => t.date <= TODAY && (s.tf === 'all' || (s.tf === 'out' ? t.cents < 0 : t.cents > 0)) && (!s.tcats.length || s.tcats.includes(t.cat)) && (!per || (t.date >= per.from && t.date <= per.to)));
      v.filter = {
        segs: [['all', 'Alle'], ['out', 'Ausgaben'], ['in', 'Einnahmen']].map(([k, label]) => ({ label, cls: 'w-seg1' + (s.tf === k ? ' on' : ''), go: () => this.setState({ tf: k }) })),
        periods: opts.map(([k, label]) => ({ label, cls: 'w-pill sm' + (((per && per.key) || null) === k ? ' on' : ''), go: () => this.setState({ period: make(k) }) }))
          .concat([{ label: custom ? custom.label : 'Monat wählen…', cls: 'w-pill sm' + (custom ? ' on' : ''), go: () => this.setState({ picking: true, pickYear: custom ? custom.y : TY }) }]),
        cats: FILTER_CATS.map((id) => { const on = s.tcats.includes(id); return { label: id === 0 ? 'Sonstiges' : catName(id), dot: catBar(P, id), cls: 'w-pill sm' + (on ? ' on' : ''), go: () => this.setState({ tcats: on ? s.tcats.filter((x) => x !== id) : s.tcats.concat([id]) }) }; }),
        reset: () => this.setState({ tf: 'all', tcats: [], period: null }), done: () => this.setState({ panel: null }), show: list.length + ' Umsätze anzeigen',
      };
    }
    if (pn === 'wkfilter') {
      const hidden = this.D.patterns.filter((p) => p.hidden);
      const all = this.D.patterns.filter((p) => !p.hidden);
      v.wkf = {
        tabs: hidden.length > 0, hiddenView: s.hiddenTab && hidden.length > 0, normal: !(s.hiddenTab && hidden.length > 0),
        tabSegs: [[false, 'Aktiv (' + all.length + ')'], [true, 'Ausgeblendet (' + hidden.length + ')']].map(([h, label]) => ({ label, cls: 'w-seg1' + (s.hiddenTab === h ? ' on' : ''), go: () => this.setState({ hiddenTab: h }) })),
        hidden: hidden.map((p, i) => { const x = this.patternInfo(p); return { name: p.name, desc: ivLabel(p.interval) + ' · ' + amt(Math.abs(x.cents), false), div: i > 0, go: () => { p.hidden = false; if (hidden.length === 1) this.setState({ hiddenTab: false }); else this.forceUpdate(); } }; }),
        view: [[false, 'Liste'], [true, '12 Monate']].map(([m, label]) => ({ label, cls: 'w-seg1' + (s.wkMonths === m ? ' on' : ''), go: () => this.setState({ wkMonths: m }) })),
        show: [['wkExp', 'Ausgaben'], ['wkInc', 'Einnahmen'], ['wkInactive', 'Inaktive']].map(([k, label]) => ({ label, on: s[k], cls: 'w-pill' + (s[k] ? ' on' : ''), go: () => this.setState({ [k]: !s[k] }) })),
        ivs: [[null, 'Alle']].concat(INTERVALS.filter(([id]) => all.some((p) => p.interval === id)).map(([id, l]) => [id, l])).map(([id, label]) => ({ label, cls: 'w-pill' + (s.wkIv === id ? ' on' : ''), go: () => this.setState({ wkIv: id === null ? null : s.wkIv === id ? null : id }) })),
        detect: () => this.fetch('Suche Muster…', null, () => { this.setState({ panel: null }); this.info('Erneut erkannt', all.length + ' feste Zahlungen'); }),
      };
    }
    if (pn === 'cat' || pn === 'mcat' || (pn === 'edit' && s.edit && s.edit.picking)) {
      if (pn === 'edit') { v.p.edit = false; v.p.cat = true; }
      const cur = pn === 'edit' ? s.edit.cat : s.sel;
      const t = route === 'tx' ? this.tx(s.txId) : null;
      const orig = pn === 'cat' && t ? t.cat : cur;
      v.cat = {
        cells: PICKER.map((id) => {
          const on = id === cur;
          return { label: id === 0 ? 'Unkategorisiert' : catName(id), dot: id !== 0, ring: id === 0, color: catBar(P, id), on, cls: 'w-ccell' + (on ? ' on' : '') + (on || id === orig ? ' b' : ''), go: () => {
            if (pn === 'edit') this.setState({ edit: Object.assign({}, s.edit, { cat: id }) }); else this.setState({ sel: id });
          } };
        }),
        apply: () => {
          if (pn === 'cat') this.applyCategory(t, cur);
          else if (pn === 'mcat') this.setState({ mCat: cur, panel: null });
          else this.setState({ edit: Object.assign({}, s.edit, { picking: false }) });
        },
      };
    }
    if (pn === 'more') {
      const t = this.tx(s.txId);
      v.more = { copy: () => { try { navigator.clipboard && navigator.clipboard.writeText(t.desc); } catch (e) { /* ignore */ } this.setState({ panel: null }); this.info('Text kopiert'); }, search: () => this.push('search', { q: t.title.slice(0, 40), quick: null }) };
    }
    if (pn === 'edit' && s.edit && !s.edit.picking) {
      const e = s.edit, p = this.D.patterns.find((x) => x.id === s.recId), x = this.patternInfo(p);
      const set = (o) => this.setState({ edit: Object.assign({}, s.edit, o) });
      v.edit = {
        merchant: 'erkannt als „' + p.merchant + '“', name: e.name, onName: (ev) => { this.state.edit.name = ev.target.value.slice(0, 60); },
        cat: catName(e.cat), dot: catBar(P, e.cat), pickCat: () => set({ picking: true }),
        ivs: [['weekly', 'Wöch.'], ['monthly', 'Monatl.'], ['quarterly', 'Viertelj.'], ['annual', 'Jährl.']].map(([k, label]) => ({ label, cls: 'w-seg1' + (e.iv === k ? ' on' : ''), go: () => set({ iv: k }) })),
        auto: !e.fixed, fixed: e.fixed, autoDesc: 'Wie die letzte Zahlung: ' + amt(Math.abs(x.last ? x.last.cents : 0), false),
        goAuto: () => set({ fixed: false }), goFixed: () => set({ fixed: true }), amount: e.amount, onAmount: (ev) => { this.state.edit.amount = ev.target.value.replace(/[^0-9,.]/g, '').slice(0, 10); },
        cancel: () => this.setState({ panel: null, edit: null }), save: () => this.saveEdit(p),
      };
    }
    if (pn === 'macct' || pn === 'mday') {
      const opts = pn === 'macct' ? ['Bargeld', 'Musterbank'] : [0, 1, 2, 3, 4, 5, 6].map(mDayLabel);
      const sel = pn === 'macct' ? opts.indexOf(s.mAcct) : s.mDay;
      v.choice = { title: pn === 'macct' ? 'Konto' : 'Datum', rows: opts.map((o, i) => ({ o, on: i === sel, div: i > 0, go: () => this.setState(pn === 'macct' ? { mAcct: o, panel: null } : { mDay: i, panel: null }) })) };
      v.p.choice = true;
    }
    if (pn === 'lang') {
      v.lang = [['Deutsch', true], ['English', false]].map(([label, on]) => ({ label, on, go: on ? () => this.setState({ panel: null }) : () => { this.setState({ panel: null }); this.demo('English'); } }));
    }
  }

  dockVals(v) {
    const d = this.state.dock;
    v.dock = !!d;
    if (!d) return;
    const look = { sync: ['var(--syncBg)', 'var(--sync)', I.sync], error: ['var(--dangerBg)', 'var(--danger)', I.error], undo: ['var(--tint)', 'var(--text)', I.undo], prompt: ['var(--accentSoft)', 'var(--accent)', I.info], info: ['var(--tint)', 'var(--pos)', I.check] }[d.kind];
    v.d = {
      even: d.id % 2 === 0, odd: d.id % 2 === 1, bg: look[0], fg: look[1], icon: look[2], title: d.title, sub: d.sub || '', hasSub: !!d.sub,
      hasAction: !!d.action, action: d.action, actionColor: d.kind === 'error' ? 'var(--danger)' : 'var(--accent)',
      go: () => { const fn = d.onAction; this.setState({ dock: null }); if (fn) fn(); },
      seamCls: 'w-seamfill ' + (d.kind === 'undo' ? 'undo' : d.progress ? 'prog' : d.kind === 'error' ? 'full' : 'none'),
      seamColor: d.kind === 'sync' ? 'var(--sync)' : d.kind === 'error' ? 'var(--danger)' : 'var(--ink)',
    };
  }

  // ---- actions ----
  setQuery(q) { this.setState({ q }); const inp = this.root() && this.root().querySelector('.w-sinput'); if (inp) inp.value = q; }
  remember(q) { this.setState({ recent: [q].concat(this.state.recent.filter((r) => r.toLowerCase() !== q.toLowerCase())).slice(0, 5) }); }
  applyCategory(t, cat) {
    this.setState({ panel: null });
    if (!t || cat === t.cat) return;
    const old = t.cat; t.cat = cat;
    this.undo('Kategorie geändert', catName(cat), () => { t.cat = old; this.forceUpdate(); });
  }
  setExcluded(t, on) {
    t.excluded = on; this.forceUpdate();
    this.undo(on ? 'Aus Summen ausgeschlossen' : 'Zählt wieder mit', null, () => { t.excluded = !on; this.forceUpdate(); });
  }
  hidePattern() {
    const p = this.D.patterns.find((x) => x.id === this.state.recId);
    if (!p) return;
    p.hidden = true; this.back();
    this.undo('Nicht mehr wiederkehrend', p.name, () => { p.hidden = false; this.forceUpdate(); });
  }
  markOneoff(p, newest, before) {
    p.oneoff[newest.id] = true; this.forceUpdate();
    this.undo(amt(Math.abs(newest.cents), false) + ' einmalig', 'Preis bleibt ' + amt(Math.abs(before.cents), false), () => { delete p.oneoff[newest.id]; this.forceUpdate(); });
  }
  acceptPrice(p, newest) { p.accepted = true; this.forceUpdate(); this.info('Neuer Preis übernommen', amt(Math.abs(newest.cents), false)); }
  editStart() {
    const p = this.D.patterns.find((x) => x.id === this.state.recId), x = this.patternInfo(p);
    return { name: p.name, cat: p.cat, iv: p.interval, fixed: p.fixed != null, amount: p.fixed != null ? (Math.abs(p.fixed) / 100).toFixed(2).replace('.', ',') : '', picking: false, last: x.cents };
  }
  saveEdit(p) {
    const e = this.state.edit;
    const name = (e.name || '').trim() || p.name;
    p.name = name; p.cat = e.cat; p.interval = e.iv;
    const cents = Math.round(parseFloat((e.amount || '').replace(/\./g, '').replace(',', '.')) * 100);
    p.fixed = e.fixed && cents > 0 ? (e.last < 0 ? -cents : cents) : null;
    this.D.txs.forEach((t) => { if (t.pid === p.id) t.title = name; });
    this.setState({ panel: null, edit: null });
    this.info('Gesichert', name);
  }
  key(k) {
    const d = this.state.digits;
    let n;
    if (k === '⌫') n = d.slice(0, -1);
    else if (k === ',') n = d.includes(',') ? d : (d === '' ? '0,' : d + ',');
    else if (d.includes(',') && d.split(',')[1].length >= 2) n = d;
    else if (!d.includes(',') && d.length >= 7) n = d;
    else n = d === '0' ? k : d + k;
    this.setState({ digits: n });
  }
  saveManual() {
    const s = this.state, cents = parseCents(s.digits), desc = s.mDesc.trim();
    if (!(cents > 0 && desc)) { this.dock({ kind: 'prompt', title: desc ? 'Betrag fehlt' : 'Beschreibung fehlt', sub: desc ? 'Tippe auf den Betrag oben.' : 'Z. B. „Wochenmarkt“', timeout: 3000 }); return; }
    const date = addDays(TODAY, -s.mDay);
    this.D.txs.push({ id: 'm' + (++this.D.n), date, title: desc, desc, kind: '', cents: s.expense ? -cents : cents, cat: s.mCat < 0 ? 0 : s.mCat, account: s.mAcct === 'Musterbank' ? 'giro' : s.mAcct, excluded: false });
    this.D.txs.sort((a, b) => (a.date < b.date ? 1 : a.date > b.date ? -1 : 0));
    this.back();
    this.info('Umsatz gespeichert', desc);
  }
}

const widths = {};
function textWidth(t) {
  if (widths[t]) return widths[t];
  const font = '700 15px Manrope';
  const c = document.createElement('canvas').getContext('2d');
  c.font = font;
  const w = c.measureText(t).width;
  if (!document.fonts || document.fonts.check(font)) widths[t] = w;
  return w;
}
function monthPeriod(y, m) {
  if (m < 1) { y -= 1; m += 12; }
  return { from: iso(y, m, 1), to: iso(y, m, dim(y, m)), label: SHORT[m - 1] + ' ' + y, key: 'm:' + y + '-' + m, y, m };
}
function parseCents(t) {
  if (!t) return 0;
  const whole = parseInt(t.split(',')[0] || '0', 10) || 0;
  const dec = parseInt(((t.split(',')[1] || '') + '00').slice(0, 2), 10) || 0;
  return whole * 100 + dec;
}
function formatTyped(t) {
  if (!t) return '0,00';
  const whole = (t.split(',')[0] || '0').replace(/\B(?=(\d{3})+(?!\d))/g, '.');
  return t.includes(',') ? whole + ',' + t.split(',')[1] : whole;
}
function mDayLabel(o) { const d = addDays(TODAY, -o); return o === 0 ? 'Heute, ' + short(d) : o === 1 ? 'Gestern, ' + short(d) : short(d); }
function snippet(t, q) {
  if (!q || t.title.toLowerCase().includes(q.toLowerCase())) return t.title;
  const i = t.desc.toLowerCase().indexOf(q.toLowerCase());
  if (i < 0) return t.title;
  const st = Math.max(0, i - 14);
  return (st > 0 ? '… ' : '') + t.desc.slice(st).trimStart();
}
function highlight(text, q) {
  if (!q) return [{ t: text, hl: false, cls: '' }];
  const out = []; const lo = text.toLowerCase(), ql = q.toLowerCase(); let from = 0;
  for (;;) {
    const i = lo.indexOf(ql, from);
    if (i < 0) { out.push({ t: text.slice(from), cls: '' }); break; }
    if (i > from) out.push({ t: text.slice(from, i), cls: '' });
    out.push({ t: text.slice(i, i + q.length), cls: 'w-hl' });
    from = i + q.length;
  }
  return out;
}
