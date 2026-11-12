
class Component extends DCLogic {
  renderVals() {
    const dark = this.props.dark ?? false;
    const state = this.props.state ?? 'empty';
    const light = {
      band: '#1D1C1A', sheet: '#FAF9F6', fade0: 'rgba(250,249,246,0)', card: '#FFFFFF', sheetEdge: '0',
      text: '#1A1A1A', text2: '#6B6A66', line: '#ECE8E1', neutralTint: '#F1EDE5', ink: '#1A1A1A',
      mark: '#D6E2F0', kbBg: '#E4E0D8', key: '#FFFFFF', key2: '#CFCAC1'
    };
    const darkT = {
      band: '#1E1E21', sheet: '#111114', fade0: 'rgba(17,17,20,0)', card: '#1C1C1E', sheetEdge: '1px solid rgba(255,255,255,0.08)',
      text: '#F2F2F3', text2: '#9A9BA0', line: 'rgba(255,255,255,0.08)', neutralTint: '#26262A', ink: '#F2F2F3',
      mark: 'rgba(143,176,211,0.35)', kbBg: '#18181B', key: '#2E2E33', key2: '#232327'
    };
    const t = dark ? darkT : light;
    const recent = [
      { q: 'spotify', hits: '10 Treffer', font: "500 15px Inter, sans-serif" },
      { q: 'KD-NR 7731 0042', hits: '3 Treffer', font: "500 14px 'JetBrains Mono', monospace" },
      { q: 'dm', hits: '6 Treffer', font: "500 15px Inter, sans-serif" }
    ];
    const quick = [
      ['Lebensmittel', dark ? '#5CC992' : '#2E9E6A'], ['Nebenkosten', dark ? '#B39AF0' : '#8A63D2'],
      ['Versicherung', dark ? '#7FA6F5' : '#3B6FD8'], ['Shopping', dark ? '#F2A65E' : '#D9822B'],
      ['Unkategorisiert', ''], ['Nur Einnahmen', ''], ['Über 100 €', ''], ['Ausgeschlossene', '']
    ].map(([name, color]) => ({ name, color: color || 'transparent', ring: color ? '0' : '1.5px solid ' + t.text2 }));
    const results = ['1. Nov. 2026', '1. Okt. 2026', '1. Sep. 2026', '1. Aug. 2026', '1. Juli 2026', '1. Juni 2026', '1. Mai 2026'].map((date) => ({ date }));
    const key = (label, flex, special) => ({ label, flex: String(flex || 1), bg: special ? t.key2 : t.key });
    const kbRows = [
      { pad: '0', keys: 'qwertzuiopü'.split('').map((c) => key(c)) },
      { pad: '0', keys: 'asdfghjklöä'.split('').map((c) => key(c)) },
      { pad: '0', keys: [key('⇧', 1.5, true)].concat('yxcvbnm'.split('').map((c) => key(c)), [key('⌫', 1.5, true)]) },
      { pad: '0', keys: [key('?123', 1.5, true), key(',', 1, true), key('', 5), key('.', 1, true), key('⌕', 1.5, true)] }
    ];
    const isEmpty = state === 'empty', isResults = state === 'results', isNone = state === 'none';
    const kb = !isResults;
    return {
      t, recent, quick, results, kbRows,
      isEmpty, isResults, isNone, notResults: !isResults, kb, noKb: !kb,
      query: isResults ? 'spotify' : (isNone ? 'netflix' : ''),
      sheetTop: isResults ? '160px' : '76px',
      barBottom: kb ? '280px' : '20px',
      fieldBorder: kb ? '1.5px solid ' + t.ink : '1.5px solid transparent'
    };
  }
}
