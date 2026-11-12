
class Component extends DCLogic {
  renderVals() {
    const dark = this.props.dark ?? false;
    const sheet = this.props.sheet ?? 'none';
    const accent = this.props.accent ?? '#4A6D96';
    const accentFg = (() => { const h = accent.replace('#',''); const [r,g,b] = [0,2,4].map(i => parseInt(h.substr(i,2),16)/255); return (0.2126*r + 0.7152*g + 0.0722*b) > 0.45 ? '#1A1A1A' : '#FFFFFF'; })();
    const light = {
      band: '#1D1C1A', sheet: '#FAF9F6', fade0: 'rgba(250,249,246,0)', card: '#FFFFFF', sheetEdge: '0',
      text: '#1A1A1A', text2: '#6B6A66', text3: '#B5B2AC', line: '#ECE8E1',
      bandNeg: '#FF9A85', bandPos: '#86DDA6', neg: '#B3261E', pos: '#1B7A43',
      neutral: '#C9C4BB', neutralTint: '#F1EDE5', ink: '#1A1A1A', inkText: '#FFFFFF', neuBg: '#ECE6FF', neuFg: '#5236C9'
    };
    const darkT = {
      band: '#1E1E21', sheet: '#111114', fade0: 'rgba(17,17,20,0)', card: '#1C1C1E', sheetEdge: '1px solid rgba(255,255,255,0.08)',
      text: '#F2F2F3', text2: '#9A9BA0', text3: '#4A4A50', line: 'rgba(255,255,255,0.08)',
      bandNeg: '#FF9A85', bandPos: '#86DDA6', neg: '#FF8A80', pos: '#6FD39A',
      neutral: '#5A5A60', neutralTint: '#26262A', ink: '#F2F2F3', inkText: '#111114', neuBg: 'rgba(185,168,255,0.18)', neuFg: '#CFC2FF'
    };
    const t = dark ? darkT : light;
    const c = dark
      ? { vers: '#7FA6F5', lebe: '#5CC992', nebe: '#B39AF0', shop: '#F2A65E', wohn: '#C9A27E', trans: '#4FC3D9' }
      : { vers: '#3B6FD8', lebe: '#2E9E6A', nebe: '#8A63D2', shop: '#D9822B', wohn: '#8B5E3C', trans: '#0E7490' };
    const a = dark ? '22' : '1A';
    const rows = [
      { name: 'Wohnen', pct: '52 %', amt: '850,00 €', color: c.wohn, w: '104px',
        icon: 'M3 10.5L12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z' },
      { name: 'Lebensmittel', pct: '18 %', amt: '286,40 €', color: c.lebe, w: '36px',
        icon: 'M3 4h2l2.4 11h10.2L20 7H6.2M9 20h.01M17 20h.01' },
      { name: 'Versicherung', pct: '9 %', amt: '142,30 €', color: c.vers, w: '18px',
        icon: 'M12 3l8 3v6c0 4.5-3.4 8.3-8 9-4.6-.7-8-4.5-8-9V6z' },
      { name: 'Transport', pct: '7 %', amt: '118,50 €', color: c.trans, w: '14px',
        icon: 'M6 4h12v11H6zM6 11h12M8 19l-2 2M16 19l2 2M9 15h.01M15 15h.01' },
      { name: 'Shopping', pct: '5 %', amt: '76,20 €', color: c.shop, w: '10px',
        icon: 'M5 8h14l-1 13H6zM9 8V6a3 3 0 0 1 6 0v2' }
    ];
    const deltas = { Wohnen: ['0 %', false], Lebensmittel: ['12 %', false], Versicherung: ['5 %', true], Transport: ['20 %', false], Shopping: ['31 %', false] };
    const cats = rows.map((r) => ({ ...r, bar: r.bar || r.color, tint: r.tint || r.color + a,
      delta: deltas[r.name][0], arrow: deltas[r.name][1] ? 'M12 4l9 12H3z' : 'M12 20L3 8h18z', dColor: deltas[r.name][1] ? t.neg : t.pos }));
    const tx = [
      { title: 'REWE Markt', sub: '12. Nov. · Lebensmittel · Lastschrift', amt: '−23,48 €', color: c.lebe, amtColor: t.text },
      { title: 'Hausrat24 Versicherung', sub: '12. Nov. · Versicherung · Lastschrift', amt: '−34,99 €', color: c.vers, amtColor: t.text }
    ];
    const names = ['Jan','Feb','Mär','Apr','Mai','Jun','Jul','Aug','Sep','Okt','Nov','Dez'];
    const months = names.map((n, i) => {
      const sel = i === 10, future = i === 11;
      return {
        label: n,
        bg: sel ? t.ink : t.neutralTint,
        fg: sel ? t.inkText : (future ? t.text3 : t.text),
        font: (sel ? '700' : '600') + ' 14px Manrope, sans-serif'
      };
    });
    const P = [
      ['Übersicht', 'M3 10.5L12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z', true, false],
      ['Umsätze', 'M8 6h13M8 12h13M8 18h13M3.5 6h.01M3.5 12h.01M3.5 18h.01', false, false],
      ['Wiederkehrend', 'M21 12a9 9 0 1 1-3-6.7L21 8M21 3v5h-5', false, false],
      ['Bankverbindung', 'M3 10l9-6 9 6M5 10v8M10 10v8M14 10v8M19 10v8M3 21h18', false, true],
      ['Import', 'M12 3v12M7 10l5 5 5-5M4 21h16', false, false],
      ['Einstellungen', 'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-2.9 1.2V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-2.9-1.2l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0-1.2-2.9H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.2-2.9l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 2.9-1.2V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 2.9 1.2l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0 1.2 2.9H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z', false, false]
    ];
    const places = P.map(([name, icon, current, gapBefore]) => ({
      name, icon, current, gapBefore,
      bg: current ? t.neutralTint : 'transparent',
      font: (current ? '700' : '600') + ' 15px Manrope, sans-serif'
    }));
    const period = this.props.period ?? 'calendar';
    const isCalendar = period === 'calendar', isNormal = period === 'normal',
      isOverdue = period === 'overdue', isPaused = period === 'paused';
    const salaryMode = isNormal || isOverdue;
    const isPlaces = sheet === 'places';
    const isSalary = sheet === 'filter' && salaryMode;
    const isFilter = sheet === 'filter' && !salaryMode;
    const cycles = [
      ['27.10. – heute', 'aktuell', true],
      ['26.09. – 26.10.', '', false],
      ['27.08. – 25.09.', '', false],
      ['28.07. – 26.08.', '', false]
    ].map(([label, note, sel]) => ({
      label, note,
      bg: sel ? t.neutralTint : 'transparent',
      font: (sel ? '700' : '600') + ' 14px Manrope, sans-serif'
    }));
    return {
      t, c, cats, tx, months, places, cycles, accent, accentFg,
      isCalendar, isNormal, isOverdue, isPaused,
      confirm: (this.props.confirm ?? false) && sheet === 'none',
      wrapReady: (this.props.wrapReady ?? false) && sheet === 'none',
      barOuterW: (((this.props.confirm ?? false) || (this.props.wrapReady ?? false)) && sheet === 'none') ? '358px' : 'auto',
      sheetTop: isOverdue ? '260px' : (isPaused ? '290px' : '222px'),
      filterLabel: salaryMode ? 'Gehalt' : 'Nov',
      isFilter, isSalary, isPlaces, anySheet: isFilter || isSalary || isPlaces,
      isFilterStr: isFilter ? 'true' : 'false', isPlacesStr: isPlaces ? 'true' : 'false',
      placeBg: isPlaces ? t.ink : t.neutralTint, placeFg: isPlaces ? t.inkText : t.text,
      filterBg: isFilter ? t.ink : t.neutralTint, filterFg: isFilter ? t.inkText : t.text
    };
  }
}
