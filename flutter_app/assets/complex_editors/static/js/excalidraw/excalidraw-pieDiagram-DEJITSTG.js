import { V as S, N as R, aw as Q, g as Y, s as tt, a as et, b as at, t as rt, q as nt, _ as p, l as F, c as it, F as st, I as lt, a1 as ot, e as ct, A as ut, G as pt } from "./excalidraw-index.js";
import { p as gt } from "./excalidraw-chunk-4BX2VUAB.js";
import { p as dt } from "./excalidraw-wardley-RL74JXVD.js";
import { d as _ } from "./excalidraw-arc.js";
import { o as ft } from "./excalidraw-ordinal.js";
function ht(t, a) {
  return a < t ? -1 : a > t ? 1 : a >= t ? 0 : NaN;
}
function mt(t) {
  return t;
}
function vt() {
  var t = mt, a = ht, f = null, w = S(0), s = S(R), g = S(0);
  function l(e) {
    var n, o = (e = Q(e)).length, d, h, v = 0, c = new Array(o), i = new Array(o), x = +w.apply(this, arguments), y = Math.min(R, Math.max(-R, s.apply(this, arguments) - x)), m, D = Math.min(Math.abs(y) / o, g.apply(this, arguments)), $ = D * (y < 0 ? -1 : 1), u;
    for (n = 0; n < o; ++n)
      (u = i[c[n] = n] = +t(e[n], n, e)) > 0 && (v += u);
    for (a != null ? c.sort(function(A, C) {
      return a(i[A], i[C]);
    }) : f != null && c.sort(function(A, C) {
      return f(e[A], e[C]);
    }), n = 0, h = v ? (y - o * $) / v : 0; n < o; ++n, x = m)
      d = c[n], u = i[d], m = x + (u > 0 ? u * h : 0) + $, i[d] = {
        data: e[d],
        index: n,
        value: u,
        startAngle: x,
        endAngle: m,
        padAngle: D
      };
    return i;
  }
  return l.value = function(e) {
    return arguments.length ? (t = typeof e == "function" ? e : S(+e), l) : t;
  }, l.sortValues = function(e) {
    return arguments.length ? (a = e, f = null, l) : a;
  }, l.sort = function(e) {
    return arguments.length ? (f = e, a = null, l) : f;
  }, l.startAngle = function(e) {
    return arguments.length ? (w = typeof e == "function" ? e : S(+e), l) : w;
  }, l.endAngle = function(e) {
    return arguments.length ? (s = typeof e == "function" ? e : S(+e), l) : s;
  }, l.padAngle = function(e) {
    return arguments.length ? (g = typeof e == "function" ? e : S(+e), l) : g;
  }, l;
}
var xt = pt.pie, W = {
  sections: /* @__PURE__ */ new Map(),
  showData: !1
}, T = W.sections, z = W.showData, St = structuredClone(xt), wt = /* @__PURE__ */ p(() => structuredClone(St), "getConfig"), yt = /* @__PURE__ */ p(() => {
  T = /* @__PURE__ */ new Map(), z = W.showData, ut();
}, "clear"), At = /* @__PURE__ */ p(({ label: t, value: a }) => {
  if (a < 0)
    throw new Error(
      `"${t}" has invalid value: ${a}. Negative values are not allowed in pie charts. All slice values must be >= 0.`
    );
  T.has(t) || (T.set(t, a), F.debug(`added new section: ${t}, with value: ${a}`));
}, "addSection"), Ct = /* @__PURE__ */ p(() => T, "getSections"), Dt = /* @__PURE__ */ p((t) => {
  z = t;
}, "setShowData"), $t = /* @__PURE__ */ p(() => z, "getShowData"), V = {
  getConfig: wt,
  clear: yt,
  setDiagramTitle: nt,
  getDiagramTitle: rt,
  setAccTitle: at,
  getAccTitle: et,
  setAccDescription: tt,
  getAccDescription: Y,
  addSection: At,
  getSections: Ct,
  setShowData: Dt,
  getShowData: $t
}, Tt = /* @__PURE__ */ p((t, a) => {
  gt(t, a), a.setShowData(t.showData), t.sections.map(a.addSection);
}, "populateDb"), bt = {
  parse: /* @__PURE__ */ p(async (t) => {
    const a = await dt("pie", t);
    F.debug(a), Tt(a, V);
  }, "parse")
}, kt = /* @__PURE__ */ p((t) => `
  .pieCircle{
    stroke: ${t.pieStrokeColor};
    stroke-width : ${t.pieStrokeWidth};
    opacity : ${t.pieOpacity};
  }
  .pieOuterCircle{
    stroke: ${t.pieOuterStrokeColor};
    stroke-width: ${t.pieOuterStrokeWidth};
    fill: none;
  }
  .pieTitleText {
    text-anchor: middle;
    font-size: ${t.pieTitleTextSize};
    fill: ${t.pieTitleTextColor};
    font-family: ${t.fontFamily};
  }
  .slice {
    font-family: ${t.fontFamily};
    fill: ${t.pieSectionTextColor};
    font-size:${t.pieSectionTextSize};
    // fill: white;
  }
  .legend text {
    fill: ${t.pieLegendTextColor};
    font-family: ${t.fontFamily};
    font-size: ${t.pieLegendTextSize};
  }
`, "getStyles"), Et = kt, Mt = /* @__PURE__ */ p((t) => {
  const a = [...t.values()].reduce((s, g) => s + g, 0), f = [...t.entries()].map(([s, g]) => ({ label: s, value: g })).filter((s) => s.value / a * 100 >= 1);
  return vt().value((s) => s.value).sort(null)(f);
}, "createPieArcs"), Rt = /* @__PURE__ */ p((t, a, f, w) => {
  var O;
  F.debug(`rendering pie chart
` + t);
  const s = w.db, g = it(), l = st(s.getConfig(), g.pie), e = 40, n = 18, o = 4, d = 450, h = d, v = lt(a), c = v.append("g");
  c.attr("transform", "translate(" + h / 2 + "," + d / 2 + ")");
  const { themeVariables: i } = g;
  let [x] = ot(i.pieOuterStrokeWidth);
  x ?? (x = 2);
  const y = l.textPosition, m = Math.min(h, d) / 2 - e, D = _().innerRadius(0).outerRadius(m), $ = _().innerRadius(m * y).outerRadius(m * y);
  c.append("circle").attr("cx", 0).attr("cy", 0).attr("r", m + x / 2).attr("class", "pieOuterCircle");
  const u = s.getSections(), A = Mt(u), C = [
    i.pie1,
    i.pie2,
    i.pie3,
    i.pie4,
    i.pie5,
    i.pie6,
    i.pie7,
    i.pie8,
    i.pie9,
    i.pie10,
    i.pie11,
    i.pie12
  ];
  let b = 0;
  u.forEach((r) => {
    b += r;
  });
  const G = A.filter((r) => (r.data.value / b * 100).toFixed(0) !== "0"), k = ft(C).domain([
    ...u.keys()
  ]);
  c.selectAll("mySlices").data(G).enter().append("path").attr("d", D).attr("fill", (r) => k(r.data.label)).attr("class", "pieCircle"), c.selectAll("mySlices").data(G).enter().append("text").text((r) => (r.data.value / b * 100).toFixed(0) + "%").attr("transform", (r) => "translate(" + $.centroid(r) + ")").style("text-anchor", "middle").attr("class", "slice");
  const U = c.append("text").text(s.getDiagramTitle()).attr("x", 0).attr("y", -400 / 2).attr("class", "pieTitleText"), N = [...u.entries()].map(([r, M]) => ({
    label: r,
    value: M
  })), E = c.selectAll(".legend").data(N).enter().append("g").attr("class", "legend").attr("transform", (r, M) => {
    const P = n + o, H = P * N.length / 2, J = 12 * n, K = M * P - H;
    return "translate(" + J + "," + K + ")";
  });
  E.append("rect").attr("width", n).attr("height", n).style("fill", (r) => k(r.label)).style("stroke", (r) => k(r.label)), E.append("text").attr("x", n + o).attr("y", n - o).text((r) => s.getShowData() ? `${r.label} [${r.value}]` : r.label);
  const j = Math.max(
    ...E.selectAll("text").nodes().map((r) => (r == null ? void 0 : r.getBoundingClientRect().width) ?? 0)
  ), q = h + e + n + o + j, L = ((O = U.node()) == null ? void 0 : O.getBoundingClientRect().width) ?? 0, X = h / 2 - L / 2, Z = h / 2 + L / 2, B = Math.min(0, X), I = Math.max(q, Z) - B;
  v.attr("viewBox", `${B} 0 ${I} ${d}`), ct(v, d, I, l.useMaxWidth);
}, "draw"), Ft = { draw: Rt }, It = {
  parser: bt,
  db: V,
  renderer: Ft,
  styles: Et
};
export {
  It as diagram
};
