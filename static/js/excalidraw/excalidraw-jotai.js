import { r as L, R as te } from "./excalidraw-react.js";
const k = {};
let re = 0;
function ge(e, n) {
  const t = `atom${++re}`, o = {
    toString() {
      return (k ? "production" : void 0) !== "production" && this.debugLabel ? t + ":" + this.debugLabel : t;
    }
  };
  return typeof e == "function" ? o.read = e : (o.init = e, o.read = oe, o.write = se), o;
}
function oe(e) {
  return e(this);
}
function se(e, n, t) {
  return n(
    this,
    typeof t == "function" ? t(e(this)) : t
  );
}
const m = (e, n) => e.unstable_is ? e.unstable_is(n) : n === e, z = (e) => "init" in e, I = (e) => !!e.write, j = /* @__PURE__ */ new WeakMap(), O = (e) => {
  var n;
  return U(e) && !((n = j.get(e)) != null && n[1]);
}, ie = (e, n) => {
  const t = j.get(e);
  if (t)
    t[1] = !0, t[0].forEach((o) => o(n));
  else if ((k ? "production" : void 0) !== "production")
    throw new Error("[Bug] cancelable promise not found");
}, ce = (e) => {
  if (j.has(e))
    return;
  const n = [/* @__PURE__ */ new Set(), !1];
  j.set(e, n);
  const t = () => {
    n[1] = !0;
  };
  e.then(t, t), e.onCancel = (o) => {
    n[0].add(o);
  };
}, U = (e) => typeof (e == null ? void 0 : e.then) == "function", q = (e) => "v" in e || "e" in e, W = (e) => {
  if ("e" in e)
    throw e.e;
  if ((k ? "production" : void 0) !== "production" && !("v" in e))
    throw new Error("[Bug] atom state is not initialized");
  return e.v;
}, Y = (e, n, t) => {
  t.p.has(e) || (t.p.add(e), n.then(
    () => {
      t.p.delete(e);
    },
    () => {
      t.p.delete(e);
    }
  ));
}, K = (e, n, t, o, d) => {
  var w;
  if ((k ? "production" : void 0) !== "production" && o === n)
    throw new Error("[Bug] atom cannot depend on itself");
  t.d.set(o, d.n), O(t.v) && Y(n, t.v, d), (w = d.m) == null || w.t.add(n), e && ue(e, o, n);
}, B = () => ({
  D: /* @__PURE__ */ new Map(),
  H: /* @__PURE__ */ new Set(),
  M: /* @__PURE__ */ new Set(),
  L: /* @__PURE__ */ new Set()
}), H = (e, n, t) => {
  e[n].add(t);
}, Q = (e, n, t) => {
  e.D.has(n) || (e.D.set(n, /* @__PURE__ */ new Set()), H(e, "M", () => {
    var o;
    (o = t.m) == null || o.l.forEach((d) => H(e, "M", d));
  }));
}, ue = (e, n, t) => {
  const o = e.D.get(n);
  o && o.add(t);
}, de = (e, n) => e.D.get(n), R = (e) => {
  let n, t = !1;
  const o = (d) => {
    try {
      d();
    } catch (w) {
      t || (n = w, t = !0);
    }
  };
  for (; e.H.size || e.M.size || e.L.size; )
    e.D.clear(), e.H.forEach(o), e.H.clear(), e.M.forEach(o), e.M.clear(), e.L.forEach(o), e.L.clear();
  if (t)
    throw n;
}, Z = (...[e, n, t, o]) => {
  const d = (c, s, i) => {
    const r = "v" in s, a = s.v, h = O(s.v) ? s.v : null;
    if (U(i)) {
      ce(i);
      for (const u of s.d.keys())
        Y(c, i, e(u));
      s.v = i;
    } else
      s.v = i;
    delete s.e, delete s.x, (!r || !Object.is(a, s.v)) && (++s.n, h && ie(h, i));
  }, w = (c, s) => {
    var i;
    const r = e(s);
    if (q(r) && (r.m && !r.x || Array.from(r.d).every(
      ([l, _]) => (
        // Recursively, read the atom state of the dependency, and
        // check if the atom epoch number is unchanged
        w(c, l).n === _
      )
    )))
      return r;
    r.d.clear();
    let a = !0;
    const h = (l) => {
      if (m(s, l)) {
        const A = e(l);
        if (!q(A))
          if (z(l))
            d(l, A, l.init);
          else
            throw new Error("no atom init");
        return W(A);
      }
      const _ = w(c, l);
      try {
        return W(_);
      } finally {
        if (a)
          K(c, s, r, l, _);
        else {
          const A = B();
          K(A, s, r, l, _), P(A, s, r), R(A);
        }
      }
    };
    let u, v;
    const y = {
      get signal() {
        return u || (u = new AbortController()), u.signal;
      },
      get setSelf() {
        return (k ? "production" : void 0) !== "production" && !I(s) && console.warn("setSelf function cannot be used with read-only atom"), !v && I(s) && (v = (...l) => {
          if ((k ? "production" : void 0) !== "production" && a && console.warn("setSelf function cannot be called in sync"), !a)
            return D(s, ...l);
        }), v;
      }
    };
    try {
      const l = n(s, h, y);
      if (d(s, r, l), U(l)) {
        (i = l.onCancel) == null || i.call(l, () => u == null ? void 0 : u.abort());
        const _ = () => {
          if (r.m) {
            const A = B();
            P(A, s, r), R(A);
          }
        };
        l.then(_, _);
      }
      return r;
    } catch (l) {
      return delete r.v, r.e = l, delete r.x, ++r.n, r;
    } finally {
      a = !1;
    }
  }, E = (c) => W(w(void 0, c)), b = (c, s, i) => {
    var r, a;
    const h = /* @__PURE__ */ new Map();
    for (const u of ((r = i.m) == null ? void 0 : r.t) || []) {
      const v = e(u);
      v.m && h.set(u, v);
    }
    for (const u of i.p)
      h.set(
        u,
        e(u)
      );
    return (a = de(c, s)) == null || a.forEach((u) => {
      h.set(u, e(u));
    }), h;
  }, p = (c, s, i) => {
    const r = [], a = /* @__PURE__ */ new Set(), h = /* @__PURE__ */ new Set(), u = [[s, i]];
    for (; u.length > 0; ) {
      const [v, y] = u[u.length - 1];
      if (h.has(v)) {
        u.pop();
        continue;
      }
      if (a.has(v)) {
        r.push([v, y, y.n]), h.add(v), y.x = !0, u.pop();
        continue;
      }
      a.add(v);
      for (const [l, _] of b(c, v, y))
        v !== l && !a.has(l) && u.push([l, _]);
    }
    H(c, "H", () => {
      const v = /* @__PURE__ */ new Set([s]);
      for (let y = r.length - 1; y >= 0; --y) {
        const [l, _, A] = r[y];
        let N = !1;
        for (const G of _.d.keys())
          if (G !== l && v.has(G)) {
            N = !0;
            break;
          }
        N && (w(c, l), P(c, l, _), A !== _.n && (Q(c, l, _), v.add(l))), delete _.x;
      }
    });
  }, f = (c, s, ...i) => {
    let r = !0;
    const a = (u) => W(w(c, u)), h = (u, ...v) => {
      const y = e(u);
      try {
        if (m(s, u)) {
          if (!z(u))
            throw new Error("atom not writable");
          const l = y.n, _ = v[0];
          d(u, y, _), P(c, u, y), l !== y.n && (Q(c, u, y), p(c, u, y));
          return;
        } else
          return f(c, u, ...v);
      } finally {
        r || R(c);
      }
    };
    try {
      return t(s, a, h, ...i);
    } finally {
      r = !1;
    }
  }, D = (c, ...s) => {
    const i = B();
    try {
      return f(i, c, ...s);
    } finally {
      R(i);
    }
  }, P = (c, s, i) => {
    if (i.m && !O(i.v)) {
      for (const r of i.d.keys())
        i.m.d.has(r) || (g(c, r, e(r)).t.add(s), i.m.d.add(r));
      for (const r of i.m.d || [])
        if (!i.d.has(r)) {
          i.m.d.delete(r);
          const a = M(c, r, e(r));
          a == null || a.t.delete(s);
        }
    }
  }, g = (c, s, i) => {
    if (!i.m) {
      w(c, s);
      for (const r of i.d.keys())
        g(c, r, e(r)).t.add(s);
      if (i.m = {
        l: /* @__PURE__ */ new Set(),
        d: new Set(i.d.keys()),
        t: /* @__PURE__ */ new Set()
      }, I(s)) {
        const r = i.m;
        let a;
        const h = (u, v) => {
          let y = !0;
          a = (...l) => {
            try {
              return f(u, s, ...l);
            } finally {
              y || R(u);
            }
          };
          try {
            return v();
          } finally {
            y = !1;
          }
        };
        H(c, "L", () => {
          const u = h(
            c,
            () => o(s, (...v) => a(...v))
          );
          u && (r.u = (v) => h(v, u));
        });
      }
    }
    return i.m;
  }, M = (c, s, i) => {
    if (i.m && !i.m.l.size && !Array.from(i.m.t).some((r) => {
      var a;
      return (a = e(r).m) == null ? void 0 : a.d.has(s);
    })) {
      const r = i.m.u;
      r && H(c, "L", () => r(c)), delete i.m;
      for (const a of i.d.keys()) {
        const h = M(c, a, e(a));
        h == null || h.t.delete(s);
      }
      return;
    }
    return i.m;
  };
  return {
    get: E,
    set: D,
    sub: (c, s) => {
      const i = B(), r = e(c), h = g(i, c, r).l;
      return h.add(s), R(i), () => {
        h.delete(s);
        const u = B();
        M(u, c, r), R(u);
      };
    },
    unstable_derive: (c) => Z(...c(e, n, t, o))
  };
}, le = (e) => {
  const n = /* @__PURE__ */ new WeakMap(), t = /* @__PURE__ */ new Set();
  let o, d = 0;
  const w = e.unstable_derive(
    (p, f, D, P) => (o = p, [
      (g) => {
        let M = n.get(g);
        if (!M) {
          const S = p(g);
          M = new Proxy(S, {
            set(C, T, c) {
              return T === "m" && t.add(g), Reflect.set(C, T, c);
            },
            deleteProperty(C, T) {
              return T === "m" && t.delete(g), Reflect.deleteProperty(C, T);
            }
          }), n.set(g, M);
        }
        return M;
      },
      f,
      (g, M, S, ...C) => d ? S(g, ...C) : D(g, M, S, ...C),
      P
    ])
  ), E = w.set;
  return Object.assign(w, {
    // store dev methods (these are tentative and subject to change without notice)
    dev4_get_internal_weak_map: () => ({
      get: (p) => {
        const f = o(p);
        if (f.n !== 0)
          return f;
      }
    }),
    dev4_get_mounted_atoms: () => t,
    dev4_restore_atoms: (p) => {
      E({
        read: () => null,
        write: (D, P) => {
          ++d;
          try {
            for (const [g, M] of p)
              z(g) && P(g, M);
          } finally {
            --d;
          }
        }
      });
    }
  });
}, fe = () => {
  const e = /* @__PURE__ */ new WeakMap(), t = Z(
    (o) => {
      if ((k ? "production" : void 0) !== "production" && !o)
        throw new Error("Atom is undefined or null");
      let d = e.get(o);
      return d || (d = { d: /* @__PURE__ */ new Map(), p: /* @__PURE__ */ new Set(), n: 0 }, e.set(o, d)), d;
    },
    (o, ...d) => o.read(...d),
    (o, ...d) => o.write(...d),
    (o, ...d) => {
      var w;
      return (w = o.onMount) == null ? void 0 : w.call(o, ...d);
    }
  );
  return (k ? "production" : void 0) !== "production" ? le(t) : t;
};
let F;
const ae = () => (F || (F = fe(), (k ? "production" : void 0) !== "production" && (globalThis.__JOTAI_DEFAULT_STORE__ || (globalThis.__JOTAI_DEFAULT_STORE__ = F), globalThis.__JOTAI_DEFAULT_STORE__ !== F && console.warn(
  "Detected multiple Jotai instances. It may cause unexpected behavior with the default store. https://github.com/pmndrs/jotai/discussions/2044"
))), F), ee = {}, ve = L.createContext(
  void 0
), $ = (e) => {
  const n = L.useContext(ve);
  return (e == null ? void 0 : e.store) || n || ae();
}, J = (e) => typeof (e == null ? void 0 : e.then) == "function", ne = (e) => {
  e.status = "pending", e.then(
    (n) => {
      e.status = "fulfilled", e.value = n;
    },
    (n) => {
      e.status = "rejected", e.reason = n;
    }
  );
}, we = te.use || ((e) => {
  if (e.status === "pending")
    throw e;
  if (e.status === "fulfilled")
    return e.value;
  throw e.status === "rejected" ? e.reason : (ne(e), e);
}), x = /* @__PURE__ */ new WeakMap(), V = (e) => {
  let n = x.get(e);
  return n || (n = new Promise((t, o) => {
    let d = e;
    const w = (p) => (f) => {
      d === p && t(f);
    }, E = (p) => (f) => {
      d === p && o(f);
    }, b = (p) => {
      "onCancel" in p && typeof p.onCancel == "function" && p.onCancel((f) => {
        if ((ee ? "production" : void 0) !== "production" && f === p)
          throw new Error("[Bug] p is not updated even after cancelation");
        J(f) ? (x.set(f, n), d = f, f.then(w(f), E(f)), b(f)) : t(f);
      });
    };
    e.then(w(e), E(e)), b(e);
  }), x.set(e, n)), n;
};
function he(e, n) {
  const t = $(n), [[o, d, w], E] = L.useReducer(
    (f) => {
      const D = t.get(e);
      return Object.is(f[0], D) && f[1] === t && f[2] === e ? f : [D, t, e];
    },
    void 0,
    () => [t.get(e), t, e]
  );
  let b = o;
  (d !== t || w !== e) && (E(), b = t.get(e));
  const p = n == null ? void 0 : n.delay;
  if (L.useEffect(() => {
    const f = t.sub(e, () => {
      if (typeof p == "number") {
        const D = t.get(e);
        J(D) && ne(V(D)), setTimeout(E, p);
        return;
      }
      E();
    });
    return E(), f;
  }, [t, e, p]), L.useDebugValue(b), J(b)) {
    const f = V(b);
    return we(f);
  }
  return b;
}
function pe(e, n) {
  const t = $(n);
  return L.useCallback(
    (...d) => {
      if ((ee ? "production" : void 0) !== "production" && !("write" in e))
        throw new Error("not writable atom");
      return t.set(e, ...d);
    },
    [t, e]
  );
}
function Me(e, n) {
  return [
    he(e, n),
    // We do wrong type assertion here, which results in throwing an error.
    pe(e, n)
  ];
}
const X = /* @__PURE__ */ new WeakMap();
function Ae(e, n) {
  const t = $(n), o = ye(t);
  for (const [d, w] of e)
    (!o.has(d) || n != null && n.dangerouslyForceHydrate) && (o.add(d), t.set(d, w));
}
const ye = (e) => {
  let n = X.get(e);
  return n || (n = /* @__PURE__ */ new WeakSet(), X.set(e, n)), n;
};
export {
  he as a,
  Me as b,
  $ as c,
  fe as d,
  Ae as e,
  ge as f,
  pe as u
};
