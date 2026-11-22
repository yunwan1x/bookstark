const w = (() => {
  if (typeof self > "u") return !1;
  if (!("top" in self && self !== top)) {
    if ("showOpenFilePicker" in self) return "showOpenFilePicker";
  }
  return !1;
})(), b = w ? Promise.resolve().then(() => S) : Promise.resolve().then(() => j);
async function L(...e) {
  return (await b).default(...e);
}
w ? Promise.resolve().then(() => A) : Promise.resolve().then(() => x);
const g = w ? Promise.resolve().then(() => R) : Promise.resolve().then(() => I);
async function F(...e) {
  return (await g).default(...e);
}
const P = async (e) => {
  const t = await e.getFile();
  return t.handle = e, t;
};
var O = async (e = [{}]) => {
  Array.isArray(e) || (e = [e]);
  const t = [];
  e.forEach((o, a) => {
    t[a] = { description: o.description || "", accept: {} }, o.mimeTypes ? o.mimeTypes.map((i) => {
      t[a].accept[i] = o.extensions || [];
    }) : t[a].accept["*/*"] = o.extensions || [];
  });
  const n = await window.showOpenFilePicker({ id: e[0].id, startIn: e[0].startIn, types: t, multiple: e[0].multiple || !1, excludeAcceptAllOption: e[0].excludeAcceptAllOption || !1 }), r = await Promise.all(n.map(P));
  return e[0].multiple ? r : r[0];
};
const S = /* @__PURE__ */ Object.freeze(/* @__PURE__ */ Object.defineProperty({
  __proto__: null,
  default: O
}, Symbol.toStringTag, { value: "Module" }));
var _ = async (e = [{}]) => (Array.isArray(e) || (e = [e]), new Promise((t, n) => {
  const r = document.createElement("input");
  r.type = "file";
  const o = [...e.map((l) => l.mimeTypes || []), ...e.map((l) => l.extensions || [])].join();
  r.multiple = e[0].multiple || !1, r.accept = o || "";
  const a = (l) => {
    typeof i == "function" && i(), t(l);
  }, i = e[0].legacySetup && e[0].legacySetup(a, () => i(n), r);
  r.addEventListener("change", () => {
    a(r.multiple ? Array.from(r.files) : r.files[0]);
  }), r.click();
}));
const j = /* @__PURE__ */ Object.freeze(/* @__PURE__ */ Object.defineProperty({
  __proto__: null,
  default: _
}, Symbol.toStringTag, { value: "Module" }));
function m(e) {
  function t(n) {
    if (Object(n) !== n) return Promise.reject(new TypeError(n + " is not an object."));
    var r = n.done;
    return Promise.resolve(n.value).then(function(o) {
      return { value: o, done: r };
    });
  }
  return m = function(n) {
    this.s = n, this.n = n.next;
  }, m.prototype = { s: null, n: null, next: function() {
    return t(this.n.apply(this.s, arguments));
  }, return: function(n) {
    var r = this.s.return;
    return r === void 0 ? Promise.resolve({ value: n, done: !0 }) : t(r.apply(this.s, arguments));
  }, throw: function(n) {
    var r = this.s.return;
    return r === void 0 ? Promise.reject(n) : t(r.apply(this.s, arguments));
  } }, new m(e);
}
const h = async (e, t, n = e.name, r) => {
  const o = [], a = [];
  var i, l = !1, u = !1;
  try {
    for (var c, p = (function(s) {
      var f, y, d, v = 2;
      for (typeof Symbol < "u" && (y = Symbol.asyncIterator, d = Symbol.iterator); v--; ) {
        if (y && (f = s[y]) != null) return f.call(s);
        if (d && (f = s[d]) != null) return new m(f.call(s));
        y = "@@asyncIterator", d = "@@iterator";
      }
      throw new TypeError("Object is not async iterable");
    })(e.values()); l = !(c = await p.next()).done; l = !1) {
      const s = c.value, f = `${n}/${s.name}`;
      s.kind === "file" ? a.push(s.getFile().then((y) => (y.directoryHandle = e, y.handle = s, Object.defineProperty(y, "webkitRelativePath", { configurable: !0, enumerable: !0, get: () => f })))) : s.kind !== "directory" || !t || r && r(s) || o.push(h(s, t, f, r));
    }
  } catch (s) {
    u = !0, i = s;
  } finally {
    try {
      l && p.return != null && await p.return();
    } finally {
      if (u) throw i;
    }
  }
  return [...(await Promise.all(o)).flat(), ...await Promise.all(a)];
};
var k = async (e = {}) => {
  e.recursive = e.recursive || !1;
  const t = await window.showDirectoryPicker({ id: e.id, startIn: e.startIn });
  return h(t, e.recursive, void 0, e.skipDirectory);
};
const A = /* @__PURE__ */ Object.freeze(/* @__PURE__ */ Object.defineProperty({
  __proto__: null,
  default: k
}, Symbol.toStringTag, { value: "Module" }));
var T = async (e = [{}]) => (Array.isArray(e) || (e = [e]), e[0].recursive = e[0].recursive || !1, new Promise((t, n) => {
  const r = document.createElement("input");
  r.type = "file", r.webkitdirectory = !0;
  const o = (i) => {
    typeof a == "function" && a(), t(i);
  }, a = e[0].legacySetup && e[0].legacySetup(o, () => a(n), r);
  r.addEventListener("change", () => {
    let i = Array.from(r.files);
    e[0].recursive ? e[0].recursive && e[0].skipDirectory && (i = i.filter((l) => l.webkitRelativePath.split("/").every((u) => !e[0].skipDirectory({ name: u, kind: "directory" })))) : i = i.filter((l) => l.webkitRelativePath.split("/").length === 2), o(i);
  }), r.click();
}));
const x = /* @__PURE__ */ Object.freeze(/* @__PURE__ */ Object.defineProperty({
  __proto__: null,
  default: T
}, Symbol.toStringTag, { value: "Module" }));
var E = async (e, t = [{}], n = null, r = !1, o = null) => {
  Array.isArray(t) || (t = [t]), t[0].fileName = t[0].fileName || "Untitled";
  const a = [];
  let i = null;
  if (e instanceof Blob && e.type ? i = e.type : e.headers && e.headers.get("content-type") && (i = e.headers.get("content-type")), t.forEach((c, p) => {
    a[p] = { description: c.description || "", accept: {} }, c.mimeTypes ? (p === 0 && i && c.mimeTypes.push(i), c.mimeTypes.map((s) => {
      a[p].accept[s] = c.extensions || [];
    })) : i && (a[p].accept[i] = c.extensions || []);
  }), n) try {
    await n.getFile();
  } catch (c) {
    if (n = null, r) throw c;
  }
  const l = n || await window.showSaveFilePicker({ suggestedName: t[0].fileName, id: t[0].id, startIn: t[0].startIn, types: a, excludeAcceptAllOption: t[0].excludeAcceptAllOption || !1 });
  !n && o && o();
  const u = await l.createWritable();
  return "stream" in e ? (await e.stream().pipeTo(u), l) : "body" in e ? (await e.body.pipeTo(u), l) : (await u.write(await e), await u.close(), l);
};
const R = /* @__PURE__ */ Object.freeze(/* @__PURE__ */ Object.defineProperty({
  __proto__: null,
  default: E
}, Symbol.toStringTag, { value: "Module" }));
var $ = async (e, t = {}) => {
  Array.isArray(t) && (t = t[0]);
  const n = document.createElement("a");
  let r = e;
  "body" in e && (r = await (async function(i, l) {
    const u = i.getReader(), c = new ReadableStream({ start: (f) => (async function y() {
      return u.read().then(({ done: d, value: v }) => {
        if (!d) return f.enqueue(v), y();
        f.close();
      });
    })() }), p = new Response(c), s = await p.blob();
    return u.releaseLock(), new Blob([s], { type: l });
  })(e.body, e.headers.get("content-type"))), n.download = t.fileName || "Untitled", n.href = URL.createObjectURL(await r);
  const o = () => {
    typeof a == "function" && a();
  }, a = t.legacySetup && t.legacySetup(o, () => a(reject), n);
  return n.addEventListener("click", () => {
    setTimeout(() => URL.revokeObjectURL(n.href), 3e4), o();
  }), n.click(), null;
};
const I = /* @__PURE__ */ Object.freeze(/* @__PURE__ */ Object.defineProperty({
  __proto__: null,
  default: $
}, Symbol.toStringTag, { value: "Module" }));
export {
  w as e,
  L as n,
  F as s
};
