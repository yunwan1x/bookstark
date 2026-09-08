import { K as ln, L as un, M as y, N as tn, O as V, P as O, Q as _, R as an, S as rn, T as Y, U as o, V as M, W as sn, X as on, Y as fn } from "./excalidraw-index.js";
function cn(l) {
  return l.innerRadius;
}
function yn(l) {
  return l.outerRadius;
}
function gn(l) {
  return l.startAngle;
}
function dn(l) {
  return l.endAngle;
}
function mn(l) {
  return l && l.padAngle;
}
function pn(l, h, D, S, v, R, N, u) {
  var E = D - l, i = S - h, n = N - v, d = u - R, a = d * E - n * i;
  if (!(a * a < y))
    return a = (n * (h - R) - d * (l - v)) / a, [l + a * E, h + a * i];
}
function G(l, h, D, S, v, R, N) {
  var u = l - D, E = h - S, i = (N ? R : -R) / Y(u * u + E * E), n = i * E, d = -i * u, a = l + n, s = h + d, f = D + n, c = S + d, Q = (a + f) / 2, t = (s + c) / 2, m = f - a, g = c - s, A = m * m + g * g, T = v - R, P = a * c - f * s, I = (g < 0 ? -1 : 1) * Y(fn(0, T * T * A - P * P)), K = (P * g - m * I) / A, L = (-P * m - g * I) / A, w = (P * g + m * I) / A, p = (-P * m + g * I) / A, x = K - Q, e = L - t, r = w - Q, U = p - t;
  return x * x + e * e > r * r + U * U && (K = w, L = p), {
    cx: K,
    cy: L,
    x01: -n,
    y01: -d,
    x11: K * (v / T - 1),
    y11: L * (v / T - 1)
  };
}
function hn() {
  var l = cn, h = yn, D = M(0), S = null, v = gn, R = dn, N = mn, u = null, E = ln(i);
  function i() {
    var n, d, a = +l.apply(this, arguments), s = +h.apply(this, arguments), f = v.apply(this, arguments) - un, c = R.apply(this, arguments) - un, Q = an(c - f), t = c > f;
    if (u || (u = n = E()), s < a && (d = s, s = a, a = d), !(s > y)) u.moveTo(0, 0);
    else if (Q > tn - y)
      u.moveTo(s * V(f), s * O(f)), u.arc(0, 0, s, f, c, !t), a > y && (u.moveTo(a * V(c), a * O(c)), u.arc(0, 0, a, c, f, t));
    else {
      var m = f, g = c, A = f, T = c, P = Q, I = Q, K = N.apply(this, arguments) / 2, L = K > y && (S ? +S.apply(this, arguments) : Y(a * a + s * s)), w = _(an(s - a) / 2, +D.apply(this, arguments)), p = w, x = w, e, r;
      if (L > y) {
        var U = sn(L / a * O(K)), j = sn(L / s * O(K));
        (P -= U * 2) > y ? (U *= t ? 1 : -1, A += U, T -= U) : (P = 0, A = T = (f + c) / 2), (I -= j * 2) > y ? (j *= t ? 1 : -1, m += j, g -= j) : (I = 0, m = g = (f + c) / 2);
      }
      var W = s * V(m), X = s * O(m), z = a * V(T), B = a * O(T);
      if (w > y) {
        var C = s * V(g), F = s * O(g), H = a * V(A), J = a * O(A), q;
        if (Q < rn)
          if (q = pn(W, X, H, J, C, F, z, B)) {
            var Z = W - q[0], $ = X - q[1], k = C - q[0], b = F - q[1], nn = 1 / O(on((Z * k + $ * b) / (Y(Z * Z + $ * $) * Y(k * k + b * b))) / 2), en = Y(q[0] * q[0] + q[1] * q[1]);
            p = _(w, (a - en) / (nn - 1)), x = _(w, (s - en) / (nn + 1));
          } else
            p = x = 0;
      }
      I > y ? x > y ? (e = G(H, J, W, X, s, x, t), r = G(C, F, z, B, s, x, t), u.moveTo(e.cx + e.x01, e.cy + e.y01), x < w ? u.arc(e.cx, e.cy, x, o(e.y01, e.x01), o(r.y01, r.x01), !t) : (u.arc(e.cx, e.cy, x, o(e.y01, e.x01), o(e.y11, e.x11), !t), u.arc(0, 0, s, o(e.cy + e.y11, e.cx + e.x11), o(r.cy + r.y11, r.cx + r.x11), !t), u.arc(r.cx, r.cy, x, o(r.y11, r.x11), o(r.y01, r.x01), !t))) : (u.moveTo(W, X), u.arc(0, 0, s, m, g, !t)) : u.moveTo(W, X), !(a > y) || !(P > y) ? u.lineTo(z, B) : p > y ? (e = G(z, B, C, F, a, -p, t), r = G(W, X, H, J, a, -p, t), u.lineTo(e.cx + e.x01, e.cy + e.y01), p < w ? u.arc(e.cx, e.cy, p, o(e.y01, e.x01), o(r.y01, r.x01), !t) : (u.arc(e.cx, e.cy, p, o(e.y01, e.x01), o(e.y11, e.x11), !t), u.arc(0, 0, a, o(e.cy + e.y11, e.cx + e.x11), o(r.cy + r.y11, r.cx + r.x11), t), u.arc(r.cx, r.cy, p, o(r.y11, r.x11), o(r.y01, r.x01), !t))) : u.arc(0, 0, a, T, A, t);
    }
    if (u.closePath(), n) return u = null, n + "" || null;
  }
  return i.centroid = function() {
    var n = (+l.apply(this, arguments) + +h.apply(this, arguments)) / 2, d = (+v.apply(this, arguments) + +R.apply(this, arguments)) / 2 - rn / 2;
    return [V(d) * n, O(d) * n];
  }, i.innerRadius = function(n) {
    return arguments.length ? (l = typeof n == "function" ? n : M(+n), i) : l;
  }, i.outerRadius = function(n) {
    return arguments.length ? (h = typeof n == "function" ? n : M(+n), i) : h;
  }, i.cornerRadius = function(n) {
    return arguments.length ? (D = typeof n == "function" ? n : M(+n), i) : D;
  }, i.padRadius = function(n) {
    return arguments.length ? (S = n == null ? null : typeof n == "function" ? n : M(+n), i) : S;
  }, i.startAngle = function(n) {
    return arguments.length ? (v = typeof n == "function" ? n : M(+n), i) : v;
  }, i.endAngle = function(n) {
    return arguments.length ? (R = typeof n == "function" ? n : M(+n), i) : R;
  }, i.padAngle = function(n) {
    return arguments.length ? (N = typeof n == "function" ? n : M(+n), i) : N;
  }, i.context = function(n) {
    return arguments.length ? (u = n ?? null, i) : u;
  }, i;
}
export {
  hn as d
};
