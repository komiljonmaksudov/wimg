
class Component extends DCLogic {
  constructor(p) { super(p); this.state = { base: 'home', over: 'none', menu: false, hint: true, toast: '' }; this.t = null; }
  componentWillUnmount() { clearTimeout(this.t); }
  say(text) { clearTimeout(this.t); this.setState({ toast: text, menu: false }); this.t = setTimeout(() => this.setState({ toast: '' }), 1900); }
  renderVals() {
    const s = this.state;
    const base = (b) => () => this.setState({ base: b, over: 'none', menu: false });
    const over = (o) => () => this.setState({ over: o, menu: false });
    const back = () => this.setState({ over: 'none' });
    const openMenu = () => this.setState({ menu: true, hint: false });
    const plus = () => this.say('Umsatz von Hand: geht in der App.');
    const H = (x, y, w, h, go, label) => ({ x, y, w, h, go, label });
    const bar = {
      home: [H(47, 775, 128, 44, openMenu, 'Bereich wechseln'), H(180, 775, 54, 44, () => this.say('Zeitraum wählen: geht in der App.'), 'Zeitraum'), H(248, 775, 46, 44, over('suche'), 'Suchen'), H(296, 775, 48, 44, plus, 'Hinzufügen')],
      ums: [H(50, 775, 122, 44, openMenu, 'Bereich wechseln'), H(248, 775, 46, 44, over('suche'), 'Suchen'), H(296, 775, 48, 44, plus, 'Hinzufügen')],
      wk: [H(32, 778, 163, 42, openMenu, 'Bereich wechseln'), H(266, 778, 44, 42, over('suche'), 'Suchen'), H(312, 778, 48, 42, plus, 'Hinzufügen'),
        H(0, 226, 390, 58, over('detTx'), 'Grünstrom AG öffnen'), H(0, 287, 390, 58, over('detHz'), 'Spotify öffnen'), H(0, 529, 390, 60, over('detFn'), 'FunkNet Mobil öffnen')],
      set: [H(90, 777, 153, 42, openMenu, 'Bereich wechseln'), H(255, 777, 48, 42, over('suche'), 'Suchen'), H(16, 606, 358, 48, base('bank'), 'Bankverbindungen')],
      bank: [H(84, 777, 114, 42, openMenu, 'Bereich wechseln'), H(212, 777, 50, 42, over('suche'), 'Suchen'), H(262, 777, 46, 42, () => this.say('Bank hinzufügen: geht in der App.'), 'Bank hinzufügen')],
    };
    const overSpots = {
      suche: [H(26, 517, 41, 41, back, 'Zurück'), H(0, 124, 390, 40, over('sucheRes'), 'spotify suchen')],
      sucheRes: [H(26, 777, 40, 42, back, 'Zurück')],
      detTx: [H(60, 778, 41, 41, back, 'Zurück')], detHz: [H(60, 778, 41, 41, back, 'Zurück')], detFn: [H(60, 778, 41, 41, back, 'Zurück')],
    };
    const spots = s.menu ? [] : (s.over === 'none' ? bar[s.base] : overSpots[s.over]);
    const sw = bar[s.base][0];
    const v = {
      spots, menu: s.menu, toast: !!s.toast, toastText: s.toast, closeMenu: () => this.setState({ menu: false }),
      hint: s.hint && s.over === 'none' && !s.menu, hx: sw.x, hy: sw.y, hw: sw.w,
      isHome: s.over === 'none' && s.base === 'home', isUms: s.over === 'none' && s.base === 'ums', isWk: s.over === 'none' && s.base === 'wk',
      isSet: s.over === 'none' && s.base === 'set', isBank: s.over === 'none' && s.base === 'bank',
      isSuche: s.over === 'suche', isSucheRes: s.over === 'sucheRes', isDetTx: s.over === 'detTx', isDetHz: s.over === 'detHz', isDetFn: s.over === 'detFn',
      goHome: base('home'), goUms: base('ums'), goWk: base('wk'), goBank: base('bank'), goSet: base('set'), goImp: () => this.say('CSV-Import: geht in der App.'),
    };
    for (const k of ['Home', 'Ums', 'Wk', 'Bank', 'Set', 'Imp']) {
      const on = { Home: 'home', Ums: 'ums', Wk: 'wk', Bank: 'bank', Set: 'set' }[k] === s.base;
      v['bg' + k] = on ? '#F3F0EA' : 'transparent'; v['ck' + k] = on ? 1 : 0;
    }
    return v;
  }
}
