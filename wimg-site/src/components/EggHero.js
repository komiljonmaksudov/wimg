
class Component extends DCLogic {
  constructor(p) { super(p); this.state = { n: 0, flyers: [], gone: {}, inside: false, weg: false, moth: false, tip: false, refill: false }; this.t = []; this.id = 0; }
  componentWillUnmount() { this.t.forEach(clearTimeout); clearTimeout(this.clr); }
  later(ms, fn) { this.t.push(setTimeout(fn, ms)); }
  addFly(kind, item, extra) {
    const id = ++this.id;
    this.setState((s) => ({ flyers: s.flyers.concat([Object.assign({ id, kind, item }, extra || {})]) }));
    clearTimeout(this.clr); this.clr = setTimeout(() => this.setState({ flyers: [] }), 1450);
  }
  tap() {
    const s = this.state;
    if (s.inside) return;
    const order = ['n50', 'n10', 'n20'];
    if (s.n < 3) {
      const k = order[s.n];
      const drift = [[330, -14, 18, -10, 24], [470, 12, -20, 14, -26], [600, -8, 26, -18, 10]][s.n];
      this.addFly('note', k, { dx: drift[0], r0: drift[1], r1: drift[2], r2: drift[3], r3: drift[4] });
      this.setState({ n: s.n + 1, gone: Object.assign({}, s.gone, { [k]: true }) });
    } else if (s.n === 3) {
      this.addFly('card', 'card');
      this.setState({ n: 4, gone: Object.assign({}, s.gone, { card: true }), tip: true });
      this.later(1100, () => this.setState((x) => ({ gone: Object.assign({}, x.gone, { card: false }) })));
      this.later(1650, () => this.setState({ tip: false }));
    } else {
      this.setState({ inside: true, moth: true, weg: true, gone: { n50: true, n10: true, n20: true, card: true } });
      this.later(1450, () => this.setState({ moth: false }));
      this.later(2000, () => this.setState({ weg: false }));
      this.later(2200, () => this.setState({ inside: false }));
      this.later(2450, () => this.setState({ n: 0, gone: {}, refill: true }));
      this.later(3000, () => this.setState({ refill: false }));
    }
  }
  renderVals() {
    const s = this.state;
    const v = { tap: () => { this.tap(); window.scrollTo({ top: 0, behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth' }); } };
    const its = ['n50', 'n10', 'n20', 'card'];
    const stag = { n50: 0, n10: 60, n20: 100, card: 0 };
    its.forEach((k) => {
      const gone = !!(s.gone || {})[k];
      v[k + 'Op'] = gone ? 0 : 1;
      v[k + 'Dy'] = gone ? -14 : 0;
      v[k + 'Dl'] = s.refill ? stag[k] + 'ms' : '0ms';
    });
    const sq = s.inside ? 0 : Math.min(s.n, 3);
    v.sqy = (1 - sq * 0.045).toFixed(3); v.sqx = (1 + sq * 0.012).toFixed(3);
    v.tongue = s.inside ? 1 : 0;
    v.flyers = (s.flyers || []).map((f) => Object.assign({}, f, {"n50":{"x":"102.3","y":"-13.9"},"n10":{"x":"106.4","y":"-15.0"},"n20":{"x":"100.0","y":"-13.6"},"card":{"x":"95.1","y":"-15.9"}}[f.item], {
      dx: f.dx || 0, r0: f.r0 || 0, r1: f.r1 || 0, r2: f.r2 || 0, r3: f.r3 || 0,
      isN50: f.item === 'n50', isN10: f.item === 'n10', isN20: f.item === 'n20', isCard: f.item === 'card',
      delay: f.at != null ? '-' + f.at + 'ms' : '0ms', dir: f.rev ? 'reverse' : 'normal' }));
    v.tipText = 'Die bleibt hier.';
    v.moth = !!s.moth; v.mothDelay = s.mothAt != null ? '-' + s.mothAt + 'ms' : '0ms';
    v.tip = !!s.tip; v.tipDelay = s.tipAt != null ? '-' + s.tipAt + 'ms' : '0ms';
    v.hlA = s.weg ? 0 : 1; v.hlAy = s.weg ? -8 : 0; v.hlB = s.weg ? 1 : 0; v.hlBy = s.weg ? 0 : 8;
    return v;
  }
}
