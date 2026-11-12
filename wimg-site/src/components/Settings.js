
class Component extends DCLogic {
  renderVals() {
    const soft = this.props.soft ?? true;
    const sh = soft ? { trackW: '48px', trackR: '8px', knobR: '6px', barR: '20px', btnR: '13px' } : { trackW: '44px', trackR: '13px', knobR: '10px', barR: '30px', btnR: '22px' };
    const dark = this.props.dark ?? false;
    const part = this.props.part ?? 'top';
    const light = {
      band: '#1D1C1A', sheet: '#FAF9F6', fade0: 'rgba(250,249,246,0)', card: '#FFFFFF', sheetEdge: '0',
      text: '#1A1A1A', text2: '#6B6A66', line: '#ECE8E1', pos: '#1B7A43', track: '#D9D4CB', trackSoft: '#E3E5E9', acc: '#4A6D96',
      neutralTint: '#F1EDE5', ink: '#1A1A1A', inkText: '#FFFFFF', danger: '#B3261E', dangerLine: '#F2C9C5',
      neuBg: '#ECE6FF', neuFg: '#5236C9'
    };
    const darkT = {
      band: '#1E1E21', sheet: '#111114', fade0: 'rgba(17,17,20,0)', card: '#1C1C1E', sheetEdge: '1px solid rgba(255,255,255,0.08)',
      text: '#F2F2F3', text2: '#9A9BA0', line: 'rgba(255,255,255,0.08)', pos: '#6FD39A', track: '#3A3A40', trackSoft: '#3A3B41', acc: '#6F93BC',
      neutralTint: '#26262A', ink: '#F2F2F3', inkText: '#111114', danger: '#FF8A80', dangerLine: 'rgba(255,138,128,0.35)',
      neuBg: 'rgba(185,168,255,0.18)', neuFg: '#CFC2FF'
    };
    const t = dark ? darkT : light;
    const nav = (label, value, extra) => ({ type: 'nav', label, value, ...extra });
    const sw = (label, on, desc, extra) => ({ type: 'switch', label, on, desc, ...extra });
    const seg = (label, opts, sel) => ({ type: 'seg', label, opts: opts.map((o) => ({ label: o, sel: o === sel })) });
    const status = (label, value) => ({ type: 'status', label, value });
    const top = [
      { title: 'Darstellung', rows: [seg('Design', ['Hell', 'Dunkel', 'System'], 'System'), nav('Sprache', 'Deutsch')] },
      { title: 'Zeitraum', neu: true, rows: [nav('Monat beginnt', 'mit dem Gehalt', { desc: 'Automatisch erkannt · Kalendermonat, wenn kein Gehalt kommt' })] },
      { title: 'Synchronisierung', rows: [
        sw('Sync aktivieren', true, 'Ende-zu-Ende-verschlüsselt zwischen deinen Geräten, ohne Konto'),
        status('Status', 'Sync aktiv'),
        nav('Sync-Schlüssel einfügen', 'Verknüpfen')
      ]},
      { title: 'Bankverbindung', rows: [
        nav('Bankverbindungen', 'Musterbank'),
        sw('Schnellabfrage im Hintergrund', !soft, 'Einmal täglich, letzte 14 Tage · nur wenn die Bank keine TAN verlangt')
      ]},
      { title: 'Sicherheit', rows: [
        sw('App-Sperre', true, 'Fingerabdruck oder Gesicht · blockiert Screenshots'),
        sw('Beträge in Widgets ausblenden', false, '')
      ]}
    ];
    const bottom = [
      { title: 'Funktionen', rows: [sw('Wiederkehrend', true, ''), sw('Rückblick', true, ''), sw('Vermögen', false, '')] },
      { title: 'Kategorien', rows: [nav('Gelernte Regeln', '12', { neu: true, desc: 'Ansehen und löschen, was wimg beim Zuordnen gelernt hat' })] },
      { title: 'Daten', rows: [
        nav('Exportieren', 'CSV, Datenbank'),
        nav('Importieren', 'CSV', { desc: 'Comdirect, Trade Republic, Scalable' })
      ]},
      { title: 'Danger Zone', danger: true, rows: [nav('Alle Daten löschen', '', { danger: true, desc: 'Fragt vorher nach Bestätigung' })] },
      { title: 'Über wimg', rows: [nav('Version', '[x.y.z]'), nav('FAQ', ''), nav('Changelog', '')] }
    ];
    const groups = (part === 'bottom' ? bottom : top).map((g) => ({
      title: g.title, neu: !!g.neu,
      titleColor: g.danger ? t.danger : t.text2,
      border: g.danger ? t.dangerLine : t.line,
      rows: g.rows.map((r, i) => ({
        label: r.label, value: r.value || '', desc: r.desc || '', neu: !!r.neu,
        color: r.danger ? t.danger : t.text,
        h: r.desc ? '64px' : '50px',
        border: i === 0 ? '0' : '1px solid ' + t.line,
        isNav: r.type === 'nav', isSwitch: r.type === 'switch', isSeg: r.type === 'seg', isStatus: r.type === 'status',
        checked: r.on ? 'true' : 'false',
        trackBg: r.on ? (soft ? t.acc : t.ink) : (soft ? t.trackSoft : t.track), knobBg: r.on ? (soft ? '#FFFFFF' : t.inkText) : '#FFFFFF',
        knobLeft: r.on ? (soft ? '25px' : '21px') : '3px',
        opts: (r.opts || []).map((o) => ({
          label: o.label, pressed: o.sel ? 'true' : 'false',
          bg: o.sel ? t.card : 'transparent', fg: o.sel ? t.text : t.text2,
          font: (o.sel ? '700' : '600') + ' 12px Manrope, sans-serif',
          shadow: o.sel ? '0 1px 2px rgba(0,0,0,0.08)' : 'none'
        }))
      }))
    }));
    return { t, groups, offset: '0px', sh };
  }
}
