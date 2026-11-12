
class Component extends DCLogic {
  renderVals() {
    const dark = this.props.dark ?? false;
    const sheet = this.props.sheet ?? 'none';
    const scrolled = this.props.scrolled ?? false;
    const accent = this.props.accent ?? '#4A6D96';
    const undo = this.props.undo ?? false;
    const light = {
      band: '#1D1C1A', sheet: '#FAF9F6', fade0: 'rgba(250,249,246,0)', card: '#FFFFFF', sheetEdge: '0',
      text: '#1A1A1A', text2: '#6B6A66', text3: '#B5B2AC', line: '#ECE8E1',
      pos: '#1B7A43', neutral: '#C9C4BB', neutralTint: '#F1EDE5', ink: '#1A1A1A', inkText: '#FFFFFF'
    };
    const darkT = {
      band: '#1E1E21', sheet: '#111114', fade0: 'rgba(17,17,20,0)', card: '#1C1C1E', sheetEdge: '1px solid rgba(255,255,255,0.08)',
      text: '#F2F2F3', text2: '#9A9BA0', text3: '#4A4A50', line: 'rgba(255,255,255,0.08)',
      pos: '#6FD39A', neutral: '#5A5A60', neutralTint: '#26262A', ink: '#F2F2F3', inkText: '#111114'
    };
    const t = dark ? darkT : light;
    const c = dark
      ? { vers: '#7FA6F5', lebe: '#5CC992', nebe: '#B39AF0', shop: '#F2A65E', essen: '#F07F5A', trans: '#4FC3D9', unter: '#F078B0' }
      : { vers: '#3B6FD8', lebe: '#2E9E6A', nebe: '#8A63D2', shop: '#D9822B', essen: '#C2410C', trans: '#0E7490', unter: '#BE185D' };
    const r = (title, sub, color, amount, positive) => {
      const parts = amount.split(',');
      const dec = parts.length > 1 ? ',' + parts[1] : '';
      return { title, sub, color, int: parts[0], dec, amtColor: positive ? t.pos : t.text };
    };
    const raw = [
      { label: 'Heute, Do. 12. Nov.', total: undo ? '−23,48 €' : '−58,47 €', pos: false, rows: [
        r('REWE Markt', 'Lebensmittel · Lastschrift', c.lebe, '−23,48 €', false),
        Object.assign(r('Hausrat24 Versicherung', undo ? 'Versicherung · ausgeschlossen' : 'Versicherung · Lastschrift', c.vers, '−34,99 €', false), undo ? { amtColor: t.text3 } : {})
      ]},
      { label: 'Gestern, Mi. 11. Nov.', total: '+2.765,05 €', pos: true, rows: [
        r('Muster GmbH', 'Einkommen · Überweisung', t.pos, '+2.840,00 €', true),
        r('Grünstrom AG', 'Nebenkosten · Lastschrift', c.nebe, '−62,50 €', false),
        r('dm-drogerie markt', 'Shopping · Karte', c.shop, '−12,45 €', false)
      ]},
      { label: 'Di. 10. Nov.', total: '−21,49 €', pos: false, rows: [
        r('Spotify', 'Unterhaltung · Lastschrift', c.unter, '−10,99 €', false),
        r('Kiosk am Markt', 'Sonstiges · Karte', t.neutral, '−10,50 €', false)
      ]}
    ];
    const start = scrolled ? 1 : 0;
    const days = raw.slice(start).map((d, di) => ({
      label: d.label, total: d.total,
      totalColor: d.pos ? t.pos : t.text2,
      gap: di === 0 ? '8px' : '12px',
      rows: d.rows.map((row, i) => ({ ...row, border: i < d.rows.length - 1 ? '1px solid ' + t.line : '0' }))
    }));
    const cats = [
      ['Lebensmittel', c.lebe], ['Essen gehen', c.essen], ['Transport', c.trans], ['Shopping', c.shop],
      ['Unterhaltung', c.unter], ['Versicherung', c.vers], ['Nebenkosten', c.nebe], ['Sonstiges', t.neutral]
    ];
    const chips = cats.map(([name, color]) => ({
      name, color, pressed: 'false', bg: 'transparent', fg: t.text, border: t.line
    }));
    const isFilter = sheet === 'filter';
    return {
      t, days, chips, accent, isFilter, scrolled, full: !scrolled, undo, barOuterW: undo ? '358px' : 'auto',
      isFilterStr: isFilter ? 'true' : 'false',
      sheetTop: scrolled ? '64px' : '132px',
      barH: scrolled ? '52px' : '60px', barPad: scrolled ? '4px' : '8px',
      filterBg: isFilter ? t.ink : t.neutralTint, filterFg: isFilter ? t.inkText : t.text
    };
  }
}
