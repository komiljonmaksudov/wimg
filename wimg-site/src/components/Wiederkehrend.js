
class Component extends DCLogic {
  renderVals() {
    const dark = this.props.dark ?? false;
    const variant = this.props.variant ?? 'real';
    const sheet = this.props.sheet ?? 'none';
    const accent = this.props.accent ?? '#4A6D96';
    const light = {
      band: '#1D1C1A', sheet: '#FAF9F6', fade0: 'rgba(250,249,246,0)', card: '#FFFFFF', sheetEdge: '0',
      text: '#1A1A1A', text2: '#6B6A66', text3: '#B5B2AC', line: '#ECE8E1',
      pos: '#1B7A43', neutralTint: '#F1EDE5', ink: '#1A1A1A', inkText: '#FFFFFF'
    };
    const darkT = {
      band: '#1E1E21', sheet: '#111114', fade0: 'rgba(17,17,20,0)', card: '#1C1C1E', sheetEdge: '1px solid rgba(255,255,255,0.08)',
      text: '#F2F2F3', text2: '#9A9BA0', text3: '#4A4A50', line: 'rgba(255,255,255,0.08)',
      pos: '#6FD39A', neutralTint: '#26262A', ink: '#F2F2F3', inkText: '#111114'
    };
    const t = dark ? darkT : light;

    const row = (day, dayLabel, name, sub, amt, state, income) => ({
      day, dayLabel, name, sub, amt,
      paid: state === 'paid',
      statusLabel: state === 'paid' ? 'bezahlt' : (state === 'open' ? 'offen' : 'inaktiv'),
      statusBg: state === 'paid' ? (income ? t.pos : t.ink) : 'transparent',
      statusBorder: state === 'paid' ? '0' : '1.5px dashed ' + t.text3,
      statusFg: state === 'paid' ? t.inkText : t.text3,
      amtColor: income ? t.pos : t.text,
      subColor: t.text2
    });
    const abo = row('1.', 'Nov.', 'Spotify', 'Monatlich · nächste in 19 Tagen', '10,99 €', 'paid', false);

    let sections, hero;
    if (variant === 'full') {
      hero = { int: '1.003', dec: ',97 €', sub: '6 feste Zahlungen erkannt', paid: '73,49 €', open: '930,48 €', paidPct: '7%', barLabel: 'Im November 73,49 von 1.003,97 Euro bezahlt' };
      sections = [
        { title: 'Monatlich', total: '1.003,97 €', rows: [
          row('1.', 'Nov.', 'Grünstrom AG', 'Abschlag Strom · Lastschrift', '62,50 €', 'paid', false),
          abo,
          row('15.', 'Nov.', 'Miete', 'Monatlich · in 3 Tagen', '850,00 €', 'open', false),
          row('20.', 'Nov.', 'Stadtgas Abschlag', 'Monatlich · in 8 Tagen', '48,00 €', 'open', false),
          row('25.', 'Nov.', 'Hausrat24', 'Versicherung · in 13 Tagen', '12,49 €', 'open', false),
          row('18.', 'Nov.', 'FunkNet Mobil', 'Preis gestiegen · vorher 14,99 €', '19,99 €', 'open', false)
        ]},
        { title: 'Einnahmen', total: '+2.840,00 €', totalColor: t.pos, rows: [
          row('~27.', 'Nov.', 'Gehalt · Muster GmbH', 'erwartet in 15 Tagen', '+2.840,00 €', 'open', true)
        ]}
      ];
    } else {
      hero = { int: '10', dec: ',99 €', sub: '1 feste Zahlung erkannt', paid: '10,99 €', open: '0,00 €', paidPct: '100%', barLabel: 'Im November alles bezahlt' };
      sections = [{ title: 'Monatlich', total: '10,99 €', rows: [abo] }];
    }
    sections = sections.map((s) => ({
      ...s, opacity: s.opacity || '1', totalColor: s.totalColor || t.text2,
      rows: s.rows.map((r, i) => ({ ...r, border: i < s.rows.length - 1 ? '1px solid ' + t.line : '0' }))
    }));

    const names = ['Jan','Feb','Mär','Apr','Mai','Jun','Jul','Aug','Sep','Okt','Nov','Dez'];
    const months = names.map((n, i) => {
      const sel = i === 10, future = i === 11, none = i === 0;
      return {
        label: n,
        amt: none ? '–' : '10,99 €',
        amtOpacity: future ? '0.55' : '1',
        bg: sel ? t.ink : (future ? 'transparent' : t.card),
        fg: sel ? t.inkText : t.text,
        border: sel ? '0' : (future ? '1.5px dashed ' + t.line : '1px solid ' + t.line)
      };
    });

    const chip = (name, on) => ({
      name, on, pressed: on ? 'true' : 'false',
      bg: on ? t.ink : 'transparent', fg: on ? t.inkText : t.text, border: on ? t.ink : t.line
    });
    const isFilter = sheet === 'filter';
    const isCalendar = variant === 'calendar';
    return {
      t, accent, hero, sections, months,
      isList: !isCalendar, isCalendar, showHint: variant === 'real',
      isFilter, isFilterStr: isFilter ? 'true' : 'false',
      filterBg: isFilter ? t.ink : t.neutralTint, filterFg: isFilter ? t.inkText : t.text,
      showChips: [chip('Ausgaben', true), chip('Einnahmen', true), chip('Inaktive', false)],
      intervalChips: [chip('Alle', true), chip('Monatlich', false), chip('Vierteljährlich', false), chip('Jährlich', false)]
    };
  }
}
