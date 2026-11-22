function Tt(a, t, s) {
  if (a && a.length) {
    const [e, n] = t, o = Math.PI / 180 * s, h = Math.cos(o), r = Math.sin(o);
    for (const i of a) {
      const [c, l] = i;
      i[0] = (c - e) * h - (l - n) * r + e, i[1] = (c - e) * r + (l - n) * h + n;
    }
  }
}
function Me(a, t, s) {
  const e = [];
  a.forEach((n) => e.push(...n)), Tt(e, t, s);
}
function ke(a, t) {
  return a[0] === t[0] && a[1] === t[1];
}
function be(a, t, s, e = 1) {
  const n = s, o = Math.max(t, 0.1), h = a[0] && a[0][0] && typeof a[0][0] == "number" ? [a] : a, r = [0, 0];
  if (n)
    for (const c of h)
      Tt(c, r, n);
  const i = me(h, o, e);
  if (n) {
    for (const c of h)
      Tt(c, r, -n);
    Me(i, r, -n);
  }
  return i;
}
function me(a, t, s) {
  const e = [];
  for (const c of a) {
    const l = [...c];
    ke(l[0], l[l.length - 1]) || l.push([l[0][0], l[0][1]]), l.length > 2 && e.push(l);
  }
  const n = [];
  t = Math.max(t, 0.1);
  const o = [];
  for (const c of e)
    for (let l = 0; l < c.length - 1; l++) {
      const p = c[l], f = c[l + 1];
      if (p[1] !== f[1]) {
        const u = Math.min(p[1], f[1]);
        o.push({
          ymin: u,
          ymax: Math.max(p[1], f[1]),
          x: u === p[1] ? p[0] : f[0],
          islope: (f[0] - p[0]) / (f[1] - p[1])
        });
      }
    }
  if (o.sort((c, l) => c.ymin < l.ymin ? -1 : c.ymin > l.ymin ? 1 : c.x < l.x ? -1 : c.x > l.x ? 1 : c.ymax === l.ymax ? 0 : (c.ymax - l.ymax) / Math.abs(c.ymax - l.ymax)), !o.length)
    return n;
  let h = [], r = o[0].ymin, i = 0;
  for (; h.length || o.length; ) {
    if (o.length) {
      let c = -1;
      for (let p = 0; p < o.length && !(o[p].ymin > r); p++)
        c = p;
      o.splice(0, c + 1).forEach((p) => {
        h.push({ s: r, edge: p });
      });
    }
    if (h = h.filter((c) => !(c.edge.ymax <= r)), h.sort((c, l) => c.edge.x === l.edge.x ? 0 : (c.edge.x - l.edge.x) / Math.abs(c.edge.x - l.edge.x)), (s !== 1 || i % t === 0) && h.length > 1)
      for (let c = 0; c < h.length; c = c + 2) {
        const l = c + 1;
        if (l >= h.length)
          break;
        const p = h[c].edge, f = h[l].edge;
        n.push([
          [Math.round(p.x), r],
          [Math.round(f.x), r]
        ]);
      }
    r += s, h.forEach((c) => {
      c.edge.x = c.edge.x + s * c.edge.islope;
    }), i++;
  }
  return n;
}
function J(a, t) {
  var s;
  const e = t.hachureAngle + 90;
  let n = t.hachureGap;
  n < 0 && (n = t.strokeWidth * 4), n = Math.max(n, 0.1);
  let o = 1;
  return t.roughness >= 1 && (((s = t.randomizer) === null || s === void 0 ? void 0 : s.next()) || Math.random()) > 0.7 && (o = n), be(a, n, e, o || 1);
}
class $t {
  constructor(t) {
    this.helper = t;
  }
  fillPolygons(t, s) {
    return this._fillPolygons(t, s);
  }
  _fillPolygons(t, s) {
    const e = J(t, s);
    return { type: "fillSketch", ops: this.renderLines(e, s) };
  }
  renderLines(t, s) {
    const e = [];
    for (const n of t)
      e.push(...this.helper.doubleLineOps(n[0][0], n[0][1], n[1][0], n[1][1], s));
    return e;
  }
}
function kt(a) {
  const t = a[0], s = a[1];
  return Math.sqrt(Math.pow(t[0] - s[0], 2) + Math.pow(t[1] - s[1], 2));
}
class ye extends $t {
  fillPolygons(t, s) {
    let e = s.hachureGap;
    e < 0 && (e = s.strokeWidth * 4), e = Math.max(e, 0.1);
    const n = Object.assign({}, s, { hachureGap: e }), o = J(t, n), h = Math.PI / 180 * s.hachureAngle, r = [], i = e * 0.5 * Math.cos(h), c = e * 0.5 * Math.sin(h);
    for (const [p, f] of o)
      kt([p, f]) && r.push([
        [p[0] - i, p[1] + c],
        [...f]
      ], [
        [p[0] + i, p[1] - c],
        [...f]
      ]);
    return { type: "fillSketch", ops: this.renderLines(r, s) };
  }
}
class Pe extends $t {
  fillPolygons(t, s) {
    const e = this._fillPolygons(t, s), n = Object.assign({}, s, { hachureAngle: s.hachureAngle + 90 }), o = this._fillPolygons(t, n);
    return e.ops = e.ops.concat(o.ops), e;
  }
}
class we {
  constructor(t) {
    this.helper = t;
  }
  fillPolygons(t, s) {
    s = Object.assign({}, s, { hachureAngle: 0 });
    const e = J(t, s);
    return this.dotsOnLines(e, s);
  }
  dotsOnLines(t, s) {
    const e = [];
    let n = s.hachureGap;
    n < 0 && (n = s.strokeWidth * 4), n = Math.max(n, 0.1);
    let o = s.fillWeight;
    o < 0 && (o = s.strokeWidth / 2);
    const h = n / 4;
    for (const r of t) {
      const i = kt(r), c = i / n, l = Math.ceil(c) - 1, p = i - l * n, f = (r[0][0] + r[1][0]) / 2 - n / 4, u = Math.min(r[0][1], r[1][1]);
      for (let d = 0; d < l; d++) {
        const g = u + p + d * n, M = f - h + Math.random() * 2 * h, k = g - h + Math.random() * 2 * h, b = this.helper.ellipse(M, k, o, o, s);
        e.push(...b.ops);
      }
    }
    return { type: "fillSketch", ops: e };
  }
}
class Se {
  constructor(t) {
    this.helper = t;
  }
  fillPolygons(t, s) {
    const e = J(t, s);
    return { type: "fillSketch", ops: this.dashedLine(e, s) };
  }
  dashedLine(t, s) {
    const e = s.dashOffset < 0 ? s.hachureGap < 0 ? s.strokeWidth * 4 : s.hachureGap : s.dashOffset, n = s.dashGap < 0 ? s.hachureGap < 0 ? s.strokeWidth * 4 : s.hachureGap : s.dashGap, o = [];
    return t.forEach((h) => {
      const r = kt(h), i = Math.floor(r / (e + n)), c = (r + n - i * (e + n)) / 2;
      let l = h[0], p = h[1];
      l[0] > p[0] && (l = h[1], p = h[0]);
      const f = Math.atan((p[1] - l[1]) / (p[0] - l[0]));
      for (let u = 0; u < i; u++) {
        const d = u * (e + n), g = d + e, M = [l[0] + d * Math.cos(f) + c * Math.cos(f), l[1] + d * Math.sin(f) + c * Math.sin(f)], k = [l[0] + g * Math.cos(f) + c * Math.cos(f), l[1] + g * Math.sin(f) + c * Math.sin(f)];
        o.push(...this.helper.doubleLineOps(M[0], M[1], k[0], k[1], s));
      }
    }), o;
  }
}
class ve {
  constructor(t) {
    this.helper = t;
  }
  fillPolygons(t, s) {
    const e = s.hachureGap < 0 ? s.strokeWidth * 4 : s.hachureGap, n = s.zigzagOffset < 0 ? e : s.zigzagOffset;
    s = Object.assign({}, s, { hachureGap: e + n });
    const o = J(t, s);
    return { type: "fillSketch", ops: this.zigzagLines(o, n, s) };
  }
  zigzagLines(t, s, e) {
    const n = [];
    return t.forEach((o) => {
      const h = kt(o), r = Math.round(h / (2 * s));
      let i = o[0], c = o[1];
      i[0] > c[0] && (i = o[1], c = o[0]);
      const l = Math.atan((c[1] - i[1]) / (c[0] - i[0]));
      for (let p = 0; p < r; p++) {
        const f = p * 2 * s, u = (p + 1) * 2 * s, d = Math.sqrt(2 * Math.pow(s, 2)), g = [i[0] + f * Math.cos(l), i[1] + f * Math.sin(l)], M = [i[0] + u * Math.cos(l), i[1] + u * Math.sin(l)], k = [g[0] + d * Math.cos(l + Math.PI / 4), g[1] + d * Math.sin(l + Math.PI / 4)];
        n.push(...this.helper.doubleLineOps(g[0], g[1], k[0], k[1], e), ...this.helper.doubleLineOps(k[0], k[1], M[0], M[1], e));
      }
    }), n;
  }
}
const _ = {};
function Oe(a, t) {
  let s = a.fillStyle || "hachure";
  if (!_[s])
    switch (s) {
      case "zigzag":
        _[s] || (_[s] = new ye(t));
        break;
      case "cross-hatch":
        _[s] || (_[s] = new Pe(t));
        break;
      case "dots":
        _[s] || (_[s] = new we(t));
        break;
      case "dashed":
        _[s] || (_[s] = new Se(t));
        break;
      case "zigzag-line":
        _[s] || (_[s] = new ve(t));
        break;
      case "hachure":
      default:
        s = "hachure", _[s] || (_[s] = new $t(t));
        break;
    }
  return _[s];
}
function xe() {
  return Math.floor(Math.random() * 2 ** 31);
}
class Le {
  constructor(t) {
    this.seed = t;
  }
  next() {
    return this.seed ? (2 ** 31 - 1 & (this.seed = Math.imul(48271, this.seed))) / 2 ** 31 : Math.random();
  }
}
const Te = 0, Dt = 1, ne = 2, tt = { A: 7, a: 7, C: 6, c: 6, H: 1, h: 1, L: 2, l: 2, M: 2, m: 2, Q: 4, q: 4, S: 4, s: 4, T: 2, t: 2, V: 1, v: 1, Z: 0, z: 0 };
function De(a) {
  const t = new Array();
  for (; a !== ""; )
    if (a.match(/^([ \t\r\n,]+)/))
      a = a.substr(RegExp.$1.length);
    else if (a.match(/^([aAcChHlLmMqQsStTvVzZ])/))
      t[t.length] = { type: Te, text: RegExp.$1 }, a = a.substr(RegExp.$1.length);
    else if (a.match(/^(([-+]?[0-9]+(\.[0-9]*)?|[-+]?\.[0-9]+)([eE][-+]?[0-9]+)?)/))
      t[t.length] = { type: Dt, text: `${parseFloat(RegExp.$1)}` }, a = a.substr(RegExp.$1.length);
    else
      return [];
  return t[t.length] = { type: ne, text: "" }, t;
}
function Pt(a, t) {
  return a.type === t;
}
function Rt(a) {
  const t = [], s = De(a);
  let e = "BOD", n = 0, o = s[n];
  for (; !Pt(o, ne); ) {
    let h = 0;
    const r = [];
    if (e === "BOD")
      if (o.text === "M" || o.text === "m")
        n++, h = tt[o.text], e = o.text;
      else
        return Rt("M0,0" + a);
    else Pt(o, Dt) ? h = tt[e] : (n++, h = tt[o.text], e = o.text);
    if (n + h < s.length) {
      for (let i = n; i < n + h; i++) {
        const c = s[i];
        if (Pt(c, Dt))
          r[r.length] = +c.text;
        else
          throw new Error("Param not a number: " + e + "," + c.text);
      }
      if (typeof tt[e] == "number") {
        const i = { key: e, data: r };
        t.push(i), n += h, o = s[n], e === "M" && (e = "L"), e === "m" && (e = "l");
      } else
        throw new Error("Bad segment: " + e);
    } else
      throw new Error("Path data ended short");
  }
  return t;
}
function ae(a) {
  let t = 0, s = 0, e = 0, n = 0;
  const o = [];
  for (const { key: h, data: r } of a)
    switch (h) {
      case "M":
        o.push({ key: "M", data: [...r] }), [t, s] = r, [e, n] = r;
        break;
      case "m":
        t += r[0], s += r[1], o.push({ key: "M", data: [t, s] }), e = t, n = s;
        break;
      case "L":
        o.push({ key: "L", data: [...r] }), [t, s] = r;
        break;
      case "l":
        t += r[0], s += r[1], o.push({ key: "L", data: [t, s] });
        break;
      case "C":
        o.push({ key: "C", data: [...r] }), t = r[4], s = r[5];
        break;
      case "c": {
        const i = r.map((c, l) => l % 2 ? c + s : c + t);
        o.push({ key: "C", data: i }), t = i[4], s = i[5];
        break;
      }
      case "Q":
        o.push({ key: "Q", data: [...r] }), t = r[2], s = r[3];
        break;
      case "q": {
        const i = r.map((c, l) => l % 2 ? c + s : c + t);
        o.push({ key: "Q", data: i }), t = i[2], s = i[3];
        break;
      }
      case "A":
        o.push({ key: "A", data: [...r] }), t = r[5], s = r[6];
        break;
      case "a":
        t += r[5], s += r[6], o.push({ key: "A", data: [r[0], r[1], r[2], r[3], r[4], t, s] });
        break;
      case "H":
        o.push({ key: "H", data: [...r] }), t = r[0];
        break;
      case "h":
        t += r[0], o.push({ key: "H", data: [t] });
        break;
      case "V":
        o.push({ key: "V", data: [...r] }), s = r[0];
        break;
      case "v":
        s += r[0], o.push({ key: "V", data: [s] });
        break;
      case "S":
        o.push({ key: "S", data: [...r] }), t = r[2], s = r[3];
        break;
      case "s": {
        const i = r.map((c, l) => l % 2 ? c + s : c + t);
        o.push({ key: "S", data: i }), t = i[2], s = i[3];
        break;
      }
      case "T":
        o.push({ key: "T", data: [...r] }), t = r[0], s = r[1];
        break;
      case "t":
        t += r[0], s += r[1], o.push({ key: "T", data: [t, s] });
        break;
      case "Z":
      case "z":
        o.push({ key: "Z", data: [] }), t = e, s = n;
        break;
    }
  return o;
}
function oe(a) {
  const t = [];
  let s = "", e = 0, n = 0, o = 0, h = 0, r = 0, i = 0;
  for (const { key: c, data: l } of a) {
    switch (c) {
      case "M":
        t.push({ key: "M", data: [...l] }), [e, n] = l, [o, h] = l;
        break;
      case "C":
        t.push({ key: "C", data: [...l] }), e = l[4], n = l[5], r = l[2], i = l[3];
        break;
      case "L":
        t.push({ key: "L", data: [...l] }), [e, n] = l;
        break;
      case "H":
        e = l[0], t.push({ key: "L", data: [e, n] });
        break;
      case "V":
        n = l[0], t.push({ key: "L", data: [e, n] });
        break;
      case "S": {
        let p = 0, f = 0;
        s === "C" || s === "S" ? (p = e + (e - r), f = n + (n - i)) : (p = e, f = n), t.push({ key: "C", data: [p, f, ...l] }), r = l[0], i = l[1], e = l[2], n = l[3];
        break;
      }
      case "T": {
        const [p, f] = l;
        let u = 0, d = 0;
        s === "Q" || s === "T" ? (u = e + (e - r), d = n + (n - i)) : (u = e, d = n);
        const g = e + 2 * (u - e) / 3, M = n + 2 * (d - n) / 3, k = p + 2 * (u - p) / 3, b = f + 2 * (d - f) / 3;
        t.push({ key: "C", data: [g, M, k, b, p, f] }), r = u, i = d, e = p, n = f;
        break;
      }
      case "Q": {
        const [p, f, u, d] = l, g = e + 2 * (p - e) / 3, M = n + 2 * (f - n) / 3, k = u + 2 * (p - u) / 3, b = d + 2 * (f - d) / 3;
        t.push({ key: "C", data: [g, M, k, b, u, d] }), r = p, i = f, e = u, n = d;
        break;
      }
      case "A": {
        const p = Math.abs(l[0]), f = Math.abs(l[1]), u = l[2], d = l[3], g = l[4], M = l[5], k = l[6];
        p === 0 || f === 0 ? (t.push({ key: "C", data: [e, n, M, k, M, k] }), e = M, n = k) : (e !== M || n !== k) && (re(e, n, M, k, p, f, u, d, g).forEach(function(P) {
          t.push({ key: "C", data: P });
        }), e = M, n = k);
        break;
      }
      case "Z":
        t.push({ key: "Z", data: [] }), e = o, n = h;
        break;
    }
    s = c;
  }
  return t;
}
function Ae(a) {
  return Math.PI * a / 180;
}
function B(a, t, s) {
  const e = a * Math.cos(s) - t * Math.sin(s), n = a * Math.sin(s) + t * Math.cos(s);
  return [e, n];
}
function re(a, t, s, e, n, o, h, r, i, c) {
  const l = Ae(h);
  let p = [], f = 0, u = 0, d = 0, g = 0;
  if (c)
    [f, u, d, g] = c;
  else {
    [a, t] = B(a, t, -l), [s, e] = B(s, e, -l);
    const T = (a - s) / 2, w = (t - e) / 2;
    let S = T * T / (n * n) + w * w / (o * o);
    S > 1 && (S = Math.sqrt(S), n = S * n, o = S * o);
    const D = r === i ? -1 : 1, W = n * n, R = o * o, mt = W * R - W * w * w - R * T * T, yt = W * w * w + R * T * T, Q = D * Math.sqrt(Math.abs(mt / yt));
    d = Q * n * w / o + (a + s) / 2, g = Q * -o * T / n + (t + e) / 2, f = Math.asin(parseFloat(((t - g) / o).toFixed(9))), u = Math.asin(parseFloat(((e - g) / o).toFixed(9))), a < d && (f = Math.PI - f), s < d && (u = Math.PI - u), f < 0 && (f = Math.PI * 2 + f), u < 0 && (u = Math.PI * 2 + u), i && f > u && (f = f - Math.PI * 2), !i && u > f && (u = u - Math.PI * 2);
  }
  let M = u - f;
  if (Math.abs(M) > Math.PI * 120 / 180) {
    const T = u, w = s, S = e;
    i && u > f ? u = f + Math.PI * 120 / 180 * 1 : u = f + Math.PI * 120 / 180 * -1, s = d + n * Math.cos(u), e = g + o * Math.sin(u), p = re(s, e, w, S, n, o, h, 0, i, [u, T, d, g]);
  }
  M = u - f;
  const k = Math.cos(f), b = Math.sin(f), P = Math.cos(u), x = Math.sin(u), O = Math.tan(M / 4), v = 4 / 3 * n * O, L = 4 / 3 * o * O, z = [a, t], q = [a + v * b, t - L * k], A = [s + v * x, e - L * P], $ = [s, e];
  if (q[0] = 2 * z[0] - q[0], q[1] = 2 * z[1] - q[1], c)
    return [q, A, $].concat(p);
  {
    p = [q, A, $].concat(p);
    const T = [];
    for (let w = 0; w < p.length; w += 3) {
      const S = B(p[w][0], p[w][1], l), D = B(p[w + 1][0], p[w + 1][1], l), W = B(p[w + 2][0], p[w + 2][1], l);
      T.push([S[0], S[1], D[0], D[1], W[0], W[1]]);
    }
    return T;
  }
}
const _e = {
  randOffset: Ee,
  randOffsetWithRange: qe,
  ellipse: We,
  doubleLineOps: $e
};
function he(a, t, s, e, n) {
  return { type: "path", ops: G(a, t, s, e, n) };
}
function ot(a, t, s) {
  const e = (a || []).length;
  if (e > 2) {
    const n = [];
    for (let o = 0; o < e - 1; o++)
      n.push(...G(a[o][0], a[o][1], a[o + 1][0], a[o + 1][1], s));
    return t && n.push(...G(a[e - 1][0], a[e - 1][1], a[0][0], a[0][1], s)), { type: "path", ops: n };
  } else if (e === 2)
    return he(a[0][0], a[0][1], a[1][0], a[1][1], s);
  return { type: "path", ops: [] };
}
function Ce(a, t) {
  return ot(a, !0, t);
}
function ze(a, t, s, e, n) {
  const o = [
    [a, t],
    [a + s, t],
    [a + s, t + e],
    [a, t + e]
  ];
  return Ce(o, n);
}
function jt(a, t) {
  let s = Nt(a, 1 * (1 + t.roughness * 0.2), t);
  if (!t.disableMultiStroke) {
    const e = Nt(a, 1.5 * (1 + t.roughness * 0.22), Re(t));
    s = s.concat(e);
  }
  return { type: "path", ops: s };
}
function We(a, t, s, e, n) {
  const o = ie(s, e, n);
  return At(a, t, n, o).opset;
}
function ie(a, t, s) {
  const e = Math.sqrt(Math.PI * 2 * Math.sqrt((Math.pow(a / 2, 2) + Math.pow(t / 2, 2)) / 2)), n = Math.ceil(Math.max(s.curveStepCount, s.curveStepCount / Math.sqrt(200) * e)), o = Math.PI * 2 / n;
  let h = Math.abs(a / 2), r = Math.abs(t / 2);
  const i = 1 - s.curveFitting;
  return h += m(h * i, s), r += m(r * i, s), { increment: o, rx: h, ry: r };
}
function At(a, t, s, e) {
  const [n, o] = Qt(e.increment, a, t, e.rx, e.ry, 1, e.increment * lt(0.1, lt(0.4, 1, s), s), s);
  let h = ut(n, null, s);
  if (!s.disableMultiStroke && s.roughness !== 0) {
    const [r] = Qt(e.increment, a, t, e.rx, e.ry, 1.5, 0, s), i = ut(r, null, s);
    h = h.concat(i);
  }
  return {
    estimatedPoints: o,
    opset: { type: "path", ops: h }
  };
}
function Vt(a, t, s, e, n, o, h, r, i) {
  const c = a, l = t;
  let p = Math.abs(s / 2), f = Math.abs(e / 2);
  p += m(p * 0.01, i), f += m(f * 0.01, i);
  let u = n, d = o;
  for (; u < 0; )
    u += Math.PI * 2, d += Math.PI * 2;
  d - u > Math.PI * 2 && (u = 0, d = Math.PI * 2);
  const g = Math.PI * 2 / i.curveStepCount, M = Math.min(g / 2, (d - u) / 2), k = Bt(M, c, l, p, f, u, d, 1, i);
  if (!i.disableMultiStroke) {
    const b = Bt(M, c, l, p, f, u, d, 1.5, i);
    k.push(...b);
  }
  return h && (r ? k.push(...G(c, l, c + p * Math.cos(u), l + f * Math.sin(u), i), ...G(c, l, c + p * Math.cos(d), l + f * Math.sin(d), i)) : k.push({ op: "lineTo", data: [c, l] }, { op: "lineTo", data: [c + p * Math.cos(u), l + f * Math.sin(u)] })), { type: "path", ops: k };
}
function Zt(a, t) {
  const s = oe(ae(Rt(a))), e = [];
  let n = [0, 0], o = [0, 0];
  for (const { key: h, data: r } of s)
    switch (h) {
      case "M": {
        o = [r[0], r[1]], n = [r[0], r[1]];
        break;
      }
      case "L":
        e.push(...G(o[0], o[1], r[0], r[1], t)), o = [r[0], r[1]];
        break;
      case "C": {
        const [i, c, l, p, f, u] = r;
        e.push(...Ge(i, c, l, p, f, u, o, t)), o = [f, u];
        break;
      }
      case "Z":
        e.push(...G(o[0], o[1], n[0], n[1], t)), o = [n[0], n[1]];
        break;
    }
  return { type: "path", ops: e };
}
function wt(a, t) {
  const s = [];
  for (const e of a)
    if (e.length) {
      const n = t.maxRandomnessOffset || 0, o = e.length;
      if (o > 2) {
        s.push({ op: "move", data: [e[0][0] + m(n, t), e[0][1] + m(n, t)] });
        for (let h = 1; h < o; h++)
          s.push({ op: "lineTo", data: [e[h][0] + m(n, t), e[h][1] + m(n, t)] });
      }
    }
  return { type: "fillPath", ops: s };
}
function N(a, t) {
  return Oe(t, _e).fillPolygons(a, t);
}
function Ie(a, t, s, e, n, o, h) {
  const r = a, i = t;
  let c = Math.abs(s / 2), l = Math.abs(e / 2);
  c += m(c * 0.01, h), l += m(l * 0.01, h);
  let p = n, f = o;
  for (; p < 0; )
    p += Math.PI * 2, f += Math.PI * 2;
  f - p > Math.PI * 2 && (p = 0, f = Math.PI * 2);
  const u = (f - p) / h.curveStepCount, d = [];
  for (let g = p; g <= f; g = g + u)
    d.push([r + c * Math.cos(g), i + l * Math.sin(g)]);
  return d.push([r + c * Math.cos(f), i + l * Math.sin(f)]), d.push([r, i]), N([d], h);
}
function Ee(a, t) {
  return m(a, t);
}
function qe(a, t, s) {
  return lt(a, t, s);
}
function $e(a, t, s, e, n) {
  return G(a, t, s, e, n, !0);
}
function Re(a) {
  const t = Object.assign({}, a);
  return t.randomizer = void 0, a.seed && (t.seed = a.seed + 1), t;
}
function ce(a) {
  return a.randomizer || (a.randomizer = new Le(a.seed || 0)), a.randomizer.next();
}
function lt(a, t, s, e = 1) {
  return s.roughness * e * (ce(s) * (t - a) + a);
}
function m(a, t, s = 1) {
  return lt(-a, a, t, s);
}
function G(a, t, s, e, n, o = !1) {
  const h = o ? n.disableMultiStrokeFill : n.disableMultiStroke, r = Ht(a, t, s, e, n, !0, !1);
  if (h)
    return r;
  const i = Ht(a, t, s, e, n, !0, !0);
  return r.concat(i);
}
function Ht(a, t, s, e, n, o, h) {
  const r = Math.pow(a - s, 2) + Math.pow(t - e, 2), i = Math.sqrt(r);
  let c = 1;
  i < 200 ? c = 1 : i > 500 ? c = 0.4 : c = -16668e-7 * i + 1.233334;
  let l = n.maxRandomnessOffset || 0;
  l * l * 100 > r && (l = i / 10);
  const p = l / 2, f = 0.2 + ce(n) * 0.2;
  let u = n.bowing * n.maxRandomnessOffset * (e - t) / 200, d = n.bowing * n.maxRandomnessOffset * (a - s) / 200;
  u = m(u, n, c), d = m(d, n, c);
  const g = [], M = () => m(p, n, c), k = () => m(l, n, c), b = n.preserveVertices;
  return h ? g.push({
    op: "move",
    data: [
      a + (b ? 0 : M()),
      t + (b ? 0 : M())
    ]
  }) : g.push({
    op: "move",
    data: [
      a + (b ? 0 : m(l, n, c)),
      t + (b ? 0 : m(l, n, c))
    ]
  }), h ? g.push({
    op: "bcurveTo",
    data: [
      u + a + (s - a) * f + M(),
      d + t + (e - t) * f + M(),
      u + a + 2 * (s - a) * f + M(),
      d + t + 2 * (e - t) * f + M(),
      s + (b ? 0 : M()),
      e + (b ? 0 : M())
    ]
  }) : g.push({
    op: "bcurveTo",
    data: [
      u + a + (s - a) * f + k(),
      d + t + (e - t) * f + k(),
      u + a + 2 * (s - a) * f + k(),
      d + t + 2 * (e - t) * f + k(),
      s + (b ? 0 : k()),
      e + (b ? 0 : k())
    ]
  }), g;
}
function Nt(a, t, s) {
  const e = [];
  e.push([
    a[0][0] + m(t, s),
    a[0][1] + m(t, s)
  ]), e.push([
    a[0][0] + m(t, s),
    a[0][1] + m(t, s)
  ]);
  for (let n = 1; n < a.length; n++)
    e.push([
      a[n][0] + m(t, s),
      a[n][1] + m(t, s)
    ]), n === a.length - 1 && e.push([
      a[n][0] + m(t, s),
      a[n][1] + m(t, s)
    ]);
  return ut(e, null, s);
}
function ut(a, t, s) {
  const e = a.length, n = [];
  if (e > 3) {
    const o = [], h = 1 - s.curveTightness;
    n.push({ op: "move", data: [a[1][0], a[1][1]] });
    for (let r = 1; r + 2 < e; r++) {
      const i = a[r];
      o[0] = [i[0], i[1]], o[1] = [i[0] + (h * a[r + 1][0] - h * a[r - 1][0]) / 6, i[1] + (h * a[r + 1][1] - h * a[r - 1][1]) / 6], o[2] = [a[r + 1][0] + (h * a[r][0] - h * a[r + 2][0]) / 6, a[r + 1][1] + (h * a[r][1] - h * a[r + 2][1]) / 6], o[3] = [a[r + 1][0], a[r + 1][1]], n.push({ op: "bcurveTo", data: [o[1][0], o[1][1], o[2][0], o[2][1], o[3][0], o[3][1]] });
    }
  } else e === 3 ? (n.push({ op: "move", data: [a[1][0], a[1][1]] }), n.push({
    op: "bcurveTo",
    data: [
      a[1][0],
      a[1][1],
      a[2][0],
      a[2][1],
      a[2][0],
      a[2][1]
    ]
  })) : e === 2 && n.push(...G(a[0][0], a[0][1], a[1][0], a[1][1], s));
  return n;
}
function Qt(a, t, s, e, n, o, h, r) {
  const i = r.roughness === 0, c = [], l = [];
  if (i) {
    a = a / 4, l.push([
      t + e * Math.cos(-a),
      s + n * Math.sin(-a)
    ]);
    for (let p = 0; p <= Math.PI * 2; p = p + a) {
      const f = [
        t + e * Math.cos(p),
        s + n * Math.sin(p)
      ];
      c.push(f), l.push(f);
    }
    l.push([
      t + e * Math.cos(0),
      s + n * Math.sin(0)
    ]), l.push([
      t + e * Math.cos(a),
      s + n * Math.sin(a)
    ]);
  } else {
    const p = m(0.5, r) - Math.PI / 2;
    l.push([
      m(o, r) + t + 0.9 * e * Math.cos(p - a),
      m(o, r) + s + 0.9 * n * Math.sin(p - a)
    ]);
    const f = Math.PI * 2 + p - 0.01;
    for (let u = p; u < f; u = u + a) {
      const d = [
        m(o, r) + t + e * Math.cos(u),
        m(o, r) + s + n * Math.sin(u)
      ];
      c.push(d), l.push(d);
    }
    l.push([
      m(o, r) + t + e * Math.cos(p + Math.PI * 2 + h * 0.5),
      m(o, r) + s + n * Math.sin(p + Math.PI * 2 + h * 0.5)
    ]), l.push([
      m(o, r) + t + 0.98 * e * Math.cos(p + h),
      m(o, r) + s + 0.98 * n * Math.sin(p + h)
    ]), l.push([
      m(o, r) + t + 0.9 * e * Math.cos(p + h * 0.5),
      m(o, r) + s + 0.9 * n * Math.sin(p + h * 0.5)
    ]);
  }
  return [l, c];
}
function Bt(a, t, s, e, n, o, h, r, i) {
  const c = o + m(0.1, i), l = [];
  l.push([
    m(r, i) + t + 0.9 * e * Math.cos(c - a),
    m(r, i) + s + 0.9 * n * Math.sin(c - a)
  ]);
  for (let p = c; p <= h; p = p + a)
    l.push([
      m(r, i) + t + e * Math.cos(p),
      m(r, i) + s + n * Math.sin(p)
    ]);
  return l.push([
    t + e * Math.cos(h),
    s + n * Math.sin(h)
  ]), l.push([
    t + e * Math.cos(h),
    s + n * Math.sin(h)
  ]), ut(l, null, i);
}
function Ge(a, t, s, e, n, o, h, r) {
  const i = [], c = [r.maxRandomnessOffset || 1, (r.maxRandomnessOffset || 1) + 0.3];
  let l = [0, 0];
  const p = r.disableMultiStroke ? 1 : 2, f = r.preserveVertices;
  for (let u = 0; u < p; u++)
    u === 0 ? i.push({ op: "move", data: [h[0], h[1]] }) : i.push({ op: "move", data: [h[0] + (f ? 0 : m(c[0], r)), h[1] + (f ? 0 : m(c[0], r))] }), l = f ? [n, o] : [n + m(c[u], r), o + m(c[u], r)], i.push({
      op: "bcurveTo",
      data: [
        a + m(c[u], r),
        t + m(c[u], r),
        s + m(c[u], r),
        e + m(c[u], r),
        l[0],
        l[1]
      ]
    });
  return i;
}
function Y(a) {
  return [...a];
}
function Fe(a, t = 0) {
  const s = a.length;
  if (s < 3)
    throw new Error("A curve must have at least three points.");
  const e = [];
  if (s === 3)
    e.push(Y(a[0]), Y(a[1]), Y(a[2]), Y(a[2]));
  else {
    const n = [];
    n.push(a[0], a[0]);
    for (let r = 1; r < a.length; r++)
      n.push(a[r]), r === a.length - 1 && n.push(a[r]);
    const o = [], h = 1 - t;
    e.push(Y(n[0]));
    for (let r = 1; r + 2 < n.length; r++) {
      const i = n[r];
      o[0] = [i[0], i[1]], o[1] = [i[0] + (h * n[r + 1][0] - h * n[r - 1][0]) / 6, i[1] + (h * n[r + 1][1] - h * n[r - 1][1]) / 6], o[2] = [n[r + 1][0] + (h * n[r][0] - h * n[r + 2][0]) / 6, n[r + 1][1] + (h * n[r][1] - h * n[r + 2][1]) / 6], o[3] = [n[r + 1][0], n[r + 1][1]], e.push(o[1], o[2], o[3]);
    }
  }
  return e;
}
function je(a, t) {
  return Math.sqrt(rt(a, t));
}
function rt(a, t) {
  return Math.pow(a[0] - t[0], 2) + Math.pow(a[1] - t[1], 2);
}
function Ve(a, t, s) {
  const e = rt(t, s);
  if (e === 0)
    return rt(a, t);
  let n = ((a[0] - t[0]) * (s[0] - t[0]) + (a[1] - t[1]) * (s[1] - t[1])) / e;
  return n = Math.max(0, Math.min(1, n)), rt(a, j(t, s, n));
}
function j(a, t, s) {
  return [
    a[0] + (t[0] - a[0]) * s,
    a[1] + (t[1] - a[1]) * s
  ];
}
function Ze(a, t) {
  const s = a[t + 0], e = a[t + 1], n = a[t + 2], o = a[t + 3];
  let h = 3 * e[0] - 2 * s[0] - o[0];
  h *= h;
  let r = 3 * e[1] - 2 * s[1] - o[1];
  r *= r;
  let i = 3 * n[0] - 2 * o[0] - s[0];
  i *= i;
  let c = 3 * n[1] - 2 * o[1] - s[1];
  return c *= c, h < i && (h = i), r < c && (r = c), h + r;
}
function _t(a, t, s, e) {
  const n = e || [];
  if (Ze(a, t) < s) {
    const o = a[t + 0];
    n.length ? je(n[n.length - 1], o) > 1 && n.push(o) : n.push(o), n.push(a[t + 3]);
  } else {
    const h = a[t + 0], r = a[t + 1], i = a[t + 2], c = a[t + 3], l = j(h, r, 0.5), p = j(r, i, 0.5), f = j(i, c, 0.5), u = j(l, p, 0.5), d = j(p, f, 0.5), g = j(u, d, 0.5);
    _t([h, l, u, g], 0, s, n), _t([g, d, f, c], 0, s, n);
  }
  return n;
}
function Ct(a, t, s, e, n) {
  const o = n || [], h = a[t], r = a[s - 1];
  let i = 0, c = 1;
  for (let l = t + 1; l < s - 1; ++l) {
    const p = Ve(a[l], h, r);
    p > i && (i = p, c = l);
  }
  return Math.sqrt(i) > e ? (Ct(a, t, c + 1, e, o), Ct(a, c, s, e, o)) : (o.length || o.push(h), o.push(r)), o;
}
function He(a, t = 0.15, s) {
  const e = [], n = (a.length - 1) / 3;
  for (let o = 0; o < n; o++) {
    const h = o * 3;
    _t(a, h, t, e);
  }
  return s && s > 0 ? Ct(e, 0, e.length, s) : e;
}
function Ne(a, t) {
  return Math.sqrt(ht(a, t));
}
function ht(a, t) {
  return Math.pow(a[0] - t[0], 2) + Math.pow(a[1] - t[1], 2);
}
function Qe(a, t, s) {
  const e = ht(t, s);
  if (e === 0)
    return ht(a, t);
  let n = ((a[0] - t[0]) * (s[0] - t[0]) + (a[1] - t[1]) * (s[1] - t[1])) / e;
  return n = Math.max(0, Math.min(1, n)), ht(a, V(t, s, n));
}
function V(a, t, s) {
  return [
    a[0] + (t[0] - a[0]) * s,
    a[1] + (t[1] - a[1]) * s
  ];
}
function Be(a, t) {
  const s = a[t + 0], e = a[t + 1], n = a[t + 2], o = a[t + 3];
  let h = 3 * e[0] - 2 * s[0] - o[0];
  h *= h;
  let r = 3 * e[1] - 2 * s[1] - o[1];
  r *= r;
  let i = 3 * n[0] - 2 * o[0] - s[0];
  i *= i;
  let c = 3 * n[1] - 2 * o[1] - s[1];
  return c *= c, h < i && (h = i), r < c && (r = c), h + r;
}
function zt(a, t, s, e) {
  const n = e || [];
  if (Be(a, t) < s) {
    const o = a[t + 0];
    n.length ? Ne(n[n.length - 1], o) > 1 && n.push(o) : n.push(o), n.push(a[t + 3]);
  } else {
    const h = a[t + 0], r = a[t + 1], i = a[t + 2], c = a[t + 3], l = V(h, r, 0.5), p = V(r, i, 0.5), f = V(i, c, 0.5), u = V(l, p, 0.5), d = V(p, f, 0.5), g = V(u, d, 0.5);
    zt([h, l, u, g], 0, s, n), zt([g, d, f, c], 0, s, n);
  }
  return n;
}
function Ye(a, t) {
  return Wt(a, 0, a.length, t);
}
function Wt(a, t, s, e, n) {
  const o = n || [], h = a[t], r = a[s - 1];
  let i = 0, c = 1;
  for (let l = t + 1; l < s - 1; ++l) {
    const p = Qe(a[l], h, r);
    p > i && (i = p, c = l);
  }
  return Math.sqrt(i) > e ? (Wt(a, t, c + 1, e, o), Wt(a, c, s, e, o)) : (o.length || o.push(h), o.push(r)), o;
}
function Xe(a, t = 0.15, s) {
  const e = [], n = (a.length - 1) / 3;
  for (let o = 0; o < n; o++) {
    const h = o * 3;
    zt(a, h, t, e);
  }
  return e;
}
function Ue(a, t, s) {
  const e = Rt(a), n = oe(ae(e)), o = [];
  let h = [], r = [0, 0], i = [];
  const c = () => {
    i.length >= 4 && h.push(...Xe(i, t)), i = [];
  }, l = () => {
    c(), h.length && (o.push(h), h = []);
  };
  for (const { key: f, data: u } of n)
    switch (f) {
      case "M":
        l(), r = [u[0], u[1]], h.push(r);
        break;
      case "L":
        c(), h.push([u[0], u[1]]);
        break;
      case "C":
        if (!i.length) {
          const d = h.length ? h[h.length - 1] : r;
          i.push([d[0], d[1]]);
        }
        i.push([u[0], u[1]]), i.push([u[2], u[3]]), i.push([u[4], u[5]]);
        break;
      case "Z":
        c(), h.push([r[0], r[1]]);
        break;
    }
  if (l(), !s)
    return o;
  const p = [];
  for (const f of o) {
    const u = Ye(f, s);
    u.length && p.push(u);
  }
  return p;
}
const I = "none";
class ft {
  constructor(t) {
    this.defaultOptions = {
      maxRandomnessOffset: 2,
      roughness: 1,
      bowing: 1,
      stroke: "#000",
      strokeWidth: 1,
      curveTightness: 0,
      curveFitting: 0.95,
      curveStepCount: 9,
      fillStyle: "hachure",
      fillWeight: -1,
      hachureAngle: -41,
      hachureGap: -1,
      dashOffset: -1,
      dashGap: -1,
      zigzagOffset: -1,
      seed: 0,
      disableMultiStroke: !1,
      disableMultiStrokeFill: !1,
      preserveVertices: !1,
      fillShapeRoughnessGain: 0.8
    }, this.config = t || {}, this.config.options && (this.defaultOptions = this._o(this.config.options));
  }
  static newSeed() {
    return xe();
  }
  _o(t) {
    return t ? Object.assign({}, this.defaultOptions, t) : this.defaultOptions;
  }
  _d(t, s, e) {
    return { shape: t, sets: s || [], options: e || this.defaultOptions };
  }
  line(t, s, e, n, o) {
    const h = this._o(o);
    return this._d("line", [he(t, s, e, n, h)], h);
  }
  rectangle(t, s, e, n, o) {
    const h = this._o(o), r = [], i = ze(t, s, e, n, h);
    if (h.fill) {
      const c = [[t, s], [t + e, s], [t + e, s + n], [t, s + n]];
      h.fillStyle === "solid" ? r.push(wt([c], h)) : r.push(N([c], h));
    }
    return h.stroke !== I && r.push(i), this._d("rectangle", r, h);
  }
  ellipse(t, s, e, n, o) {
    const h = this._o(o), r = [], i = ie(e, n, h), c = At(t, s, h, i);
    if (h.fill)
      if (h.fillStyle === "solid") {
        const l = At(t, s, h, i).opset;
        l.type = "fillPath", r.push(l);
      } else
        r.push(N([c.estimatedPoints], h));
    return h.stroke !== I && r.push(c.opset), this._d("ellipse", r, h);
  }
  circle(t, s, e, n) {
    const o = this.ellipse(t, s, e, e, n);
    return o.shape = "circle", o;
  }
  linearPath(t, s) {
    const e = this._o(s);
    return this._d("linearPath", [ot(t, !1, e)], e);
  }
  arc(t, s, e, n, o, h, r = !1, i) {
    const c = this._o(i), l = [], p = Vt(t, s, e, n, o, h, r, !0, c);
    if (r && c.fill)
      if (c.fillStyle === "solid") {
        const f = Object.assign({}, c);
        f.disableMultiStroke = !0;
        const u = Vt(t, s, e, n, o, h, !0, !1, f);
        u.type = "fillPath", l.push(u);
      } else
        l.push(Ie(t, s, e, n, o, h, c));
    return c.stroke !== I && l.push(p), this._d("arc", l, c);
  }
  curve(t, s) {
    const e = this._o(s), n = [], o = jt(t, e);
    if (e.fill && e.fill !== I && t.length >= 3)
      if (e.fillStyle === "solid") {
        const h = jt(t, Object.assign(Object.assign({}, e), { disableMultiStroke: !0, roughness: e.roughness ? e.roughness + e.fillShapeRoughnessGain : 0 }));
        n.push({
          type: "fillPath",
          ops: this._mergedShape(h.ops)
        });
      } else {
        const h = Fe(t), r = He(h, 10, (1 + e.roughness) / 2);
        n.push(N([r], e));
      }
    return e.stroke !== I && n.push(o), this._d("curve", n, e);
  }
  polygon(t, s) {
    const e = this._o(s), n = [], o = ot(t, !0, e);
    return e.fill && (e.fillStyle === "solid" ? n.push(wt([t], e)) : n.push(N([t], e))), e.stroke !== I && n.push(o), this._d("polygon", n, e);
  }
  path(t, s) {
    const e = this._o(s), n = [];
    if (!t)
      return this._d("path", n, e);
    t = (t || "").replace(/\n/g, " ").replace(/(-\s)/g, "-").replace("/(ss)/g", " ");
    const o = e.fill && e.fill !== "transparent" && e.fill !== I, h = e.stroke !== I, r = !!(e.simplification && e.simplification < 1), i = r ? 4 - 4 * (e.simplification || 1) : (1 + e.roughness) / 2, c = Ue(t, 1, i), l = Zt(t, e);
    if (o)
      if (e.fillStyle === "solid")
        if (c.length === 1) {
          const p = Zt(t, Object.assign(Object.assign({}, e), { disableMultiStroke: !0, roughness: e.roughness ? e.roughness + e.fillShapeRoughnessGain : 0 }));
          n.push({
            type: "fillPath",
            ops: this._mergedShape(p.ops)
          });
        } else
          n.push(wt(c, e));
      else
        n.push(N(c, e));
    return h && (r ? c.forEach((p) => {
      n.push(ot(p, !1, e));
    }) : n.push(l)), this._d("path", n, e);
  }
  opsToPath(t, s) {
    let e = "";
    for (const n of t.ops) {
      const o = typeof s == "number" && s >= 0 ? n.data.map((h) => +h.toFixed(s)) : n.data;
      switch (n.op) {
        case "move":
          e += `M${o[0]} ${o[1]} `;
          break;
        case "bcurveTo":
          e += `C${o[0]} ${o[1]}, ${o[2]} ${o[3]}, ${o[4]} ${o[5]} `;
          break;
        case "lineTo":
          e += `L${o[0]} ${o[1]} `;
          break;
      }
    }
    return e.trim();
  }
  toPaths(t) {
    const s = t.sets || [], e = t.options || this.defaultOptions, n = [];
    for (const o of s) {
      let h = null;
      switch (o.type) {
        case "path":
          h = {
            d: this.opsToPath(o),
            stroke: e.stroke,
            strokeWidth: e.strokeWidth,
            fill: I
          };
          break;
        case "fillPath":
          h = {
            d: this.opsToPath(o),
            stroke: I,
            strokeWidth: 0,
            fill: e.fill || I
          };
          break;
        case "fillSketch":
          h = this.fillSketch(o, e);
          break;
      }
      h && n.push(h);
    }
    return n;
  }
  fillSketch(t, s) {
    let e = s.fillWeight;
    return e < 0 && (e = s.strokeWidth / 2), {
      d: this.opsToPath(t),
      stroke: s.fill || I,
      strokeWidth: e,
      fill: I
    };
  }
  _mergedShape(t) {
    return t.filter((s, e) => e === 0 ? !0 : s.op !== "move");
  }
}
class Je {
  constructor(t, s) {
    this.canvas = t, this.ctx = this.canvas.getContext("2d"), this.gen = new ft(s);
  }
  draw(t) {
    const s = t.sets || [], e = t.options || this.getDefaultOptions(), n = this.ctx, o = t.options.fixedDecimalPlaceDigits;
    for (const h of s)
      switch (h.type) {
        case "path":
          n.save(), n.strokeStyle = e.stroke === "none" ? "transparent" : e.stroke, n.lineWidth = e.strokeWidth, e.strokeLineDash && n.setLineDash(e.strokeLineDash), e.strokeLineDashOffset && (n.lineDashOffset = e.strokeLineDashOffset), this._drawToContext(n, h, o), n.restore();
          break;
        case "fillPath": {
          n.save(), n.fillStyle = e.fill || "";
          const r = t.shape === "curve" || t.shape === "polygon" || t.shape === "path" ? "evenodd" : "nonzero";
          this._drawToContext(n, h, o, r), n.restore();
          break;
        }
        case "fillSketch":
          this.fillSketch(n, h, e);
          break;
      }
  }
  fillSketch(t, s, e) {
    let n = e.fillWeight;
    n < 0 && (n = e.strokeWidth / 2), t.save(), e.fillLineDash && t.setLineDash(e.fillLineDash), e.fillLineDashOffset && (t.lineDashOffset = e.fillLineDashOffset), t.strokeStyle = e.fill || "", t.lineWidth = n, this._drawToContext(t, s, e.fixedDecimalPlaceDigits), t.restore();
  }
  _drawToContext(t, s, e, n = "nonzero") {
    t.beginPath();
    for (const o of s.ops) {
      const h = typeof e == "number" && e >= 0 ? o.data.map((r) => +r.toFixed(e)) : o.data;
      switch (o.op) {
        case "move":
          t.moveTo(h[0], h[1]);
          break;
        case "bcurveTo":
          t.bezierCurveTo(h[0], h[1], h[2], h[3], h[4], h[5]);
          break;
        case "lineTo":
          t.lineTo(h[0], h[1]);
          break;
      }
    }
    s.type === "fillPath" ? t.fill(n) : t.stroke();
  }
  get generator() {
    return this.gen;
  }
  getDefaultOptions() {
    return this.gen.defaultOptions;
  }
  line(t, s, e, n, o) {
    const h = this.gen.line(t, s, e, n, o);
    return this.draw(h), h;
  }
  rectangle(t, s, e, n, o) {
    const h = this.gen.rectangle(t, s, e, n, o);
    return this.draw(h), h;
  }
  ellipse(t, s, e, n, o) {
    const h = this.gen.ellipse(t, s, e, n, o);
    return this.draw(h), h;
  }
  circle(t, s, e, n) {
    const o = this.gen.circle(t, s, e, n);
    return this.draw(o), o;
  }
  linearPath(t, s) {
    const e = this.gen.linearPath(t, s);
    return this.draw(e), e;
  }
  polygon(t, s) {
    const e = this.gen.polygon(t, s);
    return this.draw(e), e;
  }
  arc(t, s, e, n, o, h, r = !1, i) {
    const c = this.gen.arc(t, s, e, n, o, h, r, i);
    return this.draw(c), c;
  }
  curve(t, s) {
    const e = this.gen.curve(t, s);
    return this.draw(e), e;
  }
  path(t, s) {
    const e = this.gen.path(t, s);
    return this.draw(e), e;
  }
}
const et = "http://www.w3.org/2000/svg";
class Ke {
  constructor(t, s) {
    this.svg = t, this.gen = new ft(s);
  }
  draw(t) {
    const s = t.sets || [], e = t.options || this.getDefaultOptions(), n = this.svg.ownerDocument || window.document, o = n.createElementNS(et, "g"), h = t.options.fixedDecimalPlaceDigits;
    for (const r of s) {
      let i = null;
      switch (r.type) {
        case "path": {
          i = n.createElementNS(et, "path"), i.setAttribute("d", this.opsToPath(r, h)), i.setAttribute("stroke", e.stroke), i.setAttribute("stroke-width", e.strokeWidth + ""), i.setAttribute("fill", "none"), e.strokeLineDash && i.setAttribute("stroke-dasharray", e.strokeLineDash.join(" ").trim()), e.strokeLineDashOffset && i.setAttribute("stroke-dashoffset", `${e.strokeLineDashOffset}`);
          break;
        }
        case "fillPath": {
          i = n.createElementNS(et, "path"), i.setAttribute("d", this.opsToPath(r, h)), i.setAttribute("stroke", "none"), i.setAttribute("stroke-width", "0"), i.setAttribute("fill", e.fill || ""), (t.shape === "curve" || t.shape === "polygon") && i.setAttribute("fill-rule", "evenodd");
          break;
        }
        case "fillSketch": {
          i = this.fillSketch(n, r, e);
          break;
        }
      }
      i && o.appendChild(i);
    }
    return o;
  }
  fillSketch(t, s, e) {
    let n = e.fillWeight;
    n < 0 && (n = e.strokeWidth / 2);
    const o = t.createElementNS(et, "path");
    return o.setAttribute("d", this.opsToPath(s, e.fixedDecimalPlaceDigits)), o.setAttribute("stroke", e.fill || ""), o.setAttribute("stroke-width", n + ""), o.setAttribute("fill", "none"), e.fillLineDash && o.setAttribute("stroke-dasharray", e.fillLineDash.join(" ").trim()), e.fillLineDashOffset && o.setAttribute("stroke-dashoffset", `${e.fillLineDashOffset}`), o;
  }
  get generator() {
    return this.gen;
  }
  getDefaultOptions() {
    return this.gen.defaultOptions;
  }
  opsToPath(t, s) {
    return this.gen.opsToPath(t, s);
  }
  line(t, s, e, n, o) {
    const h = this.gen.line(t, s, e, n, o);
    return this.draw(h);
  }
  rectangle(t, s, e, n, o) {
    const h = this.gen.rectangle(t, s, e, n, o);
    return this.draw(h);
  }
  ellipse(t, s, e, n, o) {
    const h = this.gen.ellipse(t, s, e, n, o);
    return this.draw(h);
  }
  circle(t, s, e, n) {
    const o = this.gen.circle(t, s, e, n);
    return this.draw(o);
  }
  linearPath(t, s) {
    const e = this.gen.linearPath(t, s);
    return this.draw(e);
  }
  polygon(t, s) {
    const e = this.gen.polygon(t, s);
    return this.draw(e);
  }
  arc(t, s, e, n, o, h, r = !1, i) {
    const c = this.gen.arc(t, s, e, n, o, h, r, i);
    return this.draw(c);
  }
  curve(t, s) {
    const e = this.gen.curve(t, s);
    return this.draw(e);
  }
  path(t, s) {
    const e = this.gen.path(t, s);
    return this.draw(e);
  }
}
const Ms = {
  canvas(a, t) {
    return new Je(a, t);
  },
  svg(a, t) {
    return new Ke(a, t);
  },
  generator(a) {
    return new ft(a);
  },
  newSeed() {
    return ft.newSeed();
  }
};
function St(a, t, s) {
  if (a && a.length) {
    const [e, n] = t, o = Math.PI / 180 * s, h = Math.cos(o), r = Math.sin(o);
    for (const i of a) {
      const [c, l] = i;
      i[0] = (c - e) * h - (l - n) * r + e, i[1] = (c - e) * r + (l - n) * h + n;
    }
  }
}
function ts(a, t) {
  return a[0] === t[0] && a[1] === t[1];
}
function es(a, t, s, e = 1) {
  const n = s, o = Math.max(t, 0.1), h = a[0] && a[0][0] && typeof a[0][0] == "number" ? [a] : a, r = [0, 0];
  if (n) for (const c of h) St(c, r, n);
  const i = (function(c, l, p) {
    const f = [];
    for (const b of c) {
      const P = [...b];
      ts(P[0], P[P.length - 1]) || P.push([P[0][0], P[0][1]]), P.length > 2 && f.push(P);
    }
    const u = [];
    l = Math.max(l, 0.1);
    const d = [];
    for (const b of f) for (let P = 0; P < b.length - 1; P++) {
      const x = b[P], O = b[P + 1];
      if (x[1] !== O[1]) {
        const v = Math.min(x[1], O[1]);
        d.push({ ymin: v, ymax: Math.max(x[1], O[1]), x: v === x[1] ? x[0] : O[0], islope: (O[0] - x[0]) / (O[1] - x[1]) });
      }
    }
    if (d.sort(((b, P) => b.ymin < P.ymin ? -1 : b.ymin > P.ymin ? 1 : b.x < P.x ? -1 : b.x > P.x ? 1 : b.ymax === P.ymax ? 0 : (b.ymax - P.ymax) / Math.abs(b.ymax - P.ymax))), !d.length) return u;
    let g = [], M = d[0].ymin, k = 0;
    for (; g.length || d.length; ) {
      if (d.length) {
        let b = -1;
        for (let P = 0; P < d.length && !(d[P].ymin > M); P++) b = P;
        d.splice(0, b + 1).forEach(((P) => {
          g.push({ s: M, edge: P });
        }));
      }
      if (g = g.filter(((b) => !(b.edge.ymax <= M))), g.sort(((b, P) => b.edge.x === P.edge.x ? 0 : (b.edge.x - P.edge.x) / Math.abs(b.edge.x - P.edge.x))), (p !== 1 || k % l == 0) && g.length > 1) for (let b = 0; b < g.length; b += 2) {
        const P = b + 1;
        if (P >= g.length) break;
        const x = g[b].edge, O = g[P].edge;
        u.push([[Math.round(x.x), M], [Math.round(O.x), M]]);
      }
      M += p, g.forEach(((b) => {
        b.edge.x = b.edge.x + p * b.edge.islope;
      })), k++;
    }
    return u;
  })(h, o, e);
  if (n) {
    for (const c of h) St(c, r, -n);
    (function(c, l, p) {
      const f = [];
      c.forEach(((u) => f.push(...u))), St(f, l, p);
    })(i, r, -n);
  }
  return i;
}
function K(a, t) {
  var s;
  const e = t.hachureAngle + 90;
  let n = t.hachureGap;
  n < 0 && (n = 4 * t.strokeWidth), n = Math.round(Math.max(n, 0.1));
  let o = 1;
  return t.roughness >= 1 && (((s = t.randomizer) === null || s === void 0 ? void 0 : s.next()) || Math.random()) > 0.7 && (o = n), es(a, n, e, o || 1);
}
class Gt {
  constructor(t) {
    this.helper = t;
  }
  fillPolygons(t, s) {
    return this._fillPolygons(t, s);
  }
  _fillPolygons(t, s) {
    const e = K(t, s);
    return { type: "fillSketch", ops: this.renderLines(e, s) };
  }
  renderLines(t, s) {
    const e = [];
    for (const n of t) e.push(...this.helper.doubleLineOps(n[0][0], n[0][1], n[1][0], n[1][1], s));
    return e;
  }
}
function bt(a) {
  const t = a[0], s = a[1];
  return Math.sqrt(Math.pow(t[0] - s[0], 2) + Math.pow(t[1] - s[1], 2));
}
class ss extends Gt {
  fillPolygons(t, s) {
    let e = s.hachureGap;
    e < 0 && (e = 4 * s.strokeWidth), e = Math.max(e, 0.1);
    const n = K(t, Object.assign({}, s, { hachureGap: e })), o = Math.PI / 180 * s.hachureAngle, h = [], r = 0.5 * e * Math.cos(o), i = 0.5 * e * Math.sin(o);
    for (const [c, l] of n) bt([c, l]) && h.push([[c[0] - r, c[1] + i], [...l]], [[c[0] + r, c[1] - i], [...l]]);
    return { type: "fillSketch", ops: this.renderLines(h, s) };
  }
}
class ns extends Gt {
  fillPolygons(t, s) {
    const e = this._fillPolygons(t, s), n = Object.assign({}, s, { hachureAngle: s.hachureAngle + 90 }), o = this._fillPolygons(t, n);
    return e.ops = e.ops.concat(o.ops), e;
  }
}
class as {
  constructor(t) {
    this.helper = t;
  }
  fillPolygons(t, s) {
    const e = K(t, s = Object.assign({}, s, { hachureAngle: 0 }));
    return this.dotsOnLines(e, s);
  }
  dotsOnLines(t, s) {
    const e = [];
    let n = s.hachureGap;
    n < 0 && (n = 4 * s.strokeWidth), n = Math.max(n, 0.1);
    let o = s.fillWeight;
    o < 0 && (o = s.strokeWidth / 2);
    const h = n / 4;
    for (const r of t) {
      const i = bt(r), c = i / n, l = Math.ceil(c) - 1, p = i - l * n, f = (r[0][0] + r[1][0]) / 2 - n / 4, u = Math.min(r[0][1], r[1][1]);
      for (let d = 0; d < l; d++) {
        const g = u + p + d * n, M = f - h + 2 * Math.random() * h, k = g - h + 2 * Math.random() * h, b = this.helper.ellipse(M, k, o, o, s);
        e.push(...b.ops);
      }
    }
    return { type: "fillSketch", ops: e };
  }
}
class os {
  constructor(t) {
    this.helper = t;
  }
  fillPolygons(t, s) {
    const e = K(t, s);
    return { type: "fillSketch", ops: this.dashedLine(e, s) };
  }
  dashedLine(t, s) {
    const e = s.dashOffset < 0 ? s.hachureGap < 0 ? 4 * s.strokeWidth : s.hachureGap : s.dashOffset, n = s.dashGap < 0 ? s.hachureGap < 0 ? 4 * s.strokeWidth : s.hachureGap : s.dashGap, o = [];
    return t.forEach(((h) => {
      const r = bt(h), i = Math.floor(r / (e + n)), c = (r + n - i * (e + n)) / 2;
      let l = h[0], p = h[1];
      l[0] > p[0] && (l = h[1], p = h[0]);
      const f = Math.atan((p[1] - l[1]) / (p[0] - l[0]));
      for (let u = 0; u < i; u++) {
        const d = u * (e + n), g = d + e, M = [l[0] + d * Math.cos(f) + c * Math.cos(f), l[1] + d * Math.sin(f) + c * Math.sin(f)], k = [l[0] + g * Math.cos(f) + c * Math.cos(f), l[1] + g * Math.sin(f) + c * Math.sin(f)];
        o.push(...this.helper.doubleLineOps(M[0], M[1], k[0], k[1], s));
      }
    })), o;
  }
}
class rs {
  constructor(t) {
    this.helper = t;
  }
  fillPolygons(t, s) {
    const e = s.hachureGap < 0 ? 4 * s.strokeWidth : s.hachureGap, n = s.zigzagOffset < 0 ? e : s.zigzagOffset, o = K(t, s = Object.assign({}, s, { hachureGap: e + n }));
    return { type: "fillSketch", ops: this.zigzagLines(o, n, s) };
  }
  zigzagLines(t, s, e) {
    const n = [];
    return t.forEach(((o) => {
      const h = bt(o), r = Math.round(h / (2 * s));
      let i = o[0], c = o[1];
      i[0] > c[0] && (i = o[1], c = o[0]);
      const l = Math.atan((c[1] - i[1]) / (c[0] - i[0]));
      for (let p = 0; p < r; p++) {
        const f = 2 * p * s, u = 2 * (p + 1) * s, d = Math.sqrt(2 * Math.pow(s, 2)), g = [i[0] + f * Math.cos(l), i[1] + f * Math.sin(l)], M = [i[0] + u * Math.cos(l), i[1] + u * Math.sin(l)], k = [g[0] + d * Math.cos(l + Math.PI / 4), g[1] + d * Math.sin(l + Math.PI / 4)];
        n.push(...this.helper.doubleLineOps(g[0], g[1], k[0], k[1], e), ...this.helper.doubleLineOps(k[0], k[1], M[0], M[1], e));
      }
    })), n;
  }
}
const C = {};
class hs {
  constructor(t) {
    this.seed = t;
  }
  next() {
    return this.seed ? (2 ** 31 - 1 & (this.seed = Math.imul(48271, this.seed))) / 2 ** 31 : Math.random();
  }
}
const is = 0, vt = 1, Yt = 2, st = { A: 7, a: 7, C: 6, c: 6, H: 1, h: 1, L: 2, l: 2, M: 2, m: 2, Q: 4, q: 4, S: 4, s: 4, T: 2, t: 2, V: 1, v: 1, Z: 0, z: 0 };
function Ot(a, t) {
  return a.type === t;
}
function Ft(a) {
  const t = [], s = (function(h) {
    const r = new Array();
    for (; h !== ""; ) if (h.match(/^([ \t\r\n,]+)/)) h = h.substr(RegExp.$1.length);
    else if (h.match(/^([aAcChHlLmMqQsStTvVzZ])/)) r[r.length] = { type: is, text: RegExp.$1 }, h = h.substr(RegExp.$1.length);
    else {
      if (!h.match(/^(([-+]?[0-9]+(\.[0-9]*)?|[-+]?\.[0-9]+)([eE][-+]?[0-9]+)?)/)) return [];
      r[r.length] = { type: vt, text: `${parseFloat(RegExp.$1)}` }, h = h.substr(RegExp.$1.length);
    }
    return r[r.length] = { type: Yt, text: "" }, r;
  })(a);
  let e = "BOD", n = 0, o = s[n];
  for (; !Ot(o, Yt); ) {
    let h = 0;
    const r = [];
    if (e === "BOD") {
      if (o.text !== "M" && o.text !== "m") return Ft("M0,0" + a);
      n++, h = st[o.text], e = o.text;
    } else Ot(o, vt) ? h = st[e] : (n++, h = st[o.text], e = o.text);
    if (!(n + h < s.length)) throw new Error("Path data ended short");
    for (let i = n; i < n + h; i++) {
      const c = s[i];
      if (!Ot(c, vt)) throw new Error("Param not a number: " + e + "," + c.text);
      r[r.length] = +c.text;
    }
    if (typeof st[e] != "number") throw new Error("Bad segment: " + e);
    {
      const i = { key: e, data: r };
      t.push(i), n += h, o = s[n], e === "M" && (e = "L"), e === "m" && (e = "l");
    }
  }
  return t;
}
function le(a) {
  let t = 0, s = 0, e = 0, n = 0;
  const o = [];
  for (const { key: h, data: r } of a) switch (h) {
    case "M":
      o.push({ key: "M", data: [...r] }), [t, s] = r, [e, n] = r;
      break;
    case "m":
      t += r[0], s += r[1], o.push({ key: "M", data: [t, s] }), e = t, n = s;
      break;
    case "L":
      o.push({ key: "L", data: [...r] }), [t, s] = r;
      break;
    case "l":
      t += r[0], s += r[1], o.push({ key: "L", data: [t, s] });
      break;
    case "C":
      o.push({ key: "C", data: [...r] }), t = r[4], s = r[5];
      break;
    case "c": {
      const i = r.map(((c, l) => l % 2 ? c + s : c + t));
      o.push({ key: "C", data: i }), t = i[4], s = i[5];
      break;
    }
    case "Q":
      o.push({ key: "Q", data: [...r] }), t = r[2], s = r[3];
      break;
    case "q": {
      const i = r.map(((c, l) => l % 2 ? c + s : c + t));
      o.push({ key: "Q", data: i }), t = i[2], s = i[3];
      break;
    }
    case "A":
      o.push({ key: "A", data: [...r] }), t = r[5], s = r[6];
      break;
    case "a":
      t += r[5], s += r[6], o.push({ key: "A", data: [r[0], r[1], r[2], r[3], r[4], t, s] });
      break;
    case "H":
      o.push({ key: "H", data: [...r] }), t = r[0];
      break;
    case "h":
      t += r[0], o.push({ key: "H", data: [t] });
      break;
    case "V":
      o.push({ key: "V", data: [...r] }), s = r[0];
      break;
    case "v":
      s += r[0], o.push({ key: "V", data: [s] });
      break;
    case "S":
      o.push({ key: "S", data: [...r] }), t = r[2], s = r[3];
      break;
    case "s": {
      const i = r.map(((c, l) => l % 2 ? c + s : c + t));
      o.push({ key: "S", data: i }), t = i[2], s = i[3];
      break;
    }
    case "T":
      o.push({ key: "T", data: [...r] }), t = r[0], s = r[1];
      break;
    case "t":
      t += r[0], s += r[1], o.push({ key: "T", data: [t, s] });
      break;
    case "Z":
    case "z":
      o.push({ key: "Z", data: [] }), t = e, s = n;
  }
  return o;
}
function ue(a) {
  const t = [];
  let s = "", e = 0, n = 0, o = 0, h = 0, r = 0, i = 0;
  for (const { key: c, data: l } of a) {
    switch (c) {
      case "M":
        t.push({ key: "M", data: [...l] }), [e, n] = l, [o, h] = l;
        break;
      case "C":
        t.push({ key: "C", data: [...l] }), e = l[4], n = l[5], r = l[2], i = l[3];
        break;
      case "L":
        t.push({ key: "L", data: [...l] }), [e, n] = l;
        break;
      case "H":
        e = l[0], t.push({ key: "L", data: [e, n] });
        break;
      case "V":
        n = l[0], t.push({ key: "L", data: [e, n] });
        break;
      case "S": {
        let p = 0, f = 0;
        s === "C" || s === "S" ? (p = e + (e - r), f = n + (n - i)) : (p = e, f = n), t.push({ key: "C", data: [p, f, ...l] }), r = l[0], i = l[1], e = l[2], n = l[3];
        break;
      }
      case "T": {
        const [p, f] = l;
        let u = 0, d = 0;
        s === "Q" || s === "T" ? (u = e + (e - r), d = n + (n - i)) : (u = e, d = n);
        const g = e + 2 * (u - e) / 3, M = n + 2 * (d - n) / 3, k = p + 2 * (u - p) / 3, b = f + 2 * (d - f) / 3;
        t.push({ key: "C", data: [g, M, k, b, p, f] }), r = u, i = d, e = p, n = f;
        break;
      }
      case "Q": {
        const [p, f, u, d] = l, g = e + 2 * (p - e) / 3, M = n + 2 * (f - n) / 3, k = u + 2 * (p - u) / 3, b = d + 2 * (f - d) / 3;
        t.push({ key: "C", data: [g, M, k, b, u, d] }), r = p, i = f, e = u, n = d;
        break;
      }
      case "A": {
        const p = Math.abs(l[0]), f = Math.abs(l[1]), u = l[2], d = l[3], g = l[4], M = l[5], k = l[6];
        p === 0 || f === 0 ? (t.push({ key: "C", data: [e, n, M, k, M, k] }), e = M, n = k) : (e !== M || n !== k) && (fe(e, n, M, k, p, f, u, d, g).forEach((function(b) {
          t.push({ key: "C", data: b });
        })), e = M, n = k);
        break;
      }
      case "Z":
        t.push({ key: "Z", data: [] }), e = o, n = h;
    }
    s = c;
  }
  return t;
}
function X(a, t, s) {
  return [a * Math.cos(s) - t * Math.sin(s), a * Math.sin(s) + t * Math.cos(s)];
}
function fe(a, t, s, e, n, o, h, r, i, c) {
  const l = (p = h, Math.PI * p / 180);
  var p;
  let f = [], u = 0, d = 0, g = 0, M = 0;
  if (c) [u, d, g, M] = c;
  else {
    [a, t] = X(a, t, -l), [s, e] = X(s, e, -l);
    const w = (a - s) / 2, S = (t - e) / 2;
    let D = w * w / (n * n) + S * S / (o * o);
    D > 1 && (D = Math.sqrt(D), n *= D, o *= D);
    const W = n * n, R = o * o, mt = W * R - W * S * S - R * w * w, yt = W * S * S + R * w * w, Q = (r === i ? -1 : 1) * Math.sqrt(Math.abs(mt / yt));
    g = Q * n * S / o + (a + s) / 2, M = Q * -o * w / n + (t + e) / 2, u = Math.asin(parseFloat(((t - M) / o).toFixed(9))), d = Math.asin(parseFloat(((e - M) / o).toFixed(9))), a < g && (u = Math.PI - u), s < g && (d = Math.PI - d), u < 0 && (u = 2 * Math.PI + u), d < 0 && (d = 2 * Math.PI + d), i && u > d && (u -= 2 * Math.PI), !i && d > u && (d -= 2 * Math.PI);
  }
  let k = d - u;
  if (Math.abs(k) > 120 * Math.PI / 180) {
    const w = d, S = s, D = e;
    d = i && d > u ? u + 120 * Math.PI / 180 * 1 : u + 120 * Math.PI / 180 * -1, f = fe(s = g + n * Math.cos(d), e = M + o * Math.sin(d), S, D, n, o, h, 0, i, [d, w, g, M]);
  }
  k = d - u;
  const b = Math.cos(u), P = Math.sin(u), x = Math.cos(d), O = Math.sin(d), v = Math.tan(k / 4), L = 4 / 3 * n * v, z = 4 / 3 * o * v, q = [a, t], A = [a + L * P, t - z * b], $ = [s + L * O, e - z * x], T = [s, e];
  if (A[0] = 2 * q[0] - A[0], A[1] = 2 * q[1] - A[1], c) return [A, $, T].concat(f);
  {
    f = [A, $, T].concat(f);
    const w = [];
    for (let S = 0; S < f.length; S += 3) {
      const D = X(f[S][0], f[S][1], l), W = X(f[S + 1][0], f[S + 1][1], l), R = X(f[S + 2][0], f[S + 2][1], l);
      w.push([D[0], D[1], W[0], W[1], R[0], R[1]]);
    }
    return w;
  }
}
const cs = { randOffset: function(a, t) {
  return y(a, t);
}, randOffsetWithRange: function(a, t, s) {
  return pt(a, t, s);
}, ellipse: function(a, t, s, e, n) {
  const o = de(s, e, n);
  return It(a, t, n, o).opset;
}, doubleLineOps: function(a, t, s, e, n) {
  return F(a, t, s, e, n, !0);
} };
function pe(a, t, s, e, n) {
  return { type: "path", ops: F(a, t, s, e, n) };
}
function it(a, t, s) {
  const e = (a || []).length;
  if (e > 2) {
    const n = [];
    for (let o = 0; o < e - 1; o++) n.push(...F(a[o][0], a[o][1], a[o + 1][0], a[o + 1][1], s));
    return t && n.push(...F(a[e - 1][0], a[e - 1][1], a[0][0], a[0][1], s)), { type: "path", ops: n };
  }
  return e === 2 ? pe(a[0][0], a[0][1], a[1][0], a[1][1], s) : { type: "path", ops: [] };
}
function ls(a, t, s, e, n) {
  return (function(o, h) {
    return it(o, !0, h);
  })([[a, t], [a + s, t], [a + s, t + e], [a, t + e]], n);
}
function Xt(a, t) {
  if (a.length) {
    const s = typeof a[0][0] == "number" ? [a] : a, e = nt(s[0], 1 * (1 + 0.2 * t.roughness), t), n = t.disableMultiStroke ? [] : nt(s[0], 1.5 * (1 + 0.22 * t.roughness), Kt(t));
    for (let o = 1; o < s.length; o++) {
      const h = s[o];
      if (h.length) {
        const r = nt(h, 1 * (1 + 0.2 * t.roughness), t), i = t.disableMultiStroke ? [] : nt(h, 1.5 * (1 + 0.22 * t.roughness), Kt(t));
        for (const c of r) c.op !== "move" && e.push(c);
        for (const c of i) c.op !== "move" && n.push(c);
      }
    }
    return { type: "path", ops: e.concat(n) };
  }
  return { type: "path", ops: [] };
}
function de(a, t, s) {
  const e = Math.sqrt(2 * Math.PI * Math.sqrt((Math.pow(a / 2, 2) + Math.pow(t / 2, 2)) / 2)), n = Math.ceil(Math.max(s.curveStepCount, s.curveStepCount / Math.sqrt(200) * e)), o = 2 * Math.PI / n;
  let h = Math.abs(a / 2), r = Math.abs(t / 2);
  const i = 1 - s.curveFitting;
  return h += y(h * i, s), r += y(r * i, s), { increment: o, rx: h, ry: r };
}
function It(a, t, s, e) {
  const [n, o] = te(e.increment, a, t, e.rx, e.ry, 1, e.increment * pt(0.1, pt(0.4, 1, s), s), s);
  let h = dt(n, null, s);
  if (!s.disableMultiStroke && s.roughness !== 0) {
    const [r] = te(e.increment, a, t, e.rx, e.ry, 1.5, 0, s), i = dt(r, null, s);
    h = h.concat(i);
  }
  return { estimatedPoints: o, opset: { type: "path", ops: h } };
}
function Ut(a, t, s, e, n, o, h, r, i) {
  const c = a, l = t;
  let p = Math.abs(s / 2), f = Math.abs(e / 2);
  p += y(0.01 * p, i), f += y(0.01 * f, i);
  let u = n, d = o;
  for (; u < 0; ) u += 2 * Math.PI, d += 2 * Math.PI;
  d - u > 2 * Math.PI && (u = 0, d = 2 * Math.PI);
  const g = 2 * Math.PI / i.curveStepCount, M = Math.min(g / 2, (d - u) / 2), k = ee(M, c, l, p, f, u, d, 1, i);
  if (!i.disableMultiStroke) {
    const b = ee(M, c, l, p, f, u, d, 1.5, i);
    k.push(...b);
  }
  return h && (r ? k.push(...F(c, l, c + p * Math.cos(u), l + f * Math.sin(u), i), ...F(c, l, c + p * Math.cos(d), l + f * Math.sin(d), i)) : k.push({ op: "lineTo", data: [c, l] }, { op: "lineTo", data: [c + p * Math.cos(u), l + f * Math.sin(u)] })), { type: "path", ops: k };
}
function Jt(a, t) {
  const s = ue(le(Ft(a))), e = [];
  let n = [0, 0], o = [0, 0];
  for (const { key: h, data: r } of s) switch (h) {
    case "M":
      o = [r[0], r[1]], n = [r[0], r[1]];
      break;
    case "L":
      e.push(...F(o[0], o[1], r[0], r[1], t)), o = [r[0], r[1]];
      break;
    case "C": {
      const [i, c, l, p, f, u] = r;
      e.push(...us(i, c, l, p, f, u, o, t)), o = [f, u];
      break;
    }
    case "Z":
      e.push(...F(o[0], o[1], n[0], n[1], t)), o = [n[0], n[1]];
  }
  return { type: "path", ops: e };
}
function xt(a, t) {
  const s = [];
  for (const e of a) if (e.length) {
    const n = t.maxRandomnessOffset || 0, o = e.length;
    if (o > 2) {
      s.push({ op: "move", data: [e[0][0] + y(n, t), e[0][1] + y(n, t)] });
      for (let h = 1; h < o; h++) s.push({ op: "lineTo", data: [e[h][0] + y(n, t), e[h][1] + y(n, t)] });
    }
  }
  return { type: "fillPath", ops: s };
}
function H(a, t) {
  return (function(s, e) {
    let n = s.fillStyle || "hachure";
    if (!C[n]) switch (n) {
      case "zigzag":
        C[n] || (C[n] = new ss(e));
        break;
      case "cross-hatch":
        C[n] || (C[n] = new ns(e));
        break;
      case "dots":
        C[n] || (C[n] = new as(e));
        break;
      case "dashed":
        C[n] || (C[n] = new os(e));
        break;
      case "zigzag-line":
        C[n] || (C[n] = new rs(e));
        break;
      default:
        n = "hachure", C[n] || (C[n] = new Gt(e));
    }
    return C[n];
  })(t, cs).fillPolygons(a, t);
}
function Kt(a) {
  const t = Object.assign({}, a);
  return t.randomizer = void 0, a.seed && (t.seed = a.seed + 1), t;
}
function ge(a) {
  return a.randomizer || (a.randomizer = new hs(a.seed || 0)), a.randomizer.next();
}
function pt(a, t, s, e = 1) {
  return s.roughness * e * (ge(s) * (t - a) + a);
}
function y(a, t, s = 1) {
  return pt(-a, a, t, s);
}
function F(a, t, s, e, n, o = !1) {
  const h = o ? n.disableMultiStrokeFill : n.disableMultiStroke, r = Et(a, t, s, e, n, !0, !1);
  if (h) return r;
  const i = Et(a, t, s, e, n, !0, !0);
  return r.concat(i);
}
function Et(a, t, s, e, n, o, h) {
  const r = Math.pow(a - s, 2) + Math.pow(t - e, 2), i = Math.sqrt(r);
  let c = 1;
  c = i < 200 ? 1 : i > 500 ? 0.4 : -16668e-7 * i + 1.233334;
  let l = n.maxRandomnessOffset || 0;
  l * l * 100 > r && (l = i / 10);
  const p = l / 2, f = 0.2 + 0.2 * ge(n);
  let u = n.bowing * n.maxRandomnessOffset * (e - t) / 200, d = n.bowing * n.maxRandomnessOffset * (a - s) / 200;
  u = y(u, n, c), d = y(d, n, c);
  const g = [], M = () => y(p, n, c), k = () => y(l, n, c), b = n.preserveVertices;
  return h ? g.push({ op: "move", data: [a + (b ? 0 : M()), t + (b ? 0 : M())] }) : g.push({ op: "move", data: [a + (b ? 0 : y(l, n, c)), t + (b ? 0 : y(l, n, c))] }), h ? g.push({ op: "bcurveTo", data: [u + a + (s - a) * f + M(), d + t + (e - t) * f + M(), u + a + 2 * (s - a) * f + M(), d + t + 2 * (e - t) * f + M(), s + (b ? 0 : M()), e + (b ? 0 : M())] }) : g.push({ op: "bcurveTo", data: [u + a + (s - a) * f + k(), d + t + (e - t) * f + k(), u + a + 2 * (s - a) * f + k(), d + t + 2 * (e - t) * f + k(), s + (b ? 0 : k()), e + (b ? 0 : k())] }), g;
}
function nt(a, t, s) {
  if (!a.length) return [];
  const e = [];
  e.push([a[0][0] + y(t, s), a[0][1] + y(t, s)]), e.push([a[0][0] + y(t, s), a[0][1] + y(t, s)]);
  for (let n = 1; n < a.length; n++) e.push([a[n][0] + y(t, s), a[n][1] + y(t, s)]), n === a.length - 1 && e.push([a[n][0] + y(t, s), a[n][1] + y(t, s)]);
  return dt(e, null, s);
}
function dt(a, t, s) {
  const e = a.length, n = [];
  if (e > 3) {
    const o = [], h = 1 - s.curveTightness;
    n.push({ op: "move", data: [a[1][0], a[1][1]] });
    for (let r = 1; r + 2 < e; r++) {
      const i = a[r];
      o[0] = [i[0], i[1]], o[1] = [i[0] + (h * a[r + 1][0] - h * a[r - 1][0]) / 6, i[1] + (h * a[r + 1][1] - h * a[r - 1][1]) / 6], o[2] = [a[r + 1][0] + (h * a[r][0] - h * a[r + 2][0]) / 6, a[r + 1][1] + (h * a[r][1] - h * a[r + 2][1]) / 6], o[3] = [a[r + 1][0], a[r + 1][1]], n.push({ op: "bcurveTo", data: [o[1][0], o[1][1], o[2][0], o[2][1], o[3][0], o[3][1]] });
    }
  } else e === 3 ? (n.push({ op: "move", data: [a[1][0], a[1][1]] }), n.push({ op: "bcurveTo", data: [a[1][0], a[1][1], a[2][0], a[2][1], a[2][0], a[2][1]] })) : e === 2 && n.push(...Et(a[0][0], a[0][1], a[1][0], a[1][1], s, !0, !0));
  return n;
}
function te(a, t, s, e, n, o, h, r) {
  const i = [], c = [];
  if (r.roughness === 0) {
    a /= 4, c.push([t + e * Math.cos(-a), s + n * Math.sin(-a)]);
    for (let l = 0; l <= 2 * Math.PI; l += a) {
      const p = [t + e * Math.cos(l), s + n * Math.sin(l)];
      i.push(p), c.push(p);
    }
    c.push([t + e * Math.cos(0), s + n * Math.sin(0)]), c.push([t + e * Math.cos(a), s + n * Math.sin(a)]);
  } else {
    const l = y(0.5, r) - Math.PI / 2;
    c.push([y(o, r) + t + 0.9 * e * Math.cos(l - a), y(o, r) + s + 0.9 * n * Math.sin(l - a)]);
    const p = 2 * Math.PI + l - 0.01;
    for (let f = l; f < p; f += a) {
      const u = [y(o, r) + t + e * Math.cos(f), y(o, r) + s + n * Math.sin(f)];
      i.push(u), c.push(u);
    }
    c.push([y(o, r) + t + e * Math.cos(l + 2 * Math.PI + 0.5 * h), y(o, r) + s + n * Math.sin(l + 2 * Math.PI + 0.5 * h)]), c.push([y(o, r) + t + 0.98 * e * Math.cos(l + h), y(o, r) + s + 0.98 * n * Math.sin(l + h)]), c.push([y(o, r) + t + 0.9 * e * Math.cos(l + 0.5 * h), y(o, r) + s + 0.9 * n * Math.sin(l + 0.5 * h)]);
  }
  return [c, i];
}
function ee(a, t, s, e, n, o, h, r, i) {
  const c = o + y(0.1, i), l = [];
  l.push([y(r, i) + t + 0.9 * e * Math.cos(c - a), y(r, i) + s + 0.9 * n * Math.sin(c - a)]);
  for (let p = c; p <= h; p += a) l.push([y(r, i) + t + e * Math.cos(p), y(r, i) + s + n * Math.sin(p)]);
  return l.push([t + e * Math.cos(h), s + n * Math.sin(h)]), l.push([t + e * Math.cos(h), s + n * Math.sin(h)]), dt(l, null, i);
}
function us(a, t, s, e, n, o, h, r) {
  const i = [], c = [r.maxRandomnessOffset || 1, (r.maxRandomnessOffset || 1) + 0.3];
  let l = [0, 0];
  const p = r.disableMultiStroke ? 1 : 2, f = r.preserveVertices;
  for (let u = 0; u < p; u++) u === 0 ? i.push({ op: "move", data: [h[0], h[1]] }) : i.push({ op: "move", data: [h[0] + (f ? 0 : y(c[0], r)), h[1] + (f ? 0 : y(c[0], r))] }), l = f ? [n, o] : [n + y(c[u], r), o + y(c[u], r)], i.push({ op: "bcurveTo", data: [a + y(c[u], r), t + y(c[u], r), s + y(c[u], r), e + y(c[u], r), l[0], l[1]] });
  return i;
}
function U(a) {
  return [...a];
}
function se(a, t = 0) {
  const s = a.length;
  if (s < 3) throw new Error("A curve must have at least three points.");
  const e = [];
  if (s === 3) e.push(U(a[0]), U(a[1]), U(a[2]), U(a[2]));
  else {
    const n = [];
    n.push(a[0], a[0]);
    for (let r = 1; r < a.length; r++) n.push(a[r]), r === a.length - 1 && n.push(a[r]);
    const o = [], h = 1 - t;
    e.push(U(n[0]));
    for (let r = 1; r + 2 < n.length; r++) {
      const i = n[r];
      o[0] = [i[0], i[1]], o[1] = [i[0] + (h * n[r + 1][0] - h * n[r - 1][0]) / 6, i[1] + (h * n[r + 1][1] - h * n[r - 1][1]) / 6], o[2] = [n[r + 1][0] + (h * n[r][0] - h * n[r + 2][0]) / 6, n[r + 1][1] + (h * n[r][1] - h * n[r + 2][1]) / 6], o[3] = [n[r + 1][0], n[r + 1][1]], e.push(o[1], o[2], o[3]);
    }
  }
  return e;
}
function ct(a, t) {
  return Math.pow(a[0] - t[0], 2) + Math.pow(a[1] - t[1], 2);
}
function fs(a, t, s) {
  const e = ct(t, s);
  if (e === 0) return ct(a, t);
  let n = ((a[0] - t[0]) * (s[0] - t[0]) + (a[1] - t[1]) * (s[1] - t[1])) / e;
  return n = Math.max(0, Math.min(1, n)), ct(a, Z(t, s, n));
}
function Z(a, t, s) {
  return [a[0] + (t[0] - a[0]) * s, a[1] + (t[1] - a[1]) * s];
}
function qt(a, t, s, e) {
  const n = e || [];
  if ((function(r, i) {
    const c = r[i + 0], l = r[i + 1], p = r[i + 2], f = r[i + 3];
    let u = 3 * l[0] - 2 * c[0] - f[0];
    u *= u;
    let d = 3 * l[1] - 2 * c[1] - f[1];
    d *= d;
    let g = 3 * p[0] - 2 * f[0] - c[0];
    g *= g;
    let M = 3 * p[1] - 2 * f[1] - c[1];
    return M *= M, u < g && (u = g), d < M && (d = M), u + d;
  })(a, t) < s) {
    const r = a[t + 0];
    n.length ? (o = n[n.length - 1], h = r, Math.sqrt(ct(o, h)) > 1 && n.push(r)) : n.push(r), n.push(a[t + 3]);
  } else {
    const i = a[t + 0], c = a[t + 1], l = a[t + 2], p = a[t + 3], f = Z(i, c, 0.5), u = Z(c, l, 0.5), d = Z(l, p, 0.5), g = Z(f, u, 0.5), M = Z(u, d, 0.5), k = Z(g, M, 0.5);
    qt([i, f, g, k], 0, s, n), qt([k, M, d, p], 0, s, n);
  }
  var o, h;
  return n;
}
function ps(a, t) {
  return gt(a, 0, a.length, t);
}
function gt(a, t, s, e, n) {
  const o = n || [], h = a[t], r = a[s - 1];
  let i = 0, c = 1;
  for (let l = t + 1; l < s - 1; ++l) {
    const p = fs(a[l], h, r);
    p > i && (i = p, c = l);
  }
  return Math.sqrt(i) > e ? (gt(a, t, c + 1, e, o), gt(a, c, s, e, o)) : (o.length || o.push(h), o.push(r)), o;
}
function Lt(a, t = 0.15, s) {
  const e = [], n = (a.length - 1) / 3;
  for (let o = 0; o < n; o++)
    qt(a, 3 * o, t, e);
  return s && s > 0 ? gt(e, 0, e.length, s) : e;
}
const E = "none";
class Mt {
  constructor(t) {
    this.defaultOptions = { maxRandomnessOffset: 2, roughness: 1, bowing: 1, stroke: "#000", strokeWidth: 1, curveTightness: 0, curveFitting: 0.95, curveStepCount: 9, fillStyle: "hachure", fillWeight: -1, hachureAngle: -41, hachureGap: -1, dashOffset: -1, dashGap: -1, zigzagOffset: -1, seed: 0, disableMultiStroke: !1, disableMultiStrokeFill: !1, preserveVertices: !1, fillShapeRoughnessGain: 0.8 }, this.config = t || {}, this.config.options && (this.defaultOptions = this._o(this.config.options));
  }
  static newSeed() {
    return Math.floor(Math.random() * 2 ** 31);
  }
  _o(t) {
    return t ? Object.assign({}, this.defaultOptions, t) : this.defaultOptions;
  }
  _d(t, s, e) {
    return { shape: t, sets: s || [], options: e || this.defaultOptions };
  }
  line(t, s, e, n, o) {
    const h = this._o(o);
    return this._d("line", [pe(t, s, e, n, h)], h);
  }
  rectangle(t, s, e, n, o) {
    const h = this._o(o), r = [], i = ls(t, s, e, n, h);
    if (h.fill) {
      const c = [[t, s], [t + e, s], [t + e, s + n], [t, s + n]];
      h.fillStyle === "solid" ? r.push(xt([c], h)) : r.push(H([c], h));
    }
    return h.stroke !== E && r.push(i), this._d("rectangle", r, h);
  }
  ellipse(t, s, e, n, o) {
    const h = this._o(o), r = [], i = de(e, n, h), c = It(t, s, h, i);
    if (h.fill) if (h.fillStyle === "solid") {
      const l = It(t, s, h, i).opset;
      l.type = "fillPath", r.push(l);
    } else r.push(H([c.estimatedPoints], h));
    return h.stroke !== E && r.push(c.opset), this._d("ellipse", r, h);
  }
  circle(t, s, e, n) {
    const o = this.ellipse(t, s, e, e, n);
    return o.shape = "circle", o;
  }
  linearPath(t, s) {
    const e = this._o(s);
    return this._d("linearPath", [it(t, !1, e)], e);
  }
  arc(t, s, e, n, o, h, r = !1, i) {
    const c = this._o(i), l = [], p = Ut(t, s, e, n, o, h, r, !0, c);
    if (r && c.fill) if (c.fillStyle === "solid") {
      const f = Object.assign({}, c);
      f.disableMultiStroke = !0;
      const u = Ut(t, s, e, n, o, h, !0, !1, f);
      u.type = "fillPath", l.push(u);
    } else l.push((function(f, u, d, g, M, k, b) {
      const P = f, x = u;
      let O = Math.abs(d / 2), v = Math.abs(g / 2);
      O += y(0.01 * O, b), v += y(0.01 * v, b);
      let L = M, z = k;
      for (; L < 0; ) L += 2 * Math.PI, z += 2 * Math.PI;
      z - L > 2 * Math.PI && (L = 0, z = 2 * Math.PI);
      const q = (z - L) / b.curveStepCount, A = [];
      for (let $ = L; $ <= z; $ += q) A.push([P + O * Math.cos($), x + v * Math.sin($)]);
      return A.push([P + O * Math.cos(z), x + v * Math.sin(z)]), A.push([P, x]), H([A], b);
    })(t, s, e, n, o, h, c));
    return c.stroke !== E && l.push(p), this._d("arc", l, c);
  }
  curve(t, s) {
    const e = this._o(s), n = [], o = Xt(t, e);
    if (e.fill && e.fill !== E) if (e.fillStyle === "solid") {
      const h = Xt(t, Object.assign(Object.assign({}, e), { disableMultiStroke: !0, roughness: e.roughness ? e.roughness + e.fillShapeRoughnessGain : 0 }));
      n.push({ type: "fillPath", ops: this._mergedShape(h.ops) });
    } else {
      const h = [], r = t;
      if (r.length) {
        const i = typeof r[0][0] == "number" ? [r] : r;
        for (const c of i) c.length < 3 ? h.push(...c) : c.length === 3 ? h.push(...Lt(se([c[0], c[0], c[1], c[2]]), 10, (1 + e.roughness) / 2)) : h.push(...Lt(se(c), 10, (1 + e.roughness) / 2));
      }
      h.length && n.push(H([h], e));
    }
    return e.stroke !== E && n.push(o), this._d("curve", n, e);
  }
  polygon(t, s) {
    const e = this._o(s), n = [], o = it(t, !0, e);
    return e.fill && (e.fillStyle === "solid" ? n.push(xt([t], e)) : n.push(H([t], e))), e.stroke !== E && n.push(o), this._d("polygon", n, e);
  }
  path(t, s) {
    const e = this._o(s), n = [];
    if (!t) return this._d("path", n, e);
    t = (t || "").replace(/\n/g, " ").replace(/(-\s)/g, "-").replace("/(ss)/g", " ");
    const o = e.fill && e.fill !== "transparent" && e.fill !== E, h = e.stroke !== E, r = !!(e.simplification && e.simplification < 1), i = (function(l, p, f) {
      const u = ue(le(Ft(l))), d = [];
      let g = [], M = [0, 0], k = [];
      const b = () => {
        k.length >= 4 && g.push(...Lt(k, p)), k = [];
      }, P = () => {
        b(), g.length && (d.push(g), g = []);
      };
      for (const { key: O, data: v } of u) switch (O) {
        case "M":
          P(), M = [v[0], v[1]], g.push(M);
          break;
        case "L":
          b(), g.push([v[0], v[1]]);
          break;
        case "C":
          if (!k.length) {
            const L = g.length ? g[g.length - 1] : M;
            k.push([L[0], L[1]]);
          }
          k.push([v[0], v[1]]), k.push([v[2], v[3]]), k.push([v[4], v[5]]);
          break;
        case "Z":
          b(), g.push([M[0], M[1]]);
      }
      if (P(), !f) return d;
      const x = [];
      for (const O of d) {
        const v = ps(O, f);
        v.length && x.push(v);
      }
      return x;
    })(t, 1, r ? 4 - 4 * (e.simplification || 1) : (1 + e.roughness) / 2), c = Jt(t, e);
    if (o) if (e.fillStyle === "solid") if (i.length === 1) {
      const l = Jt(t, Object.assign(Object.assign({}, e), { disableMultiStroke: !0, roughness: e.roughness ? e.roughness + e.fillShapeRoughnessGain : 0 }));
      n.push({ type: "fillPath", ops: this._mergedShape(l.ops) });
    } else n.push(xt(i, e));
    else n.push(H(i, e));
    return h && (r ? i.forEach(((l) => {
      n.push(it(l, !1, e));
    })) : n.push(c)), this._d("path", n, e);
  }
  opsToPath(t, s) {
    let e = "";
    for (const n of t.ops) {
      const o = typeof s == "number" && s >= 0 ? n.data.map(((h) => +h.toFixed(s))) : n.data;
      switch (n.op) {
        case "move":
          e += `M${o[0]} ${o[1]} `;
          break;
        case "bcurveTo":
          e += `C${o[0]} ${o[1]}, ${o[2]} ${o[3]}, ${o[4]} ${o[5]} `;
          break;
        case "lineTo":
          e += `L${o[0]} ${o[1]} `;
      }
    }
    return e.trim();
  }
  toPaths(t) {
    const s = t.sets || [], e = t.options || this.defaultOptions, n = [];
    for (const o of s) {
      let h = null;
      switch (o.type) {
        case "path":
          h = { d: this.opsToPath(o), stroke: e.stroke, strokeWidth: e.strokeWidth, fill: E };
          break;
        case "fillPath":
          h = { d: this.opsToPath(o), stroke: E, strokeWidth: 0, fill: e.fill || E };
          break;
        case "fillSketch":
          h = this.fillSketch(o, e);
      }
      h && n.push(h);
    }
    return n;
  }
  fillSketch(t, s) {
    let e = s.fillWeight;
    return e < 0 && (e = s.strokeWidth / 2), { d: this.opsToPath(t), stroke: s.fill || E, strokeWidth: e, fill: E };
  }
  _mergedShape(t) {
    return t.filter(((s, e) => e === 0 || s.op !== "move"));
  }
}
class ds {
  constructor(t, s) {
    this.canvas = t, this.ctx = this.canvas.getContext("2d"), this.gen = new Mt(s);
  }
  draw(t) {
    const s = t.sets || [], e = t.options || this.getDefaultOptions(), n = this.ctx, o = t.options.fixedDecimalPlaceDigits;
    for (const h of s) switch (h.type) {
      case "path":
        n.save(), n.strokeStyle = e.stroke === "none" ? "transparent" : e.stroke, n.lineWidth = e.strokeWidth, e.strokeLineDash && n.setLineDash(e.strokeLineDash), e.strokeLineDashOffset && (n.lineDashOffset = e.strokeLineDashOffset), this._drawToContext(n, h, o), n.restore();
        break;
      case "fillPath": {
        n.save(), n.fillStyle = e.fill || "";
        const r = t.shape === "curve" || t.shape === "polygon" || t.shape === "path" ? "evenodd" : "nonzero";
        this._drawToContext(n, h, o, r), n.restore();
        break;
      }
      case "fillSketch":
        this.fillSketch(n, h, e);
    }
  }
  fillSketch(t, s, e) {
    let n = e.fillWeight;
    n < 0 && (n = e.strokeWidth / 2), t.save(), e.fillLineDash && t.setLineDash(e.fillLineDash), e.fillLineDashOffset && (t.lineDashOffset = e.fillLineDashOffset), t.strokeStyle = e.fill || "", t.lineWidth = n, this._drawToContext(t, s, e.fixedDecimalPlaceDigits), t.restore();
  }
  _drawToContext(t, s, e, n = "nonzero") {
    t.beginPath();
    for (const o of s.ops) {
      const h = typeof e == "number" && e >= 0 ? o.data.map(((r) => +r.toFixed(e))) : o.data;
      switch (o.op) {
        case "move":
          t.moveTo(h[0], h[1]);
          break;
        case "bcurveTo":
          t.bezierCurveTo(h[0], h[1], h[2], h[3], h[4], h[5]);
          break;
        case "lineTo":
          t.lineTo(h[0], h[1]);
      }
    }
    s.type === "fillPath" ? t.fill(n) : t.stroke();
  }
  get generator() {
    return this.gen;
  }
  getDefaultOptions() {
    return this.gen.defaultOptions;
  }
  line(t, s, e, n, o) {
    const h = this.gen.line(t, s, e, n, o);
    return this.draw(h), h;
  }
  rectangle(t, s, e, n, o) {
    const h = this.gen.rectangle(t, s, e, n, o);
    return this.draw(h), h;
  }
  ellipse(t, s, e, n, o) {
    const h = this.gen.ellipse(t, s, e, n, o);
    return this.draw(h), h;
  }
  circle(t, s, e, n) {
    const o = this.gen.circle(t, s, e, n);
    return this.draw(o), o;
  }
  linearPath(t, s) {
    const e = this.gen.linearPath(t, s);
    return this.draw(e), e;
  }
  polygon(t, s) {
    const e = this.gen.polygon(t, s);
    return this.draw(e), e;
  }
  arc(t, s, e, n, o, h, r = !1, i) {
    const c = this.gen.arc(t, s, e, n, o, h, r, i);
    return this.draw(c), c;
  }
  curve(t, s) {
    const e = this.gen.curve(t, s);
    return this.draw(e), e;
  }
  path(t, s) {
    const e = this.gen.path(t, s);
    return this.draw(e), e;
  }
}
const at = "http://www.w3.org/2000/svg";
class gs {
  constructor(t, s) {
    this.svg = t, this.gen = new Mt(s);
  }
  draw(t) {
    const s = t.sets || [], e = t.options || this.getDefaultOptions(), n = this.svg.ownerDocument || window.document, o = n.createElementNS(at, "g"), h = t.options.fixedDecimalPlaceDigits;
    for (const r of s) {
      let i = null;
      switch (r.type) {
        case "path":
          i = n.createElementNS(at, "path"), i.setAttribute("d", this.opsToPath(r, h)), i.setAttribute("stroke", e.stroke), i.setAttribute("stroke-width", e.strokeWidth + ""), i.setAttribute("fill", "none"), e.strokeLineDash && i.setAttribute("stroke-dasharray", e.strokeLineDash.join(" ").trim()), e.strokeLineDashOffset && i.setAttribute("stroke-dashoffset", `${e.strokeLineDashOffset}`);
          break;
        case "fillPath":
          i = n.createElementNS(at, "path"), i.setAttribute("d", this.opsToPath(r, h)), i.setAttribute("stroke", "none"), i.setAttribute("stroke-width", "0"), i.setAttribute("fill", e.fill || ""), t.shape !== "curve" && t.shape !== "polygon" || i.setAttribute("fill-rule", "evenodd");
          break;
        case "fillSketch":
          i = this.fillSketch(n, r, e);
      }
      i && o.appendChild(i);
    }
    return o;
  }
  fillSketch(t, s, e) {
    let n = e.fillWeight;
    n < 0 && (n = e.strokeWidth / 2);
    const o = t.createElementNS(at, "path");
    return o.setAttribute("d", this.opsToPath(s, e.fixedDecimalPlaceDigits)), o.setAttribute("stroke", e.fill || ""), o.setAttribute("stroke-width", n + ""), o.setAttribute("fill", "none"), e.fillLineDash && o.setAttribute("stroke-dasharray", e.fillLineDash.join(" ").trim()), e.fillLineDashOffset && o.setAttribute("stroke-dashoffset", `${e.fillLineDashOffset}`), o;
  }
  get generator() {
    return this.gen;
  }
  getDefaultOptions() {
    return this.gen.defaultOptions;
  }
  opsToPath(t, s) {
    return this.gen.opsToPath(t, s);
  }
  line(t, s, e, n, o) {
    const h = this.gen.line(t, s, e, n, o);
    return this.draw(h);
  }
  rectangle(t, s, e, n, o) {
    const h = this.gen.rectangle(t, s, e, n, o);
    return this.draw(h);
  }
  ellipse(t, s, e, n, o) {
    const h = this.gen.ellipse(t, s, e, n, o);
    return this.draw(h);
  }
  circle(t, s, e, n) {
    const o = this.gen.circle(t, s, e, n);
    return this.draw(o);
  }
  linearPath(t, s) {
    const e = this.gen.linearPath(t, s);
    return this.draw(e);
  }
  polygon(t, s) {
    const e = this.gen.polygon(t, s);
    return this.draw(e);
  }
  arc(t, s, e, n, o, h, r = !1, i) {
    const c = this.gen.arc(t, s, e, n, o, h, r, i);
    return this.draw(c);
  }
  curve(t, s) {
    const e = this.gen.curve(t, s);
    return this.draw(e);
  }
  path(t, s) {
    const e = this.gen.path(t, s);
    return this.draw(e);
  }
}
var ks = { canvas: (a, t) => new ds(a, t), svg: (a, t) => new gs(a, t), generator: (a) => new Mt(a), newSeed: () => Mt.newSeed() };
export {
  ft as R,
  ks as a,
  Le as b,
  Ms as q
};
