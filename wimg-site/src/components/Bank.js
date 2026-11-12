
class Component extends DCLogic {
  renderVals() {
    const dark = this.props.dark ?? false;
    const screen = this.props.screen ?? 'list';
    const accent = this.props.accent ?? '#4A6D96';
    const light = {
      band: '#1D1C1A', sheet: '#FAF9F6', fade0: 'rgba(250,249,246,0)', card: '#FFFFFF', sheetEdge: '0',
      text: '#1A1A1A', text2: '#6B6A66', line: '#ECE8E1', pos: '#1B7A43',
      neutralTint: '#F1EDE5', ink: '#1A1A1A', inkText: '#FFFFFF', danger: '#B3261E', dangerBg: '#FCE8E6',
      warn: '#9A5B00', warnBg: '#FFF1D6', sync: '#E8710A', syncBg: '#FDEBDC', neuBg: '#ECE6FF', neuFg: '#5236C9'
    };
    const darkT = {
      band: '#1E1E21', sheet: '#111114', fade0: 'rgba(17,17,20,0)', card: '#1C1C1E', sheetEdge: '1px solid rgba(255,255,255,0.08)',
      text: '#F2F2F3', text2: '#9A9BA0', line: 'rgba(255,255,255,0.08)', pos: '#6FD39A',
      neutralTint: '#26262A', ink: '#F2F2F3', inkText: '#111114', danger: '#FF8A80', dangerBg: 'rgba(255,138,128,0.12)',
      warn: '#F5B54A', warnBg: 'rgba(245,181,74,0.12)', sync: '#FF9A3C', syncBg: 'rgba(255,154,60,0.14)', neuBg: 'rgba(185,168,255,0.18)', neuFg: '#CFC2FF'
    };
    const t = dark ? darkT : light;
    const S = screen;
    const isList = S === 'list' || S === 'listSync' || S === 'listError';
    const isDetail = S === 'detail';
    const isFlow = !isList && !isDetail;
    const stepOf = { s1: 1, s2: 2, s2err: 2, s3: 3, s4app: 3, s4photo: 3, s4typed: 3, s4typedErr: 3, s5: 4, s6: 5, s7: 5 };
    const titles = { s1: 'Bank wählen', s2: 'Anmeldung', s2err: 'Anmeldung', s3: 'TAN-Gerät wählen', s4app: 'Freigabe', s4photo: 'photoTAN', s4typed: 'TAN eingeben', s4typedErr: 'TAN eingeben', s5: 'Zeitraum', s6: 'Abruf', s7: 'Fertig' };
    const step = stepOf[S] || 1;
    const steps = [1, 2, 3, 4, 5].map((n) => ({ bg: n <= step ? '#FFFFFF' : 'rgba(255,255,255,0.18)' }));

    const border = (i) => (i === 0 ? '0' : '1px solid ' + t.line);
    const banks = [
      ['Musterbank', '123 456 78'], ['Sparkasse KölnBonn', '370 501 98'], ['ING', '500 105 17'],
      ['DKB Deutsche Kreditbank', '120 300 00'], ['Commerzbank', '100 400 00'], ['Deutsche Bank', '100 700 00']
    ].map(([name, blz], i) => ({ name, blz, border: border(i) }));
    const media = [['Handy privat', 'SMS-TAN', true], ['Diensthandy', 'SMS-TAN', false]].map(([name, kind, sel], i) => ({
      name, kind, border: border(i), ring: '2px solid ' + (sel ? t.ink : t.text2), dot: sel ? t.ink : 'transparent'
    }));
    const periods = [['3 Monate', ''], ['6 Monate', ''], ['1 Jahr', 'empfohlen'], ['2 Jahre', ''], ['Eigener Zeitraum', 'von – bis']].map(([label, note], i) => {
      const sel = label === '1 Jahr';
      return { label, note, border: border(i), ring: '2px solid ' + (sel ? t.ink : t.text2), dot: sel ? t.ink : 'transparent', weight: sel ? '700' : '500' };
    });
    const progress = [['Verbunden mit Musterbank', 'done'], ['TAN bestätigt', 'done'], ['Umsätze laden · Seite 4', 'now'], ['Duplikate prüfen', 'todo']].map(([label, st]) => ({
      label, done: st === 'done',
      bg: st === 'done' ? t.ink : 'transparent',
      ring: st === 'done' ? '0' : (st === 'now' ? '2.5px solid ' + t.sync : '1.5px dashed ' + t.text2),
      weight: st === 'now' ? '700' : '500', color: st === 'todo' ? t.text2 : t.text
    }));
    const detailRows = [
      ['Kennung', '12345678', "'JetBrains Mono', monospace"], ['PIN', 'gespeichert · nur auf diesem Gerät', 'Inter, sans-serif'],
      ['TAN-Verfahren', 'photoTAN', 'Inter, sans-serif'], ['Letzter Abruf', 'heute, vor 2 Std. · 3 neue', 'Inter, sans-serif'],
      ['Umsätze', '214', 'Inter, sans-serif']
    ].map(([label, value, font], i) => ({ label, value, font, border: border(i) }));

    // deterministic mosaic
    const pal = ['#1A1A1A', '#FFFFFF', '#E53935', '#1E88E5', '#43A047', '#FDD835', '#8E24AA', '#FB8C00'];
    let seed = 7;
    const mosaic = Array.from({ length: 144 }, () => { seed = (seed * 9301 + 49297) % 233280; return pal[Math.floor((seed / 233280) * pal.length)]; });

    const accentFg = (() => { const h = accent.replace('#',''); const [r,g,b] = [0,2,4].map(i => parseInt(h.substr(i,2),16)/255); return (0.2126*r + 0.7152*g + 0.0722*b) > 0.45 ? '#1A1A1A' : '#FFFFFF'; })();
    const accentBtn = { bg: accent, fg: accentFg, border: '0' };
    const outlineBtn = { bg: 'transparent', fg: t.text, border: '1.5px solid ' + t.line };
    const flowMain = {
      s2: ['Anmelden', accentBtn], s2err: ['Anmelden', accentBtn], s3: ['Weiter', accentBtn],
      s4app: ['Status prüfen', outlineBtn], s4photo: ['Bestätigen', accentBtn], s4typed: ['Bestätigen', accentBtn],
      s4typedErr: ['Erneut versuchen', accentBtn], s5: ['Abrufen', accentBtn], s6: ['Im Hintergrund', accentBtn],
      s7: ['Transaktionen ansehen', accentBtn], detail: ['Schnellabfrage', accentBtn]
    }[S];
    const main = flowMain ? flowMain[0] : '';
    const mb = flowMain ? flowMain[1] : accentBtn;

    let strip = false, stripText = '', stripSub = '', stripAction = '', stripDot = t.sync, seamW = '0%';
    let cardStatus = 'zuletzt abgerufen vor 2 Std. · 3 neue Umsätze', cardStatusColor = t.text2;
    let card2Status = 'zuletzt abgerufen vor 9 Tagen · Abruf nur mit Anmeldung', card2StatusColor = t.text2;
    if (S === 'listSync') {
      strip = true; stripText = 'Umsätze laden · Seite 5 von ~9'; stripSub = 'Musterbank · läuft im Hintergrund'; stripDot = t.sync; seamW = '55%';
      cardStatus = 'Abruf läuft …'; cardStatusColor = t.sync;
    }
    if (S === 'listError') {
      strip = true; stripText = 'TAN abgelaufen'; stripSub = 'Musterbank · Abruf nicht abgeschlossen'; stripAction = 'Erneut'; stripDot = t.danger; seamW = '100%';
      cardStatus = 'Meldung der Bank: 9050 Nachricht enthält Fehler'; cardStatusColor = t.danger;
      card2Status = 'Bank nicht erreichbar · später erneut versuchen'; card2StatusColor = t.danger;
    }

    const isS6 = S === 's6';
    if (isS6) {
      strip = true; stripText = 'Umsätze laden · Seite 4 von ~9'; stripSub = 'Musterbank · ca. 100 Umsätze pro Seite'; stripDot = t.sync; seamW = '45%';
    }
    return {
      t, accent, accentBtn, step, steps, flowTitle: titles[S] || '',
      isList, isDetail, isFlow,
      isS1: S === 's1', isS2: S === 's2' || S === 's2err', isS3: S === 's3', isApp: S === 's4app', isPhoto: S === 's4photo',
      isTyped: S === 's4typed' || S === 's4typedErr', isS5: S === 's5', isS6, isS7: S === 's7',
      sheetTop: isList ? '76px' : (isDetail ? '160px' : '150px'),
      banks, media, periods, progress, detailRows, mosaic,
      pinError: S === 's2err', pinValue: S === 's2err' ? '' : '••••••',
      pinBorder: S === 's2err' ? '1.5px solid ' + t.danger : '1px solid ' + t.line,
      tanError: S === 's4typedErr', tanValue: S === 's4typedErr' ? '' : '48',
      tanBorder: S === 's4typedErr' ? '1.5px solid ' + t.danger : '1.5px solid ' + t.ink,
      strip, stripSub, seamW, stripIsError: S === 'listError', stripIsSync: S === 'listSync' || isS6, stripClose: S === 'listSync',
      stripBg: S === 'listError' ? t.dangerBg : t.syncBg,
      barOuterW: strip ? '358px' : 'auto',
      stripText, stripAction, stripDot, cardStatus, cardStatusColor, card2Status, card2StatusColor,
      syncing: isS6,
      barPlace: isList, barBack: (isFlow && S !== 's6' && S !== 's7') || isDetail, barSearch: S === 's1',
      barMore: isDetail,
      barW: strip ? '100%' : (S === 's1' || (isFlow && S !== 's4app' && S !== 's6')) ? '358px' : 'auto',
      second: S === 's7' ? 'Kategorisieren' : (isS6 ? 'Abbrechen' : ''),
      main, mainRefresh: isDetail, mainGrow: isFlow ? '1' : '0',
      mainBg: mb.bg, mainFg: mb.fg, mainBorder: mb.border
    };
  }
}
