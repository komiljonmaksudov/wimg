
class Component extends DCLogic {
  renderVals() {
    const dark = this.props.dark ?? false;
    const kind = this.props.kind ?? 'tx';
    const sheet = this.props.sheet ?? 'none';
    const accent = this.props.accent ?? '#4A6D96';
    const light = { trackSoft: '#E3E5E9',
      band: '#1D1C1A', sheet: '#FAF9F6', fade0: 'rgba(250,249,246,0)', card: '#FFFFFF', sheetEdge: '0',
      text: '#1A1A1A', text2: '#6B6A66', line: '#ECE8E1', pos: '#1B7A43', track: '#D9D4CB',
      neutral: '#C9C4BB', neutralTint: '#F1EDE5', ink: '#1A1A1A', inkText: '#FFFFFF', danger: '#B3261E',
      warn: '#9A5B00', warnBg: '#FFF1D6', neuBg: '#ECE6FF', neuFg: '#5236C9'
    };
    const darkT = { trackSoft: '#3A3B41',
      band: '#1E1E21', sheet: '#111114', fade0: 'rgba(17,17,20,0)', card: '#1C1C1E', sheetEdge: '1px solid rgba(255,255,255,0.08)',
      text: '#F2F2F3', text2: '#9A9BA0', line: 'rgba(255,255,255,0.08)', pos: '#6FD39A', track: '#3A3A40',
      neutral: '#5A5A60', neutralTint: '#26262A', ink: '#F2F2F3', inkText: '#111114', danger: '#FF8A80',
      warn: '#F5B54A', warnBg: 'rgba(245,181,74,0.12)', neuBg: 'rgba(185,168,255,0.18)', neuFg: '#CFC2FF'
    };
    const t = dark ? darkT : light;
    const P = dark ? {
      Lebensmittel: '#5CC992', 'Essen gehen': '#F07F5A', Transport: '#4FC3D9', Wohnen: '#C9A27E', Nebenkosten: '#B39AF0',
      Unterhaltung: '#F078B0', Shopping: '#F2A65E', Gesundheit: '#F07272', Versicherung: '#7FA6F5', Einkommen: '#6FD39A',
      Umbuchung: '#94A3B8', Bargeld: '#B5C25A', Abonnements: '#8B8CF5', Reisen: '#5BC0F0', Bildung: '#D9A54A', Sonstiges: '#5A5A60'
    } : {
      Lebensmittel: '#2E9E6A', 'Essen gehen': '#C2410C', Transport: '#0E7490', Wohnen: '#8B5E3C', Nebenkosten: '#8A63D2',
      Unterhaltung: '#BE185D', Shopping: '#D9822B', Gesundheit: '#D14343', Versicherung: '#3B6FD8', Einkommen: '#1B7A43',
      Umbuchung: '#64748B', Bargeld: '#7C8B2E', Abonnements: '#4F46E5', Reisen: '#0284C7', Bildung: '#A16207', Sonstiges: '#C9C4BB'
    };
    const names = ['Lebensmittel','Essen gehen','Transport','Wohnen','Nebenkosten','Unterhaltung','Shopping','Gesundheit','Versicherung','Einkommen','Umbuchung','Bargeld','Abonnements','Reisen','Bildung','Sonstiges','Unkategorisiert'];
    const cats = names.map((name) => {
      const selected = name === 'Nebenkosten';
      const current = name === 'Sonstiges';
      const unk = name === 'Unkategorisiert';
      return {
        name, selected, pressed: selected ? 'true' : 'false',
        color: unk ? 'transparent' : P[name],
        ring: unk ? '1.5px dashed ' + t.text2 : '0',
        bg: selected ? t.ink : 'transparent',
        fg: selected ? t.inkText : t.text,
        font: (selected || current ? '700' : '500') + ' 14px Inter, sans-serif'
      };
    });
    const menu = [
      { label: 'Aus Summen ausschließen', icon: 'M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18zM6 6l12 12' },
      { label: 'Text kopieren', icon: 'M9 9h11v11H9zM5 15H4V4h11v1' },
      { label: 'In Suche öffnen', icon: 'M11 4a7 7 0 1 0 0 14 7 7 0 0 0 0-14zM20 20l-3.5-3.5' }
    ];
    const recs = {
      abo: {
        label: 'Monatlich am 1. · seit Feb. 2026', int: '10', dec: ',99 €', name: 'Spotify', renamed: false, priceChange: false,
        next: '1. Dez.', nextIn: 'in 19 Tagen', year: '131,88 €', total: '109,90 €', count: '10 Zahlungen',
        history: ['1. Nov. 2026', '1. Okt. 2026', '1. Sep. 2026', '1. Aug. 2026'].map((date) => ({ date, note: '', amt: '−10,99 €' }))
      },
      mobil: {
        label: 'Monatlich · erkannt als „FUNKNET MOBIL RECHNUNG“', int: '19', dec: ',99 €', name: 'FunkNet Mobil', renamed: true, priceChange: true,
        next: '18. Nov.', nextIn: 'in 6 Tagen', year: '239,88 €', total: '99,92 €', count: '8 Zahlungen',
        history: [
          { date: '18. Okt. 2026', note: 'neuer Preis', amt: '−19,99 €' },
          { date: '18. Sep. 2026', note: '', amt: '−14,99 €' },
          { date: '18. Aug. 2026', note: 'Preis geändert', amt: '−14,99 €' },
          { date: '18. Juli 2026', note: '', amt: '−9,99 €' }
        ]
      }
    };
    const isTx = kind === 'tx';
    const isRec = !isTx;
    const isCat = sheet === 'category' && isTx;
    const isMenu = sheet === 'menu' && isTx;
    return {
      t, accent, cats, menu, rec: recs[kind] || recs.abo,
      isTx, isRec, isCat, isMenu,
      isCatStr: isCat ? 'true' : 'false', isMenuStr: isMenu ? 'true' : 'false',
      menuBg: isMenu ? t.ink : 'transparent', menuFg: isMenu ? t.inkText : t.text
    };
  }
}
