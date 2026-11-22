var ry = Object.defineProperty;
var iy = (e, t, r) => t in e ? ry(e, t, { enumerable: !0, configurable: !0, writable: !0, value: r }) : e[t] = r;
var bt = (e, t, r) => iy(e, typeof t != "symbol" ? t + "" : t, r);
import { n as ue } from "./excalidraw-nanoid.js";
import { g as sy } from "./excalidraw-react.js";
import { a as C, b as A, d as I, l as $, i as _e, r as gr } from "./excalidraw-khroma.js";
import { G as pn, H as oy, I as Rl } from "./excalidraw-lodash.js";
import { a as G } from "./excalidraw-roughjs.js";
const as = 20, ay = {
  rect: "rectangle",
  circle: "ellipse"
}, bs = {
  startOnLoad: !1,
  flowchart: { curve: "linear" },
  themeVariables: {
    fontSize: `${as}px`
  },
  maxEdges: 500,
  maxTextSize: 5e4
};
class gi {
  constructor({ converter: t }) {
    this.convert = (r, i) => this.converter(r, {
      ...i,
      fontSize: i.fontSize || as
    }), this.converter = t;
  }
}
var Je;
(function(e) {
  e.ROUND = "round", e.STADIUM = "stadium", e.DOUBLECIRCLE = "doublecircle", e.CIRCLE = "circle", e.DIAMOND = "diamond", e.CYLINDER = "cylinder";
})(Je || (Je = {}));
var jt;
(function(e) {
  e.COLOR = "color";
})(jt || (jt = {}));
var ft;
(function(e) {
  e.FILL = "fill", e.STROKE = "stroke", e.STROKE_WIDTH = "stroke-width", e.STROKE_DASHARRAY = "stroke-dasharray";
})(ft || (ft = {}));
var ki = {}, Pl;
function ny() {
  if (Pl) return ki;
  Pl = 1, Object.defineProperty(ki, "__esModule", { value: !0 }), ki.removeMarkdown = void 0;
  var e = function(t, r) {
    r === void 0 && (r = {
      listUnicodeChar: ""
    }), r = r || {}, r.listUnicodeChar = r.hasOwnProperty("listUnicodeChar") ? r.listUnicodeChar : !1, r.stripListLeaders = r.hasOwnProperty("stripListLeaders") ? r.stripListLeaders : !0, r.gfm = r.hasOwnProperty("gfm") ? r.gfm : !0, r.useImgAltText = r.hasOwnProperty("useImgAltText") ? r.useImgAltText : !0, r.preserveLinks = r.hasOwnProperty("preserveLinks") ? r.preserveLinks : !1;
    var i = t || "";
    i = i.replace(/^(-\s*?|\*\s*?|_\s*?){3,}\s*$/gm, "");
    try {
      r.stripListLeaders && (r.listUnicodeChar ? i = i.replace(/^([\s\t]*)([\*\-\+]|\d+\.)\s+/gm, r.listUnicodeChar + " $1") : i = i.replace(/^([\s\t]*)([\*\-\+]|\d+\.)\s+/gm, "$1")), r.gfm && (i = i.replace(/\n={2,}/g, `
`).replace(/~{3}.*\n/g, "").replace(/~~/g, "").replace(/`{3}.*\n/g, "")), r.preserveLinks && (i = i.replace(/\[(.*?)\][\[\(](.*?)[\]\)]/g, "$1 ($2)")), i = i.replace(/<[^>]*>/g, "").replace(/^[=\-]{2,}\s*$/g, "").replace(/\[\^.+?\](\: .*?$)?/g, "").replace(/\s{0,2}\[.*?\]: .*?$/g, "").replace(/\!\[(.*?)\][\[\(].*?[\]\)]/g, r.useImgAltText ? "$1" : "").replace(/\[(.*?)\][\[\(].*?[\]\)]/g, "$1").replace(/^\s{0,3}>\s?/g, "").replace(/(^|\n)\s{0,3}>\s?/g, `

`).replace(/^\s{1,2}\[(.*?)\]: (\S+)( ".*?")?\s*$/g, "").replace(/^(\n)?\s{0,}#{1,6}\s+| {0,}(\n)?\s{0,}#{0,} {0,}(\n)?\s{0,}$/gm, "$1$2$3").replace(/([\*_]{1,3})(\S.*?\S{0,1})\1/g, "$2").replace(/([\*_]{1,3})(\S.*?\S{0,1})\1/g, "$2").replace(/(`{3,})(.*?)\1/gm, "$2").replace(/`(.+?)`/g, "$1").replace(/\n{2,}/g, `

`);
    } catch (s) {
      return console.error(s), t;
    }
    return i;
  };
  return ki.removeMarkdown = e, ki;
}
var ly = ny();
const hy = {
  arrow_circle: {
    endArrowhead: "circle"
  },
  arrow_cross: {
    endArrowhead: "bar"
  },
  arrow_open: {
    endArrowhead: null,
    startArrowhead: null
  },
  double_arrow_circle: {
    endArrowhead: "circle",
    startArrowhead: "circle"
  },
  double_arrow_cross: {
    endArrowhead: "bar",
    startArrowhead: "bar"
  },
  double_arrow_point: {
    endArrowhead: "arrow",
    startArrowhead: "arrow"
  }
}, cy = (e) => hy[e], Vo = (e) => {
  let t = e.text;
  return e.labelType === "markdown" && (t = ly.removeMarkdown(e.text)), uy(t);
}, uy = (e) => {
  const t = /\s?(fa|fab):[a-zA-Z0-9-]+/g;
  return e.replace(t, "");
}, Ui = (e) => {
  const t = {};
  return Object.keys(e).forEach((r) => {
    var i;
    switch (r) {
      case ft.FILL: {
        t.backgroundColor = e[r], t.fillStyle = "solid";
        break;
      }
      case ft.STROKE: {
        t.strokeColor = e[r];
        break;
      }
      case ft.STROKE_WIDTH: {
        t.strokeWidth = Number((i = e[r]) == null ? void 0 : i.split("px")[0]);
        break;
      }
      case ft.STROKE_DASHARRAY: {
        t.strokeStyle = "dashed";
        break;
      }
    }
  }), t;
}, fa = (e) => {
  const t = {};
  return Object.keys(e).forEach((r) => {
    switch (r) {
      case jt.COLOR: {
        t.strokeColor = e[r];
        break;
      }
    }
  }), t;
}, dy = (e, t) => [e, t], py = 32, vc = 0.62, fy = 12, gy = 12, Lc = (e, t) => Math.max(20, Math.ceil(e.length * t * vc)), my = (e, t, r, i) => {
  const s = i || as;
  if (e !== Je.CYLINDER || !t || t.includes(`
`))
    return s;
  const o = Math.max(20, r - fy);
  return Lc(t, s) <= o ? s : Math.max(gy, Math.floor(o / (t.length * vc)));
}, yy = (e) => {
  const t = {};
  e.subGraphs.map((i) => {
    i.nodeIds.forEach((s) => {
      t[i.id] = {
        id: i.id,
        parent: null,
        isLeaf: !1
      }, t[s] = {
        id: s,
        parent: i.id,
        isLeaf: e.vertices[s] !== void 0
      };
    });
  });
  const r = {};
  return [...Object.keys(e.vertices), ...e.subGraphs.map((i) => i.id)].forEach((i) => {
    if (!t[i])
      return;
    let s = t[i];
    const o = [];
    for (s.isLeaf || o.push(`subgraph_group_${s.id}`); s.parent; )
      o.push(`subgraph_group_${s.parent}`), s = t[s.parent];
    r[i] = o;
  }), {
    getGroupIds: (i) => r[i] || [],
    getParentId: (i) => t[i] ? t[i].parent : null
  };
}, xy = new gi({
  converter: (e, t) => {
    const r = [], i = t.fontSize, { getGroupIds: s, getParentId: o } = yy(e);
    return e.subGraphs.reverse().forEach((a) => {
      const n = s(a.id), l = Vo(a), u = Lc(l, i || 16) + py * 2, p = Math.max(a.width, u), d = a.x - (p - a.width) / 2, g = Ui(a.containerStyle), m = fa(a.labelStyle), y = {
        id: a.id,
        type: "rectangle",
        groupIds: n,
        x: d,
        y: a.y,
        width: p,
        height: a.height,
        label: {
          groupIds: n,
          text: l,
          fontSize: i,
          verticalAlign: "top",
          ...m
        },
        ...g
      };
      r.push(y);
    }), Object.values(e.vertices).forEach((a) => {
      if (!a)
        return;
      const n = s(a.id), l = Vo(a), h = my(a.type, l, a.width, i), c = Ui(a.containerStyle), u = fa(a.labelStyle);
      let p = {
        id: a.id,
        type: "rectangle",
        groupIds: n,
        x: a.x,
        y: a.y,
        width: a.width,
        height: a.height,
        strokeWidth: 2,
        label: {
          groupIds: n,
          text: l,
          fontSize: h,
          ...u
        },
        link: a.link || null,
        ...c
      };
      switch (a.type) {
        case Je.STADIUM: {
          p = { ...p, roundness: { type: 3 } };
          break;
        }
        case Je.ROUND: {
          p = { ...p, roundness: { type: 3 } };
          break;
        }
        case Je.DOUBLECIRCLE: {
          n.push(`doublecircle_${a.id}}`);
          const g = {
            type: "ellipse",
            groupIds: n,
            x: a.x + 5,
            y: a.y + 5,
            width: a.width - 10,
            height: a.height - 10,
            strokeWidth: 2,
            roundness: { type: 3 },
            label: {
              groupIds: n,
              text: l,
              fontSize: h,
              ...u
            }
          };
          p = { ...p, groupIds: n, type: "ellipse" }, r.push(g);
          break;
        }
        case Je.CIRCLE: {
          p.type = "ellipse";
          break;
        }
        case Je.DIAMOND: {
          p.type = "diamond";
          break;
        }
      }
      r.push(p);
    }), e.edges.forEach((a) => {
      let n = [];
      const l = o(a.start), h = o(a.end);
      l && l === h && (n = s(l));
      const { startX: c, startY: u, reflectionPoints: p } = a, d = p.map((k) => dy(k.x - p[0].x, k.y - p[0].y)), g = cy(a.type || "arrow_point"), m = r.find((k) => k.id === a.start), y = r.find((k) => k.id === a.end);
      if (!m || !y)
        return;
      const b = {
        id: `${a.start}_${a.end}`,
        type: "arrow",
        groupIds: n,
        x: c,
        y: u,
        // 4 and 2 are the Excalidraw's stroke width of thick and thin respectively
        // TODO: use constant exported from Excalidraw package
        strokeWidth: a.stroke === "thick" ? 4 : 2,
        strokeStyle: a.stroke === "dotted" ? "dashed" : void 0,
        points: d,
        ...a.text ? { label: { text: Vo(a), fontSize: i, groupIds: n } } : {},
        roundness: {
          type: 2
        },
        ...g,
        start: {
          id: m.id || ""
        },
        end: {
          id: y.id || ""
        }
      };
      r.push(b);
    }), {
      elements: r
    };
  }
}), Cy = new gi({
  converter: (e) => {
    const t = ue(), { width: r, height: i } = e, s = {
      type: "image",
      x: 0,
      y: 0,
      width: r,
      height: i,
      status: "saved",
      fileId: t
    };
    return { files: {
      [t]: {
        id: t,
        mimeType: e.mimeType,
        dataURL: e.dataURL
      }
    }, elements: [s] };
  }
}), qi = (e, t) => [e, t], fn = (e) => e.replace(/\\n/g, `
`), mr = (e) => {
  const t = {
    type: "line",
    x: e.startX,
    y: e.startY,
    points: [
      qi(0, 0),
      qi(e.endX - e.startX, e.endY - e.startY)
    ],
    width: e.endX - e.startX,
    height: e.endY - e.startY,
    strokeStyle: e.strokeStyle || "solid",
    strokeColor: e.strokeColor || "#000",
    strokeWidth: e.strokeWidth || 1
  };
  return e.groupId && Object.assign(t, { groupIds: [e.groupId] }), e.id && Object.assign(t, { id: e.id }), t;
}, yr = (e) => {
  const t = {
    type: "text",
    x: e.x,
    y: e.y,
    width: e.width,
    height: e.height,
    text: fn(e.text) || "",
    fontSize: e.fontSize,
    verticalAlign: "top",
    strokeColor: e.color
  };
  return e.groupId && Object.assign(t, { groupIds: [e.groupId] }), e.id && Object.assign(t, { id: e.id }), t;
}, zr = (e) => {
  var s, o, a, n, l;
  const t = {
    text: fn(((s = e == null ? void 0 : e.label) == null ? void 0 : s.text) || ""),
    fontSize: (o = e == null ? void 0 : e.label) == null ? void 0 : o.fontSize,
    textAlign: (a = e.label) == null ? void 0 : a.textAlign,
    verticalAlign: ((n = e.label) == null ? void 0 : n.verticalAlign) || "middle",
    strokeColor: ((l = e.label) == null ? void 0 : l.color) || "#000",
    ...e.groupId ? { groupIds: [e.groupId] } : {}
  };
  let r = {};
  e.type === "rectangle" && e.subtype === "activation" && (r = {
    backgroundColor: "#e9ecef",
    fillStyle: "solid"
  });
  const i = {
    id: e.id,
    type: e.type,
    x: e.x,
    y: e.y,
    width: e.width,
    height: e.height,
    label: t,
    strokeStyle: e == null ? void 0 : e.strokeStyle,
    strokeWidth: e == null ? void 0 : e.strokeWidth,
    strokeColor: e == null ? void 0 : e.strokeColor,
    backgroundColor: e == null ? void 0 : e.bgColor,
    fillStyle: "solid",
    ...r
  };
  return e.groupId && Object.assign(i, { groupIds: [e.groupId] }), i;
}, gn = (e) => {
  var r, i, s, o;
  const t = {
    type: "arrow",
    x: e.startX,
    y: e.startY,
    points: ((r = e.points) == null ? void 0 : r.map(([a, n]) => qi(a, n))) || [
      qi(0, 0),
      qi(e.endX - e.startX, e.endY - e.startY)
    ],
    width: e.endX - e.startX,
    height: e.endY - e.startY,
    strokeStyle: (e == null ? void 0 : e.strokeStyle) || "solid",
    endArrowhead: (e == null ? void 0 : e.endArrowhead) || null,
    startArrowhead: (e == null ? void 0 : e.startArrowhead) || null,
    label: {
      text: fn(((i = e == null ? void 0 : e.label) == null ? void 0 : i.text) || ""),
      fontSize: 16,
      textAlign: (s = e == null ? void 0 : e.label) == null ? void 0 : s.textAlign,
      verticalAlign: (o = e == null ? void 0 : e.label) == null ? void 0 : o.verticalAlign
    },
    roundness: {
      type: 2
    },
    start: e.start,
    end: e.end
  };
  return e.groupId && Object.assign(t, { groupIds: [e.groupId] }), t;
}, ks = 10, Zo = 16, by = 24, ky = 4, Ty = (e) => {
  if (!e)
    return !0;
  const t = e.trim().toLowerCase();
  return t === "transparent" || t === "none" || t === "rgba(0,0,0,0)" || t === "rgba(0, 0, 0, 0)";
}, Sy = (e, t) => Math.max(20, Math.round(e.length * t * 0.6)), Nl = (e, t, r = !0) => {
  const i = e, s = i.groupIds ?? [];
  if (s.includes(t) || (i.groupIds = [...s, t]), !r || !i.label)
    return;
  const o = i.label.groupIds ?? [];
  o.includes(t) || (i.label.groupIds = [...o, t]);
}, wy = new gi({
  converter: (e) => {
    const t = [], r = [];
    if (Object.values(e.nodes).forEach((i) => {
      !i || !i.length || i.forEach((s) => {
        let o;
        switch (s.type) {
          case "line":
            o = mr(s);
            break;
          case "rectangle":
          case "ellipse":
            o = zr(s);
            break;
          case "text":
            o = yr(s);
            break;
          default:
            throw `unknown type ${s.type}`;
        }
        s.type === "rectangle" && (s == null ? void 0 : s.subtype) === "activation" ? r.push(o) : t.push(o);
      });
    }), Object.values(e.lines).forEach((i) => {
      i && t.push(mr(i));
    }), Object.values(e.arrows).forEach((i) => {
      i && (t.push(gn(i)), i.sequenceNumber && t.push(zr(i.sequenceNumber)));
    }), t.push(...r), e.loops) {
      const { lines: i, texts: s, nodes: o } = e.loops;
      i.forEach((a) => {
        t.push(mr(a));
      }), s.forEach((a) => {
        t.push(yr(a));
      }), o.forEach((a) => {
        t.push(zr(a));
      });
    }
    return e.groups && e.groups.forEach((i) => {
      const { actorKeys: s, name: o } = i;
      let a = 1 / 0, n = 1 / 0, l = 0, h = 0;
      if (!s.length)
        return;
      const c = t.filter((b) => {
        if (b.id) {
          const k = b.id.indexOf("-"), w = b.id.substring(0, k);
          return s.includes(w);
        }
        return !1;
      });
      if (!c.length || (c.forEach((b) => {
        b.x === void 0 || b.y === void 0 || b.width === void 0 || b.height === void 0 || (a = Math.min(a, b.x), n = Math.min(n, b.y), l = Math.max(l, b.x + b.width), h = Math.max(h, b.y + b.height));
      }), !Number.isFinite(a) || !Number.isFinite(n) || !Number.isFinite(l) || !Number.isFinite(h)))
        return;
      const u = a - ks, p = n - ks, d = l - a + ks * 2, g = h - n + ks * 2, m = ue(), y = ue(), x = zr({
        type: "rectangle",
        x: u,
        y: p,
        width: d,
        height: g,
        bgColor: Ty(i.fill) ? void 0 : i.fill,
        strokeColor: "#1f1f1f",
        strokeWidth: 1,
        id: m,
        groupId: y
      });
      if (t.unshift(x), t.forEach((b) => {
        b.id !== m && (b.x === void 0 || b.y === void 0 || b.width === void 0 || b.height === void 0 || b.x >= a && b.x + b.width <= l && b.y >= n && b.y + b.height <= h && Nl(b, y));
      }), o) {
        const b = yr({
          id: ue(),
          text: o,
          x: u + ky,
          y: p - by,
          width: Sy(o, Zo),
          height: Zo + 8,
          fontSize: Zo,
          color: "#1f1f1f",
          groupId: y
        });
        Nl(b, y, !1), t.push(b);
      }
    }), { elements: t };
  }
}), _y = new gi({
  converter: (e) => {
    const t = [];
    return e.nodes.forEach((r) => {
      !r || !r.length || r.forEach((i) => {
        let s;
        switch (i.type) {
          case "line":
            s = mr(i);
            break;
          case "rectangle":
          case "ellipse":
            s = zr(i);
            break;
          case "text":
            s = yr(i);
            break;
          default:
            throw `unknown type ${i.type}`;
        }
        t.push(s);
      });
    }), Object.values(e.lines).forEach((r) => {
      r && t.push(mr(r));
    }), Object.values(e.arrows).forEach((r) => {
      if (!r)
        return;
      const i = gn(r);
      t.push(i);
    }), Object.values(e.text).forEach((r) => {
      const i = yr(r);
      t.push(i);
    }), Object.values(e.namespaces).forEach((r) => {
      const i = Object.keys(r.classes), s = [...i], o = [...e.lines, ...e.arrows, ...e.text];
      i.forEach((n) => {
        const l = o.filter((h) => h.metadata && h.metadata.classId === n).map((h) => h.id);
        l.length && s.push(...l);
      });
      const a = {
        type: "frame",
        id: ue(),
        name: r.id,
        children: s
      };
      t.push(a);
    }), { elements: t };
  }
}), By = new gi({
  converter: (e) => {
    const t = [];
    return e.nodes.forEach((r) => {
      !r || !r.length || r.forEach((i) => {
        let s;
        switch (i.type) {
          case "line":
            s = mr(i);
            break;
          case "rectangle":
          case "ellipse":
            s = zr(i);
            break;
          case "text":
            s = yr(i);
            break;
          default:
            throw `unknown type ${i.type}`;
        }
        t.push(s);
      });
    }), e.lines.forEach((r) => {
      t.push(mr(r));
    }), e.arrows.forEach((r) => {
      t.push(gn(r));
    }), e.text.forEach((r) => {
      t.push(yr(r));
    }), { elements: t };
  }
}), Hs = (e, t) => [e, t], Fi = 16, Ac = 14, vy = 1, ga = "#000000", Ec = 5, Ly = Ec * 2, Ay = Ec * 2, Ey = 1.25, Fc = /* @__PURE__ */ new Set([
  "choice",
  "fork",
  "join",
  "stateStart",
  "stateEnd",
  "divider"
]), ma = (e) => e.shape === "stateEnd" ? [`state_end_group_${e.id}`] : void 0, Mc = (e) => e.shape === "rectWithTitle" && e.description.length ? [e.text, ...e.description].join(`
`) : e.text;
let lr;
const Fy = () => {
  if (lr !== void 0)
    return lr;
  if (typeof document > "u")
    return lr = null, lr;
  try {
    lr = document.createElement("canvas").getContext("2d");
  } catch {
    lr = null;
  }
  return lr;
}, ai = (e, t) => {
  const r = Fy();
  return r ? (r.font = `${t}px Excalifont, sans-serif`, r.measureText(e).width) : e.length * t * 0.6;
}, My = (e, t, r) => {
  if (ai(e, t) <= r)
    return [e];
  const i = [];
  let s = "";
  for (const o of e) {
    const a = `${s}${o}`;
    if (s && ai(a, t) > r) {
      i.push(s), s = o;
      continue;
    }
    s = a;
  }
  return s && i.push(s), i;
}, Iy = (e, t, r) => {
  if (!e.trim() || ai(e, t) <= r)
    return e;
  const i = e.split(/\s+/).filter(Boolean), s = [];
  let o = "";
  for (const a of i) {
    const n = My(a, t, r);
    for (const [l, h] of n.entries()) {
      const u = o ? `${o}${o && l === 0 ? " " : ""}${h}` : h;
      if (ai(u, t) <= r) {
        o = u;
        continue;
      }
      o && s.push(o), o = h;
    }
    n.length > 1;
  }
  return s.push(o), s.join(`
`);
}, $y = (e, t, r) => {
  const s = e.map((n) => Iy(n, t, r)).join(`
`).split(`
`), o = Math.max(...s.map((n) => ai(n, t))), a = s.length * t * Ey;
  return {
    width: o,
    height: a
  };
}, Oy = (e, t, r, i) => {
  const s = e.split(`
`);
  for (let o = Fi; o >= Ac; o -= vy) {
    const { height: a } = $y(s, o, t);
    if (a <= r)
      return o;
  }
  return i;
}, Dy = (e) => {
  const t = Mc(e);
  if (!t || Fc.has(e.shape))
    return Fi;
  const r = Math.max(1, e.width - Ly), i = Math.max(1, e.height - Ay), s = t.split(`
`);
  return s.length > 1 && Math.max(...s.map((a) => ai(a, Fi))) <= r ? Fi : Oy(t, r, i, s.length === 1 ? Fi : Ac);
}, Ry = (e) => {
  if (Fc.has(e.shape))
    return;
  const t = Mc(e);
  if (t)
    return {
      text: t,
      fontSize: Dy(e),
      verticalAlign: e.shape === "rectWithTitle" || e.shape === "roundedWithTitle" ? "top" : "middle",
      ...fa(e.labelStyle)
    };
}, Py = (e) => {
  const t = Ui(e.containerStyle), r = Ry(e), i = e.shape === "choice" ? "diamond" : e.shape === "stateStart" || e.shape === "stateEnd" ? "ellipse" : "rectangle", s = e.shape === "rect" || e.shape === "rectWithTitle" || e.shape === "roundedWithTitle", o = e.shape === "stateStart" || e.shape === "fork" || e.shape === "join", a = t.backgroundColor || t.strokeColor || ga, n = t.strokeColor || t.backgroundColor || ga;
  return {
    id: e.id,
    type: i,
    ...ma(e) ? { groupIds: ma(e) } : {},
    x: e.x,
    y: e.y,
    width: e.width,
    height: e.height,
    ...r ? { label: r } : {},
    ...t,
    ...s ? { roundness: { type: 3 } } : {},
    ...o ? {
      backgroundColor: a,
      strokeColor: n,
      fillStyle: "solid"
    } : {}
  };
}, Ny = (e) => {
  if (!e.dividerLine)
    return null;
  const t = Ui(e.containerStyle);
  return {
    id: `${e.id}__divider`,
    type: "line",
    x: e.dividerLine.startX,
    y: e.dividerLine.startY,
    width: e.dividerLine.endX - e.dividerLine.startX,
    height: e.dividerLine.endY - e.dividerLine.startY,
    points: [
      Hs(0, 0),
      Hs(e.dividerLine.endX - e.dividerLine.startX, e.dividerLine.endY - e.dividerLine.startY)
    ],
    strokeColor: t.strokeColor || "#000",
    strokeWidth: t.strokeWidth || 1
  };
}, qy = (e) => {
  const t = Ui(e.containerStyle), r = Math.max(2, Math.min(e.width, e.height) * 0.32), i = e.endInnerColor || t.strokeColor || t.backgroundColor || ga;
  return {
    id: `${e.id}__inner`,
    type: "ellipse",
    groupIds: ma(e),
    x: e.x + r,
    y: e.y + r,
    width: Math.max(1, e.width - r * 2),
    height: Math.max(1, e.height - r * 2),
    backgroundColor: i,
    strokeColor: i,
    fillStyle: "solid",
    strokeWidth: 1
  };
}, Wy = (e) => {
  const t = e.reflectionPoints.map((r, i, s) => {
    const o = s[0];
    return i === 0 ? Hs(0, 0) : Hs(r.x - o.x, r.y - o.y);
  });
  return {
    id: e.id,
    type: "arrow",
    x: e.startX,
    y: e.startY,
    width: e.endX - e.startX,
    height: e.endY - e.startY,
    points: t,
    strokeColor: e.strokeColor || "#000",
    strokeWidth: e.strokeWidth || 2,
    strokeStyle: e.strokeStyle || "solid",
    endArrowhead: e.isNoteEdge ? null : "triangle",
    roundness: { type: 2 },
    start: { id: e.start },
    end: { id: e.end },
    ...e.text ? {
      label: {
        text: e.text,
        fontSize: 16
      }
    } : {}
  };
}, zy = new gi({
  converter: (e) => {
    const t = [];
    return e.nodes.forEach((r) => {
      if (!r.isRenderable)
        return;
      const i = Py(r);
      t.push(i);
      const s = Ny(r);
      s && t.push(s), r.shape === "stateEnd" && t.push(qy(r));
    }), e.edges.forEach((r) => {
      t.push(Wy(r));
    }), { elements: t };
  }
}), ie = (e) => {
  e = Yy(e);
  const t = e.replace(/#(\d+);/g, "&#$1;").replace(/#([a-z]+);/g, "&$1;"), r = document.createElement("textarea");
  return r.innerHTML = t, r.value;
}, xr = (e) => {
  const t = e.getAttribute("transform"), r = t == null ? void 0 : t.match(/translate\(([ \d.-]+),\s*([\d.-]+)\)/);
  let i = 0, s = 0;
  return r && (i = Number(r[1]), s = Number(r[2])), { transformX: i, transformY: s };
}, Hy = (e) => {
  let t = e;
  return t = t.replace(/style.*:\S*#.*;/g, (r) => r.substring(0, r.length - 1)), t = t.replace(/classDef.*:\S*#.*;/g, (r) => r.substring(0, r.length - 1)), t = t.replace(/#\w+;/g, (r) => {
    const i = r.substring(1, r.length - 1);
    return /^\+?\d+$/.test(i) ? `ﬂ°°${i}¶ß` : `ﬂ°${i}¶ß`;
  }), t;
}, Yy = function(e) {
  return e.replace(/ﬂ°°/g, "#").replace(/ﬂ°/g, "&").replace(/¶ß/g, ";");
}, Xy = 0.5, mn = (e, t = Xy) => {
  const r = [];
  return e.forEach((i) => {
    const s = r[r.length - 1];
    if (!s) {
      r.push(i);
      return;
    }
    Math.hypot(i[0] - s[0], i[1] - s[1]) <= t || r.push(i);
  }), r;
}, yn = (e) => {
  const t = e.getAttribute("d");
  if (!t)
    return null;
  const r = Array.from(t.matchAll(/-?\d*\.?\d+(?:e[-+]?\d+)?/gi), (i) => Number(i[0]));
  return r.length < 4 ? null : {
    startX: r[0],
    startY: r[1],
    endX: r[r.length - 2],
    endY: r[r.length - 1]
  };
}, Ic = (e) => {
  const t = e.getAttribute("data-points");
  if (!t) {
    const r = yn(e);
    return r ? [
      { x: r.startX, y: r.startY },
      { x: r.endX, y: r.endY }
    ] : [];
  }
  try {
    const r = atob(t), i = JSON.parse(r);
    return Array.isArray(i) ? i.filter((s) => s && typeof s.x == "number" && typeof s.y == "number" && Number.isFinite(s.x) && Number.isFinite(s.y)) : [];
  } catch {
    return [];
  }
}, $c = (e, t = { x: 0, y: 0 }, r = "LM") => {
  if (e.tagName.toLowerCase() !== "path")
    throw new Error(`Invalid input: Expected an HTMLElement of tag "path", got ${e.tagName}`);
  const i = e.getAttribute("d");
  if (!i)
    throw new Error('Path element does not contain a "d" attribute');
  const s = i.split(new RegExp(`(?=[${r}])`)), o = s[0].substring(1).split(",").map((l) => parseFloat(l)), a = s[s.length - 1].substring(1).split(",").map((l) => parseFloat(l)), n = s.map((l) => {
    const h = l[0], c = l.substring(1).split(",").map((u) => parseFloat(u));
    return h === "C" ? {
      x: c[4],
      y: c[5],
      command: h
    } : { x: c[0], y: c[1], command: h };
  }).filter((l, h, c) => {
    if (h === 0 || h === c.length - 1)
      return !0;
    if (l.x === c[h - 1].x && l.y === c[h - 1].y || h === c.length - 2 && l.command === "C")
      return !1;
    if (h === c.length - 2 && (c[h - 1].x === l.x || c[h - 1].y === l.y)) {
      const u = c[c.length - 1];
      return Math.hypot(u.x - l.x, u.y - l.y) > 20;
    }
    return l.x !== c[h - 1].x || l.y !== c[h - 1].y;
  }).map((l) => ({
    x: l.x + t.x,
    y: l.y + t.y
  }));
  return {
    startX: o[0] + t.x,
    startY: o[1] + t.y,
    endX: a[0] + t.x,
    endY: a[1] + t.y,
    reflectionPoints: n
  };
}, Uy = (e) => ({
  ...e,
  elements: e.elements.map((t) => {
    if (!("points" in t) || !Array.isArray(t.points))
      return t;
    const r = t.points;
    if (r.length < 2)
      return t;
    const i = mn(r);
    return i.length === r.length ? t : {
      ...t,
      points: i
    };
  })
}), jy = (e, t = {}) => {
  const r = (() => {
    switch (e.type) {
      case "graphImage":
        return Cy.convert(e, t);
      case "flowchart":
        return xy.convert(e, t);
      case "sequence":
        return wy.convert(e, t);
      case "class":
        return _y.convert(e, t);
      case "erd":
        return By.convert(e, t);
      case "state":
        return zy.convert(e, t);
      default:
        throw new Error(`graphToExcalidraw: unknown graph type "${e.type}, only flowcharts are supported!"`);
    }
  })();
  return Uy(r);
};
var $s = { exports: {} }, Gy = $s.exports, ql;
function Vy() {
  return ql || (ql = 1, (function(e, t) {
    (function(r, i) {
      e.exports = i();
    })(Gy, (function() {
      var r = 1e3, i = 6e4, s = 36e5, o = "millisecond", a = "second", n = "minute", l = "hour", h = "day", c = "week", u = "month", p = "quarter", d = "year", g = "date", m = "Invalid Date", y = /^(\d{4})[-/]?(\d{1,2})?[-/]?(\d{0,2})[Tt\s]*(\d{1,2})?:?(\d{1,2})?:?(\d{1,2})?[.:]?(\d+)?$/, x = /\[([^\]]+)]|Y{1,4}|M{1,4}|D{1,2}|d{1,4}|H{1,2}|h{1,2}|a|A|m{1,2}|s{1,2}|Z{1,2}|SSS/g, b = { name: "en", weekdays: "Sunday_Monday_Tuesday_Wednesday_Thursday_Friday_Saturday".split("_"), months: "January_February_March_April_May_June_July_August_September_October_November_December".split("_"), ordinal: function(P) {
        var M = ["th", "st", "nd", "rd"], E = P % 100;
        return "[" + P + (M[(E - 20) % 10] || M[E] || M[0]) + "]";
      } }, k = function(P, M, E) {
        var D = String(P);
        return !D || D.length >= M ? P : "" + Array(M + 1 - D.length).join(E) + P;
      }, w = { s: k, z: function(P) {
        var M = -P.utcOffset(), E = Math.abs(M), D = Math.floor(E / 60), v = E % 60;
        return (M <= 0 ? "+" : "-") + k(D, 2, "0") + ":" + k(v, 2, "0");
      }, m: function P(M, E) {
        if (M.date() < E.date()) return -P(E, M);
        var D = 12 * (E.year() - M.year()) + (E.month() - M.month()), v = M.clone().add(D, u), R = E - v < 0, z = M.clone().add(D + (R ? -1 : 1), u);
        return +(-(D + (E - v) / (R ? v - z : z - v)) || 0);
      }, a: function(P) {
        return P < 0 ? Math.ceil(P) || 0 : Math.floor(P);
      }, p: function(P) {
        return { M: u, y: d, w: c, d: h, D: g, h: l, m: n, s: a, ms: o, Q: p }[P] || String(P || "").toLowerCase().replace(/s$/, "");
      }, u: function(P) {
        return P === void 0;
      } }, S = "en", L = {};
      L[S] = b;
      var T = "$isDayjsObject", B = function(P) {
        return P instanceof Y || !(!P || !P[T]);
      }, N = function P(M, E, D) {
        var v;
        if (!M) return S;
        if (typeof M == "string") {
          var R = M.toLowerCase();
          L[R] && (v = R), E && (L[R] = E, v = R);
          var z = M.split("-");
          if (!v && z.length > 1) return P(z[0]);
        } else {
          var X = M.name;
          L[X] = M, v = X;
        }
        return !D && v && (S = v), v || !D && S;
      }, O = function(P, M) {
        if (B(P)) return P.clone();
        var E = typeof M == "object" ? M : {};
        return E.date = P, E.args = arguments, new Y(E);
      }, F = w;
      F.l = N, F.i = B, F.w = function(P, M) {
        return O(P, { locale: M.$L, utc: M.$u, x: M.$x, $offset: M.$offset });
      };
      var Y = (function() {
        function P(E) {
          this.$L = N(E.locale, null, !0), this.parse(E), this.$x = this.$x || E.x || {}, this[T] = !0;
        }
        var M = P.prototype;
        return M.parse = function(E) {
          this.$d = (function(D) {
            var v = D.date, R = D.utc;
            if (v === null) return /* @__PURE__ */ new Date(NaN);
            if (F.u(v)) return /* @__PURE__ */ new Date();
            if (v instanceof Date) return new Date(v);
            if (typeof v == "string" && !/Z$/i.test(v)) {
              var z = v.match(y);
              if (z) {
                var X = z[2] - 1 || 0, ot = (z[7] || "0").substring(0, 3);
                return R ? new Date(Date.UTC(z[1], X, z[3] || 1, z[4] || 0, z[5] || 0, z[6] || 0, ot)) : new Date(z[1], X, z[3] || 1, z[4] || 0, z[5] || 0, z[6] || 0, ot);
              }
            }
            return new Date(v);
          })(E), this.init();
        }, M.init = function() {
          var E = this.$d;
          this.$y = E.getFullYear(), this.$M = E.getMonth(), this.$D = E.getDate(), this.$W = E.getDay(), this.$H = E.getHours(), this.$m = E.getMinutes(), this.$s = E.getSeconds(), this.$ms = E.getMilliseconds();
        }, M.$utils = function() {
          return F;
        }, M.isValid = function() {
          return this.$d.toString() !== m;
        }, M.isSame = function(E, D) {
          var v = O(E);
          return this.startOf(D) <= v && v <= this.endOf(D);
        }, M.isAfter = function(E, D) {
          return O(E) < this.startOf(D);
        }, M.isBefore = function(E, D) {
          return this.endOf(D) < O(E);
        }, M.$g = function(E, D, v) {
          return F.u(E) ? this[D] : this.set(v, E);
        }, M.unix = function() {
          return Math.floor(this.valueOf() / 1e3);
        }, M.valueOf = function() {
          return this.$d.getTime();
        }, M.startOf = function(E, D) {
          var v = this, R = !!F.u(D) || D, z = F.p(E), X = function(se, J) {
            var lt = F.w(v.$u ? Date.UTC(v.$y, J, se) : new Date(v.$y, J, se), v);
            return R ? lt : lt.endOf(h);
          }, ot = function(se, J) {
            return F.w(v.toDate()[se].apply(v.toDate("s"), (R ? [0, 0, 0, 0] : [23, 59, 59, 999]).slice(J)), v);
          }, tt = this.$W, st = this.$M, j = this.$D, dt = "set" + (this.$u ? "UTC" : "");
          switch (z) {
            case d:
              return R ? X(1, 0) : X(31, 11);
            case u:
              return R ? X(1, st) : X(0, st + 1);
            case c:
              var xt = this.$locale().weekStart || 0, _t = (tt < xt ? tt + 7 : tt) - xt;
              return X(R ? j - _t : j + (6 - _t), st);
            case h:
            case g:
              return ot(dt + "Hours", 0);
            case l:
              return ot(dt + "Minutes", 1);
            case n:
              return ot(dt + "Seconds", 2);
            case a:
              return ot(dt + "Milliseconds", 3);
            default:
              return this.clone();
          }
        }, M.endOf = function(E) {
          return this.startOf(E, !1);
        }, M.$set = function(E, D) {
          var v, R = F.p(E), z = "set" + (this.$u ? "UTC" : ""), X = (v = {}, v[h] = z + "Date", v[g] = z + "Date", v[u] = z + "Month", v[d] = z + "FullYear", v[l] = z + "Hours", v[n] = z + "Minutes", v[a] = z + "Seconds", v[o] = z + "Milliseconds", v)[R], ot = R === h ? this.$D + (D - this.$W) : D;
          if (R === u || R === d) {
            var tt = this.clone().set(g, 1);
            tt.$d[X](ot), tt.init(), this.$d = tt.set(g, Math.min(this.$D, tt.daysInMonth())).$d;
          } else X && this.$d[X](ot);
          return this.init(), this;
        }, M.set = function(E, D) {
          return this.clone().$set(E, D);
        }, M.get = function(E) {
          return this[F.p(E)]();
        }, M.add = function(E, D) {
          var v, R = this;
          E = Number(E);
          var z = F.p(D), X = function(st) {
            var j = O(R);
            return F.w(j.date(j.date() + Math.round(st * E)), R);
          };
          if (z === u) return this.set(u, this.$M + E);
          if (z === d) return this.set(d, this.$y + E);
          if (z === h) return X(1);
          if (z === c) return X(7);
          var ot = (v = {}, v[n] = i, v[l] = s, v[a] = r, v)[z] || 1, tt = this.$d.getTime() + E * ot;
          return F.w(tt, this);
        }, M.subtract = function(E, D) {
          return this.add(-1 * E, D);
        }, M.format = function(E) {
          var D = this, v = this.$locale();
          if (!this.isValid()) return v.invalidDate || m;
          var R = E || "YYYY-MM-DDTHH:mm:ssZ", z = F.z(this), X = this.$H, ot = this.$m, tt = this.$M, st = v.weekdays, j = v.months, dt = v.meridiem, xt = function(J, lt, Ct, kt) {
            return J && (J[lt] || J(D, R)) || Ct[lt].slice(0, kt);
          }, _t = function(J) {
            return F.s(X % 12 || 12, J, "0");
          }, se = dt || function(J, lt, Ct) {
            var kt = J < 12 ? "AM" : "PM";
            return Ct ? kt.toLowerCase() : kt;
          };
          return R.replace(x, (function(J, lt) {
            return lt || (function(Ct) {
              switch (Ct) {
                case "YY":
                  return String(D.$y).slice(-2);
                case "YYYY":
                  return F.s(D.$y, 4, "0");
                case "M":
                  return tt + 1;
                case "MM":
                  return F.s(tt + 1, 2, "0");
                case "MMM":
                  return xt(v.monthsShort, tt, j, 3);
                case "MMMM":
                  return xt(j, tt);
                case "D":
                  return D.$D;
                case "DD":
                  return F.s(D.$D, 2, "0");
                case "d":
                  return String(D.$W);
                case "dd":
                  return xt(v.weekdaysMin, D.$W, st, 2);
                case "ddd":
                  return xt(v.weekdaysShort, D.$W, st, 3);
                case "dddd":
                  return st[D.$W];
                case "H":
                  return String(X);
                case "HH":
                  return F.s(X, 2, "0");
                case "h":
                  return _t(1);
                case "hh":
                  return _t(2);
                case "a":
                  return se(X, ot, !0);
                case "A":
                  return se(X, ot, !1);
                case "m":
                  return String(ot);
                case "mm":
                  return F.s(ot, 2, "0");
                case "s":
                  return String(D.$s);
                case "ss":
                  return F.s(D.$s, 2, "0");
                case "SSS":
                  return F.s(D.$ms, 3, "0");
                case "Z":
                  return z;
              }
              return null;
            })(J) || z.replace(":", "");
          }));
        }, M.utcOffset = function() {
          return 15 * -Math.round(this.$d.getTimezoneOffset() / 15);
        }, M.diff = function(E, D, v) {
          var R, z = this, X = F.p(D), ot = O(E), tt = (ot.utcOffset() - this.utcOffset()) * i, st = this - ot, j = function() {
            return F.m(z, ot);
          };
          switch (X) {
            case d:
              R = j() / 12;
              break;
            case u:
              R = j();
              break;
            case p:
              R = j() / 3;
              break;
            case c:
              R = (st - tt) / 6048e5;
              break;
            case h:
              R = (st - tt) / 864e5;
              break;
            case l:
              R = st / s;
              break;
            case n:
              R = st / i;
              break;
            case a:
              R = st / r;
              break;
            default:
              R = st;
          }
          return v ? R : F.a(R);
        }, M.daysInMonth = function() {
          return this.endOf(u).$D;
        }, M.$locale = function() {
          return L[this.$L];
        }, M.locale = function(E, D) {
          if (!E) return this.$L;
          var v = this.clone(), R = N(E, D, !0);
          return R && (v.$L = R), v;
        }, M.clone = function() {
          return F.w(this.$d, this);
        }, M.toDate = function() {
          return new Date(this.valueOf());
        }, M.toJSON = function() {
          return this.isValid() ? this.toISOString() : null;
        }, M.toISOString = function() {
          return this.$d.toISOString();
        }, M.toString = function() {
          return this.$d.toUTCString();
        }, P;
      })(), H = Y.prototype;
      return O.prototype = H, [["$ms", o], ["$s", a], ["$m", n], ["$H", l], ["$W", h], ["$M", u], ["$y", d], ["$D", g]].forEach((function(P) {
        H[P[1]] = function(M) {
          return this.$g(M, P[0], P[1]);
        };
      })), O.extend = function(P, M) {
        return P.$i || (P(M, Y, O), P.$i = !0), O;
      }, O.locale = N, O.isDayjs = B, O.unix = function(P) {
        return O(1e3 * P);
      }, O.en = L[S], O.Ls = L, O.p = {}, O;
    }));
  })($s)), $s.exports;
}
var Zy = Vy();
const Ky = /* @__PURE__ */ sy(Zy);
var Oc = Object.defineProperty, f = (e, t) => Oc(e, "name", { value: t, configurable: !0 }), Qy = (e, t) => {
  for (var r in t)
    Oc(e, r, { get: t[r], enumerable: !0 });
}, qe = {
  trace: 0,
  debug: 1,
  info: 2,
  warn: 3,
  error: 4,
  fatal: 5
}, q = {
  trace: /* @__PURE__ */ f((...e) => {
  }, "trace"),
  debug: /* @__PURE__ */ f((...e) => {
  }, "debug"),
  info: /* @__PURE__ */ f((...e) => {
  }, "info"),
  warn: /* @__PURE__ */ f((...e) => {
  }, "warn"),
  error: /* @__PURE__ */ f((...e) => {
  }, "error"),
  fatal: /* @__PURE__ */ f((...e) => {
  }, "fatal")
}, xn = /* @__PURE__ */ f(function(e = "fatal") {
  let t = qe.fatal;
  typeof e == "string" ? e.toLowerCase() in qe && (t = qe[e]) : typeof e == "number" && (t = e), q.trace = () => {
  }, q.debug = () => {
  }, q.info = () => {
  }, q.warn = () => {
  }, q.error = () => {
  }, q.fatal = () => {
  }, t <= qe.fatal && (q.fatal = console.error ? console.error.bind(console, ce("FATAL"), "color: orange") : console.log.bind(console, "\x1B[35m", ce("FATAL"))), t <= qe.error && (q.error = console.error ? console.error.bind(console, ce("ERROR"), "color: orange") : console.log.bind(console, "\x1B[31m", ce("ERROR"))), t <= qe.warn && (q.warn = console.warn ? console.warn.bind(console, ce("WARN"), "color: orange") : console.log.bind(console, "\x1B[33m", ce("WARN"))), t <= qe.info && (q.info = console.info ? console.info.bind(console, ce("INFO"), "color: lightblue") : console.log.bind(console, "\x1B[34m", ce("INFO"))), t <= qe.debug && (q.debug = console.debug ? console.debug.bind(console, ce("DEBUG"), "color: lightgreen") : console.log.bind(console, "\x1B[32m", ce("DEBUG"))), t <= qe.trace && (q.trace = console.debug ? console.debug.bind(console, ce("TRACE"), "color: lightgreen") : console.log.bind(console, "\x1B[32m", ce("TRACE")));
}, "setLogLevel"), ce = /* @__PURE__ */ f((e) => `%c${Ky().format("ss.SSS")} : ${e} : `, "format");
/*! @license DOMPurify 3.4.2 | (c) Cure53 and other contributors | Released under the Apache license 2.0 and Mozilla Public License 2.0 | github.com/cure53/DOMPurify/blob/3.4.2/LICENSE */
const {
  entries: Dc,
  setPrototypeOf: Wl,
  isFrozen: Jy,
  getPrototypeOf: tx,
  getOwnPropertyDescriptor: ex
} = Object;
let {
  freeze: Zt,
  seal: de,
  create: Rr
} = Object, {
  apply: ya,
  construct: xa
} = typeof Reflect < "u" && Reflect;
Zt || (Zt = function(t) {
  return t;
});
de || (de = function(t) {
  return t;
});
ya || (ya = function(t, r) {
  for (var i = arguments.length, s = new Array(i > 2 ? i - 2 : 0), o = 2; o < i; o++)
    s[o - 2] = arguments[o];
  return t.apply(r, s);
});
xa || (xa = function(t) {
  for (var r = arguments.length, i = new Array(r > 1 ? r - 1 : 0), s = 1; s < r; s++)
    i[s - 1] = arguments[s];
  return new t(...i);
});
const Ti = Ft(Array.prototype.forEach), rx = Ft(Array.prototype.lastIndexOf), zl = Ft(Array.prototype.pop), Si = Ft(Array.prototype.push), ix = Ft(Array.prototype.splice), Ut = Array.isArray, Mi = Ft(String.prototype.toLowerCase), Ko = Ft(String.prototype.toString), Hl = Ft(String.prototype.match), $r = Ft(String.prototype.replace), Yl = Ft(String.prototype.indexOf), sx = Ft(String.prototype.trim), ox = Ft(Number.prototype.toString), ax = Ft(Boolean.prototype.toString), Xl = typeof BigInt > "u" ? null : Ft(BigInt.prototype.toString), Ul = typeof Symbol > "u" ? null : Ft(Symbol.prototype.toString), vt = Ft(Object.prototype.hasOwnProperty), wi = Ft(Object.prototype.toString), Pt = Ft(RegExp.prototype.test), Ts = nx(TypeError);
function Ft(e) {
  return function(t) {
    t instanceof RegExp && (t.lastIndex = 0);
    for (var r = arguments.length, i = new Array(r > 1 ? r - 1 : 0), s = 1; s < r; s++)
      i[s - 1] = arguments[s];
    return ya(e, t, i);
  };
}
function nx(e) {
  return function() {
    for (var t = arguments.length, r = new Array(t), i = 0; i < t; i++)
      r[i] = arguments[i];
    return xa(e, r);
  };
}
function ht(e, t) {
  let r = arguments.length > 2 && arguments[2] !== void 0 ? arguments[2] : Mi;
  if (Wl && Wl(e, null), !Ut(t))
    return e;
  let i = t.length;
  for (; i--; ) {
    let s = t[i];
    if (typeof s == "string") {
      const o = r(s);
      o !== s && (Jy(t) || (t[i] = o), s = o);
    }
    e[s] = !0;
  }
  return e;
}
function lx(e) {
  for (let t = 0; t < e.length; t++)
    vt(e, t) || (e[t] = null);
  return e;
}
function Jt(e) {
  const t = Rr(null);
  for (const [r, i] of Dc(e))
    vt(e, r) && (Ut(i) ? t[r] = lx(i) : i && typeof i == "object" && i.constructor === Object ? t[r] = Jt(i) : t[r] = i);
  return t;
}
function hx(e) {
  switch (typeof e) {
    case "string":
      return e;
    case "number":
      return ox(e);
    case "boolean":
      return ax(e);
    case "bigint":
      return Xl ? Xl(e) : "0";
    case "symbol":
      return Ul ? Ul(e) : "Symbol()";
    case "undefined":
      return wi(e);
    case "function":
    case "object": {
      if (e === null)
        return wi(e);
      const t = e, r = Pr(t, "toString");
      if (typeof r == "function") {
        const i = r(t);
        return typeof i == "string" ? i : wi(i);
      }
      return wi(e);
    }
    default:
      return wi(e);
  }
}
function Pr(e, t) {
  for (; e !== null; ) {
    const i = ex(e, t);
    if (i) {
      if (i.get)
        return Ft(i.get);
      if (typeof i.value == "function")
        return Ft(i.value);
    }
    e = tx(e);
  }
  function r() {
    return null;
  }
  return r;
}
function cx(e) {
  try {
    return Pt(e, ""), !0;
  } catch {
    return !1;
  }
}
const jl = Zt(["a", "abbr", "acronym", "address", "area", "article", "aside", "audio", "b", "bdi", "bdo", "big", "blink", "blockquote", "body", "br", "button", "canvas", "caption", "center", "cite", "code", "col", "colgroup", "content", "data", "datalist", "dd", "decorator", "del", "details", "dfn", "dialog", "dir", "div", "dl", "dt", "element", "em", "fieldset", "figcaption", "figure", "font", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "head", "header", "hgroup", "hr", "html", "i", "img", "input", "ins", "kbd", "label", "legend", "li", "main", "map", "mark", "marquee", "menu", "menuitem", "meter", "nav", "nobr", "ol", "optgroup", "option", "output", "p", "picture", "pre", "progress", "q", "rp", "rt", "ruby", "s", "samp", "search", "section", "select", "shadow", "slot", "small", "source", "spacer", "span", "strike", "strong", "style", "sub", "summary", "sup", "table", "tbody", "td", "template", "textarea", "tfoot", "th", "thead", "time", "tr", "track", "tt", "u", "ul", "var", "video", "wbr"]), Qo = Zt(["svg", "a", "altglyph", "altglyphdef", "altglyphitem", "animatecolor", "animatemotion", "animatetransform", "circle", "clippath", "defs", "desc", "ellipse", "enterkeyhint", "exportparts", "filter", "font", "g", "glyph", "glyphref", "hkern", "image", "inputmode", "line", "lineargradient", "marker", "mask", "metadata", "mpath", "part", "path", "pattern", "polygon", "polyline", "radialgradient", "rect", "stop", "style", "switch", "symbol", "text", "textpath", "title", "tref", "tspan", "view", "vkern"]), Jo = Zt(["feBlend", "feColorMatrix", "feComponentTransfer", "feComposite", "feConvolveMatrix", "feDiffuseLighting", "feDisplacementMap", "feDistantLight", "feDropShadow", "feFlood", "feFuncA", "feFuncB", "feFuncG", "feFuncR", "feGaussianBlur", "feImage", "feMerge", "feMergeNode", "feMorphology", "feOffset", "fePointLight", "feSpecularLighting", "feSpotLight", "feTile", "feTurbulence"]), ux = Zt(["animate", "color-profile", "cursor", "discard", "font-face", "font-face-format", "font-face-name", "font-face-src", "font-face-uri", "foreignobject", "hatch", "hatchpath", "mesh", "meshgradient", "meshpatch", "meshrow", "missing-glyph", "script", "set", "solidcolor", "unknown", "use"]), ta = Zt(["math", "menclose", "merror", "mfenced", "mfrac", "mglyph", "mi", "mlabeledtr", "mmultiscripts", "mn", "mo", "mover", "mpadded", "mphantom", "mroot", "mrow", "ms", "mspace", "msqrt", "mstyle", "msub", "msup", "msubsup", "mtable", "mtd", "mtext", "mtr", "munder", "munderover", "mprescripts"]), dx = Zt(["maction", "maligngroup", "malignmark", "mlongdiv", "mscarries", "mscarry", "msgroup", "mstack", "msline", "msrow", "semantics", "annotation", "annotation-xml", "mprescripts", "none"]), Gl = Zt(["#text"]), Vl = Zt(["accept", "action", "align", "alt", "autocapitalize", "autocomplete", "autopictureinpicture", "autoplay", "background", "bgcolor", "border", "capture", "cellpadding", "cellspacing", "checked", "cite", "class", "clear", "color", "cols", "colspan", "controls", "controlslist", "coords", "crossorigin", "datetime", "decoding", "default", "dir", "disabled", "disablepictureinpicture", "disableremoteplayback", "download", "draggable", "enctype", "enterkeyhint", "exportparts", "face", "for", "headers", "height", "hidden", "high", "href", "hreflang", "id", "inert", "inputmode", "integrity", "ismap", "kind", "label", "lang", "list", "loading", "loop", "low", "max", "maxlength", "media", "method", "min", "minlength", "multiple", "muted", "name", "nonce", "noshade", "novalidate", "nowrap", "open", "optimum", "part", "pattern", "placeholder", "playsinline", "popover", "popovertarget", "popovertargetaction", "poster", "preload", "pubdate", "radiogroup", "readonly", "rel", "required", "rev", "reversed", "role", "rows", "rowspan", "spellcheck", "scope", "selected", "shape", "size", "sizes", "slot", "span", "srclang", "start", "src", "srcset", "step", "style", "summary", "tabindex", "title", "translate", "type", "usemap", "valign", "value", "width", "wrap", "xmlns"]), ea = Zt(["accent-height", "accumulate", "additive", "alignment-baseline", "amplitude", "ascent", "attributename", "attributetype", "azimuth", "basefrequency", "baseline-shift", "begin", "bias", "by", "class", "clip", "clippathunits", "clip-path", "clip-rule", "color", "color-interpolation", "color-interpolation-filters", "color-profile", "color-rendering", "cx", "cy", "d", "dx", "dy", "diffuseconstant", "direction", "display", "divisor", "dur", "edgemode", "elevation", "end", "exponent", "fill", "fill-opacity", "fill-rule", "filter", "filterunits", "flood-color", "flood-opacity", "font-family", "font-size", "font-size-adjust", "font-stretch", "font-style", "font-variant", "font-weight", "fx", "fy", "g1", "g2", "glyph-name", "glyphref", "gradientunits", "gradienttransform", "height", "href", "id", "image-rendering", "in", "in2", "intercept", "k", "k1", "k2", "k3", "k4", "kerning", "keypoints", "keysplines", "keytimes", "lang", "lengthadjust", "letter-spacing", "kernelmatrix", "kernelunitlength", "lighting-color", "local", "marker-end", "marker-mid", "marker-start", "markerheight", "markerunits", "markerwidth", "maskcontentunits", "maskunits", "max", "mask", "mask-type", "media", "method", "mode", "min", "name", "numoctaves", "offset", "operator", "opacity", "order", "orient", "orientation", "origin", "overflow", "paint-order", "path", "pathlength", "patterncontentunits", "patterntransform", "patternunits", "points", "preservealpha", "preserveaspectratio", "primitiveunits", "r", "rx", "ry", "radius", "refx", "refy", "repeatcount", "repeatdur", "restart", "result", "rotate", "scale", "seed", "shape-rendering", "slope", "specularconstant", "specularexponent", "spreadmethod", "startoffset", "stddeviation", "stitchtiles", "stop-color", "stop-opacity", "stroke-dasharray", "stroke-dashoffset", "stroke-linecap", "stroke-linejoin", "stroke-miterlimit", "stroke-opacity", "stroke", "stroke-width", "style", "surfacescale", "systemlanguage", "tabindex", "tablevalues", "targetx", "targety", "transform", "transform-origin", "text-anchor", "text-decoration", "text-rendering", "textlength", "type", "u1", "u2", "unicode", "values", "viewbox", "visibility", "version", "vert-adv-y", "vert-origin-x", "vert-origin-y", "width", "word-spacing", "wrap", "writing-mode", "xchannelselector", "ychannelselector", "x", "x1", "x2", "xmlns", "y", "y1", "y2", "z", "zoomandpan"]), Zl = Zt(["accent", "accentunder", "align", "bevelled", "close", "columnalign", "columnlines", "columnspacing", "columnspan", "denomalign", "depth", "dir", "display", "displaystyle", "encoding", "fence", "frame", "height", "href", "id", "largeop", "length", "linethickness", "lquote", "lspace", "mathbackground", "mathcolor", "mathsize", "mathvariant", "maxsize", "minsize", "movablelimits", "notation", "numalign", "open", "rowalign", "rowlines", "rowspacing", "rowspan", "rspace", "rquote", "scriptlevel", "scriptminsize", "scriptsizemultiplier", "selection", "separator", "separators", "stretchy", "subscriptshift", "supscriptshift", "symmetric", "voffset", "width", "xmlns"]), Ss = Zt(["xlink:href", "xml:id", "xlink:title", "xml:space", "xmlns:xlink"]), px = de(/\{\{[\w\W]*|[\w\W]*\}\}/gm), fx = de(/<%[\w\W]*|[\w\W]*%>/gm), gx = de(/\$\{[\w\W]*/gm), mx = de(/^data-[\-\w.\u00B7-\uFFFF]+$/), yx = de(/^aria-[\-\w]+$/), Rc = de(
  /^(?:(?:(?:f|ht)tps?|mailto|tel|callto|sms|cid|xmpp|matrix):|[^a-z]|[a-z+.\-]+(?:[^a-z+.\-:]|$))/i
  // eslint-disable-line no-useless-escape
), xx = de(/^(?:\w+script|data):/i), Cx = de(
  /[\u0000-\u0020\u00A0\u1680\u180E\u2000-\u2029\u205F\u3000]/g
  // eslint-disable-line no-control-regex
), Pc = de(/^html$/i), bx = de(/^[a-z][.\w]*(-[.\w]+)+$/i);
var Kl = /* @__PURE__ */ Object.freeze({
  __proto__: null,
  ARIA_ATTR: yx,
  ATTR_WHITESPACE: Cx,
  CUSTOM_ELEMENT: bx,
  DATA_ATTR: mx,
  DOCTYPE_NAME: Pc,
  ERB_EXPR: fx,
  IS_ALLOWED_URI: Rc,
  IS_SCRIPT_OR_DATA: xx,
  MUSTACHE_EXPR: px,
  TMPLIT_EXPR: gx
});
const _i = {
  element: 1,
  text: 3,
  // Deprecated
  progressingInstruction: 7,
  comment: 8,
  document: 9
}, kx = function() {
  return typeof window > "u" ? null : window;
}, Tx = function(t, r) {
  if (typeof t != "object" || typeof t.createPolicy != "function")
    return null;
  let i = null;
  const s = "data-tt-policy-suffix";
  r && r.hasAttribute(s) && (i = r.getAttribute(s));
  const o = "dompurify" + (i ? "#" + i : "");
  try {
    return t.createPolicy(o, {
      createHTML(a) {
        return a;
      },
      createScriptURL(a) {
        return a;
      }
    });
  } catch {
    return console.warn("TrustedTypes policy " + o + " could not be created."), null;
  }
}, Ql = function() {
  return {
    afterSanitizeAttributes: [],
    afterSanitizeElements: [],
    afterSanitizeShadowDOM: [],
    beforeSanitizeAttributes: [],
    beforeSanitizeElements: [],
    beforeSanitizeShadowDOM: [],
    uponSanitizeAttribute: [],
    uponSanitizeElement: [],
    uponSanitizeShadowNode: []
  };
};
function Nc() {
  let e = arguments.length > 0 && arguments[0] !== void 0 ? arguments[0] : kx();
  const t = (rt) => Nc(rt);
  if (t.version = "3.4.2", t.removed = [], !e || !e.document || e.document.nodeType !== _i.document || !e.Element)
    return t.isSupported = !1, t;
  let {
    document: r
  } = e;
  const i = r, s = i.currentScript, {
    DocumentFragment: o,
    HTMLTemplateElement: a,
    Node: n,
    Element: l,
    NodeFilter: h,
    NamedNodeMap: c = e.NamedNodeMap || e.MozNamedAttrMap,
    HTMLFormElement: u,
    DOMParser: p,
    trustedTypes: d
  } = e, g = l.prototype, m = Pr(g, "cloneNode"), y = Pr(g, "remove"), x = Pr(g, "nextSibling"), b = Pr(g, "childNodes"), k = Pr(g, "parentNode");
  if (typeof a == "function") {
    const rt = r.createElement("template");
    rt.content && rt.content.ownerDocument && (r = rt.content.ownerDocument);
  }
  let w, S = "";
  const {
    implementation: L,
    createNodeIterator: T,
    createDocumentFragment: B,
    getElementsByTagName: N
  } = r, {
    importNode: O
  } = i;
  let F = Ql();
  t.isSupported = typeof Dc == "function" && typeof k == "function" && L && L.createHTMLDocument !== void 0;
  const {
    MUSTACHE_EXPR: Y,
    ERB_EXPR: H,
    TMPLIT_EXPR: P,
    DATA_ATTR: M,
    ARIA_ATTR: E,
    IS_SCRIPT_OR_DATA: D,
    ATTR_WHITESPACE: v,
    CUSTOM_ELEMENT: R
  } = Kl;
  let {
    IS_ALLOWED_URI: z
  } = Kl, X = null;
  const ot = ht({}, [...jl, ...Qo, ...Jo, ...ta, ...Gl]);
  let tt = null;
  const st = ht({}, [...Vl, ...ea, ...Zl, ...Ss]);
  let j = Object.seal(Rr(null, {
    tagNameCheck: {
      writable: !0,
      configurable: !1,
      enumerable: !0,
      value: null
    },
    attributeNameCheck: {
      writable: !0,
      configurable: !1,
      enumerable: !0,
      value: null
    },
    allowCustomizedBuiltInElements: {
      writable: !0,
      configurable: !1,
      enumerable: !0,
      value: !1
    }
  })), dt = null, xt = null;
  const _t = Object.seal(Rr(null, {
    tagCheck: {
      writable: !0,
      configurable: !1,
      enumerable: !0,
      value: null
    },
    attributeCheck: {
      writable: !0,
      configurable: !1,
      enumerable: !0,
      value: null
    }
  }));
  let se = !0, J = !0, lt = !1, Ct = !0, kt = !1, oe = !0, Wt = !1, Er = !1, gs = !1, ve = !1, ms = !1, ys = !1, Cl = !0, bl = !1;
  const kl = "user-content-";
  let Po = !0, Ci = !1, Fr = {}, Le = null;
  const No = ht({}, ["annotation-xml", "audio", "colgroup", "desc", "foreignobject", "head", "iframe", "math", "mi", "mn", "mo", "ms", "mtext", "noembed", "noframes", "noscript", "plaintext", "script", "style", "svg", "template", "thead", "title", "video", "xmp"]);
  let Tl = null;
  const Sl = ht({}, ["audio", "video", "img", "source", "image", "track"]);
  let qo = null;
  const wl = ht({}, ["alt", "class", "for", "id", "label", "name", "pattern", "placeholder", "role", "summary", "title", "value", "style", "xmlns"]), xs = "http://www.w3.org/1998/Math/MathML", Cs = "http://www.w3.org/2000/svg", Ae = "http://www.w3.org/1999/xhtml";
  let Mr = Ae, Wo = !1, zo = null;
  const Vm = ht({}, [xs, Cs, Ae], Ko);
  let Ho = ht({}, ["mi", "mo", "mn", "ms", "mtext"]), Yo = ht({}, ["annotation-xml"]);
  const Zm = ht({}, ["title", "style", "font", "a", "script"]);
  let bi = null;
  const Km = ["application/xhtml+xml", "text/html"], Qm = "text/html";
  let Mt = null, Ir = null;
  const Jm = r.createElement("form"), _l = function(_) {
    return _ instanceof RegExp || _ instanceof Function;
  }, Xo = function() {
    let _ = arguments.length > 0 && arguments[0] !== void 0 ? arguments[0] : {};
    if (Ir && Ir === _)
      return;
    (!_ || typeof _ != "object") && (_ = {}), _ = Jt(_), bi = // eslint-disable-next-line unicorn/prefer-includes
    Km.indexOf(_.PARSER_MEDIA_TYPE) === -1 ? Qm : _.PARSER_MEDIA_TYPE, Mt = bi === "application/xhtml+xml" ? Ko : Mi, X = vt(_, "ALLOWED_TAGS") && Ut(_.ALLOWED_TAGS) ? ht({}, _.ALLOWED_TAGS, Mt) : ot, tt = vt(_, "ALLOWED_ATTR") && Ut(_.ALLOWED_ATTR) ? ht({}, _.ALLOWED_ATTR, Mt) : st, zo = vt(_, "ALLOWED_NAMESPACES") && Ut(_.ALLOWED_NAMESPACES) ? ht({}, _.ALLOWED_NAMESPACES, Ko) : Vm, qo = vt(_, "ADD_URI_SAFE_ATTR") && Ut(_.ADD_URI_SAFE_ATTR) ? ht(Jt(wl), _.ADD_URI_SAFE_ATTR, Mt) : wl, Tl = vt(_, "ADD_DATA_URI_TAGS") && Ut(_.ADD_DATA_URI_TAGS) ? ht(Jt(Sl), _.ADD_DATA_URI_TAGS, Mt) : Sl, Le = vt(_, "FORBID_CONTENTS") && Ut(_.FORBID_CONTENTS) ? ht({}, _.FORBID_CONTENTS, Mt) : No, dt = vt(_, "FORBID_TAGS") && Ut(_.FORBID_TAGS) ? ht({}, _.FORBID_TAGS, Mt) : Jt({}), xt = vt(_, "FORBID_ATTR") && Ut(_.FORBID_ATTR) ? ht({}, _.FORBID_ATTR, Mt) : Jt({}), Fr = vt(_, "USE_PROFILES") ? _.USE_PROFILES && typeof _.USE_PROFILES == "object" ? Jt(_.USE_PROFILES) : _.USE_PROFILES : !1, se = _.ALLOW_ARIA_ATTR !== !1, J = _.ALLOW_DATA_ATTR !== !1, lt = _.ALLOW_UNKNOWN_PROTOCOLS || !1, Ct = _.ALLOW_SELF_CLOSE_IN_ATTR !== !1, kt = _.SAFE_FOR_TEMPLATES || !1, oe = _.SAFE_FOR_XML !== !1, Wt = _.WHOLE_DOCUMENT || !1, ve = _.RETURN_DOM || !1, ms = _.RETURN_DOM_FRAGMENT || !1, ys = _.RETURN_TRUSTED_TYPE || !1, gs = _.FORCE_BODY || !1, Cl = _.SANITIZE_DOM !== !1, bl = _.SANITIZE_NAMED_PROPS || !1, Po = _.KEEP_CONTENT !== !1, Ci = _.IN_PLACE || !1, z = cx(_.ALLOWED_URI_REGEXP) ? _.ALLOWED_URI_REGEXP : Rc, Mr = typeof _.NAMESPACE == "string" ? _.NAMESPACE : Ae, Ho = vt(_, "MATHML_TEXT_INTEGRATION_POINTS") && _.MATHML_TEXT_INTEGRATION_POINTS && typeof _.MATHML_TEXT_INTEGRATION_POINTS == "object" ? Jt(_.MATHML_TEXT_INTEGRATION_POINTS) : ht({}, ["mi", "mo", "mn", "ms", "mtext"]), Yo = vt(_, "HTML_INTEGRATION_POINTS") && _.HTML_INTEGRATION_POINTS && typeof _.HTML_INTEGRATION_POINTS == "object" ? Jt(_.HTML_INTEGRATION_POINTS) : ht({}, ["annotation-xml"]);
    const W = vt(_, "CUSTOM_ELEMENT_HANDLING") && _.CUSTOM_ELEMENT_HANDLING && typeof _.CUSTOM_ELEMENT_HANDLING == "object" ? Jt(_.CUSTOM_ELEMENT_HANDLING) : Rr(null);
    if (j = Rr(null), vt(W, "tagNameCheck") && _l(W.tagNameCheck) && (j.tagNameCheck = W.tagNameCheck), vt(W, "attributeNameCheck") && _l(W.attributeNameCheck) && (j.attributeNameCheck = W.attributeNameCheck), vt(W, "allowCustomizedBuiltInElements") && typeof W.allowCustomizedBuiltInElements == "boolean" && (j.allowCustomizedBuiltInElements = W.allowCustomizedBuiltInElements), kt && (J = !1), ms && (ve = !0), Fr && (X = ht({}, Gl), tt = Rr(null), Fr.html === !0 && (ht(X, jl), ht(tt, Vl)), Fr.svg === !0 && (ht(X, Qo), ht(tt, ea), ht(tt, Ss)), Fr.svgFilters === !0 && (ht(X, Jo), ht(tt, ea), ht(tt, Ss)), Fr.mathMl === !0 && (ht(X, ta), ht(tt, Zl), ht(tt, Ss))), _t.tagCheck = null, _t.attributeCheck = null, vt(_, "ADD_TAGS") && (typeof _.ADD_TAGS == "function" ? _t.tagCheck = _.ADD_TAGS : Ut(_.ADD_TAGS) && (X === ot && (X = Jt(X)), ht(X, _.ADD_TAGS, Mt))), vt(_, "ADD_ATTR") && (typeof _.ADD_ATTR == "function" ? _t.attributeCheck = _.ADD_ATTR : Ut(_.ADD_ATTR) && (tt === st && (tt = Jt(tt)), ht(tt, _.ADD_ATTR, Mt))), vt(_, "ADD_URI_SAFE_ATTR") && Ut(_.ADD_URI_SAFE_ATTR) && ht(qo, _.ADD_URI_SAFE_ATTR, Mt), vt(_, "FORBID_CONTENTS") && Ut(_.FORBID_CONTENTS) && (Le === No && (Le = Jt(Le)), ht(Le, _.FORBID_CONTENTS, Mt)), vt(_, "ADD_FORBID_CONTENTS") && Ut(_.ADD_FORBID_CONTENTS) && (Le === No && (Le = Jt(Le)), ht(Le, _.ADD_FORBID_CONTENTS, Mt)), Po && (X["#text"] = !0), Wt && ht(X, ["html", "head", "body"]), X.table && (ht(X, ["tbody"]), delete dt.tbody), _.TRUSTED_TYPES_POLICY) {
      if (typeof _.TRUSTED_TYPES_POLICY.createHTML != "function")
        throw Ts('TRUSTED_TYPES_POLICY configuration option must provide a "createHTML" hook.');
      if (typeof _.TRUSTED_TYPES_POLICY.createScriptURL != "function")
        throw Ts('TRUSTED_TYPES_POLICY configuration option must provide a "createScriptURL" hook.');
      w = _.TRUSTED_TYPES_POLICY, S = w.createHTML("");
    } else
      w === void 0 && (w = Tx(d, s)), w !== null && typeof S == "string" && (S = w.createHTML(""));
    Zt && Zt(_), Ir = _;
  }, Bl = ht({}, [...Qo, ...Jo, ...ux]), vl = ht({}, [...ta, ...dx]), ty = function(_) {
    let W = k(_);
    (!W || !W.tagName) && (W = {
      namespaceURI: Mr,
      tagName: "template"
    });
    const V = Mi(_.tagName), Tt = Mi(W.tagName);
    return zo[_.namespaceURI] ? _.namespaceURI === Cs ? W.namespaceURI === Ae ? V === "svg" : W.namespaceURI === xs ? V === "svg" && (Tt === "annotation-xml" || Ho[Tt]) : !!Bl[V] : _.namespaceURI === xs ? W.namespaceURI === Ae ? V === "math" : W.namespaceURI === Cs ? V === "math" && Yo[Tt] : !!vl[V] : _.namespaceURI === Ae ? W.namespaceURI === Cs && !Yo[Tt] || W.namespaceURI === xs && !Ho[Tt] ? !1 : !vl[V] && (Zm[V] || !Bl[V]) : !!(bi === "application/xhtml+xml" && zo[_.namespaceURI]) : !1;
  }, me = function(_) {
    Si(t.removed, {
      element: _
    });
    try {
      k(_).removeChild(_);
    } catch {
      y(_);
    }
  }, nr = function(_, W) {
    try {
      Si(t.removed, {
        attribute: W.getAttributeNode(_),
        from: W
      });
    } catch {
      Si(t.removed, {
        attribute: null,
        from: W
      });
    }
    if (W.removeAttribute(_), _ === "is")
      if (ve || ms)
        try {
          me(W);
        } catch {
        }
      else
        try {
          W.setAttribute(_, "");
        } catch {
        }
  }, Ll = function(_) {
    let W = null, V = null;
    if (gs)
      _ = "<remove></remove>" + _;
    else {
      const At = Hl(_, /^[\r\n\t ]+/);
      V = At && At[0];
    }
    bi === "application/xhtml+xml" && Mr === Ae && (_ = '<html xmlns="http://www.w3.org/1999/xhtml"><head></head><body>' + _ + "</body></html>");
    const Tt = w ? w.createHTML(_) : _;
    if (Mr === Ae)
      try {
        W = new p().parseFromString(Tt, bi);
      } catch {
      }
    if (!W || !W.documentElement) {
      W = L.createDocument(Mr, "template", null);
      try {
        W.documentElement.innerHTML = Wo ? S : Tt;
      } catch {
      }
    }
    const zt = W.body || W.documentElement;
    return _ && V && zt.insertBefore(r.createTextNode(V), zt.childNodes[0] || null), Mr === Ae ? N.call(W, Wt ? "html" : "body")[0] : Wt ? W.documentElement : zt;
  }, Al = function(_) {
    return T.call(
      _.ownerDocument || _,
      _,
      // eslint-disable-next-line no-bitwise
      h.SHOW_ELEMENT | h.SHOW_COMMENT | h.SHOW_TEXT | h.SHOW_PROCESSING_INSTRUCTION | h.SHOW_CDATA_SECTION,
      null
    );
  }, Uo = function(_) {
    return _ instanceof u && (typeof _.nodeName != "string" || typeof _.textContent != "string" || typeof _.removeChild != "function" || !(_.attributes instanceof c) || typeof _.removeAttribute != "function" || typeof _.setAttribute != "function" || typeof _.namespaceURI != "string" || typeof _.insertBefore != "function" || typeof _.hasChildNodes != "function");
  }, jo = function(_) {
    return typeof n == "function" && _ instanceof n;
  };
  function Ne(rt, _, W) {
    Ti(rt, (V) => {
      V.call(t, _, W, Ir);
    });
  }
  const El = function(_) {
    let W = null;
    if (Ne(F.beforeSanitizeElements, _, null), Uo(_))
      return me(_), !0;
    const V = Mt(_.nodeName);
    if (Ne(F.uponSanitizeElement, _, {
      tagName: V,
      allowedTags: X
    }), oe && _.hasChildNodes() && !jo(_.firstElementChild) && Pt(/<[/\w!]/g, _.innerHTML) && Pt(/<[/\w!]/g, _.textContent) || oe && _.namespaceURI === Ae && V === "style" && jo(_.firstElementChild) || _.nodeType === _i.progressingInstruction || oe && _.nodeType === _i.comment && Pt(/<[/\w]/g, _.data))
      return me(_), !0;
    if (dt[V] || !(_t.tagCheck instanceof Function && _t.tagCheck(V)) && !X[V]) {
      if (!dt[V] && Ml(V) && (j.tagNameCheck instanceof RegExp && Pt(j.tagNameCheck, V) || j.tagNameCheck instanceof Function && j.tagNameCheck(V)))
        return !1;
      if (Po && !Le[V]) {
        const Tt = k(_) || _.parentNode, zt = b(_) || _.childNodes;
        if (zt && Tt) {
          const At = zt.length;
          for (let Qt = At - 1; Qt >= 0; --Qt) {
            const he = m(zt[Qt], !0);
            Tt.insertBefore(he, x(_));
          }
        }
      }
      return me(_), !0;
    }
    return _ instanceof l && !ty(_) || (V === "noscript" || V === "noembed" || V === "noframes") && Pt(/<\/no(script|embed|frames)/i, _.innerHTML) ? (me(_), !0) : (kt && _.nodeType === _i.text && (W = _.textContent, Ti([Y, H, P], (Tt) => {
      W = $r(W, Tt, " ");
    }), _.textContent !== W && (Si(t.removed, {
      element: _.cloneNode()
    }), _.textContent = W)), Ne(F.afterSanitizeElements, _, null), !1);
  }, Fl = function(_, W, V) {
    if (xt[W] || Cl && (W === "id" || W === "name") && (V in r || V in Jm))
      return !1;
    const Tt = tt[W] || _t.attributeCheck instanceof Function && _t.attributeCheck(W, _);
    if (!(J && !xt[W] && Pt(M, W))) {
      if (!(se && Pt(E, W))) {
        if (!Tt || xt[W]) {
          if (
            // First condition does a very basic check if a) it's basically a valid custom element tagname AND
            // b) if the tagName passes whatever the user has configured for CUSTOM_ELEMENT_HANDLING.tagNameCheck
            // and c) if the attribute name passes whatever the user has configured for CUSTOM_ELEMENT_HANDLING.attributeNameCheck
            !(Ml(_) && (j.tagNameCheck instanceof RegExp && Pt(j.tagNameCheck, _) || j.tagNameCheck instanceof Function && j.tagNameCheck(_)) && (j.attributeNameCheck instanceof RegExp && Pt(j.attributeNameCheck, W) || j.attributeNameCheck instanceof Function && j.attributeNameCheck(W, _)) || // Alternative, second condition checks if it's an `is`-attribute, AND
            // the value passes whatever the user has configured for CUSTOM_ELEMENT_HANDLING.tagNameCheck
            W === "is" && j.allowCustomizedBuiltInElements && (j.tagNameCheck instanceof RegExp && Pt(j.tagNameCheck, V) || j.tagNameCheck instanceof Function && j.tagNameCheck(V)))
          ) return !1;
        } else if (!qo[W]) {
          if (!Pt(z, $r(V, v, ""))) {
            if (!((W === "src" || W === "xlink:href" || W === "href") && _ !== "script" && Yl(V, "data:") === 0 && Tl[_])) {
              if (!(lt && !Pt(D, $r(V, v, "")))) {
                if (V)
                  return !1;
              }
            }
          }
        }
      }
    }
    return !0;
  }, ey = ht({}, ["annotation-xml", "color-profile", "font-face", "font-face-format", "font-face-name", "font-face-src", "font-face-uri", "missing-glyph"]), Ml = function(_) {
    return !ey[Mi(_)] && Pt(R, _);
  }, Il = function(_) {
    Ne(F.beforeSanitizeAttributes, _, null);
    const {
      attributes: W
    } = _;
    if (!W || Uo(_))
      return;
    const V = {
      attrName: "",
      attrValue: "",
      keepAttr: !0,
      allowedAttributes: tt,
      forceKeepAttr: void 0
    };
    let Tt = W.length;
    for (; Tt--; ) {
      const zt = W[Tt], {
        name: At,
        namespaceURI: Qt,
        value: he
      } = zt, ye = Mt(At), Go = he;
      let Dt = At === "value" ? Go : sx(Go);
      if (V.attrName = ye, V.attrValue = Dt, V.keepAttr = !0, V.forceKeepAttr = void 0, Ne(F.uponSanitizeAttribute, _, V), Dt = V.attrValue, bl && (ye === "id" || ye === "name") && Yl(Dt, kl) !== 0 && (nr(At, _), Dt = kl + Dt), oe && Pt(/((--!?|])>)|<\/(style|script|title|xmp|textarea|noscript|iframe|noembed|noframes)/i, Dt)) {
        nr(At, _);
        continue;
      }
      if (ye === "attributename" && Hl(Dt, "href")) {
        nr(At, _);
        continue;
      }
      if (V.forceKeepAttr)
        continue;
      if (!V.keepAttr) {
        nr(At, _);
        continue;
      }
      if (!Ct && Pt(/\/>/i, Dt)) {
        nr(At, _);
        continue;
      }
      kt && Ti([Y, H, P], (Dl) => {
        Dt = $r(Dt, Dl, " ");
      });
      const Ol = Mt(_.nodeName);
      if (!Fl(Ol, ye, Dt)) {
        nr(At, _);
        continue;
      }
      if (w && typeof d == "object" && typeof d.getAttributeType == "function" && !Qt)
        switch (d.getAttributeType(Ol, ye)) {
          case "TrustedHTML": {
            Dt = w.createHTML(Dt);
            break;
          }
          case "TrustedScriptURL": {
            Dt = w.createScriptURL(Dt);
            break;
          }
        }
      if (Dt !== Go)
        try {
          Qt ? _.setAttributeNS(Qt, At, Dt) : _.setAttribute(At, Dt), Uo(_) ? me(_) : zl(t.removed);
        } catch {
          nr(At, _);
        }
    }
    Ne(F.afterSanitizeAttributes, _, null);
  }, $l = function(_) {
    let W = null;
    const V = Al(_);
    for (Ne(F.beforeSanitizeShadowDOM, _, null); W = V.nextNode(); )
      Ne(F.uponSanitizeShadowNode, W, null), El(W), Il(W), W.content instanceof o && $l(W.content);
    Ne(F.afterSanitizeShadowDOM, _, null);
  };
  return t.sanitize = function(rt) {
    let _ = arguments.length > 1 && arguments[1] !== void 0 ? arguments[1] : {}, W = null, V = null, Tt = null, zt = null;
    if (Wo = !rt, Wo && (rt = "<!-->"), typeof rt != "string" && !jo(rt) && (rt = hx(rt), typeof rt != "string"))
      throw Ts("dirty is not a string, aborting");
    if (!t.isSupported)
      return rt;
    if (Er || Xo(_), t.removed = [], typeof rt == "string" && (Ci = !1), Ci) {
      const he = rt.nodeName;
      if (typeof he == "string") {
        const ye = Mt(he);
        if (!X[ye] || dt[ye])
          throw Ts("root node is forbidden and cannot be sanitized in-place");
      }
    } else if (rt instanceof n)
      W = Ll("<!---->"), V = W.ownerDocument.importNode(rt, !0), V.nodeType === _i.element && V.nodeName === "BODY" || V.nodeName === "HTML" ? W = V : W.appendChild(V);
    else {
      if (!ve && !kt && !Wt && // eslint-disable-next-line unicorn/prefer-includes
      rt.indexOf("<") === -1)
        return w && ys ? w.createHTML(rt) : rt;
      if (W = Ll(rt), !W)
        return ve ? null : ys ? S : "";
    }
    W && gs && me(W.firstChild);
    const At = Al(Ci ? rt : W);
    for (; Tt = At.nextNode(); )
      El(Tt), Il(Tt), Tt.content instanceof o && $l(Tt.content);
    if (Ci)
      return rt;
    if (ve) {
      if (kt) {
        W.normalize();
        let he = W.innerHTML;
        Ti([Y, H, P], (ye) => {
          he = $r(he, ye, " ");
        }), W.innerHTML = he;
      }
      if (ms)
        for (zt = B.call(W.ownerDocument); W.firstChild; )
          zt.appendChild(W.firstChild);
      else
        zt = W;
      return (tt.shadowroot || tt.shadowrootmode) && (zt = O.call(i, zt, !0)), zt;
    }
    let Qt = Wt ? W.outerHTML : W.innerHTML;
    return Wt && X["!doctype"] && W.ownerDocument && W.ownerDocument.doctype && W.ownerDocument.doctype.name && Pt(Pc, W.ownerDocument.doctype.name) && (Qt = "<!DOCTYPE " + W.ownerDocument.doctype.name + `>
` + Qt), kt && Ti([Y, H, P], (he) => {
      Qt = $r(Qt, he, " ");
    }), w && ys ? w.createHTML(Qt) : Qt;
  }, t.setConfig = function() {
    let rt = arguments.length > 0 && arguments[0] !== void 0 ? arguments[0] : {};
    Xo(rt), Er = !0;
  }, t.clearConfig = function() {
    Ir = null, Er = !1;
  }, t.isValidAttribute = function(rt, _, W) {
    Ir || Xo({});
    const V = Mt(rt), Tt = Mt(_);
    return Fl(V, Tt, W);
  }, t.addHook = function(rt, _) {
    typeof _ == "function" && Si(F[rt], _);
  }, t.removeHook = function(rt, _) {
    if (_ !== void 0) {
      const W = rx(F[rt], _);
      return W === -1 ? void 0 : ix(F[rt], W, 1)[0];
    }
    return zl(F[rt]);
  }, t.removeHooks = function(rt) {
    F[rt] = [];
  }, t.removeAllHooks = function() {
    F = Ql();
  }, t;
}
var ni = Nc(), qc = /^-{3}\s*[\n\r](.*?)[\n\r]-{3}\s*[\n\r]+/s, Wi = /%{2}{\s*(?:(\w+)\s*:|(\w+))\s*(?:(\w+)|((?:(?!}%{2}).|\r?\n)*))?\s*(?:}%{2})?/gi, Sx = /\s*%%.*\n/gm, Ur, Wc = (Ur = class extends Error {
  constructor(t) {
    super(t), this.name = "UnknownDiagramError";
  }
}, f(Ur, "UnknownDiagramError"), Ur), kr = {}, Cn = /* @__PURE__ */ f(function(e, t) {
  e = e.replace(qc, "").replace(Wi, "").replace(Sx, `
`);
  for (const [r, { detector: i }] of Object.entries(kr))
    if (i(e, t))
      return r;
  throw new Wc(
    `No diagram type detected matching given configuration for text: ${e}`
  );
}, "detectType"), Ca = /* @__PURE__ */ f((...e) => {
  for (const { id: t, detector: r, loader: i } of e)
    zc(t, r, i);
}, "registerLazyLoadedDiagrams"), zc = /* @__PURE__ */ f((e, t, r) => {
  kr[e] && q.warn(`Detector with key ${e} already exists. Overwriting.`), kr[e] = { detector: t, loader: r }, q.debug(`Detector with key ${e} added${r ? " with loader" : ""}`);
}, "addDetector"), wx = /* @__PURE__ */ f((e) => kr[e].loader, "getDiagramLoader"), ba = /* @__PURE__ */ f((e, t, { depth: r = 2, clobber: i = !1 } = {}) => {
  const s = { depth: r, clobber: i };
  return Array.isArray(t) && !Array.isArray(e) ? (t.forEach((o) => ba(e, o, s)), e) : Array.isArray(t) && Array.isArray(e) ? (t.forEach((o) => {
    e.includes(o) || e.push(o);
  }), e) : e === void 0 || r <= 0 ? e != null && typeof e == "object" && typeof t == "object" ? Object.assign(e, t) : t : (t !== void 0 && typeof e == "object" && typeof t == "object" && Object.keys(t).forEach((o) => {
    typeof t[o] == "object" && t[o] !== null && (e[o] === void 0 || typeof e[o] == "object") ? (e[o] === void 0 && (e[o] = Array.isArray(t[o]) ? [] : {}), e[o] = ba(e[o], t[o], { depth: r - 1, clobber: i })) : (i || typeof e[o] != "object" && typeof t[o] != "object") && (e[o] = t[o]);
  }), e);
}, "assignWithDepth"), $t = ba, De = "#ffffff", Re = "#f2f2f2", nt = /* @__PURE__ */ f((e, t) => t ? C(e, { s: -40, l: 10 }) : C(e, { s: -40, l: -10 }), "mkBorder"), jr, _x = (jr = class {
  constructor() {
    this.background = "#f4f4f4", this.primaryColor = "#fff4dd", this.noteBkgColor = "#fff5ad", this.noteTextColor = "#333", this.THEME_COLOR_LIMIT = 12, this.radius = 5, this.strokeWidth = 1, this.fontFamily = '"trebuchet ms", verdana, arial, sans-serif', this.fontSize = "16px", this.useGradient = !0, this.dropShadow = "drop-shadow( 1px 2px 2px rgba(185,185,185,1))";
  }
  updateColors() {
    var r, i, s, o, a, n, l, h, c, u, p, d, g, m, y, x, b, k, w, S, L, T;
    if (this.primaryTextColor = this.primaryTextColor || (this.darkMode ? "#eee" : "#333"), this.secondaryColor = this.secondaryColor || C(this.primaryColor, { h: -120 }), this.tertiaryColor = this.tertiaryColor || C(this.primaryColor, { h: 180, l: 5 }), this.primaryBorderColor = this.primaryBorderColor || nt(this.primaryColor, this.darkMode), this.secondaryBorderColor = this.secondaryBorderColor || nt(this.secondaryColor, this.darkMode), this.tertiaryBorderColor = this.tertiaryBorderColor || nt(this.tertiaryColor, this.darkMode), this.noteBorderColor = this.noteBorderColor || nt(this.noteBkgColor, this.darkMode), this.noteBkgColor = this.noteBkgColor || "#fff5ad", this.noteTextColor = this.noteTextColor || "#333", this.secondaryTextColor = this.secondaryTextColor || A(this.secondaryColor), this.tertiaryTextColor = this.tertiaryTextColor || A(this.tertiaryColor), this.lineColor = this.lineColor || A(this.background), this.arrowheadColor = this.arrowheadColor || A(this.background), this.textColor = this.textColor || this.primaryTextColor, this.border2 = this.border2 || this.tertiaryBorderColor, this.nodeBkg = this.nodeBkg || this.primaryColor, this.mainBkg = this.mainBkg || this.primaryColor, this.nodeBorder = this.nodeBorder || this.primaryBorderColor, this.clusterBkg = this.clusterBkg || this.tertiaryColor, this.clusterBorder = this.clusterBorder || this.tertiaryBorderColor, this.defaultLinkColor = this.defaultLinkColor || this.lineColor, this.titleColor = this.titleColor || this.tertiaryTextColor, this.edgeLabelBackground = this.edgeLabelBackground || (this.darkMode ? I(this.secondaryColor, 30) : this.secondaryColor), this.nodeTextColor = this.nodeTextColor || this.primaryTextColor, this.actorBorder = this.actorBorder || this.primaryBorderColor, this.actorBkg = this.actorBkg || this.mainBkg, this.actorTextColor = this.actorTextColor || this.primaryTextColor, this.actorLineColor = this.actorLineColor || this.actorBorder, this.labelBoxBkgColor = this.labelBoxBkgColor || this.actorBkg, this.signalColor = this.signalColor || this.textColor, this.signalTextColor = this.signalTextColor || this.textColor, this.labelBoxBorderColor = this.labelBoxBorderColor || this.actorBorder, this.labelTextColor = this.labelTextColor || this.actorTextColor, this.loopTextColor = this.loopTextColor || this.actorTextColor, this.activationBorderColor = this.activationBorderColor || I(this.secondaryColor, 10), this.activationBkgColor = this.activationBkgColor || this.secondaryColor, this.sequenceNumberColor = this.sequenceNumberColor || A(this.lineColor), this.sectionBkgColor = this.sectionBkgColor || this.tertiaryColor, this.altSectionBkgColor = this.altSectionBkgColor || "white", this.sectionBkgColor = this.sectionBkgColor || this.secondaryColor, this.sectionBkgColor2 = this.sectionBkgColor2 || this.primaryColor, this.excludeBkgColor = this.excludeBkgColor || "#eeeeee", this.taskBorderColor = this.taskBorderColor || this.primaryBorderColor, this.taskBkgColor = this.taskBkgColor || this.primaryColor, this.activeTaskBorderColor = this.activeTaskBorderColor || this.primaryColor, this.activeTaskBkgColor = this.activeTaskBkgColor || $(this.primaryColor, 23), this.gridColor = this.gridColor || "lightgrey", this.doneTaskBkgColor = this.doneTaskBkgColor || "lightgrey", this.doneTaskBorderColor = this.doneTaskBorderColor || "grey", this.critBorderColor = this.critBorderColor || "#ff8888", this.critBkgColor = this.critBkgColor || "red", this.todayLineColor = this.todayLineColor || "red", this.vertLineColor = this.vertLineColor || "navy", this.taskTextColor = this.taskTextColor || this.textColor, this.taskTextOutsideColor = this.taskTextOutsideColor || this.textColor, this.taskTextLightColor = this.taskTextLightColor || this.textColor, this.taskTextColor = this.taskTextColor || this.primaryTextColor, this.taskTextDarkColor = this.taskTextDarkColor || this.textColor, this.taskTextClickableColor = this.taskTextClickableColor || "#003163", this.noteFontWeight = this.noteFontWeight || "normal", this.fontWeight = this.fontWeight || "normal", this.personBorder = this.personBorder || this.primaryBorderColor, this.personBkg = this.personBkg || this.mainBkg, this.darkMode ? (this.rowOdd = this.rowOdd || I(this.mainBkg, 5) || "#ffffff", this.rowEven = this.rowEven || I(this.mainBkg, 10)) : (this.rowOdd = this.rowOdd || $(this.mainBkg, 75) || "#ffffff", this.rowEven = this.rowEven || $(this.mainBkg, 5)), this.transitionColor = this.transitionColor || this.lineColor, this.transitionLabelColor = this.transitionLabelColor || this.textColor, this.stateLabelColor = this.stateLabelColor || this.stateBkg || this.primaryTextColor, this.stateBkg = this.stateBkg || this.mainBkg, this.labelBackgroundColor = this.labelBackgroundColor || this.stateBkg, this.compositeBackground = this.compositeBackground || this.background || this.tertiaryColor, this.altBackground = this.altBackground || this.tertiaryColor, this.compositeTitleBackground = this.compositeTitleBackground || this.mainBkg, this.compositeBorder = this.compositeBorder || this.nodeBorder, this.innerEndBackground = this.nodeBorder, this.errorBkgColor = this.errorBkgColor || this.tertiaryColor, this.errorTextColor = this.errorTextColor || this.tertiaryTextColor, this.transitionColor = this.transitionColor || this.lineColor, this.specialStateColor = this.lineColor, this.cScale0 = this.cScale0 || this.primaryColor, this.cScale1 = this.cScale1 || this.secondaryColor, this.cScale2 = this.cScale2 || this.tertiaryColor, this.cScale3 = this.cScale3 || C(this.primaryColor, { h: 30 }), this.cScale4 = this.cScale4 || C(this.primaryColor, { h: 60 }), this.cScale5 = this.cScale5 || C(this.primaryColor, { h: 90 }), this.cScale6 = this.cScale6 || C(this.primaryColor, { h: 120 }), this.cScale7 = this.cScale7 || C(this.primaryColor, { h: 150 }), this.cScale8 = this.cScale8 || C(this.primaryColor, { h: 210, l: 150 }), this.cScale9 = this.cScale9 || C(this.primaryColor, { h: 270 }), this.cScale10 = this.cScale10 || C(this.primaryColor, { h: 300 }), this.cScale11 = this.cScale11 || C(this.primaryColor, { h: 330 }), this.darkMode)
      for (let B = 0; B < this.THEME_COLOR_LIMIT; B++)
        this["cScale" + B] = I(this["cScale" + B], 75);
    else
      for (let B = 0; B < this.THEME_COLOR_LIMIT; B++)
        this["cScale" + B] = I(this["cScale" + B], 25);
    for (let B = 0; B < this.THEME_COLOR_LIMIT; B++)
      this["cScaleInv" + B] = this["cScaleInv" + B] || A(this["cScale" + B]);
    for (let B = 0; B < this.THEME_COLOR_LIMIT; B++)
      this.darkMode ? this["cScalePeer" + B] = this["cScalePeer" + B] || $(this["cScale" + B], 10) : this["cScalePeer" + B] = this["cScalePeer" + B] || I(this["cScale" + B], 10);
    this.scaleLabelColor = this.scaleLabelColor || this.labelTextColor;
    for (let B = 0; B < this.THEME_COLOR_LIMIT; B++)
      this["cScaleLabel" + B] = this["cScaleLabel" + B] || this.scaleLabelColor;
    const t = this.darkMode ? -4 : -1;
    for (let B = 0; B < 5; B++)
      this["surface" + B] = this["surface" + B] || C(this.mainBkg, { h: 180, s: -15, l: t * (5 + B * 3) }), this["surfacePeer" + B] = this["surfacePeer" + B] || C(this.mainBkg, { h: 180, s: -15, l: t * (8 + B * 3) });
    this.classText = this.classText || this.textColor, this.fillType0 = this.fillType0 || this.primaryColor, this.fillType1 = this.fillType1 || this.secondaryColor, this.fillType2 = this.fillType2 || C(this.primaryColor, { h: 64 }), this.fillType3 = this.fillType3 || C(this.secondaryColor, { h: 64 }), this.fillType4 = this.fillType4 || C(this.primaryColor, { h: -64 }), this.fillType5 = this.fillType5 || C(this.secondaryColor, { h: -64 }), this.fillType6 = this.fillType6 || C(this.primaryColor, { h: 128 }), this.fillType7 = this.fillType7 || C(this.secondaryColor, { h: 128 }), this.pie1 = this.pie1 || this.primaryColor, this.pie2 = this.pie2 || this.secondaryColor, this.pie3 = this.pie3 || this.tertiaryColor, this.pie4 = this.pie4 || C(this.primaryColor, { l: -10 }), this.pie5 = this.pie5 || C(this.secondaryColor, { l: -10 }), this.pie6 = this.pie6 || C(this.tertiaryColor, { l: -10 }), this.pie7 = this.pie7 || C(this.primaryColor, { h: 60, l: -10 }), this.pie8 = this.pie8 || C(this.primaryColor, { h: -60, l: -10 }), this.pie9 = this.pie9 || C(this.primaryColor, { h: 120, l: 0 }), this.pie10 = this.pie10 || C(this.primaryColor, { h: 60, l: -20 }), this.pie11 = this.pie11 || C(this.primaryColor, { h: -60, l: -20 }), this.pie12 = this.pie12 || C(this.primaryColor, { h: 120, l: -10 }), this.pieTitleTextSize = this.pieTitleTextSize || "25px", this.pieTitleTextColor = this.pieTitleTextColor || this.taskTextDarkColor, this.pieSectionTextSize = this.pieSectionTextSize || "17px", this.pieSectionTextColor = this.pieSectionTextColor || this.textColor, this.pieLegendTextSize = this.pieLegendTextSize || "17px", this.pieLegendTextColor = this.pieLegendTextColor || this.taskTextDarkColor, this.pieStrokeColor = this.pieStrokeColor || "black", this.pieStrokeWidth = this.pieStrokeWidth || "2px", this.pieOuterStrokeWidth = this.pieOuterStrokeWidth || "2px", this.pieOuterStrokeColor = this.pieOuterStrokeColor || "black", this.pieOpacity = this.pieOpacity || "0.7", this.venn1 = this.venn1 ?? C(this.primaryColor, { l: -30 }), this.venn2 = this.venn2 ?? C(this.secondaryColor, { l: -30 }), this.venn3 = this.venn3 ?? C(this.tertiaryColor, { l: -30 }), this.venn4 = this.venn4 ?? C(this.primaryColor, { h: 60, l: -30 }), this.venn5 = this.venn5 ?? C(this.primaryColor, { h: -60, l: -30 }), this.venn6 = this.venn6 ?? C(this.secondaryColor, { h: 60, l: -30 }), this.venn7 = this.venn7 ?? C(this.primaryColor, { h: 120, l: -30 }), this.venn8 = this.venn8 ?? C(this.secondaryColor, { h: 120, l: -30 }), this.vennTitleTextColor = this.vennTitleTextColor ?? this.titleColor, this.vennSetTextColor = this.vennSetTextColor ?? this.textColor, this.radar = {
      axisColor: ((r = this.radar) == null ? void 0 : r.axisColor) || this.lineColor,
      axisStrokeWidth: ((i = this.radar) == null ? void 0 : i.axisStrokeWidth) || 2,
      axisLabelFontSize: ((s = this.radar) == null ? void 0 : s.axisLabelFontSize) || 12,
      curveOpacity: ((o = this.radar) == null ? void 0 : o.curveOpacity) || 0.5,
      curveStrokeWidth: ((a = this.radar) == null ? void 0 : a.curveStrokeWidth) || 2,
      graticuleColor: ((n = this.radar) == null ? void 0 : n.graticuleColor) || "#DEDEDE",
      graticuleStrokeWidth: ((l = this.radar) == null ? void 0 : l.graticuleStrokeWidth) || 1,
      graticuleOpacity: ((h = this.radar) == null ? void 0 : h.graticuleOpacity) || 0.3,
      legendBoxSize: ((c = this.radar) == null ? void 0 : c.legendBoxSize) || 12,
      legendFontSize: ((u = this.radar) == null ? void 0 : u.legendFontSize) || 12
    }, this.archEdgeColor = this.archEdgeColor || "#777", this.archEdgeArrowColor = this.archEdgeArrowColor || "#777", this.archEdgeWidth = this.archEdgeWidth || "3", this.archGroupBorderColor = this.archGroupBorderColor || "#000", this.archGroupBorderWidth = this.archGroupBorderWidth || "2px", this.quadrant1Fill = this.quadrant1Fill || this.primaryColor, this.quadrant2Fill = this.quadrant2Fill || C(this.primaryColor, { r: 5, g: 5, b: 5 }), this.quadrant3Fill = this.quadrant3Fill || C(this.primaryColor, { r: 10, g: 10, b: 10 }), this.quadrant4Fill = this.quadrant4Fill || C(this.primaryColor, { r: 15, g: 15, b: 15 }), this.quadrant1TextFill = this.quadrant1TextFill || this.primaryTextColor, this.quadrant2TextFill = this.quadrant2TextFill || C(this.primaryTextColor, { r: -5, g: -5, b: -5 }), this.quadrant3TextFill = this.quadrant3TextFill || C(this.primaryTextColor, { r: -10, g: -10, b: -10 }), this.quadrant4TextFill = this.quadrant4TextFill || C(this.primaryTextColor, { r: -15, g: -15, b: -15 }), this.quadrantPointFill = this.quadrantPointFill || _e(this.quadrant1Fill) ? $(this.quadrant1Fill) : I(this.quadrant1Fill), this.quadrantPointTextFill = this.quadrantPointTextFill || this.primaryTextColor, this.quadrantXAxisTextFill = this.quadrantXAxisTextFill || this.primaryTextColor, this.quadrantYAxisTextFill = this.quadrantYAxisTextFill || this.primaryTextColor, this.quadrantInternalBorderStrokeFill = this.quadrantInternalBorderStrokeFill || this.primaryBorderColor, this.quadrantExternalBorderStrokeFill = this.quadrantExternalBorderStrokeFill || this.primaryBorderColor, this.quadrantTitleFill = this.quadrantTitleFill || this.primaryTextColor, this.xyChart = {
      backgroundColor: ((p = this.xyChart) == null ? void 0 : p.backgroundColor) || this.background,
      titleColor: ((d = this.xyChart) == null ? void 0 : d.titleColor) || this.primaryTextColor,
      dataLabelColor: ((g = this.xyChart) == null ? void 0 : g.dataLabelColor) || this.primaryTextColor,
      xAxisTitleColor: ((m = this.xyChart) == null ? void 0 : m.xAxisTitleColor) || this.primaryTextColor,
      xAxisLabelColor: ((y = this.xyChart) == null ? void 0 : y.xAxisLabelColor) || this.primaryTextColor,
      xAxisTickColor: ((x = this.xyChart) == null ? void 0 : x.xAxisTickColor) || this.primaryTextColor,
      xAxisLineColor: ((b = this.xyChart) == null ? void 0 : b.xAxisLineColor) || this.primaryTextColor,
      yAxisTitleColor: ((k = this.xyChart) == null ? void 0 : k.yAxisTitleColor) || this.primaryTextColor,
      yAxisLabelColor: ((w = this.xyChart) == null ? void 0 : w.yAxisLabelColor) || this.primaryTextColor,
      yAxisTickColor: ((S = this.xyChart) == null ? void 0 : S.yAxisTickColor) || this.primaryTextColor,
      yAxisLineColor: ((L = this.xyChart) == null ? void 0 : L.yAxisLineColor) || this.primaryTextColor,
      plotColorPalette: ((T = this.xyChart) == null ? void 0 : T.plotColorPalette) || "#FFF4DD,#FFD8B1,#FFA07A,#ECEFF1,#D6DBDF,#C3E0A8,#FFB6A4,#FFD74D,#738FA7,#FFFFF0"
    }, this.requirementBackground = this.requirementBackground || this.primaryColor, this.requirementBorderColor = this.requirementBorderColor || this.primaryBorderColor, this.requirementBorderSize = this.requirementBorderSize || "1", this.requirementTextColor = this.requirementTextColor || this.primaryTextColor, this.relationColor = this.relationColor || this.lineColor, this.relationLabelBackground = this.relationLabelBackground || (this.darkMode ? I(this.secondaryColor, 30) : this.secondaryColor), this.relationLabelColor = this.relationLabelColor || this.actorTextColor, this.git0 = this.git0 || this.primaryColor, this.git1 = this.git1 || this.secondaryColor, this.git2 = this.git2 || this.tertiaryColor, this.git3 = this.git3 || C(this.primaryColor, { h: -30 }), this.git4 = this.git4 || C(this.primaryColor, { h: -60 }), this.git5 = this.git5 || C(this.primaryColor, { h: -90 }), this.git6 = this.git6 || C(this.primaryColor, { h: 60 }), this.git7 = this.git7 || C(this.primaryColor, { h: 120 }), this.darkMode ? (this.git0 = $(this.git0, 25), this.git1 = $(this.git1, 25), this.git2 = $(this.git2, 25), this.git3 = $(this.git3, 25), this.git4 = $(this.git4, 25), this.git5 = $(this.git5, 25), this.git6 = $(this.git6, 25), this.git7 = $(this.git7, 25)) : (this.git0 = I(this.git0, 25), this.git1 = I(this.git1, 25), this.git2 = I(this.git2, 25), this.git3 = I(this.git3, 25), this.git4 = I(this.git4, 25), this.git5 = I(this.git5, 25), this.git6 = I(this.git6, 25), this.git7 = I(this.git7, 25)), this.gitInv0 = this.gitInv0 || A(this.git0), this.gitInv1 = this.gitInv1 || A(this.git1), this.gitInv2 = this.gitInv2 || A(this.git2), this.gitInv3 = this.gitInv3 || A(this.git3), this.gitInv4 = this.gitInv4 || A(this.git4), this.gitInv5 = this.gitInv5 || A(this.git5), this.gitInv6 = this.gitInv6 || A(this.git6), this.gitInv7 = this.gitInv7 || A(this.git7), this.branchLabelColor = this.branchLabelColor || (this.darkMode ? "black" : this.labelTextColor), this.gitBranchLabel0 = this.gitBranchLabel0 || this.branchLabelColor, this.gitBranchLabel1 = this.gitBranchLabel1 || this.branchLabelColor, this.gitBranchLabel2 = this.gitBranchLabel2 || this.branchLabelColor, this.gitBranchLabel3 = this.gitBranchLabel3 || this.branchLabelColor, this.gitBranchLabel4 = this.gitBranchLabel4 || this.branchLabelColor, this.gitBranchLabel5 = this.gitBranchLabel5 || this.branchLabelColor, this.gitBranchLabel6 = this.gitBranchLabel6 || this.branchLabelColor, this.gitBranchLabel7 = this.gitBranchLabel7 || this.branchLabelColor, this.tagLabelColor = this.tagLabelColor || this.primaryTextColor, this.tagLabelBackground = this.tagLabelBackground || this.primaryColor, this.tagLabelBorder = this.tagBorder || this.primaryBorderColor, this.tagLabelFontSize = this.tagLabelFontSize || "10px", this.commitLabelColor = this.commitLabelColor || this.secondaryTextColor, this.commitLabelBackground = this.commitLabelBackground || this.secondaryColor, this.commitLabelFontSize = this.commitLabelFontSize || "10px", this.attributeBackgroundColorOdd = this.attributeBackgroundColorOdd || De, this.attributeBackgroundColorEven = this.attributeBackgroundColorEven || Re, this.gradientStart = this.primaryBorderColor, this.gradientStop = this.secondaryBorderColor;
  }
  calculate(t) {
    if (typeof t != "object") {
      this.updateColors();
      return;
    }
    const r = Object.keys(t);
    r.forEach((i) => {
      this[i] = t[i];
    }), this.updateColors(), r.forEach((i) => {
      this[i] = t[i];
    });
  }
}, f(jr, "Theme"), jr), Bx = /* @__PURE__ */ f((e) => {
  const t = new _x();
  return t.calculate(e), t;
}, "getThemeVariables"), Gr, vx = (Gr = class {
  constructor() {
    this.background = "#333", this.primaryColor = "#1f2020", this.secondaryColor = $(this.primaryColor, 16), this.tertiaryColor = C(this.primaryColor, { h: -160 }), this.primaryBorderColor = A(this.background), this.secondaryBorderColor = nt(this.secondaryColor, this.darkMode), this.tertiaryBorderColor = nt(this.tertiaryColor, this.darkMode), this.primaryTextColor = A(this.primaryColor), this.secondaryTextColor = A(this.secondaryColor), this.tertiaryTextColor = A(this.tertiaryColor), this.lineColor = A(this.background), this.textColor = A(this.background), this.mainBkg = "#1f2020", this.secondBkg = "calculated", this.mainContrastColor = "lightgrey", this.darkTextColor = $(A("#323D47"), 10), this.lineColor = "calculated", this.border1 = "#ccc", this.border2 = gr(255, 255, 255, 0.25), this.arrowheadColor = "calculated", this.fontFamily = '"trebuchet ms", verdana, arial, sans-serif', this.fontSize = "16px", this.labelBackground = "#181818", this.textColor = "#ccc", this.THEME_COLOR_LIMIT = 12, this.radius = 5, this.strokeWidth = 1, this.nodeBkg = "calculated", this.nodeBorder = "calculated", this.clusterBkg = "calculated", this.clusterBorder = "calculated", this.defaultLinkColor = "calculated", this.titleColor = "#F9FFFE", this.edgeLabelBackground = "calculated", this.actorBorder = "calculated", this.actorBkg = "calculated", this.actorTextColor = "calculated", this.actorLineColor = "calculated", this.signalColor = "calculated", this.signalTextColor = "calculated", this.labelBoxBkgColor = "calculated", this.labelBoxBorderColor = "calculated", this.labelTextColor = "calculated", this.loopTextColor = "calculated", this.noteBorderColor = "calculated", this.noteBkgColor = "#fff5ad", this.noteTextColor = "calculated", this.activationBorderColor = "calculated", this.activationBkgColor = "calculated", this.sequenceNumberColor = "black", this.clusterBkg = "#302F3D", this.sectionBkgColor = I("#EAE8D9", 30), this.altSectionBkgColor = "calculated", this.sectionBkgColor2 = "#EAE8D9", this.excludeBkgColor = I(this.sectionBkgColor, 10), this.taskBorderColor = gr(255, 255, 255, 70), this.taskBkgColor = "calculated", this.taskTextColor = "calculated", this.taskTextLightColor = "calculated", this.taskTextOutsideColor = "calculated", this.taskTextClickableColor = "#003163", this.activeTaskBorderColor = gr(255, 255, 255, 50), this.activeTaskBkgColor = "#81B1DB", this.gridColor = "calculated", this.doneTaskBkgColor = "calculated", this.doneTaskBorderColor = "grey", this.critBorderColor = "#E83737", this.critBkgColor = "#E83737", this.taskTextDarkColor = "calculated", this.todayLineColor = "#DB5757", this.vertLineColor = "#00BFFF", this.personBorder = this.primaryBorderColor, this.personBkg = this.mainBkg, this.archEdgeColor = "calculated", this.archEdgeArrowColor = "calculated", this.archEdgeWidth = "3", this.archGroupBorderColor = this.primaryBorderColor, this.archGroupBorderWidth = "2px", this.rowOdd = this.rowOdd || $(this.mainBkg, 5) || "#ffffff", this.rowEven = this.rowEven || I(this.mainBkg, 10), this.labelColor = "calculated", this.errorBkgColor = "#a44141", this.errorTextColor = "#ddd", this.useGradient = !0, this.gradientStart = this.primaryBorderColor, this.gradientStop = this.secondaryBorderColor, this.dropShadow = "drop-shadow( 1px 2px 2px rgba(185,185,185,1))", this.noteFontWeight = this.noteFontWeight || "normal", this.fontWeight = this.fontWeight || "normal";
  }
  updateColors() {
    var t, r, i, s, o, a, n, l, h, c, u, p, d, g, m, y, x, b, k, w, S, L;
    this.secondBkg = $(this.mainBkg, 16), this.lineColor = this.mainContrastColor, this.arrowheadColor = this.mainContrastColor, this.nodeBkg = this.mainBkg, this.nodeBorder = this.border1, this.clusterBkg = this.secondBkg, this.clusterBorder = this.border2, this.defaultLinkColor = this.lineColor, this.edgeLabelBackground = $(this.labelBackground, 25), this.actorBorder = this.border1, this.actorBkg = this.mainBkg, this.actorTextColor = this.mainContrastColor, this.actorLineColor = this.actorBorder, this.signalColor = this.mainContrastColor, this.signalTextColor = this.mainContrastColor, this.labelBoxBkgColor = this.actorBkg, this.labelBoxBorderColor = this.actorBorder, this.labelTextColor = this.mainContrastColor, this.loopTextColor = this.mainContrastColor, this.noteBorderColor = this.secondaryBorderColor, this.noteBkgColor = this.secondBkg, this.noteTextColor = this.secondaryTextColor, this.activationBorderColor = this.border1, this.activationBkgColor = this.secondBkg, this.altSectionBkgColor = this.background, this.taskBkgColor = $(this.mainBkg, 23), this.taskTextColor = this.darkTextColor, this.taskTextLightColor = this.mainContrastColor, this.taskTextOutsideColor = this.taskTextLightColor, this.gridColor = this.mainContrastColor, this.doneTaskBkgColor = this.mainContrastColor, this.taskTextDarkColor = A(this.doneTaskBkgColor), this.archEdgeColor = this.lineColor, this.archEdgeArrowColor = this.lineColor, this.transitionColor = this.transitionColor || this.lineColor, this.transitionLabelColor = this.transitionLabelColor || this.textColor, this.stateLabelColor = this.stateLabelColor || this.stateBkg || this.primaryTextColor, this.stateBkg = this.stateBkg || this.mainBkg, this.labelBackgroundColor = this.labelBackgroundColor || this.stateBkg, this.compositeBackground = this.compositeBackground || this.background || this.tertiaryColor, this.altBackground = this.altBackground || "#555", this.compositeTitleBackground = this.compositeTitleBackground || this.mainBkg, this.compositeBorder = this.compositeBorder || this.nodeBorder, this.innerEndBackground = this.primaryBorderColor, this.specialStateColor = "#f4f4f4", this.errorBkgColor = this.errorBkgColor || this.tertiaryColor, this.errorTextColor = this.errorTextColor || this.tertiaryTextColor, this.fillType0 = this.primaryColor, this.fillType1 = this.secondaryColor, this.fillType2 = C(this.primaryColor, { h: 64 }), this.fillType3 = C(this.secondaryColor, { h: 64 }), this.fillType4 = C(this.primaryColor, { h: -64 }), this.fillType5 = C(this.secondaryColor, { h: -64 }), this.fillType6 = C(this.primaryColor, { h: 128 }), this.fillType7 = C(this.secondaryColor, { h: 128 }), this.cScale1 = this.cScale1 || "#0b0000", this.cScale2 = this.cScale2 || "#4d1037", this.cScale3 = this.cScale3 || "#3f5258", this.cScale4 = this.cScale4 || "#4f2f1b", this.cScale5 = this.cScale5 || "#6e0a0a", this.cScale6 = this.cScale6 || "#3b0048", this.cScale7 = this.cScale7 || "#995a01", this.cScale8 = this.cScale8 || "#154706", this.cScale9 = this.cScale9 || "#161722", this.cScale10 = this.cScale10 || "#00296f", this.cScale11 = this.cScale11 || "#01629c", this.cScale12 = this.cScale12 || "#010029", this.cScale0 = this.cScale0 || this.primaryColor, this.cScale1 = this.cScale1 || this.secondaryColor, this.cScale2 = this.cScale2 || this.tertiaryColor, this.cScale3 = this.cScale3 || C(this.primaryColor, { h: 30 }), this.cScale4 = this.cScale4 || C(this.primaryColor, { h: 60 }), this.cScale5 = this.cScale5 || C(this.primaryColor, { h: 90 }), this.cScale6 = this.cScale6 || C(this.primaryColor, { h: 120 }), this.cScale7 = this.cScale7 || C(this.primaryColor, { h: 150 }), this.cScale8 = this.cScale8 || C(this.primaryColor, { h: 210 }), this.cScale9 = this.cScale9 || C(this.primaryColor, { h: 270 }), this.cScale10 = this.cScale10 || C(this.primaryColor, { h: 300 }), this.cScale11 = this.cScale11 || C(this.primaryColor, { h: 330 });
    for (let T = 0; T < this.THEME_COLOR_LIMIT; T++)
      this["cScaleInv" + T] = this["cScaleInv" + T] || A(this["cScale" + T]);
    for (let T = 0; T < this.THEME_COLOR_LIMIT; T++)
      this["cScalePeer" + T] = this["cScalePeer" + T] || $(this["cScale" + T], 10);
    for (let T = 0; T < 5; T++)
      this["surface" + T] = this["surface" + T] || C(this.mainBkg, { h: 30, s: -30, l: -(-10 + T * 4) }), this["surfacePeer" + T] = this["surfacePeer" + T] || C(this.mainBkg, { h: 30, s: -30, l: -(-7 + T * 4) });
    this.scaleLabelColor = this.scaleLabelColor || (this.darkMode ? "black" : this.labelTextColor);
    for (let T = 0; T < this.THEME_COLOR_LIMIT; T++)
      this["cScaleLabel" + T] = this["cScaleLabel" + T] || this.scaleLabelColor;
    for (let T = 0; T < this.THEME_COLOR_LIMIT; T++)
      this["pie" + T] = this["cScale" + T];
    this.pieTitleTextSize = this.pieTitleTextSize || "25px", this.pieTitleTextColor = this.pieTitleTextColor || this.mainContrastColor, this.pieSectionTextSize = this.pieSectionTextSize || "17px", this.pieSectionTextColor = this.pieSectionTextColor || this.textColor, this.pieLegendTextSize = this.pieLegendTextSize || "17px", this.pieLegendTextColor = this.pieLegendTextColor || this.mainContrastColor, this.pieStrokeColor = this.pieStrokeColor || "black", this.pieStrokeWidth = this.pieStrokeWidth || "2px", this.pieOuterStrokeWidth = this.pieOuterStrokeWidth || "2px", this.pieOuterStrokeColor = this.pieOuterStrokeColor || "black", this.pieOpacity = this.pieOpacity || "0.7";
    for (let T = 0; T < 8; T++)
      this["venn" + (T + 1)] = this["venn" + (T + 1)] ?? $(this["cScale" + T], 30);
    this.vennTitleTextColor = this.vennTitleTextColor ?? this.titleColor, this.vennSetTextColor = this.vennSetTextColor ?? this.textColor, this.quadrant1Fill = this.quadrant1Fill || this.primaryColor, this.quadrant2Fill = this.quadrant2Fill || C(this.primaryColor, { r: 5, g: 5, b: 5 }), this.quadrant3Fill = this.quadrant3Fill || C(this.primaryColor, { r: 10, g: 10, b: 10 }), this.quadrant4Fill = this.quadrant4Fill || C(this.primaryColor, { r: 15, g: 15, b: 15 }), this.quadrant1TextFill = this.quadrant1TextFill || this.primaryTextColor, this.quadrant2TextFill = this.quadrant2TextFill || C(this.primaryTextColor, { r: -5, g: -5, b: -5 }), this.quadrant3TextFill = this.quadrant3TextFill || C(this.primaryTextColor, { r: -10, g: -10, b: -10 }), this.quadrant4TextFill = this.quadrant4TextFill || C(this.primaryTextColor, { r: -15, g: -15, b: -15 }), this.quadrantPointFill = this.quadrantPointFill || _e(this.quadrant1Fill) ? $(this.quadrant1Fill) : I(this.quadrant1Fill), this.quadrantPointTextFill = this.quadrantPointTextFill || this.primaryTextColor, this.quadrantXAxisTextFill = this.quadrantXAxisTextFill || this.primaryTextColor, this.quadrantYAxisTextFill = this.quadrantYAxisTextFill || this.primaryTextColor, this.quadrantInternalBorderStrokeFill = this.quadrantInternalBorderStrokeFill || this.primaryBorderColor, this.quadrantExternalBorderStrokeFill = this.quadrantExternalBorderStrokeFill || this.primaryBorderColor, this.quadrantTitleFill = this.quadrantTitleFill || this.primaryTextColor, this.xyChart = {
      backgroundColor: ((t = this.xyChart) == null ? void 0 : t.backgroundColor) || this.background,
      titleColor: ((r = this.xyChart) == null ? void 0 : r.titleColor) || this.primaryTextColor,
      dataLabelColor: ((i = this.xyChart) == null ? void 0 : i.dataLabelColor) || this.primaryTextColor,
      xAxisTitleColor: ((s = this.xyChart) == null ? void 0 : s.xAxisTitleColor) || this.primaryTextColor,
      xAxisLabelColor: ((o = this.xyChart) == null ? void 0 : o.xAxisLabelColor) || this.primaryTextColor,
      xAxisTickColor: ((a = this.xyChart) == null ? void 0 : a.xAxisTickColor) || this.primaryTextColor,
      xAxisLineColor: ((n = this.xyChart) == null ? void 0 : n.xAxisLineColor) || this.primaryTextColor,
      yAxisTitleColor: ((l = this.xyChart) == null ? void 0 : l.yAxisTitleColor) || this.primaryTextColor,
      yAxisLabelColor: ((h = this.xyChart) == null ? void 0 : h.yAxisLabelColor) || this.primaryTextColor,
      yAxisTickColor: ((c = this.xyChart) == null ? void 0 : c.yAxisTickColor) || this.primaryTextColor,
      yAxisLineColor: ((u = this.xyChart) == null ? void 0 : u.yAxisLineColor) || this.primaryTextColor,
      plotColorPalette: ((p = this.xyChart) == null ? void 0 : p.plotColorPalette) || "#3498db,#2ecc71,#e74c3c,#f1c40f,#bdc3c7,#ffffff,#34495e,#9b59b6,#1abc9c,#e67e22"
    }, this.packet = {
      startByteColor: this.primaryTextColor,
      endByteColor: this.primaryTextColor,
      labelColor: this.primaryTextColor,
      titleColor: this.primaryTextColor,
      blockStrokeColor: this.primaryTextColor,
      blockFillColor: this.background
    }, this.radar = {
      axisColor: ((d = this.radar) == null ? void 0 : d.axisColor) || this.lineColor,
      axisStrokeWidth: ((g = this.radar) == null ? void 0 : g.axisStrokeWidth) || 2,
      axisLabelFontSize: ((m = this.radar) == null ? void 0 : m.axisLabelFontSize) || 12,
      curveOpacity: ((y = this.radar) == null ? void 0 : y.curveOpacity) || 0.5,
      curveStrokeWidth: ((x = this.radar) == null ? void 0 : x.curveStrokeWidth) || 2,
      graticuleColor: ((b = this.radar) == null ? void 0 : b.graticuleColor) || "#DEDEDE",
      graticuleStrokeWidth: ((k = this.radar) == null ? void 0 : k.graticuleStrokeWidth) || 1,
      graticuleOpacity: ((w = this.radar) == null ? void 0 : w.graticuleOpacity) || 0.3,
      legendBoxSize: ((S = this.radar) == null ? void 0 : S.legendBoxSize) || 12,
      legendFontSize: ((L = this.radar) == null ? void 0 : L.legendFontSize) || 12
    }, this.classText = this.primaryTextColor, this.requirementBackground = this.requirementBackground || this.primaryColor, this.requirementBorderColor = this.requirementBorderColor || this.primaryBorderColor, this.requirementBorderSize = this.requirementBorderSize || "1", this.requirementTextColor = this.requirementTextColor || this.primaryTextColor, this.relationColor = this.relationColor || this.lineColor, this.relationLabelBackground = this.relationLabelBackground || (this.darkMode ? I(this.secondaryColor, 30) : this.secondaryColor), this.relationLabelColor = this.relationLabelColor || this.actorTextColor, this.git0 = $(this.secondaryColor, 20), this.git1 = $(this.pie2 || this.secondaryColor, 20), this.git2 = $(this.pie3 || this.tertiaryColor, 20), this.git3 = $(this.pie4 || C(this.primaryColor, { h: -30 }), 20), this.git4 = $(this.pie5 || C(this.primaryColor, { h: -60 }), 20), this.git5 = $(this.pie6 || C(this.primaryColor, { h: -90 }), 10), this.git6 = $(this.pie7 || C(this.primaryColor, { h: 60 }), 10), this.git7 = $(this.pie8 || C(this.primaryColor, { h: 120 }), 20), this.gitInv0 = this.gitInv0 || A(this.git0), this.gitInv1 = this.gitInv1 || A(this.git1), this.gitInv2 = this.gitInv2 || A(this.git2), this.gitInv3 = this.gitInv3 || A(this.git3), this.gitInv4 = this.gitInv4 || A(this.git4), this.gitInv5 = this.gitInv5 || A(this.git5), this.gitInv6 = this.gitInv6 || A(this.git6), this.gitInv7 = this.gitInv7 || A(this.git7), this.gitBranchLabel0 = this.gitBranchLabel0 || A(this.labelTextColor), this.gitBranchLabel1 = this.gitBranchLabel1 || this.labelTextColor, this.gitBranchLabel2 = this.gitBranchLabel2 || this.labelTextColor, this.gitBranchLabel3 = this.gitBranchLabel3 || A(this.labelTextColor), this.gitBranchLabel4 = this.gitBranchLabel4 || this.labelTextColor, this.gitBranchLabel5 = this.gitBranchLabel5 || this.labelTextColor, this.gitBranchLabel6 = this.gitBranchLabel6 || this.labelTextColor, this.gitBranchLabel7 = this.gitBranchLabel7 || this.labelTextColor, this.tagLabelColor = this.tagLabelColor || this.primaryTextColor, this.tagLabelBackground = this.tagLabelBackground || this.primaryColor, this.tagLabelBorder = this.tagBorder || this.primaryBorderColor, this.tagLabelFontSize = this.tagLabelFontSize || "10px", this.commitLabelColor = this.commitLabelColor || this.secondaryTextColor, this.commitLabelBackground = this.commitLabelBackground || this.secondaryColor, this.commitLabelFontSize = this.commitLabelFontSize || "10px", this.attributeBackgroundColorOdd = this.attributeBackgroundColorOdd || $(this.background, 12), this.attributeBackgroundColorEven = this.attributeBackgroundColorEven || $(this.background, 2), this.nodeBorder = this.nodeBorder || "#999";
  }
  calculate(t) {
    if (typeof t != "object") {
      this.updateColors();
      return;
    }
    const r = Object.keys(t);
    r.forEach((i) => {
      this[i] = t[i];
    }), this.updateColors(), r.forEach((i) => {
      this[i] = t[i];
    });
  }
}, f(Gr, "Theme"), Gr), Lx = /* @__PURE__ */ f((e) => {
  const t = new vx();
  return t.calculate(e), t;
}, "getThemeVariables"), Vr, Ax = (Vr = class {
  constructor() {
    this.background = "#f4f4f4", this.primaryColor = "#ECECFF", this.secondaryColor = C(this.primaryColor, { h: 120 }), this.secondaryColor = "#ffffde", this.tertiaryColor = C(this.primaryColor, { h: -160 }), this.primaryBorderColor = nt(this.primaryColor, this.darkMode), this.secondaryBorderColor = nt(this.secondaryColor, this.darkMode), this.tertiaryBorderColor = nt(this.tertiaryColor, this.darkMode), this.primaryTextColor = A(this.primaryColor), this.secondaryTextColor = A(this.secondaryColor), this.tertiaryTextColor = A(this.tertiaryColor), this.lineColor = A(this.background), this.textColor = A(this.background), this.background = "white", this.mainBkg = "#ECECFF", this.secondBkg = "#ffffde", this.lineColor = "#333333", this.border1 = "#9370DB", this.primaryBorderColor = nt(this.primaryColor, this.darkMode), this.border2 = "#aaaa33", this.arrowheadColor = "#333333", this.fontFamily = '"trebuchet ms", verdana, arial, sans-serif', this.fontSize = "16px", this.labelBackground = "rgba(232,232,232, 0.8)", this.textColor = "#333", this.THEME_COLOR_LIMIT = 12, this.radius = 5, this.strokeWidth = 1, this.nodeBkg = "calculated", this.nodeBorder = "calculated", this.clusterBkg = "calculated", this.clusterBorder = "calculated", this.defaultLinkColor = "calculated", this.titleColor = "calculated", this.edgeLabelBackground = "calculated", this.actorBorder = "calculated", this.actorBkg = "calculated", this.actorTextColor = "black", this.actorLineColor = "calculated", this.signalColor = "calculated", this.signalTextColor = "calculated", this.labelBoxBkgColor = "calculated", this.labelBoxBorderColor = "calculated", this.labelTextColor = "calculated", this.loopTextColor = "calculated", this.noteBorderColor = "calculated", this.noteBkgColor = "#fff5ad", this.noteTextColor = "calculated", this.activationBorderColor = "#666", this.activationBkgColor = "#f4f4f4", this.sequenceNumberColor = "white", this.clusterBkg = "#FBFBFF", this.sectionBkgColor = "calculated", this.altSectionBkgColor = "calculated", this.sectionBkgColor2 = "calculated", this.excludeBkgColor = "#eeeeee", this.taskBorderColor = "calculated", this.taskBkgColor = "calculated", this.taskTextLightColor = "calculated", this.taskTextColor = this.taskTextLightColor, this.taskTextDarkColor = "calculated", this.taskTextOutsideColor = this.taskTextDarkColor, this.taskTextClickableColor = "calculated", this.activeTaskBorderColor = "calculated", this.activeTaskBkgColor = "calculated", this.gridColor = "calculated", this.doneTaskBkgColor = "calculated", this.doneTaskBorderColor = "calculated", this.critBorderColor = "calculated", this.critBkgColor = "calculated", this.todayLineColor = "calculated", this.vertLineColor = "calculated", this.sectionBkgColor = gr(102, 102, 255, 0.49), this.altSectionBkgColor = "white", this.sectionBkgColor2 = "#fff400", this.taskBorderColor = "#534fbc", this.taskBkgColor = "#8a90dd", this.taskTextLightColor = "white", this.taskTextColor = "calculated", this.taskTextDarkColor = "black", this.taskTextOutsideColor = "calculated", this.taskTextClickableColor = "#003163", this.activeTaskBorderColor = "#534fbc", this.activeTaskBkgColor = "#bfc7ff", this.gridColor = "lightgrey", this.doneTaskBkgColor = "lightgrey", this.doneTaskBorderColor = "grey", this.critBorderColor = "#ff8888", this.critBkgColor = "red", this.todayLineColor = "red", this.vertLineColor = "navy", this.noteFontWeight = this.noteFontWeight || "normal", this.fontWeight = this.fontWeight || "normal", this.personBorder = this.primaryBorderColor, this.personBkg = this.mainBkg, this.archEdgeColor = "calculated", this.archEdgeArrowColor = "calculated", this.archEdgeWidth = "3", this.archGroupBorderColor = this.primaryBorderColor, this.archGroupBorderWidth = "2px", this.rowOdd = "calculated", this.rowEven = "calculated", this.labelColor = "black", this.errorBkgColor = "#552222", this.errorTextColor = "#552222", this.useGradient = !1, this.gradientStart = this.primaryBorderColor, this.gradientStop = this.secondaryBorderColor, this.dropShadow = "drop-shadow(1px 2px 2px rgba(185, 185, 185, 1))", this.updateColors();
  }
  updateColors() {
    var t, r, i, s, o, a, n, l, h, c, u, p, d, g, m, y, x, b, k, w, S, L;
    this.cScale0 = this.cScale0 || this.primaryColor, this.cScale1 = this.cScale1 || this.secondaryColor, this.cScale2 = this.cScale2 || this.tertiaryColor, this.cScale3 = this.cScale3 || C(this.primaryColor, { h: 30 }), this.cScale4 = this.cScale4 || C(this.primaryColor, { h: 60 }), this.cScale5 = this.cScale5 || C(this.primaryColor, { h: 90 }), this.cScale6 = this.cScale6 || C(this.primaryColor, { h: 120 }), this.cScale7 = this.cScale7 || C(this.primaryColor, { h: 150 }), this.cScale8 = this.cScale8 || C(this.primaryColor, { h: 210 }), this.cScale9 = this.cScale9 || C(this.primaryColor, { h: 270 }), this.cScale10 = this.cScale10 || C(this.primaryColor, { h: 300 }), this.cScale11 = this.cScale11 || C(this.primaryColor, { h: 330 }), this.cScalePeer1 = this.cScalePeer1 || I(this.secondaryColor, 45), this.cScalePeer2 = this.cScalePeer2 || I(this.tertiaryColor, 40);
    for (let T = 0; T < this.THEME_COLOR_LIMIT; T++)
      this["cScale" + T] = I(this["cScale" + T], 10), this["cScalePeer" + T] = this["cScalePeer" + T] || I(this["cScale" + T], 25);
    for (let T = 0; T < this.THEME_COLOR_LIMIT; T++)
      this["cScaleInv" + T] = this["cScaleInv" + T] || C(this["cScale" + T], { h: 180 });
    for (let T = 0; T < 5; T++)
      this["surface" + T] = this["surface" + T] || C(this.mainBkg, { h: 30, l: -(5 + T * 5) }), this["surfacePeer" + T] = this["surfacePeer" + T] || C(this.mainBkg, { h: 30, l: -(7 + T * 5) });
    if (this.scaleLabelColor = this.scaleLabelColor !== "calculated" && this.scaleLabelColor ? this.scaleLabelColor : this.labelTextColor, this.labelTextColor !== "calculated") {
      this.cScaleLabel0 = this.cScaleLabel0 || A(this.labelTextColor), this.cScaleLabel3 = this.cScaleLabel3 || A(this.labelTextColor);
      for (let T = 0; T < this.THEME_COLOR_LIMIT; T++)
        this["cScaleLabel" + T] = this["cScaleLabel" + T] || this.labelTextColor;
    }
    this.nodeBkg = this.mainBkg, this.nodeBorder = this.border1, this.clusterBkg = this.secondBkg, this.clusterBorder = this.border2, this.defaultLinkColor = this.lineColor, this.titleColor = this.textColor, this.edgeLabelBackground = this.labelBackground, this.actorBorder = this.border1, this.actorBkg = this.mainBkg, this.labelBoxBkgColor = this.actorBkg, this.signalColor = this.textColor, this.signalTextColor = this.textColor, this.labelBoxBorderColor = this.actorBorder, this.labelTextColor = this.actorTextColor, this.loopTextColor = this.actorTextColor, this.noteBorderColor = this.border2, this.noteTextColor = this.actorTextColor, this.actorLineColor = this.actorBorder, this.taskTextColor = this.taskTextLightColor, this.taskTextOutsideColor = this.taskTextDarkColor, this.archEdgeColor = this.lineColor, this.archEdgeArrowColor = this.lineColor, this.rowOdd = this.rowOdd || $(this.primaryColor, 75) || "#ffffff", this.rowEven = this.rowEven || $(this.primaryColor, 1), this.transitionColor = this.transitionColor || this.lineColor, this.transitionLabelColor = this.transitionLabelColor || this.textColor, this.stateLabelColor = this.stateLabelColor || this.stateBkg || this.primaryTextColor, this.stateBkg = this.stateBkg || this.mainBkg, this.labelBackgroundColor = this.labelBackgroundColor || this.stateBkg, this.compositeBackground = this.compositeBackground || this.background || this.tertiaryColor, this.altBackground = this.altBackground || "#f0f0f0", this.compositeTitleBackground = this.compositeTitleBackground || this.mainBkg, this.compositeBorder = this.compositeBorder || this.nodeBorder, this.innerEndBackground = this.nodeBorder, this.specialStateColor = this.lineColor, this.errorBkgColor = this.errorBkgColor || this.tertiaryColor, this.errorTextColor = this.errorTextColor || this.tertiaryTextColor, this.transitionColor = this.transitionColor || this.lineColor, this.classText = this.primaryTextColor, this.fillType0 = this.primaryColor, this.fillType1 = this.secondaryColor, this.fillType2 = C(this.primaryColor, { h: 64 }), this.fillType3 = C(this.secondaryColor, { h: 64 }), this.fillType4 = C(this.primaryColor, { h: -64 }), this.fillType5 = C(this.secondaryColor, { h: -64 }), this.fillType6 = C(this.primaryColor, { h: 128 }), this.fillType7 = C(this.secondaryColor, { h: 128 }), this.pie1 = this.pie1 || this.primaryColor, this.pie2 = this.pie2 || this.secondaryColor, this.pie3 = this.pie3 || C(this.tertiaryColor, { l: -40 }), this.pie4 = this.pie4 || C(this.primaryColor, { l: -10 }), this.pie5 = this.pie5 || C(this.secondaryColor, { l: -30 }), this.pie6 = this.pie6 || C(this.tertiaryColor, { l: -20 }), this.pie7 = this.pie7 || C(this.primaryColor, { h: 60, l: -20 }), this.pie8 = this.pie8 || C(this.primaryColor, { h: -60, l: -40 }), this.pie9 = this.pie9 || C(this.primaryColor, { h: 120, l: -40 }), this.pie10 = this.pie10 || C(this.primaryColor, { h: 60, l: -40 }), this.pie11 = this.pie11 || C(this.primaryColor, { h: -90, l: -40 }), this.pie12 = this.pie12 || C(this.primaryColor, { h: 120, l: -30 }), this.pieTitleTextSize = this.pieTitleTextSize || "25px", this.pieTitleTextColor = this.pieTitleTextColor || this.taskTextDarkColor, this.pieSectionTextSize = this.pieSectionTextSize || "17px", this.pieSectionTextColor = this.pieSectionTextColor || this.textColor, this.pieLegendTextSize = this.pieLegendTextSize || "17px", this.pieLegendTextColor = this.pieLegendTextColor || this.taskTextDarkColor, this.pieStrokeColor = this.pieStrokeColor || "black", this.pieStrokeWidth = this.pieStrokeWidth || "2px", this.pieOuterStrokeWidth = this.pieOuterStrokeWidth || "2px", this.pieOuterStrokeColor = this.pieOuterStrokeColor || "black", this.pieOpacity = this.pieOpacity || "0.7", this.venn1 = this.venn1 ?? C(this.primaryColor, { l: -30 }), this.venn2 = this.venn2 ?? C(this.secondaryColor, { l: -30 }), this.venn3 = this.venn3 ?? C(this.tertiaryColor, { l: -40 }), this.venn4 = this.venn4 ?? C(this.primaryColor, { h: 60, l: -30 }), this.venn5 = this.venn5 ?? C(this.primaryColor, { h: -60, l: -30 }), this.venn6 = this.venn6 ?? C(this.secondaryColor, { h: 60, l: -30 }), this.venn7 = this.venn7 ?? C(this.primaryColor, { h: 120, l: -30 }), this.venn8 = this.venn8 ?? C(this.secondaryColor, { h: 120, l: -30 }), this.vennTitleTextColor = this.vennTitleTextColor ?? this.titleColor, this.vennSetTextColor = this.vennSetTextColor ?? this.textColor, this.quadrant1Fill = this.quadrant1Fill || this.primaryColor, this.quadrant2Fill = this.quadrant2Fill || C(this.primaryColor, { r: 5, g: 5, b: 5 }), this.quadrant3Fill = this.quadrant3Fill || C(this.primaryColor, { r: 10, g: 10, b: 10 }), this.quadrant4Fill = this.quadrant4Fill || C(this.primaryColor, { r: 15, g: 15, b: 15 }), this.quadrant1TextFill = this.quadrant1TextFill || this.primaryTextColor, this.quadrant2TextFill = this.quadrant2TextFill || C(this.primaryTextColor, { r: -5, g: -5, b: -5 }), this.quadrant3TextFill = this.quadrant3TextFill || C(this.primaryTextColor, { r: -10, g: -10, b: -10 }), this.quadrant4TextFill = this.quadrant4TextFill || C(this.primaryTextColor, { r: -15, g: -15, b: -15 }), this.quadrantPointFill = this.quadrantPointFill || _e(this.quadrant1Fill) ? $(this.quadrant1Fill) : I(this.quadrant1Fill), this.quadrantPointTextFill = this.quadrantPointTextFill || this.primaryTextColor, this.quadrantXAxisTextFill = this.quadrantXAxisTextFill || this.primaryTextColor, this.quadrantYAxisTextFill = this.quadrantYAxisTextFill || this.primaryTextColor, this.quadrantInternalBorderStrokeFill = this.quadrantInternalBorderStrokeFill || this.primaryBorderColor, this.quadrantExternalBorderStrokeFill = this.quadrantExternalBorderStrokeFill || this.primaryBorderColor, this.quadrantTitleFill = this.quadrantTitleFill || this.primaryTextColor, this.radar = {
      axisColor: ((t = this.radar) == null ? void 0 : t.axisColor) || this.lineColor,
      axisStrokeWidth: ((r = this.radar) == null ? void 0 : r.axisStrokeWidth) || 2,
      axisLabelFontSize: ((i = this.radar) == null ? void 0 : i.axisLabelFontSize) || 12,
      curveOpacity: ((s = this.radar) == null ? void 0 : s.curveOpacity) || 0.5,
      curveStrokeWidth: ((o = this.radar) == null ? void 0 : o.curveStrokeWidth) || 2,
      graticuleColor: ((a = this.radar) == null ? void 0 : a.graticuleColor) || "#DEDEDE",
      graticuleStrokeWidth: ((n = this.radar) == null ? void 0 : n.graticuleStrokeWidth) || 1,
      graticuleOpacity: ((l = this.radar) == null ? void 0 : l.graticuleOpacity) || 0.3,
      legendBoxSize: ((h = this.radar) == null ? void 0 : h.legendBoxSize) || 12,
      legendFontSize: ((c = this.radar) == null ? void 0 : c.legendFontSize) || 12
    }, this.xyChart = {
      backgroundColor: ((u = this.xyChart) == null ? void 0 : u.backgroundColor) || this.background,
      titleColor: ((p = this.xyChart) == null ? void 0 : p.titleColor) || this.primaryTextColor,
      dataLabelColor: ((d = this.xyChart) == null ? void 0 : d.dataLabelColor) || this.primaryTextColor,
      xAxisTitleColor: ((g = this.xyChart) == null ? void 0 : g.xAxisTitleColor) || this.primaryTextColor,
      xAxisLabelColor: ((m = this.xyChart) == null ? void 0 : m.xAxisLabelColor) || this.primaryTextColor,
      xAxisTickColor: ((y = this.xyChart) == null ? void 0 : y.xAxisTickColor) || this.primaryTextColor,
      xAxisLineColor: ((x = this.xyChart) == null ? void 0 : x.xAxisLineColor) || this.primaryTextColor,
      yAxisTitleColor: ((b = this.xyChart) == null ? void 0 : b.yAxisTitleColor) || this.primaryTextColor,
      yAxisLabelColor: ((k = this.xyChart) == null ? void 0 : k.yAxisLabelColor) || this.primaryTextColor,
      yAxisTickColor: ((w = this.xyChart) == null ? void 0 : w.yAxisTickColor) || this.primaryTextColor,
      yAxisLineColor: ((S = this.xyChart) == null ? void 0 : S.yAxisLineColor) || this.primaryTextColor,
      plotColorPalette: ((L = this.xyChart) == null ? void 0 : L.plotColorPalette) || "#ECECFF,#8493A6,#FFC3A0,#DCDDE1,#B8E994,#D1A36F,#C3CDE6,#FFB6C1,#496078,#F8F3E3"
    }, this.requirementBackground = this.requirementBackground || this.primaryColor, this.requirementBorderColor = this.requirementBorderColor || this.primaryBorderColor, this.requirementBorderSize = this.requirementBorderSize || "1", this.requirementTextColor = this.requirementTextColor || this.primaryTextColor, this.relationColor = this.relationColor || this.lineColor, this.relationLabelBackground = this.relationLabelBackground || this.labelBackground, this.relationLabelColor = this.relationLabelColor || this.actorTextColor, this.git0 = this.git0 || this.primaryColor, this.git1 = this.git1 || this.secondaryColor, this.git2 = this.git2 || this.tertiaryColor, this.git3 = this.git3 || C(this.primaryColor, { h: -30 }), this.git4 = this.git4 || C(this.primaryColor, { h: -60 }), this.git5 = this.git5 || C(this.primaryColor, { h: -90 }), this.git6 = this.git6 || C(this.primaryColor, { h: 60 }), this.git7 = this.git7 || C(this.primaryColor, { h: 120 }), this.darkMode ? (this.git0 = $(this.git0, 25), this.git1 = $(this.git1, 25), this.git2 = $(this.git2, 25), this.git3 = $(this.git3, 25), this.git4 = $(this.git4, 25), this.git5 = $(this.git5, 25), this.git6 = $(this.git6, 25), this.git7 = $(this.git7, 25)) : (this.git0 = I(this.git0, 25), this.git1 = I(this.git1, 25), this.git2 = I(this.git2, 25), this.git3 = I(this.git3, 25), this.git4 = I(this.git4, 25), this.git5 = I(this.git5, 25), this.git6 = I(this.git6, 25), this.git7 = I(this.git7, 25)), this.gitInv0 = this.gitInv0 || I(A(this.git0), 25), this.gitInv1 = this.gitInv1 || A(this.git1), this.gitInv2 = this.gitInv2 || A(this.git2), this.gitInv3 = this.gitInv3 || A(this.git3), this.gitInv4 = this.gitInv4 || A(this.git4), this.gitInv5 = this.gitInv5 || A(this.git5), this.gitInv6 = this.gitInv6 || A(this.git6), this.gitInv7 = this.gitInv7 || A(this.git7), this.gitBranchLabel0 = this.gitBranchLabel0 || A(this.labelTextColor), this.gitBranchLabel1 = this.gitBranchLabel1 || this.labelTextColor, this.gitBranchLabel2 = this.gitBranchLabel2 || this.labelTextColor, this.gitBranchLabel3 = this.gitBranchLabel3 || A(this.labelTextColor), this.gitBranchLabel4 = this.gitBranchLabel4 || this.labelTextColor, this.gitBranchLabel5 = this.gitBranchLabel5 || this.labelTextColor, this.gitBranchLabel6 = this.gitBranchLabel6 || this.labelTextColor, this.gitBranchLabel7 = this.gitBranchLabel7 || this.labelTextColor, this.tagLabelColor = this.tagLabelColor || this.primaryTextColor, this.tagLabelBackground = this.tagLabelBackground || this.primaryColor, this.tagLabelBorder = this.tagBorder || this.primaryBorderColor, this.tagLabelFontSize = this.tagLabelFontSize || "10px", this.commitLabelColor = this.commitLabelColor || this.secondaryTextColor, this.commitLabelBackground = this.commitLabelBackground || this.secondaryColor, this.commitLabelFontSize = this.commitLabelFontSize || "10px", this.attributeBackgroundColorOdd = this.attributeBackgroundColorOdd || De, this.attributeBackgroundColorEven = this.attributeBackgroundColorEven || Re;
  }
  calculate(t) {
    if (Object.keys(this).forEach((i) => {
      this[i] === "calculated" && (this[i] = void 0);
    }), typeof t != "object") {
      this.updateColors();
      return;
    }
    const r = Object.keys(t);
    r.forEach((i) => {
      this[i] = t[i];
    }), this.updateColors(), r.forEach((i) => {
      this[i] = t[i];
    });
  }
}, f(Vr, "Theme"), Vr), Ex = /* @__PURE__ */ f((e) => {
  const t = new Ax();
  return t.calculate(e), t;
}, "getThemeVariables"), Zr, Fx = (Zr = class {
  constructor() {
    this.background = "#f4f4f4", this.primaryColor = "#cde498", this.secondaryColor = "#cdffb2", this.background = "white", this.mainBkg = "#cde498", this.secondBkg = "#cdffb2", this.lineColor = "green", this.border1 = "#13540c", this.border2 = "#6eaa49", this.arrowheadColor = "green", this.fontFamily = '"trebuchet ms", verdana, arial, sans-serif', this.fontSize = "16px", this.tertiaryColor = $("#cde498", 10), this.primaryBorderColor = nt(this.primaryColor, this.darkMode), this.secondaryBorderColor = nt(this.secondaryColor, this.darkMode), this.tertiaryBorderColor = nt(this.tertiaryColor, this.darkMode), this.primaryTextColor = A(this.primaryColor), this.secondaryTextColor = A(this.secondaryColor), this.tertiaryTextColor = A(this.primaryColor), this.lineColor = A(this.background), this.textColor = A(this.background), this.THEME_COLOR_LIMIT = 12, this.radius = 5, this.strokeWidth = 1, this.nodeBkg = "calculated", this.nodeBorder = "calculated", this.clusterBkg = "calculated", this.clusterBorder = "calculated", this.defaultLinkColor = "calculated", this.titleColor = "#333", this.edgeLabelBackground = "#e8e8e8", this.actorBorder = "calculated", this.actorBkg = "calculated", this.actorTextColor = "black", this.actorLineColor = "calculated", this.signalColor = "#333", this.signalTextColor = "#333", this.labelBoxBkgColor = "calculated", this.labelBoxBorderColor = "#326932", this.labelTextColor = "calculated", this.loopTextColor = "calculated", this.noteBorderColor = "calculated", this.noteBkgColor = "#fff5ad", this.noteTextColor = "calculated", this.activationBorderColor = "#666", this.activationBkgColor = "#f4f4f4", this.sequenceNumberColor = "white", this.sectionBkgColor = "#6eaa49", this.altSectionBkgColor = "white", this.sectionBkgColor2 = "#6eaa49", this.excludeBkgColor = "#eeeeee", this.taskBorderColor = "calculated", this.taskBkgColor = "#487e3a", this.taskTextLightColor = "white", this.taskTextColor = "calculated", this.taskTextDarkColor = "black", this.taskTextOutsideColor = "calculated", this.taskTextClickableColor = "#003163", this.activeTaskBorderColor = "calculated", this.activeTaskBkgColor = "calculated", this.gridColor = "lightgrey", this.doneTaskBkgColor = "lightgrey", this.doneTaskBorderColor = "grey", this.critBorderColor = "#ff8888", this.critBkgColor = "red", this.todayLineColor = "red", this.vertLineColor = "#00BFFF", this.personBorder = this.primaryBorderColor, this.personBkg = this.mainBkg, this.archEdgeColor = "calculated", this.archEdgeArrowColor = "calculated", this.archEdgeWidth = "3", this.archGroupBorderColor = this.primaryBorderColor, this.archGroupBorderWidth = "2px", this.noteFontWeight = "normal", this.fontWeight = "normal", this.labelColor = "black", this.errorBkgColor = "#552222", this.errorTextColor = "#552222", this.useGradient = !0, this.gradientStart = this.primaryBorderColor, this.gradientStop = this.secondaryBorderColor, this.dropShadow = "drop-shadow( 1px 2px 2px rgba(185,185,185,0.5))";
  }
  updateColors() {
    var t, r, i, s, o, a, n, l, h, c, u, p, d, g, m, y, x, b, k, w, S, L;
    this.actorBorder = I(this.mainBkg, 20), this.actorBkg = this.mainBkg, this.labelBoxBkgColor = this.actorBkg, this.labelTextColor = this.actorTextColor, this.loopTextColor = this.actorTextColor, this.noteBorderColor = this.border2, this.noteTextColor = this.actorTextColor, this.actorLineColor = this.actorBorder, this.cScale0 = this.cScale0 || this.primaryColor, this.cScale1 = this.cScale1 || this.secondaryColor, this.cScale2 = this.cScale2 || this.tertiaryColor, this.cScale3 = this.cScale3 || C(this.primaryColor, { h: 30 }), this.cScale4 = this.cScale4 || C(this.primaryColor, { h: 60 }), this.cScale5 = this.cScale5 || C(this.primaryColor, { h: 90 }), this.cScale6 = this.cScale6 || C(this.primaryColor, { h: 120 }), this.cScale7 = this.cScale7 || C(this.primaryColor, { h: 150 }), this.cScale8 = this.cScale8 || C(this.primaryColor, { h: 210 }), this.cScale9 = this.cScale9 || C(this.primaryColor, { h: 270 }), this.cScale10 = this.cScale10 || C(this.primaryColor, { h: 300 }), this.cScale11 = this.cScale11 || C(this.primaryColor, { h: 330 }), this.cScalePeer1 = this.cScalePeer1 || I(this.secondaryColor, 45), this.cScalePeer2 = this.cScalePeer2 || I(this.tertiaryColor, 40);
    for (let T = 0; T < this.THEME_COLOR_LIMIT; T++)
      this["cScale" + T] = I(this["cScale" + T], 10), this["cScalePeer" + T] = this["cScalePeer" + T] || I(this["cScale" + T], 25);
    for (let T = 0; T < this.THEME_COLOR_LIMIT; T++)
      this["cScaleInv" + T] = this["cScaleInv" + T] || C(this["cScale" + T], { h: 180 });
    this.scaleLabelColor = this.scaleLabelColor !== "calculated" && this.scaleLabelColor ? this.scaleLabelColor : this.labelTextColor;
    for (let T = 0; T < this.THEME_COLOR_LIMIT; T++)
      this["cScaleLabel" + T] = this["cScaleLabel" + T] || this.scaleLabelColor;
    for (let T = 0; T < 5; T++)
      this["surface" + T] = this["surface" + T] || C(this.mainBkg, { h: 30, s: -30, l: -(5 + T * 5) }), this["surfacePeer" + T] = this["surfacePeer" + T] || C(this.mainBkg, { h: 30, s: -30, l: -(8 + T * 5) });
    this.nodeBkg = this.mainBkg, this.nodeBorder = this.border1, this.clusterBkg = this.secondBkg, this.clusterBorder = this.border2, this.defaultLinkColor = this.lineColor, this.taskBorderColor = this.border1, this.taskTextColor = this.taskTextLightColor, this.taskTextOutsideColor = this.taskTextDarkColor, this.activeTaskBorderColor = this.taskBorderColor, this.activeTaskBkgColor = this.mainBkg, this.archEdgeColor = this.lineColor, this.archEdgeArrowColor = this.lineColor, this.rowOdd = this.rowOdd || $(this.mainBkg, 75) || "#ffffff", this.rowEven = this.rowEven || $(this.mainBkg, 20), this.transitionColor = this.transitionColor || this.lineColor, this.transitionLabelColor = this.transitionLabelColor || this.textColor, this.stateLabelColor = this.stateLabelColor || this.stateBkg || this.primaryTextColor, this.stateBkg = this.stateBkg || this.mainBkg, this.labelBackgroundColor = this.labelBackgroundColor || this.stateBkg, this.compositeBackground = this.compositeBackground || this.background || this.tertiaryColor, this.altBackground = this.altBackground || "#f0f0f0", this.compositeTitleBackground = this.compositeTitleBackground || this.mainBkg, this.compositeBorder = this.compositeBorder || this.nodeBorder, this.innerEndBackground = this.primaryBorderColor, this.specialStateColor = this.lineColor, this.errorBkgColor = this.errorBkgColor || this.tertiaryColor, this.errorTextColor = this.errorTextColor || this.tertiaryTextColor, this.transitionColor = this.transitionColor || this.lineColor, this.classText = this.primaryTextColor, this.fillType0 = this.primaryColor, this.fillType1 = this.secondaryColor, this.fillType2 = C(this.primaryColor, { h: 64 }), this.fillType3 = C(this.secondaryColor, { h: 64 }), this.fillType4 = C(this.primaryColor, { h: -64 }), this.fillType5 = C(this.secondaryColor, { h: -64 }), this.fillType6 = C(this.primaryColor, { h: 128 }), this.fillType7 = C(this.secondaryColor, { h: 128 }), this.pie1 = this.pie1 || this.primaryColor, this.pie2 = this.pie2 || this.secondaryColor, this.pie3 = this.pie3 || this.tertiaryColor, this.pie4 = this.pie4 || C(this.primaryColor, { l: -30 }), this.pie5 = this.pie5 || C(this.secondaryColor, { l: -30 }), this.pie6 = this.pie6 || C(this.tertiaryColor, { h: 40, l: -40 }), this.pie7 = this.pie7 || C(this.primaryColor, { h: 60, l: -10 }), this.pie8 = this.pie8 || C(this.primaryColor, { h: -60, l: -10 }), this.pie9 = this.pie9 || C(this.primaryColor, { h: 120, l: 0 }), this.pie10 = this.pie10 || C(this.primaryColor, { h: 60, l: -50 }), this.pie11 = this.pie11 || C(this.primaryColor, { h: -60, l: -50 }), this.pie12 = this.pie12 || C(this.primaryColor, { h: 120, l: -50 }), this.pieTitleTextSize = this.pieTitleTextSize || "25px", this.pieTitleTextColor = this.pieTitleTextColor || this.taskTextDarkColor, this.pieSectionTextSize = this.pieSectionTextSize || "17px", this.pieSectionTextColor = this.pieSectionTextColor || this.textColor, this.pieLegendTextSize = this.pieLegendTextSize || "17px", this.pieLegendTextColor = this.pieLegendTextColor || this.taskTextDarkColor, this.pieStrokeColor = this.pieStrokeColor || "black", this.pieStrokeWidth = this.pieStrokeWidth || "2px", this.pieOuterStrokeWidth = this.pieOuterStrokeWidth || "2px", this.pieOuterStrokeColor = this.pieOuterStrokeColor || "black", this.pieOpacity = this.pieOpacity || "0.7", this.venn1 = this.venn1 ?? C(this.primaryColor, { l: -30 }), this.venn2 = this.venn2 ?? C(this.secondaryColor, { l: -30 }), this.venn3 = this.venn3 ?? C(this.tertiaryColor, { l: -30 }), this.venn4 = this.venn4 ?? C(this.primaryColor, { h: 60, l: -30 }), this.venn5 = this.venn5 ?? C(this.primaryColor, { h: -60, l: -30 }), this.venn6 = this.venn6 ?? C(this.secondaryColor, { h: 60, l: -30 }), this.venn7 = this.venn7 ?? C(this.primaryColor, { h: 120, l: -30 }), this.venn8 = this.venn8 ?? C(this.secondaryColor, { h: 120, l: -30 }), this.vennTitleTextColor = this.vennTitleTextColor ?? this.titleColor, this.vennSetTextColor = this.vennSetTextColor ?? this.textColor, this.quadrant1Fill = this.quadrant1Fill || this.primaryColor, this.quadrant2Fill = this.quadrant2Fill || C(this.primaryColor, { r: 5, g: 5, b: 5 }), this.quadrant3Fill = this.quadrant3Fill || C(this.primaryColor, { r: 10, g: 10, b: 10 }), this.quadrant4Fill = this.quadrant4Fill || C(this.primaryColor, { r: 15, g: 15, b: 15 }), this.quadrant1TextFill = this.quadrant1TextFill || this.primaryTextColor, this.quadrant2TextFill = this.quadrant2TextFill || C(this.primaryTextColor, { r: -5, g: -5, b: -5 }), this.quadrant3TextFill = this.quadrant3TextFill || C(this.primaryTextColor, { r: -10, g: -10, b: -10 }), this.quadrant4TextFill = this.quadrant4TextFill || C(this.primaryTextColor, { r: -15, g: -15, b: -15 }), this.quadrantPointFill = this.quadrantPointFill || _e(this.quadrant1Fill) ? $(this.quadrant1Fill) : I(this.quadrant1Fill), this.quadrantPointTextFill = this.quadrantPointTextFill || this.primaryTextColor, this.quadrantXAxisTextFill = this.quadrantXAxisTextFill || this.primaryTextColor, this.quadrantYAxisTextFill = this.quadrantYAxisTextFill || this.primaryTextColor, this.quadrantInternalBorderStrokeFill = this.quadrantInternalBorderStrokeFill || this.primaryBorderColor, this.quadrantExternalBorderStrokeFill = this.quadrantExternalBorderStrokeFill || this.primaryBorderColor, this.quadrantTitleFill = this.quadrantTitleFill || this.primaryTextColor, this.packet = {
      startByteColor: this.primaryTextColor,
      endByteColor: this.primaryTextColor,
      labelColor: this.primaryTextColor,
      titleColor: this.primaryTextColor,
      blockStrokeColor: this.primaryTextColor,
      blockFillColor: this.mainBkg
    }, this.radar = {
      axisColor: ((t = this.radar) == null ? void 0 : t.axisColor) || this.lineColor,
      axisStrokeWidth: ((r = this.radar) == null ? void 0 : r.axisStrokeWidth) || 2,
      axisLabelFontSize: ((i = this.radar) == null ? void 0 : i.axisLabelFontSize) || 12,
      curveOpacity: ((s = this.radar) == null ? void 0 : s.curveOpacity) || 0.5,
      curveStrokeWidth: ((o = this.radar) == null ? void 0 : o.curveStrokeWidth) || 2,
      graticuleColor: ((a = this.radar) == null ? void 0 : a.graticuleColor) || "#DEDEDE",
      graticuleStrokeWidth: ((n = this.radar) == null ? void 0 : n.graticuleStrokeWidth) || 1,
      graticuleOpacity: ((l = this.radar) == null ? void 0 : l.graticuleOpacity) || 0.3,
      legendBoxSize: ((h = this.radar) == null ? void 0 : h.legendBoxSize) || 12,
      legendFontSize: ((c = this.radar) == null ? void 0 : c.legendFontSize) || 12
    }, this.xyChart = {
      backgroundColor: ((u = this.xyChart) == null ? void 0 : u.backgroundColor) || this.background,
      titleColor: ((p = this.xyChart) == null ? void 0 : p.titleColor) || this.primaryTextColor,
      dataLabelColor: ((d = this.xyChart) == null ? void 0 : d.dataLabelColor) || this.primaryTextColor,
      xAxisTitleColor: ((g = this.xyChart) == null ? void 0 : g.xAxisTitleColor) || this.primaryTextColor,
      xAxisLabelColor: ((m = this.xyChart) == null ? void 0 : m.xAxisLabelColor) || this.primaryTextColor,
      xAxisTickColor: ((y = this.xyChart) == null ? void 0 : y.xAxisTickColor) || this.primaryTextColor,
      xAxisLineColor: ((x = this.xyChart) == null ? void 0 : x.xAxisLineColor) || this.primaryTextColor,
      yAxisTitleColor: ((b = this.xyChart) == null ? void 0 : b.yAxisTitleColor) || this.primaryTextColor,
      yAxisLabelColor: ((k = this.xyChart) == null ? void 0 : k.yAxisLabelColor) || this.primaryTextColor,
      yAxisTickColor: ((w = this.xyChart) == null ? void 0 : w.yAxisTickColor) || this.primaryTextColor,
      yAxisLineColor: ((S = this.xyChart) == null ? void 0 : S.yAxisLineColor) || this.primaryTextColor,
      plotColorPalette: ((L = this.xyChart) == null ? void 0 : L.plotColorPalette) || "#CDE498,#FF6B6B,#A0D2DB,#D7BDE2,#F0F0F0,#FFC3A0,#7FD8BE,#FF9A8B,#FAF3E0,#FFF176"
    }, this.requirementBackground = this.requirementBackground || this.primaryColor, this.requirementBorderColor = this.requirementBorderColor || this.primaryBorderColor, this.requirementBorderSize = this.requirementBorderSize || "1", this.requirementTextColor = this.requirementTextColor || this.primaryTextColor, this.relationColor = this.relationColor || this.lineColor, this.relationLabelBackground = this.relationLabelBackground || this.edgeLabelBackground, this.relationLabelColor = this.relationLabelColor || this.actorTextColor, this.git0 = this.git0 || this.primaryColor, this.git1 = this.git1 || this.secondaryColor, this.git2 = this.git2 || this.tertiaryColor, this.git3 = this.git3 || C(this.primaryColor, { h: -30 }), this.git4 = this.git4 || C(this.primaryColor, { h: -60 }), this.git5 = this.git5 || C(this.primaryColor, { h: -90 }), this.git6 = this.git6 || C(this.primaryColor, { h: 60 }), this.git7 = this.git7 || C(this.primaryColor, { h: 120 }), this.darkMode ? (this.git0 = $(this.git0, 25), this.git1 = $(this.git1, 25), this.git2 = $(this.git2, 25), this.git3 = $(this.git3, 25), this.git4 = $(this.git4, 25), this.git5 = $(this.git5, 25), this.git6 = $(this.git6, 25), this.git7 = $(this.git7, 25)) : (this.git0 = I(this.git0, 25), this.git1 = I(this.git1, 25), this.git2 = I(this.git2, 25), this.git3 = I(this.git3, 25), this.git4 = I(this.git4, 25), this.git5 = I(this.git5, 25), this.git6 = I(this.git6, 25), this.git7 = I(this.git7, 25)), this.gitInv0 = this.gitInv0 || A(this.git0), this.gitInv1 = this.gitInv1 || A(this.git1), this.gitInv2 = this.gitInv2 || A(this.git2), this.gitInv3 = this.gitInv3 || A(this.git3), this.gitInv4 = this.gitInv4 || A(this.git4), this.gitInv5 = this.gitInv5 || A(this.git5), this.gitInv6 = this.gitInv6 || A(this.git6), this.gitInv7 = this.gitInv7 || A(this.git7), this.gitBranchLabel0 = this.gitBranchLabel0 || A(this.labelTextColor), this.gitBranchLabel1 = this.gitBranchLabel1 || this.labelTextColor, this.gitBranchLabel2 = this.gitBranchLabel2 || this.labelTextColor, this.gitBranchLabel3 = this.gitBranchLabel3 || A(this.labelTextColor), this.gitBranchLabel4 = this.gitBranchLabel4 || this.labelTextColor, this.gitBranchLabel5 = this.gitBranchLabel5 || this.labelTextColor, this.gitBranchLabel6 = this.gitBranchLabel6 || this.labelTextColor, this.gitBranchLabel7 = this.gitBranchLabel7 || this.labelTextColor, this.tagLabelColor = this.tagLabelColor || this.primaryTextColor, this.tagLabelBackground = this.tagLabelBackground || this.primaryColor, this.tagLabelBorder = this.tagBorder || this.primaryBorderColor, this.tagLabelFontSize = this.tagLabelFontSize || "10px", this.commitLabelColor = this.commitLabelColor || this.secondaryTextColor, this.commitLabelBackground = this.commitLabelBackground || this.secondaryColor, this.commitLabelFontSize = this.commitLabelFontSize || "10px", this.attributeBackgroundColorOdd = this.attributeBackgroundColorOdd || De, this.attributeBackgroundColorEven = this.attributeBackgroundColorEven || Re;
  }
  calculate(t) {
    if (typeof t != "object") {
      this.updateColors();
      return;
    }
    const r = Object.keys(t);
    r.forEach((i) => {
      this[i] = t[i];
    }), this.updateColors(), r.forEach((i) => {
      this[i] = t[i];
    });
  }
}, f(Zr, "Theme"), Zr), Mx = /* @__PURE__ */ f((e) => {
  const t = new Fx();
  return t.calculate(e), t;
}, "getThemeVariables"), Kr, Ix = (Kr = class {
  constructor() {
    this.primaryColor = "#eee", this.contrast = "#707070", this.secondaryColor = $(this.contrast, 55), this.background = "#ffffff", this.tertiaryColor = C(this.primaryColor, { h: -160 }), this.primaryBorderColor = nt(this.primaryColor, this.darkMode), this.secondaryBorderColor = nt(this.secondaryColor, this.darkMode), this.tertiaryBorderColor = nt(this.tertiaryColor, this.darkMode), this.primaryTextColor = A(this.primaryColor), this.secondaryTextColor = A(this.secondaryColor), this.tertiaryTextColor = A(this.tertiaryColor), this.lineColor = A(this.background), this.textColor = A(this.background), this.mainBkg = "#eee", this.secondBkg = "calculated", this.lineColor = "#666", this.border1 = "#999", this.border2 = "calculated", this.note = "#ffa", this.text = "#333", this.critical = "#d42", this.done = "#bbb", this.arrowheadColor = "#333333", this.fontFamily = '"trebuchet ms", verdana, arial, sans-serif', this.fontSize = "16px", this.THEME_COLOR_LIMIT = 12, this.radius = 5, this.strokeWidth = 1, this.nodeBkg = "calculated", this.nodeBorder = "calculated", this.clusterBkg = "calculated", this.clusterBorder = "calculated", this.defaultLinkColor = "calculated", this.titleColor = "calculated", this.edgeLabelBackground = "white", this.actorBorder = "calculated", this.actorBkg = "calculated", this.actorTextColor = "calculated", this.actorLineColor = this.actorBorder, this.signalColor = "calculated", this.signalTextColor = "calculated", this.labelBoxBkgColor = "calculated", this.labelBoxBorderColor = "calculated", this.labelTextColor = "calculated", this.loopTextColor = "calculated", this.noteBorderColor = "calculated", this.noteBkgColor = "calculated", this.noteTextColor = "calculated", this.activationBorderColor = "#666", this.activationBkgColor = "#f4f4f4", this.sequenceNumberColor = "white", this.sectionBkgColor = "calculated", this.altSectionBkgColor = "white", this.sectionBkgColor2 = "calculated", this.excludeBkgColor = "#eeeeee", this.taskBorderColor = "calculated", this.taskBkgColor = "calculated", this.taskTextLightColor = "white", this.taskTextColor = "calculated", this.taskTextDarkColor = "calculated", this.taskTextOutsideColor = "calculated", this.taskTextClickableColor = "#003163", this.activeTaskBorderColor = "calculated", this.activeTaskBkgColor = "calculated", this.gridColor = "calculated", this.doneTaskBkgColor = "calculated", this.doneTaskBorderColor = "calculated", this.critBkgColor = "calculated", this.critBorderColor = "calculated", this.todayLineColor = "calculated", this.vertLineColor = "calculated", this.personBorder = this.primaryBorderColor, this.personBkg = this.mainBkg, this.archEdgeColor = "calculated", this.archEdgeArrowColor = "calculated", this.archEdgeWidth = "3", this.archGroupBorderColor = this.primaryBorderColor, this.archGroupBorderWidth = "2px", this.noteFontWeight = "normal", this.fontWeight = "normal", this.rowOdd = this.rowOdd || $(this.mainBkg, 75) || "#ffffff", this.rowEven = this.rowEven || "#f4f4f4", this.labelColor = "black", this.errorBkgColor = "#552222", this.errorTextColor = "#552222", this.useGradient = !0, this.gradientStart = this.primaryBorderColor, this.gradientStop = this.secondaryBorderColor, this.dropShadow = "drop-shadow( 1px 2px 2px rgba(185,185,185,1))";
  }
  updateColors() {
    var t, r, i, s, o, a, n, l, h, c, u, p, d, g, m, y, x, b, k, w, S, L;
    this.secondBkg = $(this.contrast, 55), this.border2 = this.contrast, this.actorBorder = $(this.border1, 23), this.actorBkg = this.mainBkg, this.actorTextColor = this.text, this.actorLineColor = this.actorBorder, this.signalColor = this.text, this.signalTextColor = this.text, this.labelBoxBkgColor = this.actorBkg, this.labelBoxBorderColor = this.actorBorder, this.labelTextColor = this.text, this.loopTextColor = this.text, this.noteBorderColor = "#999", this.noteBkgColor = "#666", this.noteTextColor = "#fff", this.cScale0 = this.cScale0 || "#555", this.cScale1 = this.cScale1 || "#F4F4F4", this.cScale2 = this.cScale2 || "#555", this.cScale3 = this.cScale3 || "#BBB", this.cScale4 = this.cScale4 || "#777", this.cScale5 = this.cScale5 || "#999", this.cScale6 = this.cScale6 || "#DDD", this.cScale7 = this.cScale7 || "#FFF", this.cScale8 = this.cScale8 || "#DDD", this.cScale9 = this.cScale9 || "#BBB", this.cScale10 = this.cScale10 || "#999", this.cScale11 = this.cScale11 || "#777";
    for (let T = 0; T < this.THEME_COLOR_LIMIT; T++)
      this["cScaleInv" + T] = this["cScaleInv" + T] || A(this["cScale" + T]);
    for (let T = 0; T < this.THEME_COLOR_LIMIT; T++)
      this.darkMode ? this["cScalePeer" + T] = this["cScalePeer" + T] || $(this["cScale" + T], 10) : this["cScalePeer" + T] = this["cScalePeer" + T] || I(this["cScale" + T], 10);
    this.scaleLabelColor = this.scaleLabelColor || (this.darkMode ? "black" : this.labelTextColor), this.cScaleLabel0 = this.cScaleLabel0 || this.cScale1, this.cScaleLabel2 = this.cScaleLabel2 || this.cScale1;
    for (let T = 0; T < this.THEME_COLOR_LIMIT; T++)
      this["cScaleLabel" + T] = this["cScaleLabel" + T] || this.scaleLabelColor;
    for (let T = 0; T < 5; T++)
      this["surface" + T] = this["surface" + T] || C(this.mainBkg, { l: -(5 + T * 5) }), this["surfacePeer" + T] = this["surfacePeer" + T] || C(this.mainBkg, { l: -(8 + T * 5) });
    this.nodeBkg = this.mainBkg, this.nodeBorder = this.border1, this.clusterBkg = this.secondBkg, this.clusterBorder = this.border2, this.defaultLinkColor = this.lineColor, this.titleColor = this.text, this.sectionBkgColor = $(this.contrast, 30), this.sectionBkgColor2 = $(this.contrast, 30), this.taskBorderColor = I(this.contrast, 10), this.taskBkgColor = this.contrast, this.taskTextColor = this.taskTextLightColor, this.taskTextDarkColor = this.text, this.taskTextOutsideColor = this.taskTextDarkColor, this.activeTaskBorderColor = this.taskBorderColor, this.activeTaskBkgColor = this.mainBkg, this.gridColor = $(this.border1, 30), this.doneTaskBkgColor = this.done, this.doneTaskBorderColor = this.lineColor, this.critBkgColor = this.critical, this.critBorderColor = I(this.critBkgColor, 10), this.todayLineColor = this.critBkgColor, this.vertLineColor = this.critBkgColor, this.archEdgeColor = this.lineColor, this.archEdgeArrowColor = this.lineColor, this.transitionColor = this.transitionColor || "#000", this.transitionLabelColor = this.transitionLabelColor || this.textColor, this.stateLabelColor = this.stateLabelColor || this.stateBkg || this.primaryTextColor, this.stateBkg = this.stateBkg || this.mainBkg, this.labelBackgroundColor = this.labelBackgroundColor || this.stateBkg, this.compositeBackground = this.compositeBackground || this.background || this.tertiaryColor, this.altBackground = this.altBackground || "#f4f4f4", this.compositeTitleBackground = this.compositeTitleBackground || this.mainBkg, this.stateBorder = this.stateBorder || "#000", this.innerEndBackground = this.primaryBorderColor, this.specialStateColor = "#222", this.errorBkgColor = this.errorBkgColor || this.tertiaryColor, this.errorTextColor = this.errorTextColor || this.tertiaryTextColor, this.classText = this.primaryTextColor, this.fillType0 = this.primaryColor, this.fillType1 = this.secondaryColor, this.fillType2 = C(this.primaryColor, { h: 64 }), this.fillType3 = C(this.secondaryColor, { h: 64 }), this.fillType4 = C(this.primaryColor, { h: -64 }), this.fillType5 = C(this.secondaryColor, { h: -64 }), this.fillType6 = C(this.primaryColor, { h: 128 }), this.fillType7 = C(this.secondaryColor, { h: 128 });
    for (let T = 0; T < this.THEME_COLOR_LIMIT; T++)
      this["pie" + T] = this["cScale" + T];
    this.pie12 = this.pie0, this.pieTitleTextSize = this.pieTitleTextSize || "25px", this.pieTitleTextColor = this.pieTitleTextColor || this.taskTextDarkColor, this.pieSectionTextSize = this.pieSectionTextSize || "17px", this.pieSectionTextColor = this.pieSectionTextColor || this.textColor, this.pieLegendTextSize = this.pieLegendTextSize || "17px", this.pieLegendTextColor = this.pieLegendTextColor || this.taskTextDarkColor, this.pieStrokeColor = this.pieStrokeColor || "black", this.pieStrokeWidth = this.pieStrokeWidth || "2px", this.pieOuterStrokeWidth = this.pieOuterStrokeWidth || "2px", this.pieOuterStrokeColor = this.pieOuterStrokeColor || "black", this.pieOpacity = this.pieOpacity || "0.7";
    for (let T = 0; T < 8; T++)
      this["venn" + (T + 1)] = this["venn" + (T + 1)] ?? this["cScale" + T];
    this.vennTitleTextColor = this.vennTitleTextColor ?? this.titleColor, this.vennSetTextColor = this.vennSetTextColor ?? this.textColor, this.quadrant1Fill = this.quadrant1Fill || this.primaryColor, this.quadrant2Fill = this.quadrant2Fill || C(this.primaryColor, { r: 5, g: 5, b: 5 }), this.quadrant3Fill = this.quadrant3Fill || C(this.primaryColor, { r: 10, g: 10, b: 10 }), this.quadrant4Fill = this.quadrant4Fill || C(this.primaryColor, { r: 15, g: 15, b: 15 }), this.quadrant1TextFill = this.quadrant1TextFill || this.primaryTextColor, this.quadrant2TextFill = this.quadrant2TextFill || C(this.primaryTextColor, { r: -5, g: -5, b: -5 }), this.quadrant3TextFill = this.quadrant3TextFill || C(this.primaryTextColor, { r: -10, g: -10, b: -10 }), this.quadrant4TextFill = this.quadrant4TextFill || C(this.primaryTextColor, { r: -15, g: -15, b: -15 }), this.quadrantPointFill = this.quadrantPointFill || _e(this.quadrant1Fill) ? $(this.quadrant1Fill) : I(this.quadrant1Fill), this.quadrantPointTextFill = this.quadrantPointTextFill || this.primaryTextColor, this.quadrantXAxisTextFill = this.quadrantXAxisTextFill || this.primaryTextColor, this.quadrantYAxisTextFill = this.quadrantYAxisTextFill || this.primaryTextColor, this.quadrantInternalBorderStrokeFill = this.quadrantInternalBorderStrokeFill || this.primaryBorderColor, this.quadrantExternalBorderStrokeFill = this.quadrantExternalBorderStrokeFill || this.primaryBorderColor, this.quadrantTitleFill = this.quadrantTitleFill || this.primaryTextColor, this.xyChart = {
      backgroundColor: ((t = this.xyChart) == null ? void 0 : t.backgroundColor) || this.background,
      titleColor: ((r = this.xyChart) == null ? void 0 : r.titleColor) || this.primaryTextColor,
      dataLabelColor: ((i = this.xyChart) == null ? void 0 : i.dataLabelColor) || this.primaryTextColor,
      xAxisTitleColor: ((s = this.xyChart) == null ? void 0 : s.xAxisTitleColor) || this.primaryTextColor,
      xAxisLabelColor: ((o = this.xyChart) == null ? void 0 : o.xAxisLabelColor) || this.primaryTextColor,
      xAxisTickColor: ((a = this.xyChart) == null ? void 0 : a.xAxisTickColor) || this.primaryTextColor,
      xAxisLineColor: ((n = this.xyChart) == null ? void 0 : n.xAxisLineColor) || this.primaryTextColor,
      yAxisTitleColor: ((l = this.xyChart) == null ? void 0 : l.yAxisTitleColor) || this.primaryTextColor,
      yAxisLabelColor: ((h = this.xyChart) == null ? void 0 : h.yAxisLabelColor) || this.primaryTextColor,
      yAxisTickColor: ((c = this.xyChart) == null ? void 0 : c.yAxisTickColor) || this.primaryTextColor,
      yAxisLineColor: ((u = this.xyChart) == null ? void 0 : u.yAxisLineColor) || this.primaryTextColor,
      plotColorPalette: ((p = this.xyChart) == null ? void 0 : p.plotColorPalette) || "#EEE,#6BB8E4,#8ACB88,#C7ACD6,#E8DCC2,#FFB2A8,#FFF380,#7E8D91,#FFD8B1,#FAF3E0"
    }, this.radar = {
      axisColor: ((d = this.radar) == null ? void 0 : d.axisColor) || this.lineColor,
      axisStrokeWidth: ((g = this.radar) == null ? void 0 : g.axisStrokeWidth) || 2,
      axisLabelFontSize: ((m = this.radar) == null ? void 0 : m.axisLabelFontSize) || 12,
      curveOpacity: ((y = this.radar) == null ? void 0 : y.curveOpacity) || 0.5,
      curveStrokeWidth: ((x = this.radar) == null ? void 0 : x.curveStrokeWidth) || 2,
      graticuleColor: ((b = this.radar) == null ? void 0 : b.graticuleColor) || "#DEDEDE",
      graticuleStrokeWidth: ((k = this.radar) == null ? void 0 : k.graticuleStrokeWidth) || 1,
      graticuleOpacity: ((w = this.radar) == null ? void 0 : w.graticuleOpacity) || 0.3,
      legendBoxSize: ((S = this.radar) == null ? void 0 : S.legendBoxSize) || 12,
      legendFontSize: ((L = this.radar) == null ? void 0 : L.legendFontSize) || 12
    }, this.requirementBackground = this.requirementBackground || this.primaryColor, this.requirementBorderColor = this.requirementBorderColor || this.primaryBorderColor, this.requirementBorderSize = this.requirementBorderSize || "1", this.requirementTextColor = this.requirementTextColor || this.primaryTextColor, this.relationColor = this.relationColor || this.lineColor, this.relationLabelBackground = this.relationLabelBackground || this.edgeLabelBackground, this.relationLabelColor = this.relationLabelColor || this.actorTextColor, this.git0 = I(this.pie1, 25) || this.primaryColor, this.git1 = this.pie2 || this.secondaryColor, this.git2 = this.pie3 || this.tertiaryColor, this.git3 = this.pie4 || C(this.primaryColor, { h: -30 }), this.git4 = this.pie5 || C(this.primaryColor, { h: -60 }), this.git5 = this.pie6 || C(this.primaryColor, { h: -90 }), this.git6 = this.pie7 || C(this.primaryColor, { h: 60 }), this.git7 = this.pie8 || C(this.primaryColor, { h: 120 }), this.gitInv0 = this.gitInv0 || A(this.git0), this.gitInv1 = this.gitInv1 || A(this.git1), this.gitInv2 = this.gitInv2 || A(this.git2), this.gitInv3 = this.gitInv3 || A(this.git3), this.gitInv4 = this.gitInv4 || A(this.git4), this.gitInv5 = this.gitInv5 || A(this.git5), this.gitInv6 = this.gitInv6 || A(this.git6), this.gitInv7 = this.gitInv7 || A(this.git7), this.branchLabelColor = this.branchLabelColor || this.labelTextColor, this.gitBranchLabel0 = this.branchLabelColor, this.gitBranchLabel1 = "white", this.gitBranchLabel2 = this.branchLabelColor, this.gitBranchLabel3 = "white", this.gitBranchLabel4 = this.branchLabelColor, this.gitBranchLabel5 = this.branchLabelColor, this.gitBranchLabel6 = this.branchLabelColor, this.gitBranchLabel7 = this.branchLabelColor, this.tagLabelColor = this.tagLabelColor || this.primaryTextColor, this.tagLabelBackground = this.tagLabelBackground || this.primaryColor, this.tagLabelBorder = this.tagBorder || this.primaryBorderColor, this.tagLabelFontSize = this.tagLabelFontSize || "10px", this.commitLabelColor = this.commitLabelColor || this.secondaryTextColor, this.commitLabelBackground = this.commitLabelBackground || this.secondaryColor, this.commitLabelFontSize = this.commitLabelFontSize || "10px", this.attributeBackgroundColorOdd = this.attributeBackgroundColorOdd || De, this.attributeBackgroundColorEven = this.attributeBackgroundColorEven || Re;
  }
  calculate(t) {
    if (typeof t != "object") {
      this.updateColors();
      return;
    }
    const r = Object.keys(t);
    r.forEach((i) => {
      this[i] = t[i];
    }), this.updateColors(), r.forEach((i) => {
      this[i] = t[i];
    });
  }
}, f(Kr, "Theme"), Kr), $x = /* @__PURE__ */ f((e) => {
  const t = new Ix();
  return t.calculate(e), t;
}, "getThemeVariables"), Qr, Ox = (Qr = class {
  constructor() {
    this.background = "#ffffff", this.primaryColor = "#cccccc", this.mainBkg = "#ffffff", this.noteBkgColor = "#fff5ad", this.noteTextColor = "#333", this.THEME_COLOR_LIMIT = 12, this.radius = 3, this.strokeWidth = 2, this.primaryBorderColor = nt(this.primaryColor, this.darkMode), this.fontFamily = "arial, sans-serif", this.fontSize = "14px", this.nodeBorder = "#000000", this.stateBorder = "#000000", this.useGradient = !0, this.gradientStart = "#0042eb", this.gradientStop = "#eb0042", this.dropShadow = "drop-shadow( 0px 1px 2px rgba(0, 0, 0, 0.25));", this.tertiaryColor = "#ffffff", this.archEdgeColor = "calculated", this.archEdgeArrowColor = "calculated", this.archEdgeWidth = "3", this.archGroupBorderColor = this.primaryBorderColor, this.archGroupBorderWidth = "2px", this.noteFontWeight = "normal", this.fontWeight = "normal";
  }
  updateColors() {
    var o, a, n, l, h, c, u, p, d, g, m;
    this.primaryTextColor = this.primaryTextColor || (this.darkMode ? "#eee" : "#333"), this.secondaryColor = this.secondaryColor || C(this.primaryColor, { h: -120 }), this.tertiaryColor = this.tertiaryColor || C(this.primaryColor, { h: 180, l: 5 }), this.primaryBorderColor = this.primaryBorderColor || nt(this.primaryColor, this.darkMode), this.secondaryBorderColor = this.secondaryBorderColor || nt(this.secondaryColor, this.darkMode), this.tertiaryBorderColor = this.tertiaryBorderColor || nt(this.tertiaryColor, this.darkMode), this.noteBorderColor = this.noteBorderColor || nt(this.noteBkgColor, this.darkMode), this.noteBkgColor = this.noteBkgColor || "#fff5ad", this.noteTextColor = this.noteTextColor || "#333", this.secondaryTextColor = this.secondaryTextColor || A(this.secondaryColor), this.tertiaryTextColor = this.tertiaryTextColor || A(this.tertiaryColor), this.lineColor = this.lineColor || A(this.background), this.arrowheadColor = this.arrowheadColor || A(this.background), this.textColor = this.textColor || this.primaryTextColor, this.border2 = this.border2 || this.tertiaryBorderColor, this.nodeBkg = this.nodeBkg || this.primaryColor, this.mainBkg = this.mainBkg || this.primaryColor, this.nodeBorder = this.nodeBorder || this.primaryBorderColor, this.clusterBkg = this.clusterBkg || this.tertiaryColor, this.clusterBorder = this.clusterBorder || this.tertiaryBorderColor, this.defaultLinkColor = this.defaultLinkColor || this.lineColor, this.titleColor = this.titleColor || this.tertiaryTextColor, this.edgeLabelBackground = this.edgeLabelBackground || (this.darkMode ? I(this.secondaryColor, 30) : this.secondaryColor), this.nodeTextColor = this.nodeTextColor || this.primaryTextColor, this.actorBorder = this.actorBorder || this.primaryBorderColor, this.actorBkg = this.actorBkg || this.mainBkg, this.actorTextColor = this.actorTextColor || this.primaryTextColor, this.actorLineColor = this.actorLineColor || this.actorBorder, this.labelBoxBkgColor = this.labelBoxBkgColor || this.actorBkg, this.signalColor = this.signalColor || this.textColor, this.signalTextColor = this.signalTextColor || this.textColor, this.labelBoxBorderColor = this.labelBoxBorderColor || this.actorBorder, this.labelTextColor = this.labelTextColor || this.actorTextColor, this.loopTextColor = this.loopTextColor || this.actorTextColor, this.activationBorderColor = this.activationBorderColor || I(this.secondaryColor, 10), this.activationBkgColor = this.activationBkgColor || this.secondaryColor, this.sequenceNumberColor = this.sequenceNumberColor || A(this.lineColor);
    const t = "#ECECFE", r = "#E9E9F1", i = C(t, { h: 180, l: 5 });
    if (this.sectionBkgColor = this.sectionBkgColor || i, this.altSectionBkgColor = this.altSectionBkgColor || "white", this.sectionBkgColor = this.sectionBkgColor || r, this.sectionBkgColor2 = this.sectionBkgColor2 || t, this.excludeBkgColor = this.excludeBkgColor || "#eeeeee", this.taskBorderColor = this.taskBorderColor || this.primaryBorderColor, this.taskBkgColor = this.taskBkgColor || t, this.activeTaskBorderColor = this.activeTaskBorderColor || t, this.activeTaskBkgColor = this.activeTaskBkgColor || $(t, 23), this.gridColor = this.gridColor || "lightgrey", this.doneTaskBkgColor = this.doneTaskBkgColor || "lightgrey", this.doneTaskBorderColor = this.doneTaskBorderColor || "grey", this.critBorderColor = this.critBorderColor || "#ff8888", this.critBkgColor = this.critBkgColor || "red", this.todayLineColor = this.todayLineColor || "red", this.taskTextColor = this.taskTextColor || this.textColor, this.taskTextOutsideColor = this.taskTextOutsideColor || this.textColor, this.vertLineColor = this.vertLineColor || this.primaryBorderColor, this.taskTextLightColor = this.taskTextLightColor || this.textColor, this.taskTextColor = this.taskTextColor || this.primaryTextColor, this.taskTextDarkColor = this.taskTextDarkColor || this.textColor, this.taskTextClickableColor = this.taskTextClickableColor || "#003163", this.archEdgeColor = this.lineColor, this.archEdgeArrowColor = this.lineColor, this.personBorder = this.personBorder || this.primaryBorderColor, this.personBkg = this.personBkg || this.mainBkg, this.transitionColor = this.transitionColor || this.lineColor, this.transitionLabelColor = this.transitionLabelColor || this.textColor, this.stateLabelColor = this.stateLabelColor || this.stateBkg || this.primaryTextColor, this.stateBkg = this.stateBkg || this.mainBkg, this.labelBackgroundColor = this.labelBackgroundColor || this.stateBkg, this.compositeBackground = this.compositeBackground || this.background || this.tertiaryColor, this.altBackground = this.altBackground || "#f0f0f0", this.compositeTitleBackground = this.compositeTitleBackground || this.mainBkg, this.compositeBorder = this.compositeBorder || this.nodeBorder, this.innerEndBackground = this.nodeBorder, this.errorBkgColor = this.errorBkgColor || this.tertiaryColor, this.errorTextColor = this.errorTextColor || this.tertiaryTextColor, this.transitionColor = this.transitionColor || this.lineColor, this.specialStateColor = this.lineColor, this.cScale0 = this.cScale0 || t, this.cScale1 = this.cScale1 || r, this.cScale2 = this.cScale2 || i, this.cScale3 = this.cScale3 || C(t, { h: 30 }), this.cScale4 = this.cScale4 || C(t, { h: 60 }), this.cScale5 = this.cScale5 || C(t, { h: 90 }), this.cScale6 = this.cScale6 || C(t, { h: 120 }), this.cScale7 = this.cScale7 || C(t, { h: 150 }), this.cScale8 = this.cScale8 || C(t, { h: 210, l: 150 }), this.cScale9 = this.cScale9 || C(t, { h: 270 }), this.cScale10 = this.cScale10 || C(t, { h: 300 }), this.cScale11 = this.cScale11 || C(t, { h: 330 }), this.darkMode)
      for (let y = 0; y < this.THEME_COLOR_LIMIT; y++)
        this["cScale" + y] = I(this["cScale" + y], 75);
    else
      for (let y = 0; y < this.THEME_COLOR_LIMIT; y++)
        this["cScale" + y] = I(this["cScale" + y], 25);
    for (let y = 0; y < this.THEME_COLOR_LIMIT; y++)
      this["cScaleInv" + y] = this["cScaleInv" + y] || A(this["cScale" + y]);
    for (let y = 0; y < this.THEME_COLOR_LIMIT; y++)
      this.darkMode ? this["cScalePeer" + y] = this["cScalePeer" + y] || $(this["cScale" + y], 10) : this["cScalePeer" + y] = this["cScalePeer" + y] || I(this["cScale" + y], 10);
    this.scaleLabelColor = this.scaleLabelColor || this.labelTextColor;
    for (let y = 0; y < this.THEME_COLOR_LIMIT; y++)
      this["cScaleLabel" + y] = this["cScaleLabel" + y] || this.scaleLabelColor;
    const s = this.darkMode ? -4 : -1;
    for (let y = 0; y < 5; y++)
      this["surface" + y] = this["surface" + y] || C(this.mainBkg, { h: 180, s: -15, l: s * (5 + y * 3) }), this["surfacePeer" + y] = this["surfacePeer" + y] || C(this.mainBkg, { h: 180, s: -15, l: s * (8 + y * 3) });
    this.classText = this.classText || this.textColor, this.fillType0 = this.fillType0 || t, this.fillType1 = this.fillType1 || r, this.fillType2 = this.fillType2 || C(t, { h: 64 }), this.fillType3 = this.fillType3 || C(r, { h: 64 }), this.fillType4 = this.fillType4 || C(t, { h: -64 }), this.fillType5 = this.fillType5 || C(r, { h: -64 }), this.fillType6 = this.fillType6 || C(t, { h: 128 }), this.fillType7 = this.fillType7 || C(r, { h: 128 }), this.pie1 = this.pie1 || t, this.pie2 = this.pie2 || r, this.pie3 = this.pie3 || i, this.pie4 = this.pie4 || C(t, { l: -10 }), this.pie5 = this.pie5 || C(r, { l: -10 }), this.pie6 = this.pie6 || C(i, { l: -10 }), this.pie7 = this.pie7 || C(t, { h: 60, l: -10 }), this.pie8 = this.pie8 || C(t, { h: -60, l: -10 }), this.pie9 = this.pie9 || C(t, { h: 120, l: 0 }), this.pie10 = this.pie10 || C(t, { h: 60, l: -20 }), this.pie11 = this.pie11 || C(t, { h: -60, l: -20 }), this.pie12 = this.pie12 || C(t, { h: 120, l: -10 }), this.pieTitleTextSize = this.pieTitleTextSize || "25px", this.pieTitleTextColor = this.pieTitleTextColor || this.taskTextDarkColor, this.pieSectionTextSize = this.pieSectionTextSize || "17px", this.pieSectionTextColor = this.pieSectionTextColor || this.textColor, this.pieLegendTextSize = this.pieLegendTextSize || "17px", this.pieLegendTextColor = this.pieLegendTextColor || this.taskTextDarkColor, this.pieStrokeColor = this.pieStrokeColor || "black", this.pieStrokeWidth = this.pieStrokeWidth || "2px", this.pieOuterStrokeWidth = this.pieOuterStrokeWidth || "2px", this.pieOuterStrokeColor = this.pieOuterStrokeColor || "black", this.pieOpacity = this.pieOpacity || "0.7", this.vennTitleTextColor = this.vennTitleTextColor ?? this.titleColor, this.vennSetTextColor = this.vennSetTextColor ?? this.textColor, this.quadrant1Fill = this.quadrant1Fill || t, this.quadrant2Fill = this.quadrant2Fill || C(t, { r: 5, g: 5, b: 5 }), this.quadrant3Fill = this.quadrant3Fill || C(t, { r: 10, g: 10, b: 10 }), this.quadrant4Fill = this.quadrant4Fill || C(t, { r: 15, g: 15, b: 15 }), this.quadrant1TextFill = this.quadrant1TextFill || this.primaryTextColor, this.quadrant2TextFill = this.quadrant2TextFill || C(this.primaryTextColor, { r: -5, g: -5, b: -5 }), this.quadrant3TextFill = this.quadrant3TextFill || C(this.primaryTextColor, { r: -10, g: -10, b: -10 }), this.quadrant4TextFill = this.quadrant4TextFill || C(this.primaryTextColor, { r: -15, g: -15, b: -15 }), this.quadrantPointFill = this.quadrantPointFill || _e(this.quadrant1Fill) ? $(this.quadrant1Fill) : I(this.quadrant1Fill), this.quadrantPointTextFill = this.quadrantPointTextFill || this.primaryTextColor, this.quadrantXAxisTextFill = this.quadrantXAxisTextFill || this.primaryTextColor, this.quadrantYAxisTextFill = this.quadrantYAxisTextFill || this.primaryTextColor, this.quadrantInternalBorderStrokeFill = this.quadrantInternalBorderStrokeFill || this.primaryBorderColor, this.quadrantExternalBorderStrokeFill = this.quadrantExternalBorderStrokeFill || this.primaryBorderColor, this.quadrantTitleFill = this.quadrantTitleFill || this.primaryTextColor, this.xyChart = {
      backgroundColor: ((o = this.xyChart) == null ? void 0 : o.backgroundColor) || this.background,
      titleColor: ((a = this.xyChart) == null ? void 0 : a.titleColor) || this.primaryTextColor,
      xAxisTitleColor: ((n = this.xyChart) == null ? void 0 : n.xAxisTitleColor) || this.primaryTextColor,
      xAxisLabelColor: ((l = this.xyChart) == null ? void 0 : l.xAxisLabelColor) || this.primaryTextColor,
      xAxisTickColor: ((h = this.xyChart) == null ? void 0 : h.xAxisTickColor) || this.primaryTextColor,
      xAxisLineColor: ((c = this.xyChart) == null ? void 0 : c.xAxisLineColor) || this.primaryTextColor,
      yAxisTitleColor: ((u = this.xyChart) == null ? void 0 : u.yAxisTitleColor) || this.primaryTextColor,
      yAxisLabelColor: ((p = this.xyChart) == null ? void 0 : p.yAxisLabelColor) || this.primaryTextColor,
      yAxisTickColor: ((d = this.xyChart) == null ? void 0 : d.yAxisTickColor) || this.primaryTextColor,
      yAxisLineColor: ((g = this.xyChart) == null ? void 0 : g.yAxisLineColor) || this.primaryTextColor,
      plotColorPalette: ((m = this.xyChart) == null ? void 0 : m.plotColorPalette) || "#FFF4DD,#FFD8B1,#FFA07A,#ECEFF1,#D6DBDF,#C3E0A8,#FFB6A4,#FFD74D,#738FA7,#FFFFF0"
    }, this.requirementBackground = this.requirementBackground || t, this.requirementBorderColor = this.requirementBorderColor || this.primaryBorderColor, this.requirementBorderSize = this.requirementBorderSize || "1", this.requirementTextColor = this.requirementTextColor || this.primaryTextColor, this.relationColor = this.relationColor || this.lineColor, this.relationLabelBackground = this.relationLabelBackground || (this.darkMode ? I(this.secondaryColor, 30) : this.secondaryColor), this.relationLabelColor = this.relationLabelColor || this.actorTextColor, this.git0 = this.git0 || t, this.git1 = this.git1 || r, this.git2 = this.git2 || i, this.git3 = this.git3 || C(t, { h: -30 }), this.git4 = this.git4 || C(t, { h: -60 }), this.git5 = this.git5 || C(t, { h: -90 }), this.git6 = this.git6 || C(t, { h: 60 }), this.git7 = this.git7 || C(t, { h: 120 }), this.darkMode ? (this.git0 = $(this.git0, 25), this.git1 = $(this.git1, 25), this.git2 = $(this.git2, 25), this.git3 = $(this.git3, 25), this.git4 = $(this.git4, 25), this.git5 = $(this.git5, 25), this.git6 = $(this.git6, 25), this.git7 = $(this.git7, 25)) : (this.git0 = I(this.git0, 25), this.git1 = I(this.git1, 25), this.git2 = I(this.git2, 25), this.git3 = I(this.git3, 25), this.git4 = I(this.git4, 25), this.git5 = I(this.git5, 25), this.git6 = I(this.git6, 25), this.git7 = I(this.git7, 25)), this.gitInv0 = this.gitInv0 || A(this.git0), this.gitInv1 = this.gitInv1 || A(this.git1), this.gitInv2 = this.gitInv2 || A(this.git2), this.gitInv3 = this.gitInv3 || A(this.git3), this.gitInv4 = this.gitInv4 || A(this.git4), this.gitInv5 = this.gitInv5 || A(this.git5), this.gitInv6 = this.gitInv6 || A(this.git6), this.gitInv7 = this.gitInv7 || A(this.git7), this.branchLabelColor = this.branchLabelColor || (this.darkMode ? "black" : this.labelTextColor), this.gitBranchLabel0 = this.gitBranchLabel0 || this.branchLabelColor, this.gitBranchLabel1 = this.gitBranchLabel1 || this.branchLabelColor, this.gitBranchLabel2 = this.gitBranchLabel2 || this.branchLabelColor, this.gitBranchLabel3 = this.gitBranchLabel3 || this.branchLabelColor, this.gitBranchLabel4 = this.gitBranchLabel4 || this.branchLabelColor, this.gitBranchLabel5 = this.gitBranchLabel5 || this.branchLabelColor, this.gitBranchLabel6 = this.gitBranchLabel6 || this.branchLabelColor, this.gitBranchLabel7 = this.gitBranchLabel7 || this.branchLabelColor, this.tagLabelColor = this.tagLabelColor || this.primaryTextColor, this.tagLabelBackground = this.tagLabelBackground || this.primaryColor, this.tagLabelBorder = this.tagBorder || this.primaryBorderColor, this.tagLabelFontSize = this.tagLabelFontSize || "10px", this.commitLabelColor = this.commitLabelColor || this.secondaryTextColor, this.commitLabelBackground = this.commitLabelBackground || this.secondaryColor, this.commitLabelFontSize = this.commitLabelFontSize || "10px", this.attributeBackgroundColorOdd = this.attributeBackgroundColorOdd || De, this.attributeBackgroundColorEven = this.attributeBackgroundColorEven || Re;
  }
  calculate(t) {
    if (typeof t != "object") {
      this.updateColors();
      return;
    }
    const r = Object.keys(t);
    r.forEach((i) => {
      this[i] = t[i];
    }), this.updateColors(), r.forEach((i) => {
      this[i] = t[i];
    });
  }
}, f(Qr, "Theme"), Qr), Dx = /* @__PURE__ */ f((e) => {
  const t = new Ox();
  return t.calculate(e), t;
}, "getThemeVariables"), Jr, Rx = (Jr = class {
  constructor() {
    this.background = "#333", this.primaryColor = "#1f2020", this.secondaryColor = $(this.primaryColor, 16), this.tertiaryColor = C(this.primaryColor, { h: -160 }), this.primaryBorderColor = A(this.background), this.secondaryBorderColor = nt(this.secondaryColor, this.darkMode), this.tertiaryBorderColor = nt(this.tertiaryColor, this.darkMode), this.primaryTextColor = A(this.primaryColor), this.secondaryTextColor = A(this.secondaryColor), this.tertiaryTextColor = A(this.tertiaryColor), this.mainBkg = "#2a2020", this.secondBkg = "calculated", this.mainContrastColor = "lightgrey", this.darkTextColor = $(A("#323D47"), 10), this.border1 = "#ccc", this.border2 = gr(255, 255, 255, 0.25), this.arrowheadColor = A(this.background), this.fontFamily = "arial, sans-serif", this.fontSize = "14px", this.labelBackground = "#181818", this.textColor = "#ccc", this.THEME_COLOR_LIMIT = 12, this.radius = 3, this.strokeWidth = 1, this.noteBkgColor = "#fff5ad", this.noteTextColor = "#333", this.THEME_COLOR_LIMIT = 12, this.fontFamily = "arial, sans-serif", this.fontSize = "14px", this.useGradient = !0, this.gradientStart = "#0042eb", this.gradientStop = "#eb0042", this.dropShadow = "drop-shadow( 1px 2px 2px rgba(185,185,185,0.2))", this.archEdgeColor = "calculated", this.archEdgeArrowColor = "calculated", this.archEdgeWidth = "3", this.archGroupBorderColor = this.primaryBorderColor, this.archGroupBorderWidth = "2px", this.noteFontWeight = "normal", this.fontWeight = "normal";
  }
  updateColors() {
    var r, i, s, o, a, n, l, h, c, u, p;
    if (this.primaryTextColor = this.primaryTextColor || (this.darkMode ? "#eee" : "#333"), this.secondaryColor = this.secondaryColor || C(this.primaryColor, { h: -120 }), this.tertiaryColor = this.tertiaryColor || C(this.primaryColor, { h: 180, l: 5 }), this.primaryBorderColor = this.primaryBorderColor || nt(this.primaryColor, this.darkMode), this.secondaryBorderColor = this.secondaryBorderColor || nt(this.secondaryColor, this.darkMode), this.tertiaryBorderColor = this.tertiaryBorderColor || nt(this.tertiaryColor, this.darkMode), this.noteBorderColor = this.noteBorderColor || nt(this.noteBkgColor, this.darkMode), this.noteBkgColor = this.noteBkgColor || "#fff5ad", this.noteTextColor = this.noteTextColor || "#333", this.secondaryTextColor = this.secondaryTextColor || A(this.secondaryColor), this.tertiaryTextColor = this.tertiaryTextColor || A(this.tertiaryColor), this.lineColor = this.lineColor || A(this.background), this.arrowheadColor = this.arrowheadColor || A(this.background), this.textColor = this.textColor || this.primaryTextColor, this.border2 = this.border2 || this.tertiaryBorderColor, this.nodeBkg = this.nodeBkg || this.primaryColor, this.mainBkg = this.mainBkg || this.primaryColor, this.nodeBorder = this.nodeBorder || this.border1, this.clusterBkg = this.clusterBkg || this.tertiaryColor, this.clusterBorder = this.clusterBorder || this.tertiaryBorderColor, this.defaultLinkColor = this.defaultLinkColor || this.lineColor, this.titleColor = this.titleColor || this.tertiaryTextColor, this.edgeLabelBackground = this.edgeLabelBackground || (this.darkMode ? I(this.secondaryColor, 30) : this.secondaryColor), this.nodeTextColor = this.nodeTextColor || this.primaryTextColor, this.actorBorder = this.actorBorder || this.primaryBorderColor, this.actorBkg = this.actorBkg || this.mainBkg, this.actorTextColor = this.actorTextColor || this.primaryTextColor, this.actorLineColor = this.actorLineColor || this.actorBorder, this.labelBoxBkgColor = this.labelBoxBkgColor || this.actorBkg, this.signalColor = this.signalColor || this.textColor, this.signalTextColor = this.signalTextColor || this.textColor, this.labelBoxBorderColor = this.labelBoxBorderColor || this.actorBorder, this.labelTextColor = this.labelTextColor || this.actorTextColor, this.loopTextColor = this.loopTextColor || this.actorTextColor, this.activationBorderColor = this.activationBorderColor || I(this.secondaryColor, 10), this.activationBkgColor = this.activationBkgColor || this.secondaryColor, this.sequenceNumberColor = this.sequenceNumberColor || A(this.lineColor), this.sectionBkgColor = this.sectionBkgColor || this.tertiaryColor, this.altSectionBkgColor = this.altSectionBkgColor || "white", this.sectionBkgColor = this.sectionBkgColor || this.secondaryColor, this.sectionBkgColor2 = this.sectionBkgColor2 || this.primaryColor, this.excludeBkgColor = this.excludeBkgColor || "#eeeeee", this.taskBorderColor = this.taskBorderColor || this.primaryBorderColor, this.taskBkgColor = this.taskBkgColor || this.primaryColor, this.activeTaskBorderColor = this.activeTaskBorderColor || this.primaryColor, this.activeTaskBkgColor = this.activeTaskBkgColor || $(this.primaryColor, 23), this.gridColor = this.gridColor || "lightgrey", this.doneTaskBkgColor = this.doneTaskBkgColor || "lightgrey", this.doneTaskBorderColor = this.doneTaskBorderColor || "grey", this.critBorderColor = this.critBorderColor || "#ff8888", this.critBkgColor = this.critBkgColor || "red", this.todayLineColor = this.todayLineColor || "red", this.vertLineColor = this.vertLineColor || this.primaryBorderColor, this.taskTextColor = this.taskTextColor || this.textColor, this.taskTextOutsideColor = this.taskTextOutsideColor || this.textColor, this.taskTextLightColor = this.taskTextLightColor || this.textColor, this.taskTextColor = this.taskTextColor || this.primaryTextColor, this.taskTextDarkColor = this.taskTextDarkColor || this.textColor, this.taskTextClickableColor = this.taskTextClickableColor || "#003163", this.archEdgeColor = this.lineColor, this.archEdgeArrowColor = this.lineColor, this.personBorder = this.personBorder || this.primaryBorderColor, this.personBkg = this.personBkg || this.mainBkg, this.transitionColor = this.transitionColor || this.lineColor, this.transitionLabelColor = this.transitionLabelColor || this.textColor, this.stateLabelColor = this.stateLabelColor || this.stateBkg || this.primaryTextColor, this.stateBkg = this.stateBkg || this.mainBkg, this.labelBackgroundColor = this.labelBackgroundColor || this.stateBkg, this.compositeBackground = this.compositeBackground || this.background || this.tertiaryColor, this.altBackground = this.altBackground || "#f0f0f0", this.compositeTitleBackground = this.compositeTitleBackground || this.mainBkg, this.compositeBorder = this.compositeBorder || this.nodeBorder, this.innerEndBackground = this.nodeBorder, this.errorBkgColor = this.errorBkgColor || this.tertiaryColor, this.errorTextColor = this.errorTextColor || this.tertiaryTextColor, this.transitionColor = this.transitionColor || this.lineColor, this.specialStateColor = this.lineColor, this.cScale0 = this.cScale0 || this.primaryColor, this.cScale1 = this.cScale1 || this.secondaryColor, this.cScale2 = this.cScale2 || this.tertiaryColor, this.cScale3 = this.cScale3 || C(this.primaryColor, { h: 30 }), this.cScale4 = this.cScale4 || C(this.primaryColor, { h: 60 }), this.cScale5 = this.cScale5 || C(this.primaryColor, { h: 90 }), this.cScale6 = this.cScale6 || C(this.primaryColor, { h: 120 }), this.cScale7 = this.cScale7 || C(this.primaryColor, { h: 150 }), this.cScale8 = this.cScale8 || C(this.primaryColor, { h: 210, l: 150 }), this.cScale9 = this.cScale9 || C(this.primaryColor, { h: 270 }), this.cScale10 = this.cScale10 || C(this.primaryColor, { h: 300 }), this.cScale11 = this.cScale11 || C(this.primaryColor, { h: 330 }), this.darkMode)
      for (let d = 0; d < this.THEME_COLOR_LIMIT; d++)
        this["cScale" + d] = I(this["cScale" + d], 75);
    else
      for (let d = 0; d < this.THEME_COLOR_LIMIT; d++)
        this["cScale" + d] = I(this["cScale" + d], 25);
    for (let d = 0; d < this.THEME_COLOR_LIMIT; d++)
      this["cScaleInv" + d] = this["cScaleInv" + d] || A(this["cScale" + d]);
    for (let d = 0; d < this.THEME_COLOR_LIMIT; d++)
      this.darkMode ? this["cScalePeer" + d] = this["cScalePeer" + d] || $(this["cScale" + d], 10) : this["cScalePeer" + d] = this["cScalePeer" + d] || I(this["cScale" + d], 10);
    this.scaleLabelColor = this.scaleLabelColor || this.labelTextColor;
    for (let d = 0; d < this.THEME_COLOR_LIMIT; d++)
      this["cScaleLabel" + d] = this["cScaleLabel" + d] || this.scaleLabelColor;
    const t = this.darkMode ? -4 : -1;
    for (let d = 0; d < 5; d++)
      this["surface" + d] = this["surface" + d] || C(this.mainBkg, { h: 180, s: -15, l: t * (5 + d * 3) }), this["surfacePeer" + d] = this["surfacePeer" + d] || C(this.mainBkg, { h: 180, s: -15, l: t * (8 + d * 3) });
    this.classText = this.classText || this.textColor, this.fillType0 = this.fillType0 || this.primaryColor, this.fillType1 = this.fillType1 || this.secondaryColor, this.fillType2 = this.fillType2 || C(this.primaryColor, { h: 64 }), this.fillType3 = this.fillType3 || C(this.secondaryColor, { h: 64 }), this.fillType4 = this.fillType4 || C(this.primaryColor, { h: -64 }), this.fillType5 = this.fillType5 || C(this.secondaryColor, { h: -64 }), this.fillType6 = this.fillType6 || C(this.primaryColor, { h: 128 }), this.fillType7 = this.fillType7 || C(this.secondaryColor, { h: 128 }), this.pie1 = this.pie1 || this.primaryColor, this.pie2 = this.pie2 || this.secondaryColor, this.pie3 = this.pie3 || this.tertiaryColor, this.pie4 = this.pie4 || C(this.primaryColor, { l: -10 }), this.pie5 = this.pie5 || C(this.secondaryColor, { l: -10 }), this.pie6 = this.pie6 || C(this.tertiaryColor, { l: -10 }), this.pie7 = this.pie7 || C(this.primaryColor, { h: 60, l: -10 }), this.pie8 = this.pie8 || C(this.primaryColor, { h: -60, l: -10 }), this.pie9 = this.pie9 || C(this.primaryColor, { h: 120, l: 0 }), this.pie10 = this.pie10 || C(this.primaryColor, { h: 60, l: -20 }), this.pie11 = this.pie11 || C(this.primaryColor, { h: -60, l: -20 }), this.pie12 = this.pie12 || C(this.primaryColor, { h: 120, l: -10 }), this.pieTitleTextSize = this.pieTitleTextSize || "25px", this.pieTitleTextColor = this.pieTitleTextColor || this.taskTextDarkColor, this.pieSectionTextSize = this.pieSectionTextSize || "17px", this.pieSectionTextColor = this.pieSectionTextColor || this.textColor, this.pieLegendTextSize = this.pieLegendTextSize || "17px", this.pieLegendTextColor = this.pieLegendTextColor || this.taskTextDarkColor, this.pieStrokeColor = this.pieStrokeColor || "black", this.pieStrokeWidth = this.pieStrokeWidth || "2px", this.pieOuterStrokeWidth = this.pieOuterStrokeWidth || "2px", this.pieOuterStrokeColor = this.pieOuterStrokeColor || "black", this.pieOpacity = this.pieOpacity || "0.7", this.vennTitleTextColor = this.vennTitleTextColor ?? this.titleColor, this.vennSetTextColor = this.vennSetTextColor ?? this.textColor, this.quadrant1Fill = this.quadrant1Fill || this.primaryColor, this.quadrant2Fill = this.quadrant2Fill || C(this.primaryColor, { r: 5, g: 5, b: 5 }), this.quadrant3Fill = this.quadrant3Fill || C(this.primaryColor, { r: 10, g: 10, b: 10 }), this.quadrant4Fill = this.quadrant4Fill || C(this.primaryColor, { r: 15, g: 15, b: 15 }), this.quadrant1TextFill = this.quadrant1TextFill || this.primaryTextColor, this.quadrant2TextFill = this.quadrant2TextFill || C(this.primaryTextColor, { r: -5, g: -5, b: -5 }), this.quadrant3TextFill = this.quadrant3TextFill || C(this.primaryTextColor, { r: -10, g: -10, b: -10 }), this.quadrant4TextFill = this.quadrant4TextFill || C(this.primaryTextColor, { r: -15, g: -15, b: -15 }), this.quadrantPointFill = this.quadrantPointFill || _e(this.quadrant1Fill) ? $(this.quadrant1Fill) : I(this.quadrant1Fill), this.quadrantPointTextFill = this.quadrantPointTextFill || this.primaryTextColor, this.quadrantXAxisTextFill = this.quadrantXAxisTextFill || this.primaryTextColor, this.quadrantYAxisTextFill = this.quadrantYAxisTextFill || this.primaryTextColor, this.quadrantInternalBorderStrokeFill = this.quadrantInternalBorderStrokeFill || this.primaryBorderColor, this.quadrantExternalBorderStrokeFill = this.quadrantExternalBorderStrokeFill || this.primaryBorderColor, this.quadrantTitleFill = this.quadrantTitleFill || this.primaryTextColor, this.xyChart = {
      backgroundColor: ((r = this.xyChart) == null ? void 0 : r.backgroundColor) || this.background,
      titleColor: ((i = this.xyChart) == null ? void 0 : i.titleColor) || this.primaryTextColor,
      xAxisTitleColor: ((s = this.xyChart) == null ? void 0 : s.xAxisTitleColor) || this.primaryTextColor,
      xAxisLabelColor: ((o = this.xyChart) == null ? void 0 : o.xAxisLabelColor) || this.primaryTextColor,
      xAxisTickColor: ((a = this.xyChart) == null ? void 0 : a.xAxisTickColor) || this.primaryTextColor,
      xAxisLineColor: ((n = this.xyChart) == null ? void 0 : n.xAxisLineColor) || this.primaryTextColor,
      yAxisTitleColor: ((l = this.xyChart) == null ? void 0 : l.yAxisTitleColor) || this.primaryTextColor,
      yAxisLabelColor: ((h = this.xyChart) == null ? void 0 : h.yAxisLabelColor) || this.primaryTextColor,
      yAxisTickColor: ((c = this.xyChart) == null ? void 0 : c.yAxisTickColor) || this.primaryTextColor,
      yAxisLineColor: ((u = this.xyChart) == null ? void 0 : u.yAxisLineColor) || this.primaryTextColor,
      plotColorPalette: ((p = this.xyChart) == null ? void 0 : p.plotColorPalette) || "#FFF4DD,#FFD8B1,#FFA07A,#ECEFF1,#D6DBDF,#C3E0A8,#FFB6A4,#FFD74D,#738FA7,#FFFFF0"
    }, this.requirementBackground = this.requirementBackground || this.primaryColor, this.requirementBorderColor = this.requirementBorderColor || this.primaryBorderColor, this.requirementBorderSize = this.requirementBorderSize || "1", this.requirementTextColor = this.requirementTextColor || this.primaryTextColor, this.relationColor = this.relationColor || this.lineColor, this.relationLabelBackground = this.relationLabelBackground || (this.darkMode ? I(this.secondaryColor, 30) : this.secondaryColor), this.relationLabelColor = this.relationLabelColor || this.actorTextColor, this.git0 = this.git0 || "#0b0000", this.git1 = this.git1 || "#4d1037", this.git2 = this.git2 || "#3f5258", this.git3 = this.git3 || "#4f2f1b", this.git4 = this.git4 || "#6e0a0a", this.git5 = this.git5 || "#3b0048", this.git6 = this.git6 || "#995a01", this.git7 = this.git7 || "#154706", this.gitDarkMode = !0, this.gitDarkMode ? (this.git0 = $(this.git0, 25), this.git1 = $(this.git1, 25), this.git2 = $(this.git2, 25), this.git3 = $(this.git3, 25), this.git4 = $(this.git4, 25), this.git5 = $(this.git5, 25), this.git6 = $(this.git6, 25), this.git7 = $(this.git7, 25)) : (this.git0 = I(this.git0, 25), this.git1 = I(this.git1, 25), this.git2 = I(this.git2, 25), this.git3 = I(this.git3, 25), this.git4 = I(this.git4, 25), this.git5 = I(this.git5, 25), this.git6 = I(this.git6, 25), this.git7 = I(this.git7, 25)), this.gitInv0 = this.gitInv0 || A(this.git0), this.gitInv1 = this.gitInv1 || A(this.git1), this.gitInv2 = this.gitInv2 || A(this.git2), this.gitInv3 = this.gitInv3 || A(this.git3), this.gitInv4 = this.gitInv4 || A(this.git4), this.gitInv5 = this.gitInv5 || A(this.git5), this.gitInv6 = this.gitInv6 || A(this.git6), this.gitInv7 = this.gitInv7 || A(this.git7), this.branchLabelColor = this.branchLabelColor || (this.darkMode ? "black" : this.labelTextColor), this.gitBranchLabel0 = this.gitBranchLabel0 || this.branchLabelColor, this.gitBranchLabel1 = this.gitBranchLabel1 || this.branchLabelColor, this.gitBranchLabel2 = this.gitBranchLabel2 || this.branchLabelColor, this.gitBranchLabel3 = this.gitBranchLabel3 || this.branchLabelColor, this.gitBranchLabel4 = this.gitBranchLabel4 || this.branchLabelColor, this.gitBranchLabel5 = this.gitBranchLabel5 || this.branchLabelColor, this.gitBranchLabel6 = this.gitBranchLabel6 || this.branchLabelColor, this.gitBranchLabel7 = this.gitBranchLabel7 || this.branchLabelColor, this.tagLabelColor = this.tagLabelColor || this.primaryTextColor, this.tagLabelBackground = this.tagLabelBackground || this.primaryColor, this.tagLabelBorder = this.tagBorder || this.primaryBorderColor, this.tagLabelFontSize = this.tagLabelFontSize || "10px", this.commitLabelColor = this.commitLabelColor || this.secondaryTextColor, this.commitLabelBackground = this.commitLabelBackground || this.secondaryColor, this.commitLabelFontSize = this.commitLabelFontSize || "10px", this.attributeBackgroundColorOdd = this.attributeBackgroundColorOdd || De, this.attributeBackgroundColorEven = this.attributeBackgroundColorEven || Re;
  }
  calculate(t) {
    if (typeof t != "object") {
      this.updateColors();
      return;
    }
    const r = Object.keys(t);
    r.forEach((i) => {
      this[i] = t[i];
    }), this.updateColors(), r.forEach((i) => {
      this[i] = t[i];
    });
  }
}, f(Jr, "Theme"), Jr), Px = /* @__PURE__ */ f((e) => {
  const t = new Rx();
  return t.calculate(e), t;
}, "getThemeVariables"), ti, Nx = (ti = class {
  constructor() {
    this.background = "#ffffff", this.primaryColor = "#cccccc", this.mainBkg = "#ffffff", this.noteBkgColor = "#fff5ad", this.noteTextColor = "#28253D", this.THEME_COLOR_LIMIT = 12, this.radius = 12, this.strokeWidth = 2, this.primaryBorderColor = nt("#28253D", this.darkMode), this.fontFamily = '"Recursive Variable", arial, sans-serif', this.fontSize = "14px", this.nodeBorder = "#28253D", this.stateBorder = "#28253D", this.useGradient = !1, this.gradientStart = "#0042eb", this.gradientStop = "#eb0042", this.dropShadow = "url(#drop-shadow)", this.nodeShadow = !0, this.tertiaryColor = "#ffffff", this.clusterBkg = "#F9F9FB", this.clusterBorder = "#BDBCCC", this.noteBorderColor = "#FACC15", this.archEdgeColor = "calculated", this.archEdgeArrowColor = "calculated", this.archEdgeWidth = "3", this.archGroupBorderColor = this.primaryBorderColor, this.archGroupBorderWidth = "2px", this.actorBorder = "#28253D", this.filterColor = "#000000";
  }
  updateColors() {
    var o, a, n, l, h, c, u, p, d, g, m;
    this.primaryTextColor = this.primaryTextColor || (this.darkMode ? "#eee" : "#28253D"), this.secondaryColor = this.secondaryColor || C(this.primaryColor, { h: -120 }), this.tertiaryColor = this.tertiaryColor || C(this.primaryColor, { h: 180, l: 5 }), this.primaryBorderColor = this.primaryBorderColor || nt(this.primaryColor, this.darkMode), this.secondaryBorderColor = this.secondaryBorderColor || nt(this.secondaryColor, this.darkMode), this.tertiaryBorderColor = this.tertiaryBorderColor || nt(this.tertiaryColor, this.darkMode), this.noteBorderColor = this.noteBorderColor || nt(this.noteBkgColor, this.darkMode), this.noteBkgColor = this.noteBkgColor || "#FEF9C3", this.noteTextColor = this.noteTextColor || "#28253D", this.secondaryTextColor = this.secondaryTextColor || A(this.secondaryColor), this.tertiaryTextColor = this.tertiaryTextColor || A(this.tertiaryColor), this.lineColor = this.lineColor || A(this.background), this.arrowheadColor = this.arrowheadColor || A(this.background), this.textColor = this.textColor || this.primaryTextColor, this.border2 = this.border2 || this.tertiaryBorderColor, this.nodeBkg = this.nodeBkg || this.primaryColor, this.mainBkg = this.mainBkg || this.primaryColor, this.nodeBorder = this.nodeBorder || this.primaryBorderColor, this.clusterBkg = this.clusterBkg || this.tertiaryColor, this.clusterBorder = this.clusterBorder || this.tertiaryBorderColor, this.defaultLinkColor = this.defaultLinkColor || this.lineColor, this.titleColor = this.titleColor || this.tertiaryTextColor, this.edgeLabelBackground = this.edgeLabelBackground || (this.darkMode ? I(this.secondaryColor, 30) : this.secondaryColor), this.nodeTextColor = this.nodeTextColor || this.primaryTextColor, this.noteFontWeight = 600, this.actorBorder = this.actorBorder || this.primaryBorderColor, this.actorBkg = this.actorBkg || this.mainBkg, this.actorTextColor = this.actorTextColor || this.primaryTextColor, this.actorLineColor = this.actorLineColor || this.actorBorder, this.labelBoxBkgColor = this.labelBoxBkgColor || this.actorBkg, this.signalColor = this.signalColor || this.textColor, this.signalTextColor = this.signalTextColor || this.textColor, this.labelBoxBorderColor = this.labelBoxBorderColor || this.actorBorder, this.labelTextColor = this.labelTextColor || this.actorTextColor, this.loopTextColor = this.loopTextColor || this.actorTextColor, this.activationBorderColor = this.activationBorderColor || I(this.secondaryColor, 10), this.activationBkgColor = this.activationBkgColor || this.secondaryColor, this.sequenceNumberColor = this.sequenceNumberColor || A(this.lineColor);
    const t = "#ECECFE", r = "#E9E9F1", i = C(t, { h: 180, l: 5 });
    this.sectionBkgColor = this.sectionBkgColor || i, this.altSectionBkgColor = this.altSectionBkgColor || "white", this.sectionBkgColor = this.sectionBkgColor || r, this.sectionBkgColor2 = this.sectionBkgColor2 || t, this.excludeBkgColor = this.excludeBkgColor || "#eeeeee", this.taskBorderColor = this.taskBorderColor || this.primaryBorderColor, this.taskBkgColor = this.taskBkgColor || t, this.activeTaskBorderColor = this.activeTaskBorderColor || t, this.activeTaskBkgColor = this.activeTaskBkgColor || $(t, 23), this.gridColor = this.gridColor || "lightgrey", this.doneTaskBkgColor = this.doneTaskBkgColor || "lightgrey", this.doneTaskBorderColor = this.doneTaskBorderColor || "grey", this.critBorderColor = this.critBorderColor || "#ff8888", this.critBkgColor = this.critBkgColor || "red", this.todayLineColor = this.todayLineColor || "red", this.taskTextColor = this.taskTextColor || this.textColor, this.vertLineColor = this.vertLineColor || this.primaryBorderColor, this.taskTextOutsideColor = this.taskTextOutsideColor || this.textColor, this.taskTextLightColor = this.taskTextLightColor || this.textColor, this.taskTextColor = this.taskTextColor || this.primaryTextColor, this.taskTextDarkColor = this.taskTextDarkColor || this.textColor, this.taskTextClickableColor = this.taskTextClickableColor || "#003163", this.archEdgeColor = this.lineColor, this.archEdgeArrowColor = this.lineColor, this.personBorder = this.personBorder || this.primaryBorderColor, this.personBkg = this.personBkg || this.mainBkg, this.transitionColor = this.transitionColor || this.lineColor, this.transitionLabelColor = this.transitionLabelColor || this.textColor, this.stateLabelColor = this.stateLabelColor || this.stateBkg || this.primaryTextColor, this.compositeTitleBackground = "#F9F9FB", this.altBackground = "#F9F9FB", this.stateEdgeLabelBackground = "#FFFFFF", this.fontWeight = 600, this.stateBkg = this.stateBkg || this.mainBkg, this.labelBackgroundColor = this.labelBackgroundColor || this.stateBkg, this.compositeBackground = this.compositeBackground || this.background || this.tertiaryColor, this.altBackground = this.altBackground || "#f0f0f0", this.compositeTitleBackground = this.compositeTitleBackground || this.mainBkg, this.compositeBorder = this.compositeBorder || this.nodeBorder, this.innerEndBackground = this.nodeBorder, this.errorBkgColor = this.errorBkgColor || this.tertiaryColor, this.errorTextColor = this.errorTextColor || this.tertiaryTextColor, this.transitionColor = this.transitionColor || this.lineColor, this.specialStateColor = this.lineColor;
    for (let y = 0; y < this.THEME_COLOR_LIMIT; y++)
      this["cScale" + y] = this.mainBkg;
    if (this.darkMode)
      for (let y = 0; y < this.THEME_COLOR_LIMIT; y++)
        this["cScale" + y] = I(this["cScale" + y], 75);
    else
      for (let y = 0; y < this.THEME_COLOR_LIMIT; y++)
        this["cScale" + y] = I(this["cScale" + y], 25);
    for (let y = 0; y < this.THEME_COLOR_LIMIT; y++)
      this["cScaleInv" + y] = this["cScaleInv" + y] || A(this["cScale" + y]);
    for (let y = 0; y < this.THEME_COLOR_LIMIT; y++)
      this.darkMode ? this["cScalePeer" + y] = this["cScalePeer" + y] || $(this["cScale" + y], 10) : this["cScalePeer" + y] = this["cScalePeer" + y] || I(this["cScale" + y], 10);
    this.scaleLabelColor = this.scaleLabelColor || this.labelTextColor;
    for (let y = 0; y < this.THEME_COLOR_LIMIT; y++)
      this["cScaleLabel" + y] = this["cScaleLabel" + y] || this.scaleLabelColor;
    const s = this.darkMode ? -4 : -1;
    for (let y = 0; y < 5; y++)
      this["surface" + y] = this["surface" + y] || C(this.mainBkg, { h: 180, s: -15, l: s * (5 + y * 3) }), this["surfacePeer" + y] = this["surfacePeer" + y] || C(this.mainBkg, { h: 180, s: -15, l: s * (8 + y * 3) });
    this.classText = this.classText || this.textColor, this.fillType0 = this.fillType0 || t, this.fillType1 = this.fillType1 || r, this.fillType2 = this.fillType2 || C(t, { h: 64 }), this.fillType3 = this.fillType3 || C(r, { h: 64 }), this.fillType4 = this.fillType4 || C(t, { h: -64 }), this.fillType5 = this.fillType5 || C(r, { h: -64 }), this.fillType6 = this.fillType6 || C(t, { h: 128 }), this.fillType7 = this.fillType7 || C(r, { h: 128 }), this.pie1 = this.pie1 || t, this.pie2 = this.pie2 || r, this.pie3 = this.pie3 || i, this.pie4 = this.pie4 || C(t, { l: -10 }), this.pie5 = this.pie5 || C(r, { l: -10 }), this.pie6 = this.pie6 || C(i, { l: -10 }), this.pie7 = this.pie7 || C(t, { h: 60, l: -10 }), this.pie8 = this.pie8 || C(t, { h: -60, l: -10 }), this.pie9 = this.pie9 || C(t, { h: 120, l: 0 }), this.pie10 = this.pie10 || C(t, { h: 60, l: -20 }), this.pie11 = this.pie11 || C(t, { h: -60, l: -20 }), this.pie12 = this.pie12 || C(t, { h: 120, l: -10 }), this.pieTitleTextSize = this.pieTitleTextSize || "25px", this.pieTitleTextColor = this.pieTitleTextColor || this.taskTextDarkColor, this.pieSectionTextSize = this.pieSectionTextSize || "17px", this.pieSectionTextColor = this.pieSectionTextColor || this.textColor, this.pieLegendTextSize = this.pieLegendTextSize || "17px", this.pieLegendTextColor = this.pieLegendTextColor || this.taskTextDarkColor, this.pieStrokeColor = this.pieStrokeColor || "black", this.pieStrokeWidth = this.pieStrokeWidth || "2px", this.pieOuterStrokeWidth = this.pieOuterStrokeWidth || "2px", this.pieOuterStrokeColor = this.pieOuterStrokeColor || "black", this.pieOpacity = this.pieOpacity || "0.7", this.vennTitleTextColor = this.vennTitleTextColor ?? this.titleColor, this.vennSetTextColor = this.vennSetTextColor ?? this.textColor, this.quadrant1Fill = this.quadrant1Fill || t, this.quadrant2Fill = this.quadrant2Fill || C(t, { r: 5, g: 5, b: 5 }), this.quadrant3Fill = this.quadrant3Fill || C(t, { r: 10, g: 10, b: 10 }), this.quadrant4Fill = this.quadrant4Fill || C(t, { r: 15, g: 15, b: 15 }), this.quadrant1TextFill = this.quadrant1TextFill || this.primaryTextColor, this.quadrant2TextFill = this.quadrant2TextFill || C(this.primaryTextColor, { r: -5, g: -5, b: -5 }), this.quadrant3TextFill = this.quadrant3TextFill || C(this.primaryTextColor, { r: -10, g: -10, b: -10 }), this.quadrant4TextFill = this.quadrant4TextFill || C(this.primaryTextColor, { r: -15, g: -15, b: -15 }), this.quadrantPointFill = this.quadrantPointFill || _e(this.quadrant1Fill) ? $(this.quadrant1Fill) : I(this.quadrant1Fill), this.quadrantPointTextFill = this.quadrantPointTextFill || this.primaryTextColor, this.quadrantXAxisTextFill = this.quadrantXAxisTextFill || this.primaryTextColor, this.quadrantYAxisTextFill = this.quadrantYAxisTextFill || this.primaryTextColor, this.quadrantInternalBorderStrokeFill = this.quadrantInternalBorderStrokeFill || this.primaryBorderColor, this.quadrantExternalBorderStrokeFill = this.quadrantExternalBorderStrokeFill || this.primaryBorderColor, this.quadrantTitleFill = this.quadrantTitleFill || this.primaryTextColor, this.xyChart = {
      backgroundColor: ((o = this.xyChart) == null ? void 0 : o.backgroundColor) || this.background,
      titleColor: ((a = this.xyChart) == null ? void 0 : a.titleColor) || this.primaryTextColor,
      xAxisTitleColor: ((n = this.xyChart) == null ? void 0 : n.xAxisTitleColor) || this.primaryTextColor,
      xAxisLabelColor: ((l = this.xyChart) == null ? void 0 : l.xAxisLabelColor) || this.primaryTextColor,
      xAxisTickColor: ((h = this.xyChart) == null ? void 0 : h.xAxisTickColor) || this.primaryTextColor,
      xAxisLineColor: ((c = this.xyChart) == null ? void 0 : c.xAxisLineColor) || this.primaryTextColor,
      yAxisTitleColor: ((u = this.xyChart) == null ? void 0 : u.yAxisTitleColor) || this.primaryTextColor,
      yAxisLabelColor: ((p = this.xyChart) == null ? void 0 : p.yAxisLabelColor) || this.primaryTextColor,
      yAxisTickColor: ((d = this.xyChart) == null ? void 0 : d.yAxisTickColor) || this.primaryTextColor,
      yAxisLineColor: ((g = this.xyChart) == null ? void 0 : g.yAxisLineColor) || this.primaryTextColor,
      plotColorPalette: ((m = this.xyChart) == null ? void 0 : m.plotColorPalette) || "#FFF4DD,#FFD8B1,#FFA07A,#ECEFF1,#D6DBDF,#C3E0A8,#FFB6A4,#FFD74D,#738FA7,#FFFFF0"
    }, this.requirementBackground = this.requirementBackground || t, this.requirementBorderColor = this.requirementBorderColor || this.primaryBorderColor, this.requirementBorderSize = this.requirementBorderSize || "1", this.requirementTextColor = this.requirementTextColor || this.primaryTextColor, this.relationColor = this.relationColor || this.lineColor, this.relationLabelBackground = this.relationLabelBackground || (this.darkMode ? I(this.secondaryColor, 30) : this.secondaryColor), this.relationLabelColor = this.relationLabelColor || this.actorTextColor, this.requirementEdgeLabelBackground = "#FFFFFF", this.git0 = this.git0 || t, this.git1 = this.git1 || r, this.git2 = this.git2 || i, this.git3 = this.git3 || C(t, { h: -30 }), this.git4 = this.git4 || C(t, { h: -60 }), this.git5 = this.git5 || C(t, { h: -90 }), this.git6 = this.git6 || C(t, { h: 60 }), this.git7 = this.git7 || C(t, { h: 120 }), this.darkMode ? (this.git0 = $(this.git0, 25), this.git1 = $(this.git1, 25), this.git2 = $(this.git2, 25), this.git3 = $(this.git3, 25), this.git4 = $(this.git4, 25), this.git5 = $(this.git5, 25), this.git6 = $(this.git6, 25), this.git7 = $(this.git7, 25)) : (this.git0 = I(this.git0, 25), this.git1 = I(this.git1, 25), this.git2 = I(this.git2, 25), this.git3 = I(this.git3, 25), this.git4 = I(this.git4, 25), this.git5 = I(this.git5, 25), this.git6 = I(this.git6, 25), this.git7 = I(this.git7, 25)), this.gitInv0 = this.gitInv0 || A(this.git0), this.gitInv1 = this.gitInv1 || A(this.git1), this.gitInv2 = this.gitInv2 || A(this.git2), this.gitInv3 = this.gitInv3 || A(this.git3), this.gitInv4 = this.gitInv4 || A(this.git4), this.gitInv5 = this.gitInv5 || A(this.git5), this.gitInv6 = this.gitInv6 || A(this.git6), this.gitInv7 = this.gitInv7 || A(this.git7), this.branchLabelColor = this.branchLabelColor || (this.darkMode ? "black" : this.labelTextColor), this.gitBranchLabel0 = this.gitBranchLabel0 || this.branchLabelColor, this.gitBranchLabel1 = this.gitBranchLabel1 || this.branchLabelColor, this.gitBranchLabel2 = this.gitBranchLabel2 || this.branchLabelColor, this.gitBranchLabel3 = this.gitBranchLabel3 || this.branchLabelColor, this.gitBranchLabel4 = this.gitBranchLabel4 || this.branchLabelColor, this.gitBranchLabel5 = this.gitBranchLabel5 || this.branchLabelColor, this.gitBranchLabel6 = this.gitBranchLabel6 || this.branchLabelColor, this.gitBranchLabel7 = this.gitBranchLabel7 || this.branchLabelColor, this.tagLabelColor = this.tagLabelColor || this.primaryTextColor, this.tagLabelBackground = this.tagLabelBackground || this.primaryColor, this.tagLabelBorder = this.tagBorder || this.primaryBorderColor, this.tagLabelFontSize = this.tagLabelFontSize || "10px", this.commitLabelColor = this.commitLabelColor || this.secondaryTextColor, this.commitLabelBackground = this.commitLabelBackground || this.secondaryColor, this.commitLabelFontSize = this.commitLabelFontSize || "10px", this.commitLineColor = this.commitLineColor ?? "#BDBCCC", this.erEdgeLabelBackground = "#FFFFFF", this.attributeBackgroundColorOdd = this.attributeBackgroundColorOdd || De, this.attributeBackgroundColorEven = this.attributeBackgroundColorEven || Re;
  }
  calculate(t) {
    if (typeof t != "object") {
      this.updateColors();
      return;
    }
    const r = Object.keys(t);
    r.forEach((i) => {
      this[i] = t[i];
    }), this.updateColors(), r.forEach((i) => {
      this[i] = t[i];
    });
  }
}, f(ti, "Theme"), ti), qx = /* @__PURE__ */ f((e) => {
  const t = new Nx();
  return t.calculate(e), t;
}, "getThemeVariables"), ei, Wx = (ei = class {
  constructor() {
    this.background = "#333", this.primaryColor = "#1f2020", this.secondaryColor = $(this.primaryColor, 16), this.tertiaryColor = C(this.primaryColor, { h: -160 }), this.primaryBorderColor = A(this.background), this.secondaryBorderColor = nt(this.secondaryColor, this.darkMode), this.tertiaryBorderColor = nt(this.tertiaryColor, this.darkMode), this.primaryTextColor = A(this.primaryColor), this.secondaryTextColor = A(this.secondaryColor), this.tertiaryTextColor = A(this.tertiaryColor), this.mainBkg = "#111113", this.secondBkg = "calculated", this.mainContrastColor = "lightgrey", this.darkTextColor = $(A("#323D47"), 10), this.border1 = "#ccc", this.border2 = gr(255, 255, 255, 0.25), this.arrowheadColor = A(this.background), this.fontFamily = '"Recursive Variable", arial, sans-serif', this.fontSize = "14px", this.labelBackground = "#111113", this.textColor = "#ccc", this.THEME_COLOR_LIMIT = 12, this.radius = 12, this.strokeWidth = 2, this.noteBkgColor = this.noteBkgColor ?? "#FEF9C3", this.noteTextColor = this.noteTextColor ?? "#28253D", this.THEME_COLOR_LIMIT = 12, this.fontFamily = '"Recursive Variable", arial, sans-serif', this.fontSize = "14px", this.nodeBorder = "#FFFFFF", this.stateBorder = "#FFFFFF", this.useGradient = !1, this.gradientStart = "#0042eb", this.gradientStop = "#eb0042", this.dropShadow = "url(#drop-shadow)", this.nodeShadow = !0, this.archEdgeColor = "calculated", this.archEdgeArrowColor = "calculated", this.archEdgeWidth = "3", this.archGroupBorderColor = this.primaryBorderColor, this.archGroupBorderWidth = "2px", this.clusterBkg = "#1E1A2E", this.clusterBorder = "#BDBCCC", this.noteBorderColor = "#FACC15", this.noteFontWeight = 600, this.filterColor = "#FFFFFF";
  }
  updateColors() {
    var r, i, s, o, a, n, l, h, c, u, p;
    if (this.primaryTextColor = this.primaryTextColor || (this.darkMode ? "#eee" : "#FFFFFF"), this.secondaryColor = this.secondaryColor || C(this.primaryColor, { h: -120 }), this.tertiaryColor = this.tertiaryColor || C(this.primaryColor, { h: 180, l: 5 }), this.primaryBorderColor = this.primaryBorderColor || nt(this.primaryColor, this.darkMode), this.secondaryBorderColor = this.secondaryBorderColor || nt(this.secondaryColor, this.darkMode), this.tertiaryBorderColor = this.tertiaryBorderColor || nt(this.tertiaryColor, this.darkMode), this.noteBorderColor = this.noteBorderColor || nt(this.noteBkgColor, this.darkMode), this.noteBkgColor = this.noteBkgColor || "#fff5ad", this.noteTextColor = this.noteTextColor || "#FFFFFF", this.secondaryTextColor = this.secondaryTextColor || A(this.secondaryColor), this.tertiaryTextColor = this.tertiaryTextColor || A(this.tertiaryColor), this.lineColor = this.lineColor || A(this.background), this.arrowheadColor = this.arrowheadColor || A(this.background), this.textColor = this.textColor || this.primaryTextColor, this.border2 = this.border2 || this.tertiaryBorderColor, this.nodeBkg = this.nodeBkg || this.primaryColor, this.mainBkg = this.mainBkg || this.primaryColor, this.nodeBorder = this.nodeBorder || this.border1, this.clusterBkg = this.clusterBkg || this.tertiaryColor, this.clusterBorder = this.clusterBorder || this.tertiaryBorderColor, this.defaultLinkColor = this.defaultLinkColor || this.lineColor, this.titleColor = this.titleColor || this.tertiaryTextColor, this.edgeLabelBackground = this.edgeLabelBackground || (this.darkMode ? I(this.secondaryColor, 30) : this.secondaryColor), this.nodeTextColor = this.nodeTextColor || this.primaryTextColor, this.actorBorder = "#FFFFFF", this.signalColor = "#FFFFFF", this.labelBoxBorderColor = "#BDBCCC", this.actorBorder = this.actorBorder || this.primaryBorderColor, this.actorBkg = this.actorBkg || this.mainBkg, this.actorTextColor = this.actorTextColor || this.primaryTextColor, this.actorLineColor = this.actorLineColor || this.actorBorder, this.labelBoxBkgColor = this.labelBoxBkgColor || this.actorBkg, this.signalColor = this.signalColor || this.textColor, this.signalTextColor = this.signalTextColor || this.textColor, this.labelBoxBorderColor = this.labelBoxBorderColor || this.actorBorder, this.labelTextColor = this.labelTextColor || this.actorTextColor, this.loopTextColor = this.loopTextColor || this.actorTextColor, this.activationBorderColor = this.activationBorderColor || I(this.secondaryColor, 10), this.activationBkgColor = this.activationBkgColor || this.secondaryColor, this.sequenceNumberColor = this.sequenceNumberColor || A(this.lineColor), this.sectionBkgColor = this.sectionBkgColor || this.tertiaryColor, this.altSectionBkgColor = this.altSectionBkgColor || "white", this.sectionBkgColor = this.sectionBkgColor || this.secondaryColor, this.sectionBkgColor2 = this.sectionBkgColor2 || this.primaryColor, this.excludeBkgColor = this.excludeBkgColor || "#eeeeee", this.taskBorderColor = this.taskBorderColor || this.primaryBorderColor, this.taskBkgColor = this.taskBkgColor || this.primaryColor, this.activeTaskBorderColor = this.activeTaskBorderColor || this.primaryColor, this.activeTaskBkgColor = this.activeTaskBkgColor || $(this.primaryColor, 23), this.gridColor = this.gridColor || "lightgrey", this.doneTaskBkgColor = this.doneTaskBkgColor || "lightgrey", this.doneTaskBorderColor = this.doneTaskBorderColor || "grey", this.critBorderColor = this.critBorderColor || "#ff8888", this.critBkgColor = this.critBkgColor || "red", this.todayLineColor = this.todayLineColor || "red", this.taskTextColor = this.taskTextColor || this.textColor, this.taskTextOutsideColor = this.taskTextOutsideColor || this.textColor, this.taskTextLightColor = this.taskTextLightColor || this.textColor, this.taskTextColor = this.taskTextColor || this.primaryTextColor, this.taskTextDarkColor = this.taskTextDarkColor || this.textColor, this.taskTextClickableColor = this.taskTextClickableColor || "#003163", this.archEdgeColor = this.lineColor, this.archEdgeArrowColor = this.lineColor, this.personBorder = this.personBorder || this.primaryBorderColor, this.personBkg = this.personBkg || this.mainBkg, this.transitionColor = this.transitionColor || this.lineColor, this.transitionLabelColor = this.transitionLabelColor || this.textColor, this.stateLabelColor = this.stateLabelColor || this.stateBkg || this.primaryTextColor, this.vertLineColor = this.vertLineColor || this.primaryBorderColor, this.compositeBackground = "#16141F", this.altBackground = "#16141F", this.compositeTitleBackground = "#16141F", this.stateEdgeLabelBackground = "#16141F", this.fontWeight = 600, this.stateBkg = this.stateBkg || this.mainBkg, this.labelBackgroundColor = this.labelBackgroundColor || this.stateBkg, this.compositeBackground = this.compositeBackground || this.background || this.tertiaryColor, this.altBackground = this.altBackground || "#f0f0f0", this.compositeTitleBackground = this.compositeTitleBackground || this.mainBkg, this.compositeBorder = this.compositeBorder || this.nodeBorder, this.innerEndBackground = this.nodeBorder, this.errorBkgColor = this.errorBkgColor || this.tertiaryColor, this.errorTextColor = this.errorTextColor || this.tertiaryTextColor, this.transitionColor = this.transitionColor || this.lineColor, this.specialStateColor = this.lineColor, this.cScale0 = this.cScale0 || this.primaryColor, this.cScale1 = this.cScale1 || this.secondaryColor, this.cScale2 = this.cScale2 || this.tertiaryColor, this.cScale3 = this.cScale3 || C(this.primaryColor, { h: 30 }), this.cScale4 = this.cScale4 || C(this.primaryColor, { h: 60 }), this.cScale5 = this.cScale5 || C(this.primaryColor, { h: 90 }), this.cScale6 = this.cScale6 || C(this.primaryColor, { h: 120 }), this.cScale7 = this.cScale7 || C(this.primaryColor, { h: 150 }), this.cScale8 = this.cScale8 || C(this.primaryColor, { h: 210, l: 150 }), this.cScale9 = this.cScale9 || C(this.primaryColor, { h: 270 }), this.cScale10 = this.cScale10 || C(this.primaryColor, { h: 300 }), this.cScale11 = this.cScale11 || C(this.primaryColor, { h: 330 }), this.darkMode)
      for (let d = 0; d < this.THEME_COLOR_LIMIT; d++)
        this["cScale" + d] = I(this["cScale" + d], 75);
    else
      for (let d = 0; d < this.THEME_COLOR_LIMIT; d++)
        this["cScale" + d] = I(this["cScale" + d], 25);
    for (let d = 0; d < this.THEME_COLOR_LIMIT; d++)
      this["cScaleInv" + d] = this["cScaleInv" + d] || A(this["cScale" + d]);
    for (let d = 0; d < this.THEME_COLOR_LIMIT; d++)
      this.darkMode ? this["cScalePeer" + d] = this["cScalePeer" + d] || $(this["cScale" + d], 10) : this["cScalePeer" + d] = this["cScalePeer" + d] || I(this["cScale" + d], 10);
    this.scaleLabelColor = this.scaleLabelColor || this.labelTextColor;
    for (let d = 0; d < this.THEME_COLOR_LIMIT; d++)
      this["cScaleLabel" + d] = this["cScaleLabel" + d] || this.scaleLabelColor;
    const t = this.darkMode ? -4 : -1;
    for (let d = 0; d < 5; d++)
      this["surface" + d] = this["surface" + d] || C(this.mainBkg, { h: 180, s: -15, l: t * (5 + d * 3) }), this["surfacePeer" + d] = this["surfacePeer" + d] || C(this.mainBkg, { h: 180, s: -15, l: t * (8 + d * 3) });
    this.classText = this.classText || this.textColor, this.fillType0 = this.fillType0 || this.primaryColor, this.fillType1 = this.fillType1 || this.secondaryColor, this.fillType2 = this.fillType2 || C(this.primaryColor, { h: 64 }), this.fillType3 = this.fillType3 || C(this.secondaryColor, { h: 64 }), this.fillType4 = this.fillType4 || C(this.primaryColor, { h: -64 }), this.fillType5 = this.fillType5 || C(this.secondaryColor, { h: -64 }), this.fillType6 = this.fillType6 || C(this.primaryColor, { h: 128 }), this.fillType7 = this.fillType7 || C(this.secondaryColor, { h: 128 }), this.pie1 = this.pie1 || this.primaryColor, this.pie2 = this.pie2 || this.secondaryColor, this.pie3 = this.pie3 || this.tertiaryColor, this.pie4 = this.pie4 || C(this.primaryColor, { l: -10 }), this.pie5 = this.pie5 || C(this.secondaryColor, { l: -10 }), this.pie6 = this.pie6 || C(this.tertiaryColor, { l: -10 }), this.pie7 = this.pie7 || C(this.primaryColor, { h: 60, l: -10 }), this.pie8 = this.pie8 || C(this.primaryColor, { h: -60, l: -10 }), this.pie9 = this.pie9 || C(this.primaryColor, { h: 120, l: 0 }), this.pie10 = this.pie10 || C(this.primaryColor, { h: 60, l: -20 }), this.pie11 = this.pie11 || C(this.primaryColor, { h: -60, l: -20 }), this.pie12 = this.pie12 || C(this.primaryColor, { h: 120, l: -10 }), this.pieTitleTextSize = this.pieTitleTextSize || "25px", this.pieTitleTextColor = this.pieTitleTextColor || this.taskTextDarkColor, this.pieSectionTextSize = this.pieSectionTextSize || "17px", this.pieSectionTextColor = this.pieSectionTextColor || this.textColor, this.pieLegendTextSize = this.pieLegendTextSize || "17px", this.pieLegendTextColor = this.pieLegendTextColor || this.taskTextDarkColor, this.pieStrokeColor = this.pieStrokeColor || "black", this.pieStrokeWidth = this.pieStrokeWidth || "2px", this.pieOuterStrokeWidth = this.pieOuterStrokeWidth || "2px", this.pieOuterStrokeColor = this.pieOuterStrokeColor || "black", this.pieOpacity = this.pieOpacity || "0.7", this.vennTitleTextColor = this.vennTitleTextColor ?? this.titleColor, this.vennSetTextColor = this.vennSetTextColor ?? this.textColor, this.quadrant1Fill = this.quadrant1Fill || this.primaryColor, this.quadrant2Fill = this.quadrant2Fill || C(this.primaryColor, { r: 5, g: 5, b: 5 }), this.quadrant3Fill = this.quadrant3Fill || C(this.primaryColor, { r: 10, g: 10, b: 10 }), this.quadrant4Fill = this.quadrant4Fill || C(this.primaryColor, { r: 15, g: 15, b: 15 }), this.quadrant1TextFill = this.quadrant1TextFill || this.primaryTextColor, this.quadrant2TextFill = this.quadrant2TextFill || C(this.primaryTextColor, { r: -5, g: -5, b: -5 }), this.quadrant3TextFill = this.quadrant3TextFill || C(this.primaryTextColor, { r: -10, g: -10, b: -10 }), this.quadrant4TextFill = this.quadrant4TextFill || C(this.primaryTextColor, { r: -15, g: -15, b: -15 }), this.quadrantPointFill = this.quadrantPointFill || _e(this.quadrant1Fill) ? $(this.quadrant1Fill) : I(this.quadrant1Fill), this.quadrantPointTextFill = this.quadrantPointTextFill || this.primaryTextColor, this.quadrantXAxisTextFill = this.quadrantXAxisTextFill || this.primaryTextColor, this.quadrantYAxisTextFill = this.quadrantYAxisTextFill || this.primaryTextColor, this.quadrantInternalBorderStrokeFill = this.quadrantInternalBorderStrokeFill || this.primaryBorderColor, this.quadrantExternalBorderStrokeFill = this.quadrantExternalBorderStrokeFill || this.primaryBorderColor, this.quadrantTitleFill = this.quadrantTitleFill || this.primaryTextColor, this.xyChart = {
      backgroundColor: ((r = this.xyChart) == null ? void 0 : r.backgroundColor) || this.background,
      titleColor: ((i = this.xyChart) == null ? void 0 : i.titleColor) || this.primaryTextColor,
      xAxisTitleColor: ((s = this.xyChart) == null ? void 0 : s.xAxisTitleColor) || this.primaryTextColor,
      xAxisLabelColor: ((o = this.xyChart) == null ? void 0 : o.xAxisLabelColor) || this.primaryTextColor,
      xAxisTickColor: ((a = this.xyChart) == null ? void 0 : a.xAxisTickColor) || this.primaryTextColor,
      xAxisLineColor: ((n = this.xyChart) == null ? void 0 : n.xAxisLineColor) || this.primaryTextColor,
      yAxisTitleColor: ((l = this.xyChart) == null ? void 0 : l.yAxisTitleColor) || this.primaryTextColor,
      yAxisLabelColor: ((h = this.xyChart) == null ? void 0 : h.yAxisLabelColor) || this.primaryTextColor,
      yAxisTickColor: ((c = this.xyChart) == null ? void 0 : c.yAxisTickColor) || this.primaryTextColor,
      yAxisLineColor: ((u = this.xyChart) == null ? void 0 : u.yAxisLineColor) || this.primaryTextColor,
      plotColorPalette: ((p = this.xyChart) == null ? void 0 : p.plotColorPalette) || "#FFF4DD,#FFD8B1,#FFA07A,#ECEFF1,#D6DBDF,#C3E0A8,#FFB6A4,#FFD74D,#738FA7,#FFFFF0"
    }, this.requirementBackground = this.requirementBackground || this.primaryColor, this.requirementBorderColor = this.requirementBorderColor || this.primaryBorderColor, this.requirementBorderSize = this.requirementBorderSize || "1", this.requirementTextColor = this.requirementTextColor || this.primaryTextColor, this.relationColor = this.relationColor || this.lineColor, this.relationLabelBackground = this.relationLabelBackground || (this.darkMode ? I(this.secondaryColor, 30) : this.secondaryColor), this.relationLabelColor = this.relationLabelColor || this.actorTextColor, this.requirementEdgeLabelBackground = "#16141F", this.git0 = this.git0 || this.primaryColor, this.git1 = this.git1 || this.secondaryColor, this.git2 = this.git2 || this.tertiaryColor, this.git3 = this.git3 || C(this.primaryColor, { h: -30 }), this.git4 = this.git4 || C(this.primaryColor, { h: -60 }), this.git5 = this.git5 || C(this.primaryColor, { h: -90 }), this.git6 = this.git6 || C(this.primaryColor, { h: 60 }), this.git7 = this.git7 || C(this.primaryColor, { h: 120 }), this.darkMode ? (this.git0 = $(this.git0, 25), this.git1 = $(this.git1, 25), this.git2 = $(this.git2, 25), this.git3 = $(this.git3, 25), this.git4 = $(this.git4, 25), this.git5 = $(this.git5, 25), this.git6 = $(this.git6, 25), this.git7 = $(this.git7, 25)) : (this.git0 = I(this.git0, 25), this.git1 = I(this.git1, 25), this.git2 = I(this.git2, 25), this.git3 = I(this.git3, 25), this.git4 = I(this.git4, 25), this.git5 = I(this.git5, 25), this.git6 = I(this.git6, 25), this.git7 = I(this.git7, 25)), this.gitInv0 = this.gitInv0 || A(this.git0), this.gitInv1 = this.gitInv1 || A(this.git1), this.gitInv2 = this.gitInv2 || A(this.git2), this.gitInv3 = this.gitInv3 || A(this.git3), this.gitInv4 = this.gitInv4 || A(this.git4), this.gitInv5 = this.gitInv5 || A(this.git5), this.gitInv6 = this.gitInv6 || A(this.git6), this.gitInv7 = this.gitInv7 || A(this.git7), this.branchLabelColor = this.branchLabelColor || (this.darkMode ? "black" : this.labelTextColor), this.gitBranchLabel0 = this.gitBranchLabel0 || this.branchLabelColor, this.gitBranchLabel1 = this.gitBranchLabel1 || this.branchLabelColor, this.gitBranchLabel2 = this.gitBranchLabel2 || this.branchLabelColor, this.gitBranchLabel3 = this.gitBranchLabel3 || this.branchLabelColor, this.gitBranchLabel4 = this.gitBranchLabel4 || this.branchLabelColor, this.gitBranchLabel5 = this.gitBranchLabel5 || this.branchLabelColor, this.gitBranchLabel6 = this.gitBranchLabel6 || this.branchLabelColor, this.gitBranchLabel7 = this.gitBranchLabel7 || this.branchLabelColor, this.tagLabelColor = this.tagLabelColor || this.primaryTextColor, this.tagLabelBackground = this.tagLabelBackground || this.primaryColor, this.tagLabelBorder = this.tagBorder || this.primaryBorderColor, this.tagLabelFontSize = this.tagLabelFontSize || "10px", this.commitLabelColor = this.commitLabelColor || this.secondaryTextColor, this.commitLabelBackground = this.commitLabelBackground || this.secondaryColor, this.commitLabelFontSize = this.commitLabelFontSize || "10px", this.commitLineColor = this.commitLineColor ?? "#BDBCCC", this.erEdgeLabelBackground = "#16141F", this.attributeBackgroundColorOdd = this.attributeBackgroundColorOdd || De, this.attributeBackgroundColorEven = this.attributeBackgroundColorEven || Re;
  }
  calculate(t) {
    if (typeof t != "object") {
      this.updateColors();
      return;
    }
    const r = Object.keys(t);
    r.forEach((i) => {
      this[i] = t[i];
    }), this.updateColors(), r.forEach((i) => {
      this[i] = t[i];
    });
  }
}, f(ei, "Theme"), ei), zx = /* @__PURE__ */ f((e) => {
  const t = new Wx();
  return t.calculate(e), t;
}, "getThemeVariables"), ri, Hx = (ri = class {
  constructor() {
    this.background = "#ffffff", this.primaryColor = "#cccccc", this.mainBkg = "#ffffff", this.noteBkgColor = "#fff5ad", this.noteTextColor = "#28253D", this.THEME_COLOR_LIMIT = 12, this.radius = 12, this.strokeWidth = 2, this.primaryBorderColor = nt(this.primaryColor, this.darkMode), this.fontFamily = '"Recursive Variable", arial, sans-serif', this.fontSize = "14px", this.nodeBorder = "#28253D", this.stateBorder = "#28253D", this.useGradient = !1, this.gradientStart = "#0042eb", this.gradientStop = "#eb0042", this.dropShadow = "url(#drop-shadow)", this.nodeShadow = !0, this.tertiaryColor = "#ffffff", this.archEdgeColor = "calculated", this.archEdgeArrowColor = "calculated", this.archEdgeWidth = "3", this.archGroupBorderColor = this.primaryBorderColor, this.archGroupBorderWidth = "2px", this.actorBorder = "#28253D", this.noteBorderColor = "#FACC15", this.noteFontWeight = 600, this.borderColorArray = [
      "#E879F9",
      //Fuchsia-400
      "#2DD4BF",
      //Teal-400
      "#FB923C",
      //Orange-400
      "#22D3EE",
      // Cyan-400
      "#4ADE80",
      // Green-400
      "#A78BFA",
      //Violet-400
      "#F87171",
      //red-400
      "#FACC15",
      //yellow-400
      "#818CF8",
      //indigo-400
      "#A3E635 ",
      //Lime-400
      "#38BDF8",
      //Sky-400
      "#FB7185"
      //Rose-400
    ], this.bkgColorArray = [
      "#FDF4FF",
      //Fuchsia-50
      "#F0FDFA",
      //Teal-50
      "#FFF7ED",
      //Orange-50
      "#ECFEFF",
      // Cyan-50
      "#F0FDF4",
      // Green-50
      "#F5F3FF",
      //Violet-50
      "#FEF2F2",
      //red-50
      "#FEFCE8",
      //yellow-50
      "#EEF2FF",
      //indigo-50
      "#F7FEE7",
      //Lime-50
      "#F0F9FF",
      //Sky-50
      "#FFF1F2"
      //Rose-50
    ], this.filterColor = "#000000";
  }
  updateColors() {
    var o, a, n, l, h, c, u, p, d, g, m;
    this.primaryTextColor = this.primaryTextColor || (this.darkMode ? "#eee" : "#28253D"), this.secondaryColor = this.secondaryColor || C(this.primaryColor, { h: -120 }), this.tertiaryColor = this.tertiaryColor || C(this.primaryColor, { h: 180, l: 5 }), this.primaryBorderColor = this.primaryBorderColor || nt(this.primaryColor, this.darkMode), this.secondaryBorderColor = this.secondaryBorderColor || nt(this.secondaryColor, this.darkMode), this.tertiaryBorderColor = this.tertiaryBorderColor || nt(this.tertiaryColor, this.darkMode), this.noteBorderColor = this.noteBorderColor || nt(this.noteBkgColor, this.darkMode), this.noteBkgColor = this.noteBkgColor || "#fff5ad", this.noteTextColor = this.noteTextColor || "#28253D", this.secondaryTextColor = this.secondaryTextColor || A(this.secondaryColor), this.tertiaryTextColor = this.tertiaryTextColor || A(this.tertiaryColor), this.lineColor = this.lineColor || A(this.background), this.arrowheadColor = this.arrowheadColor || A(this.background), this.textColor = this.textColor || this.primaryTextColor, this.border2 = this.border2 || this.tertiaryBorderColor, this.nodeBkg = this.nodeBkg || this.primaryColor, this.mainBkg = this.mainBkg || this.primaryColor, this.nodeBorder = this.nodeBorder || this.primaryBorderColor, this.clusterBkg = this.clusterBkg || this.tertiaryColor, this.clusterBorder = this.clusterBorder || this.tertiaryBorderColor, this.defaultLinkColor = this.defaultLinkColor || this.lineColor, this.titleColor = this.titleColor || this.tertiaryTextColor, this.edgeLabelBackground = this.edgeLabelBackground || (this.darkMode ? I(this.secondaryColor, 30) : this.secondaryColor), this.nodeTextColor = this.nodeTextColor || this.primaryTextColor, this.actorBorder = this.actorBorder || this.primaryBorderColor, this.actorBkg = this.actorBkg || this.mainBkg, this.actorTextColor = this.actorTextColor || this.primaryTextColor, this.actorLineColor = this.actorLineColor || this.actorBorder, this.labelBoxBkgColor = this.labelBoxBkgColor || this.actorBkg, this.signalColor = this.signalColor || this.textColor, this.signalTextColor = this.signalTextColor || this.textColor, this.labelBoxBorderColor = this.labelBoxBorderColor || this.actorBorder, this.labelTextColor = this.labelTextColor || this.actorTextColor, this.loopTextColor = this.loopTextColor || this.actorTextColor, this.activationBorderColor = this.activationBorderColor || I(this.secondaryColor, 10), this.activationBkgColor = this.activationBkgColor || this.secondaryColor, this.sequenceNumberColor = this.sequenceNumberColor || A(this.lineColor);
    const t = "#ECECFE", r = "#E9E9F1", i = C(t, { h: 180, l: 5 });
    this.sectionBkgColor = this.sectionBkgColor || i, this.altSectionBkgColor = this.altSectionBkgColor || "white", this.sectionBkgColor = this.sectionBkgColor || r, this.sectionBkgColor2 = this.sectionBkgColor2 || t, this.excludeBkgColor = this.excludeBkgColor || "#eeeeee", this.taskBorderColor = this.taskBorderColor || this.primaryBorderColor, this.taskBkgColor = this.taskBkgColor || t, this.activeTaskBorderColor = this.activeTaskBorderColor || t, this.activeTaskBkgColor = this.activeTaskBkgColor || $(t, 23), this.gridColor = this.gridColor || "lightgrey", this.doneTaskBkgColor = this.doneTaskBkgColor || "lightgrey", this.doneTaskBorderColor = this.doneTaskBorderColor || "grey", this.critBorderColor = this.critBorderColor || "#ff8888", this.critBkgColor = this.critBkgColor || "red", this.todayLineColor = this.todayLineColor || "red", this.taskTextColor = this.taskTextColor || this.textColor, this.vertLineColor = this.vertLineColor || this.primaryBorderColor, this.taskTextOutsideColor = this.taskTextOutsideColor || this.textColor, this.taskTextLightColor = this.taskTextLightColor || this.textColor, this.taskTextColor = this.taskTextColor || this.primaryTextColor, this.taskTextDarkColor = this.taskTextDarkColor || this.textColor, this.taskTextClickableColor = this.taskTextClickableColor || "#003163", this.archEdgeColor = this.lineColor, this.archEdgeArrowColor = this.lineColor, this.personBorder = this.personBorder || this.primaryBorderColor, this.personBkg = this.personBkg || this.mainBkg, this.transitionColor = this.transitionColor || this.lineColor, this.transitionLabelColor = this.transitionLabelColor || this.textColor, this.stateLabelColor = this.stateLabelColor || this.stateBkg || this.primaryTextColor, this.stateBkg = this.stateBkg || this.mainBkg, this.labelBackgroundColor = this.labelBackgroundColor || this.stateBkg, this.compositeBackground = this.compositeBackground || this.background || this.tertiaryColor, this.altBackground = this.altBackground || "#f0f0f0", this.compositeTitleBackground = this.compositeTitleBackground || this.mainBkg, this.compositeBorder = this.compositeBorder || this.nodeBorder, this.innerEndBackground = this.nodeBorder, this.errorBkgColor = this.errorBkgColor || this.tertiaryColor, this.errorTextColor = this.errorTextColor || this.tertiaryTextColor, this.transitionColor = this.transitionColor || this.lineColor, this.specialStateColor = this.lineColor, this.cScale0 = this.cScale0 || "#f4a8ff", this.cScale1 = this.cScale1 || "#46ecd5", this.cScale2 = this.cScale2 || "#ffb86a", this.cScale3 = this.cScale3 || "#dab2ff", this.cScale4 = this.cScale4 || "#7bf1a8", this.cScale5 = this.cScale5 || "#c4b4ff", this.cScale6 = this.cScale6 || "#ffa2a2", this.cScale7 = this.cScale7 || "#ffdf20", this.cScale8 = this.cScale8 || "#a3b3ff", this.cScale9 = this.cScale9 || "#bbf451", this.cScale10 = this.cScale10 || "#74d4ff", this.cScale11 = this.cScale11 || "#ffa1ad";
    for (let y = 0; y < this.THEME_COLOR_LIMIT; y++)
      this["cScaleInv" + y] = this["cScaleInv" + y] || A(this["cScale" + y]);
    for (let y = 0; y < this.THEME_COLOR_LIMIT; y++)
      this.darkMode ? this["cScalePeer" + y] = this["cScalePeer" + y] || $(this["cScale" + y], 10) : this["cScalePeer" + y] = this["cScalePeer" + y] || I(this["cScale" + y], 10);
    this.scaleLabelColor = this.scaleLabelColor || this.labelTextColor;
    for (let y = 0; y < this.THEME_COLOR_LIMIT; y++)
      this["cScaleLabel" + y] = this["cScaleLabel" + y] || this.scaleLabelColor;
    const s = this.darkMode ? -4 : -1;
    for (let y = 0; y < 5; y++)
      this["surface" + y] = this["surface" + y] || C(this.mainBkg, { h: 180, s: -15, l: s * (5 + y * 3) }), this["surfacePeer" + y] = this["surfacePeer" + y] || C(this.mainBkg, { h: 180, s: -15, l: s * (8 + y * 3) });
    this.classText = this.classText || this.textColor, this.fillType0 = this.fillType0 || t, this.fillType1 = this.fillType1 || r, this.fillType2 = this.fillType2 || C(t, { h: 64 }), this.fillType3 = this.fillType3 || C(r, { h: 64 }), this.fillType4 = this.fillType4 || C(t, { h: -64 }), this.fillType5 = this.fillType5 || C(r, { h: -64 }), this.fillType6 = this.fillType6 || C(t, { h: 128 }), this.fillType7 = this.fillType7 || C(r, { h: 128 }), this.pie1 = this.pie1 || t, this.pie2 = this.pie2 || r, this.pie3 = this.pie3 || i, this.pie4 = this.pie4 || C(t, { l: -10 }), this.pie5 = this.pie5 || C(r, { l: -10 }), this.pie6 = this.pie6 || C(i, { l: -10 }), this.pie7 = this.pie7 || C(t, { h: 60, l: -10 }), this.pie8 = this.pie8 || C(t, { h: -60, l: -10 }), this.pie9 = this.pie9 || C(t, { h: 120, l: 0 }), this.pie10 = this.pie10 || C(t, { h: 60, l: -20 }), this.pie11 = this.pie11 || C(t, { h: -60, l: -20 }), this.pie12 = this.pie12 || C(t, { h: 120, l: -10 }), this.pieTitleTextSize = this.pieTitleTextSize || "25px", this.pieTitleTextColor = this.pieTitleTextColor || this.taskTextDarkColor, this.pieSectionTextSize = this.pieSectionTextSize || "17px", this.pieSectionTextColor = this.pieSectionTextColor || this.textColor, this.pieLegendTextSize = this.pieLegendTextSize || "17px", this.pieLegendTextColor = this.pieLegendTextColor || this.taskTextDarkColor, this.pieStrokeColor = this.pieStrokeColor || "black", this.pieStrokeWidth = this.pieStrokeWidth || "2px", this.pieOuterStrokeWidth = this.pieOuterStrokeWidth || "2px", this.pieOuterStrokeColor = this.pieOuterStrokeColor || "black", this.pieOpacity = this.pieOpacity || "0.7", this.vennTitleTextColor = this.vennTitleTextColor ?? this.titleColor, this.vennSetTextColor = this.vennSetTextColor ?? this.textColor, this.quadrant1Fill = this.quadrant1Fill || t, this.quadrant2Fill = this.quadrant2Fill || C(t, { r: 5, g: 5, b: 5 }), this.quadrant3Fill = this.quadrant3Fill || C(t, { r: 10, g: 10, b: 10 }), this.quadrant4Fill = this.quadrant4Fill || C(t, { r: 15, g: 15, b: 15 }), this.quadrant1TextFill = this.quadrant1TextFill || this.primaryTextColor, this.quadrant2TextFill = this.quadrant2TextFill || C(this.primaryTextColor, { r: -5, g: -5, b: -5 }), this.quadrant3TextFill = this.quadrant3TextFill || C(this.primaryTextColor, { r: -10, g: -10, b: -10 }), this.quadrant4TextFill = this.quadrant4TextFill || C(this.primaryTextColor, { r: -15, g: -15, b: -15 }), this.quadrantPointFill = this.quadrantPointFill || _e(this.quadrant1Fill) ? $(this.quadrant1Fill) : I(this.quadrant1Fill), this.quadrantPointTextFill = this.quadrantPointTextFill || this.primaryTextColor, this.quadrantXAxisTextFill = this.quadrantXAxisTextFill || this.primaryTextColor, this.quadrantYAxisTextFill = this.quadrantYAxisTextFill || this.primaryTextColor, this.quadrantInternalBorderStrokeFill = this.quadrantInternalBorderStrokeFill || this.primaryBorderColor, this.quadrantExternalBorderStrokeFill = this.quadrantExternalBorderStrokeFill || this.primaryBorderColor, this.quadrantTitleFill = this.quadrantTitleFill || this.primaryTextColor, this.xyChart = {
      backgroundColor: ((o = this.xyChart) == null ? void 0 : o.backgroundColor) || this.background,
      titleColor: ((a = this.xyChart) == null ? void 0 : a.titleColor) || this.primaryTextColor,
      xAxisTitleColor: ((n = this.xyChart) == null ? void 0 : n.xAxisTitleColor) || this.primaryTextColor,
      xAxisLabelColor: ((l = this.xyChart) == null ? void 0 : l.xAxisLabelColor) || this.primaryTextColor,
      xAxisTickColor: ((h = this.xyChart) == null ? void 0 : h.xAxisTickColor) || this.primaryTextColor,
      xAxisLineColor: ((c = this.xyChart) == null ? void 0 : c.xAxisLineColor) || this.primaryTextColor,
      yAxisTitleColor: ((u = this.xyChart) == null ? void 0 : u.yAxisTitleColor) || this.primaryTextColor,
      yAxisLabelColor: ((p = this.xyChart) == null ? void 0 : p.yAxisLabelColor) || this.primaryTextColor,
      yAxisTickColor: ((d = this.xyChart) == null ? void 0 : d.yAxisTickColor) || this.primaryTextColor,
      yAxisLineColor: ((g = this.xyChart) == null ? void 0 : g.yAxisLineColor) || this.primaryTextColor,
      plotColorPalette: ((m = this.xyChart) == null ? void 0 : m.plotColorPalette) || "#FFF4DD,#FFD8B1,#FFA07A,#ECEFF1,#D6DBDF,#C3E0A8,#FFB6A4,#FFD74D,#738FA7,#FFFFF0"
    }, this.requirementBackground = this.requirementBackground || t, this.requirementBorderColor = this.requirementBorderColor || this.primaryBorderColor, this.requirementBorderSize = this.requirementBorderSize || "1", this.requirementTextColor = this.requirementTextColor || this.primaryTextColor, this.relationColor = this.relationColor || this.lineColor, this.relationLabelBackground = this.relationLabelBackground || (this.darkMode ? I(this.secondaryColor, 30) : this.secondaryColor), this.relationLabelColor = this.relationLabelColor || this.actorTextColor, this.git0 = this.git0 || t, this.git1 = this.git1 || r, this.git2 = this.git2 || i, this.git3 = this.git3 || C(t, { h: -30 }), this.git4 = this.git4 || C(t, { h: -60 }), this.git5 = this.git5 || C(t, { h: -90 }), this.git6 = this.git6 || C(t, { h: 60 }), this.git7 = this.git7 || C(t, { h: 120 }), this.darkMode ? (this.git0 = $(this.git0, 25), this.git1 = $(this.git1, 25), this.git2 = $(this.git2, 25), this.git3 = $(this.git3, 25), this.git4 = $(this.git4, 25), this.git5 = $(this.git5, 25), this.git6 = $(this.git6, 25), this.git7 = $(this.git7, 25)) : (this.git0 = I(this.git0, 25), this.git1 = I(this.git1, 25), this.git2 = I(this.git2, 25), this.git3 = I(this.git3, 25), this.git4 = I(this.git4, 25), this.git5 = I(this.git5, 25), this.git6 = I(this.git6, 25), this.git7 = I(this.git7, 25)), this.gitInv0 = this.gitInv0 || A(this.git0), this.gitInv1 = this.gitInv1 || A(this.git1), this.gitInv2 = this.gitInv2 || A(this.git2), this.gitInv3 = this.gitInv3 || A(this.git3), this.gitInv4 = this.gitInv4 || A(this.git4), this.gitInv5 = this.gitInv5 || A(this.git5), this.gitInv6 = this.gitInv6 || A(this.git6), this.gitInv7 = this.gitInv7 || A(this.git7), this.branchLabelColor = this.branchLabelColor || (this.darkMode ? "black" : this.labelTextColor), this.gitBranchLabel0 = this.gitBranchLabel0 || this.branchLabelColor, this.gitBranchLabel1 = this.gitBranchLabel1 || this.branchLabelColor, this.gitBranchLabel2 = this.gitBranchLabel2 || this.branchLabelColor, this.gitBranchLabel3 = this.gitBranchLabel3 || this.branchLabelColor, this.gitBranchLabel4 = this.gitBranchLabel4 || this.branchLabelColor, this.gitBranchLabel5 = this.gitBranchLabel5 || this.branchLabelColor, this.gitBranchLabel6 = this.gitBranchLabel6 || this.branchLabelColor, this.gitBranchLabel7 = this.gitBranchLabel7 || this.branchLabelColor, this.tagLabelColor = this.tagLabelColor || this.primaryTextColor, this.tagLabelBackground = this.tagLabelBackground || this.primaryColor, this.tagLabelBorder = this.tagBorder || this.primaryBorderColor, this.tagLabelFontSize = this.tagLabelFontSize || "10px", this.commitLabelColor = this.commitLabelColor || this.secondaryTextColor, this.commitLabelBackground = this.commitLabelBackground || this.secondaryColor, this.commitLineColor = this.commitLineColor ?? "#BDBCCC", this.commitLabelFontSize = this.commitLabelFontSize || "10px", this.fontWeight = 600, this.erEdgeLabelBackground = "#FFFFFF", this.attributeBackgroundColorOdd = this.attributeBackgroundColorOdd || De, this.attributeBackgroundColorEven = this.attributeBackgroundColorEven || Re;
  }
  calculate(t) {
    if (typeof t != "object") {
      this.updateColors();
      return;
    }
    const r = Object.keys(t);
    r.forEach((i) => {
      this[i] = t[i];
    }), this.updateColors(), r.forEach((i) => {
      this[i] = t[i];
    });
  }
}, f(ri, "Theme"), ri), Yx = /* @__PURE__ */ f((e) => {
  const t = new Hx();
  return t.calculate(e), t;
}, "getThemeVariables"), ii, Xx = (ii = class {
  constructor() {
    this.background = "#333", this.primaryColor = "#1f2020", this.secondaryColor = $(this.primaryColor, 16), this.tertiaryColor = C(this.primaryColor, { h: -160 }), this.primaryBorderColor = A(this.background), this.secondaryBorderColor = nt(this.secondaryColor, this.darkMode), this.tertiaryBorderColor = nt(this.tertiaryColor, this.darkMode), this.primaryTextColor = A(this.primaryColor), this.secondaryTextColor = A(this.secondaryColor), this.tertiaryTextColor = A(this.tertiaryColor), this.mainBkg = "#111113", this.secondBkg = "calculated", this.mainContrastColor = "lightgrey", this.darkTextColor = $(A("#323D47"), 10), this.border1 = "#ccc", this.border2 = gr(255, 255, 255, 0.25), this.arrowheadColor = A(this.background), this.fontFamily = '"Recursive Variable", arial, sans-serif', this.fontSize = "14px", this.labelBackground = "#111113", this.textColor = "#ccc", this.THEME_COLOR_LIMIT = 12, this.radius = 12, this.strokeWidth = 2, this.noteBkgColor = this.noteBkgColor ?? "#FEF9C3", this.noteTextColor = this.noteTextColor ?? "#28253D", this.THEME_COLOR_LIMIT = 12, this.fontFamily = '"Recursive Variable", arial, sans-serif', this.fontSize = "14px", this.nodeBorder = "#FFFFFF", this.stateBorder = "#FFFFFF", this.useGradient = !1, this.gradientStart = "#0042eb", this.gradientStop = "#eb0042", this.dropShadow = "url(#drop-shadow)", this.nodeShadow = !0, this.archEdgeColor = "calculated", this.archEdgeArrowColor = "calculated", this.archEdgeWidth = "3", this.archGroupBorderColor = this.primaryBorderColor, this.archGroupBorderWidth = "2px", this.clusterBkg = "#1E1A2E", this.clusterBorder = "#BDBCCC", this.noteBorderColor = "#FACC15", this.noteFontWeight = 600, this.borderColorArray = [
      "#E879F9",
      //Fuchsia-400
      "#2DD4BF",
      //Teal-400
      "#FB923C",
      //Orange-400
      "#22D3EE",
      // Cyan-400
      "#4ADE80",
      // Green-400
      "#A78BFA",
      //Violet-400
      "#F87171",
      //red-400
      "#FACC15",
      //yellow-400
      "#818CF8",
      //indigo-400
      "#A3E635 ",
      //Lime-400
      "#38BDF8",
      //Sky-400
      "#FB7185"
      //Rose-400
    ], this.bkgColorArray = [], this.filterColor = "#FFFFFF";
  }
  updateColors() {
    var r, i, s, o, a, n, l, h, c, u, p;
    this.primaryTextColor = this.primaryTextColor || (this.darkMode ? "#eee" : "#FFFFFF"), this.secondaryColor = this.secondaryColor || C(this.primaryColor, { h: -120 }), this.tertiaryColor = this.tertiaryColor || C(this.primaryColor, { h: 180, l: 5 }), this.primaryBorderColor = this.primaryBorderColor || nt(this.primaryColor, this.darkMode), this.secondaryBorderColor = this.secondaryBorderColor || nt(this.secondaryColor, this.darkMode), this.tertiaryBorderColor = this.tertiaryBorderColor || nt(this.tertiaryColor, this.darkMode), this.noteBorderColor = this.noteBorderColor || nt(this.noteBkgColor, this.darkMode), this.noteBkgColor = this.noteBkgColor || "#fff5ad", this.noteTextColor = this.noteTextColor || "#FFFFFF", this.secondaryTextColor = this.secondaryTextColor || A(this.secondaryColor), this.tertiaryTextColor = this.tertiaryTextColor || A(this.tertiaryColor), this.lineColor = this.lineColor || A(this.background), this.arrowheadColor = this.arrowheadColor || A(this.background), this.textColor = this.textColor || this.primaryTextColor, this.border2 = this.border2 || this.tertiaryBorderColor, this.nodeBkg = this.nodeBkg || this.primaryColor, this.mainBkg = this.mainBkg || this.primaryColor, this.nodeBorder = this.nodeBorder || this.border1, this.clusterBkg = this.clusterBkg || this.tertiaryColor, this.clusterBorder = this.clusterBorder || this.tertiaryBorderColor, this.defaultLinkColor = this.defaultLinkColor || this.lineColor, this.titleColor = this.titleColor || this.tertiaryTextColor, this.edgeLabelBackground = this.edgeLabelBackground || (this.darkMode ? I(this.secondaryColor, 30) : this.secondaryColor), this.nodeTextColor = this.nodeTextColor || this.primaryTextColor, this.actorBorder = "#FFFFFF", this.signalColor = "#FFFFFF", this.labelBoxBorderColor = "#BDBCCC", this.actorBorder = this.actorBorder || this.primaryBorderColor, this.actorBkg = this.actorBkg || this.mainBkg, this.actorTextColor = this.actorTextColor || this.primaryTextColor, this.actorLineColor = this.actorLineColor || this.actorBorder, this.labelBoxBkgColor = this.labelBoxBkgColor || this.actorBkg, this.signalColor = this.signalColor || this.textColor, this.signalTextColor = this.signalTextColor || this.textColor, this.labelBoxBorderColor = this.labelBoxBorderColor || this.actorBorder, this.labelTextColor = this.labelTextColor || this.actorTextColor, this.loopTextColor = this.loopTextColor || this.actorTextColor, this.activationBorderColor = this.activationBorderColor || I(this.secondaryColor, 10), this.activationBkgColor = this.activationBkgColor || this.secondaryColor, this.sequenceNumberColor = this.sequenceNumberColor || A(this.lineColor), this.rootLabelColor = "#FFFFFF", this.sectionBkgColor = this.sectionBkgColor || this.tertiaryColor, this.altSectionBkgColor = this.altSectionBkgColor || "white", this.sectionBkgColor = this.sectionBkgColor || this.secondaryColor, this.sectionBkgColor2 = this.sectionBkgColor2 || this.primaryColor, this.excludeBkgColor = this.excludeBkgColor || "#eeeeee", this.taskBorderColor = this.taskBorderColor || this.primaryBorderColor, this.taskBkgColor = this.taskBkgColor || this.primaryColor, this.activeTaskBorderColor = this.activeTaskBorderColor || this.primaryColor, this.activeTaskBkgColor = this.activeTaskBkgColor || $(this.primaryColor, 23), this.gridColor = this.gridColor || "lightgrey", this.doneTaskBkgColor = this.doneTaskBkgColor || "lightgrey", this.doneTaskBorderColor = this.doneTaskBorderColor || "grey", this.critBorderColor = this.critBorderColor || "#ff8888", this.critBkgColor = this.critBkgColor || "red", this.todayLineColor = this.todayLineColor || "red", this.taskTextColor = this.taskTextColor || this.textColor, this.vertLineColor = this.vertLineColor || this.primaryBorderColor, this.taskTextOutsideColor = this.taskTextOutsideColor || this.textColor, this.taskTextLightColor = this.taskTextLightColor || this.textColor, this.taskTextColor = this.taskTextColor || this.primaryTextColor, this.taskTextDarkColor = this.taskTextDarkColor || this.textColor, this.taskTextClickableColor = this.taskTextClickableColor || "#003163", this.archEdgeColor = this.lineColor, this.archEdgeArrowColor = this.lineColor, this.personBorder = this.personBorder || this.primaryBorderColor, this.personBkg = this.personBkg || this.mainBkg, this.transitionColor = this.transitionColor || this.lineColor, this.transitionLabelColor = this.transitionLabelColor || this.textColor, this.stateLabelColor = this.stateLabelColor || this.stateBkg || this.primaryTextColor, this.stateBkg = this.stateBkg || this.mainBkg, this.labelBackgroundColor = this.labelBackgroundColor || this.stateBkg, this.compositeBackground = this.compositeBackground || this.background || this.tertiaryColor, this.altBackground = this.altBackground || "#f0f0f0", this.compositeTitleBackground = this.compositeTitleBackground || this.mainBkg, this.compositeBorder = this.compositeBorder || this.nodeBorder, this.innerEndBackground = this.nodeBorder, this.errorBkgColor = this.errorBkgColor || this.tertiaryColor, this.errorTextColor = this.errorTextColor || this.tertiaryTextColor, this.transitionColor = this.transitionColor || this.lineColor, this.specialStateColor = this.lineColor, this.cScale0 = this.cScale0 || "#f4a8ff", this.cScale1 = this.cScale1 || "#46ecd5", this.cScale2 = this.cScale2 || "#ffb86a", this.cScale3 = this.cScale3 || "#dab2ff", this.cScale4 = this.cScale4 || "#7bf1a8", this.cScale5 = this.cScale5 || "#c4b4ff", this.cScale6 = this.cScale6 || "#ffa2a2", this.cScale7 = this.cScale7 || "#ffdf20", this.cScale8 = this.cScale8 || "#a3b3ff", this.cScale9 = this.cScale9 || "#bbf451", this.cScale10 = this.cScale10 || "#74d4ff", this.cScale11 = this.cScale11 || "#ffa1ad";
    for (let d = 0; d < this.THEME_COLOR_LIMIT; d++)
      this["cScaleInv" + d] = this["cScaleInv" + d] || A(this["cScale" + d]);
    for (let d = 0; d < this.THEME_COLOR_LIMIT; d++)
      this.darkMode ? this["cScalePeer" + d] = this["cScalePeer" + d] || $(this["cScale" + d], 10) : this["cScalePeer" + d] = this["cScalePeer" + d] || I(this["cScale" + d], 10);
    this.scaleLabelColor = this.scaleLabelColor || this.labelTextColor;
    for (let d = 0; d < this.THEME_COLOR_LIMIT; d++)
      this["cScaleLabel" + d] = I(this["cScale" + d], 75);
    const t = this.darkMode ? -4 : -1;
    for (let d = 0; d < 5; d++)
      this["surface" + d] = this["surface" + d] || C(this.mainBkg, { h: 180, s: -15, l: t * (5 + d * 3) }), this["surfacePeer" + d] = this["surfacePeer" + d] || C(this.mainBkg, { h: 180, s: -15, l: t * (8 + d * 3) });
    this.classText = this.classText || this.textColor, this.fillType0 = this.fillType0 || this.primaryColor, this.fillType1 = this.fillType1 || this.secondaryColor, this.fillType2 = this.fillType2 || C(this.primaryColor, { h: 64 }), this.fillType3 = this.fillType3 || C(this.secondaryColor, { h: 64 }), this.fillType4 = this.fillType4 || C(this.primaryColor, { h: -64 }), this.fillType5 = this.fillType5 || C(this.secondaryColor, { h: -64 }), this.fillType6 = this.fillType6 || C(this.primaryColor, { h: 128 }), this.fillType7 = this.fillType7 || C(this.secondaryColor, { h: 128 }), this.pie1 = this.pie1 || this.primaryColor, this.pie2 = this.pie2 || this.secondaryColor, this.pie3 = this.pie3 || this.tertiaryColor, this.pie4 = this.pie4 || C(this.primaryColor, { l: -10 }), this.pie5 = this.pie5 || C(this.secondaryColor, { l: -10 }), this.pie6 = this.pie6 || C(this.tertiaryColor, { l: -10 }), this.pie7 = this.pie7 || C(this.primaryColor, { h: 60, l: -10 }), this.pie8 = this.pie8 || C(this.primaryColor, { h: -60, l: -10 }), this.pie9 = this.pie9 || C(this.primaryColor, { h: 120, l: 0 }), this.pie10 = this.pie10 || C(this.primaryColor, { h: 60, l: -20 }), this.pie11 = this.pie11 || C(this.primaryColor, { h: -60, l: -20 }), this.pie12 = this.pie12 || C(this.primaryColor, { h: 120, l: -10 }), this.pieTitleTextSize = this.pieTitleTextSize || "25px", this.pieTitleTextColor = this.pieTitleTextColor || this.taskTextDarkColor, this.pieSectionTextSize = this.pieSectionTextSize || "17px", this.pieSectionTextColor = this.pieSectionTextColor || this.textColor, this.pieLegendTextSize = this.pieLegendTextSize || "17px", this.pieLegendTextColor = this.pieLegendTextColor || this.taskTextDarkColor, this.pieStrokeColor = this.pieStrokeColor || "black", this.pieStrokeWidth = this.pieStrokeWidth || "2px", this.pieOuterStrokeWidth = this.pieOuterStrokeWidth || "2px", this.pieOuterStrokeColor = this.pieOuterStrokeColor || "black", this.pieOpacity = this.pieOpacity || "0.7", this.vennTitleTextColor = this.vennTitleTextColor ?? this.titleColor, this.vennSetTextColor = this.vennSetTextColor ?? this.textColor, this.quadrant1Fill = this.quadrant1Fill || this.primaryColor, this.quadrant2Fill = this.quadrant2Fill || C(this.primaryColor, { r: 5, g: 5, b: 5 }), this.quadrant3Fill = this.quadrant3Fill || C(this.primaryColor, { r: 10, g: 10, b: 10 }), this.quadrant4Fill = this.quadrant4Fill || C(this.primaryColor, { r: 15, g: 15, b: 15 }), this.quadrant1TextFill = this.quadrant1TextFill || this.primaryTextColor, this.quadrant2TextFill = this.quadrant2TextFill || C(this.primaryTextColor, { r: -5, g: -5, b: -5 }), this.quadrant3TextFill = this.quadrant3TextFill || C(this.primaryTextColor, { r: -10, g: -10, b: -10 }), this.quadrant4TextFill = this.quadrant4TextFill || C(this.primaryTextColor, { r: -15, g: -15, b: -15 }), this.quadrantPointFill = this.quadrantPointFill || _e(this.quadrant1Fill) ? $(this.quadrant1Fill) : I(this.quadrant1Fill), this.quadrantPointTextFill = this.quadrantPointTextFill || this.primaryTextColor, this.quadrantXAxisTextFill = this.quadrantXAxisTextFill || this.primaryTextColor, this.quadrantYAxisTextFill = this.quadrantYAxisTextFill || this.primaryTextColor, this.quadrantInternalBorderStrokeFill = this.quadrantInternalBorderStrokeFill || this.primaryBorderColor, this.quadrantExternalBorderStrokeFill = this.quadrantExternalBorderStrokeFill || this.primaryBorderColor, this.quadrantTitleFill = this.quadrantTitleFill || this.primaryTextColor, this.xyChart = {
      backgroundColor: ((r = this.xyChart) == null ? void 0 : r.backgroundColor) || this.background,
      titleColor: ((i = this.xyChart) == null ? void 0 : i.titleColor) || this.primaryTextColor,
      xAxisTitleColor: ((s = this.xyChart) == null ? void 0 : s.xAxisTitleColor) || this.primaryTextColor,
      xAxisLabelColor: ((o = this.xyChart) == null ? void 0 : o.xAxisLabelColor) || this.primaryTextColor,
      xAxisTickColor: ((a = this.xyChart) == null ? void 0 : a.xAxisTickColor) || this.primaryTextColor,
      xAxisLineColor: ((n = this.xyChart) == null ? void 0 : n.xAxisLineColor) || this.primaryTextColor,
      yAxisTitleColor: ((l = this.xyChart) == null ? void 0 : l.yAxisTitleColor) || this.primaryTextColor,
      yAxisLabelColor: ((h = this.xyChart) == null ? void 0 : h.yAxisLabelColor) || this.primaryTextColor,
      yAxisTickColor: ((c = this.xyChart) == null ? void 0 : c.yAxisTickColor) || this.primaryTextColor,
      yAxisLineColor: ((u = this.xyChart) == null ? void 0 : u.yAxisLineColor) || this.primaryTextColor,
      plotColorPalette: ((p = this.xyChart) == null ? void 0 : p.plotColorPalette) || "#FFF4DD,#FFD8B1,#FFA07A,#ECEFF1,#D6DBDF,#C3E0A8,#FFB6A4,#FFD74D,#738FA7,#FFFFF0"
    }, this.requirementBackground = this.requirementBackground || this.primaryColor, this.requirementBorderColor = this.requirementBorderColor || this.primaryBorderColor, this.requirementBorderSize = this.requirementBorderSize || "1", this.requirementTextColor = this.requirementTextColor || this.primaryTextColor, this.relationColor = this.relationColor || this.lineColor, this.relationLabelBackground = this.relationLabelBackground || (this.darkMode ? I(this.secondaryColor, 30) : this.secondaryColor), this.relationLabelColor = this.relationLabelColor || this.actorTextColor, this.git0 = this.git0 || this.primaryColor, this.git1 = this.git1 || this.secondaryColor, this.git2 = this.git2 || this.tertiaryColor, this.git3 = this.git3 || C(this.primaryColor, { h: -30 }), this.git4 = this.git4 || C(this.primaryColor, { h: -60 }), this.git5 = this.git5 || C(this.primaryColor, { h: -90 }), this.git6 = this.git6 || C(this.primaryColor, { h: 60 }), this.git7 = this.git7 || C(this.primaryColor, { h: 120 }), this.darkMode ? (this.git0 = $(this.git0, 25), this.git1 = $(this.git1, 25), this.git2 = $(this.git2, 25), this.git3 = $(this.git3, 25), this.git4 = $(this.git4, 25), this.git5 = $(this.git5, 25), this.git6 = $(this.git6, 25), this.git7 = $(this.git7, 25)) : (this.git0 = I(this.git0, 25), this.git1 = I(this.git1, 25), this.git2 = I(this.git2, 25), this.git3 = I(this.git3, 25), this.git4 = I(this.git4, 25), this.git5 = I(this.git5, 25), this.git6 = I(this.git6, 25), this.git7 = I(this.git7, 25)), this.gitInv0 = this.gitInv0 || A(this.git0), this.gitInv1 = this.gitInv1 || A(this.git1), this.gitInv2 = this.gitInv2 || A(this.git2), this.gitInv3 = this.gitInv3 || A(this.git3), this.gitInv4 = this.gitInv4 || A(this.git4), this.gitInv5 = this.gitInv5 || A(this.git5), this.gitInv6 = this.gitInv6 || A(this.git6), this.gitInv7 = this.gitInv7 || A(this.git7), this.branchLabelColor = this.branchLabelColor || (this.darkMode ? "black" : this.labelTextColor), this.gitBranchLabel0 = this.gitBranchLabel0 || this.branchLabelColor, this.gitBranchLabel1 = this.gitBranchLabel1 || this.branchLabelColor, this.gitBranchLabel2 = this.gitBranchLabel2 || this.branchLabelColor, this.gitBranchLabel3 = this.gitBranchLabel3 || this.branchLabelColor, this.gitBranchLabel4 = this.gitBranchLabel4 || this.branchLabelColor, this.gitBranchLabel5 = this.gitBranchLabel5 || this.branchLabelColor, this.gitBranchLabel6 = this.gitBranchLabel6 || this.branchLabelColor, this.gitBranchLabel7 = this.gitBranchLabel7 || this.branchLabelColor, this.tagLabelColor = this.tagLabelColor || this.primaryTextColor, this.tagLabelBackground = this.tagLabelBackground || this.primaryColor, this.tagLabelBorder = this.tagBorder || this.primaryBorderColor, this.tagLabelFontSize = this.tagLabelFontSize || "10px", this.commitLabelColor = this.commitLabelColor || this.secondaryTextColor, this.commitLabelBackground = this.commitLabelBackground || this.secondaryColor, this.commitLabelFontSize = this.commitLabelFontSize || "10px", this.commitLineColor = this.commitLineColor ?? "#BDBCCC", this.fontWeight = 600, this.erEdgeLabelBackground = "#16141F", this.attributeBackgroundColorOdd = this.attributeBackgroundColorOdd || De, this.attributeBackgroundColorEven = this.attributeBackgroundColorEven || Re;
  }
  calculate(t) {
    if (typeof t != "object") {
      this.updateColors();
      return;
    }
    const r = Object.keys(t);
    r.forEach((i) => {
      this[i] = t[i];
    }), this.updateColors(), r.forEach((i) => {
      this[i] = t[i];
    });
  }
}, f(ii, "Theme"), ii), Ux = /* @__PURE__ */ f((e) => {
  const t = new Xx();
  return t.calculate(e), t;
}, "getThemeVariables"), Ye = {
  base: {
    getThemeVariables: Bx
  },
  dark: {
    getThemeVariables: Lx
  },
  default: {
    getThemeVariables: Ex
  },
  forest: {
    getThemeVariables: Mx
  },
  neutral: {
    getThemeVariables: $x
  },
  neo: {
    getThemeVariables: Dx
  },
  "neo-dark": {
    getThemeVariables: Px
  },
  redux: {
    getThemeVariables: qx
  },
  "redux-dark": {
    getThemeVariables: zx
  },
  "redux-color": {
    getThemeVariables: Yx
  },
  "redux-dark-color": {
    getThemeVariables: Ux
  }
}, ae = {
  flowchart: {
    useMaxWidth: !0,
    titleTopMargin: 25,
    subGraphTitleMargin: {
      top: 0,
      bottom: 0
    },
    diagramPadding: 8,
    htmlLabels: null,
    nodeSpacing: 50,
    rankSpacing: 50,
    curve: "basis",
    padding: 15,
    defaultRenderer: "dagre-wrapper",
    wrappingWidth: 200,
    inheritDir: !1
  },
  sequence: {
    useMaxWidth: !0,
    hideUnusedParticipants: !1,
    activationWidth: 10,
    diagramMarginX: 50,
    diagramMarginY: 10,
    actorMargin: 50,
    width: 150,
    height: 65,
    boxMargin: 10,
    boxTextMargin: 5,
    noteMargin: 10,
    messageMargin: 35,
    messageAlign: "center",
    mirrorActors: !0,
    forceMenus: !1,
    bottomMarginAdj: 1,
    rightAngles: !1,
    showSequenceNumbers: !1,
    actorFontSize: 14,
    actorFontFamily: '"Open Sans", sans-serif',
    actorFontWeight: 400,
    noteFontSize: 14,
    noteFontFamily: '"trebuchet ms", verdana, arial, sans-serif',
    noteFontWeight: 400,
    noteAlign: "center",
    messageFontSize: 16,
    messageFontFamily: '"trebuchet ms", verdana, arial, sans-serif',
    messageFontWeight: 400,
    wrap: !1,
    wrapPadding: 10,
    labelBoxWidth: 50,
    labelBoxHeight: 20
  },
  gantt: {
    useMaxWidth: !0,
    titleTopMargin: 25,
    barHeight: 20,
    barGap: 4,
    topPadding: 50,
    rightPadding: 75,
    leftPadding: 75,
    gridLineStartPadding: 35,
    fontSize: 11,
    sectionFontSize: 11,
    numberSectionStyles: 4,
    axisFormat: "%Y-%m-%d",
    topAxis: !1,
    displayMode: "",
    weekday: "sunday"
  },
  journey: {
    useMaxWidth: !0,
    diagramMarginX: 50,
    diagramMarginY: 10,
    leftMargin: 150,
    maxLabelWidth: 360,
    width: 150,
    height: 50,
    boxMargin: 10,
    boxTextMargin: 5,
    noteMargin: 10,
    messageMargin: 35,
    messageAlign: "center",
    bottomMarginAdj: 1,
    rightAngles: !1,
    taskFontSize: 14,
    taskFontFamily: '"Open Sans", sans-serif',
    taskMargin: 50,
    activationWidth: 10,
    textPlacement: "fo",
    actorColours: [
      "#8FBC8F",
      "#7CFC00",
      "#00FFFF",
      "#20B2AA",
      "#B0E0E6",
      "#FFFFE0"
    ],
    sectionFills: [
      "#191970",
      "#8B008B",
      "#4B0082",
      "#2F4F4F",
      "#800000",
      "#8B4513",
      "#00008B"
    ],
    sectionColours: [
      "#fff"
    ],
    titleColor: "",
    titleFontFamily: '"trebuchet ms", verdana, arial, sans-serif',
    titleFontSize: "4ex"
  },
  class: {
    useMaxWidth: !0,
    titleTopMargin: 25,
    arrowMarkerAbsolute: !1,
    dividerMargin: 10,
    padding: 5,
    textHeight: 10,
    defaultRenderer: "dagre-wrapper",
    htmlLabels: !1,
    hideEmptyMembersBox: !1
  },
  state: {
    useMaxWidth: !0,
    titleTopMargin: 25,
    dividerMargin: 10,
    sizeUnit: 5,
    padding: 8,
    textHeight: 10,
    titleShift: -15,
    noteMargin: 10,
    forkWidth: 70,
    forkHeight: 7,
    miniPadding: 2,
    fontSizeFactor: 5.02,
    fontSize: 24,
    labelHeight: 16,
    edgeLengthFactor: "20",
    compositTitleSize: 35,
    radius: 5,
    defaultRenderer: "dagre-wrapper"
  },
  er: {
    useMaxWidth: !0,
    titleTopMargin: 25,
    diagramPadding: 20,
    layoutDirection: "TB",
    minEntityWidth: 100,
    minEntityHeight: 75,
    entityPadding: 15,
    nodeSpacing: 140,
    rankSpacing: 80,
    stroke: "gray",
    fill: "honeydew",
    fontSize: 12
  },
  pie: {
    useMaxWidth: !0,
    textPosition: 0.75
  },
  quadrantChart: {
    useMaxWidth: !0,
    chartWidth: 500,
    chartHeight: 500,
    titleFontSize: 20,
    titlePadding: 10,
    quadrantPadding: 5,
    xAxisLabelPadding: 5,
    yAxisLabelPadding: 5,
    xAxisLabelFontSize: 16,
    yAxisLabelFontSize: 16,
    quadrantLabelFontSize: 16,
    quadrantTextTopPadding: 5,
    pointTextPadding: 5,
    pointLabelFontSize: 12,
    pointRadius: 5,
    xAxisPosition: "top",
    yAxisPosition: "left",
    quadrantInternalBorderStrokeWidth: 1,
    quadrantExternalBorderStrokeWidth: 2
  },
  xyChart: {
    useMaxWidth: !0,
    width: 700,
    height: 500,
    titleFontSize: 20,
    titlePadding: 10,
    showDataLabel: !1,
    showDataLabelOutsideBar: !1,
    showTitle: !0,
    xAxis: {
      $ref: "#/$defs/XYChartAxisConfig",
      showLabel: !0,
      labelFontSize: 14,
      labelPadding: 5,
      showTitle: !0,
      titleFontSize: 16,
      titlePadding: 5,
      showTick: !0,
      tickLength: 5,
      tickWidth: 2,
      showAxisLine: !0,
      axisLineWidth: 2
    },
    yAxis: {
      $ref: "#/$defs/XYChartAxisConfig",
      showLabel: !0,
      labelFontSize: 14,
      labelPadding: 5,
      showTitle: !0,
      titleFontSize: 16,
      titlePadding: 5,
      showTick: !0,
      tickLength: 5,
      tickWidth: 2,
      showAxisLine: !0,
      axisLineWidth: 2
    },
    chartOrientation: "vertical",
    plotReservedSpacePercent: 50
  },
  requirement: {
    useMaxWidth: !0,
    rect_fill: "#f9f9f9",
    text_color: "#333",
    rect_border_size: "0.5px",
    rect_border_color: "#bbb",
    rect_min_width: 200,
    rect_min_height: 200,
    fontSize: 14,
    rect_padding: 10,
    line_height: 20
  },
  mindmap: {
    useMaxWidth: !0,
    padding: 10,
    maxNodeWidth: 200,
    layoutAlgorithm: "cose-bilkent"
  },
  ishikawa: {
    useMaxWidth: !0,
    diagramPadding: 20
  },
  kanban: {
    useMaxWidth: !0,
    padding: 8,
    sectionWidth: 200,
    ticketBaseUrl: ""
  },
  timeline: {
    useMaxWidth: !0,
    diagramMarginX: 50,
    diagramMarginY: 10,
    leftMargin: 150,
    width: 150,
    height: 50,
    boxMargin: 10,
    boxTextMargin: 5,
    noteMargin: 10,
    messageMargin: 35,
    messageAlign: "center",
    bottomMarginAdj: 1,
    rightAngles: !1,
    taskFontSize: 14,
    taskFontFamily: '"Open Sans", sans-serif',
    taskMargin: 50,
    activationWidth: 10,
    textPlacement: "fo",
    actorColours: [
      "#8FBC8F",
      "#7CFC00",
      "#00FFFF",
      "#20B2AA",
      "#B0E0E6",
      "#FFFFE0"
    ],
    sectionFills: [
      "#191970",
      "#8B008B",
      "#4B0082",
      "#2F4F4F",
      "#800000",
      "#8B4513",
      "#00008B"
    ],
    sectionColours: [
      "#fff"
    ],
    disableMulticolor: !1
  },
  gitGraph: {
    useMaxWidth: !0,
    titleTopMargin: 25,
    diagramPadding: 8,
    nodeLabel: {
      width: 75,
      height: 100,
      x: -25,
      y: 0
    },
    mainBranchName: "main",
    mainBranchOrder: 0,
    showCommitLabel: !0,
    showBranches: !0,
    rotateCommitLabel: !0,
    parallelCommits: !1,
    arrowMarkerAbsolute: !1
  },
  c4: {
    useMaxWidth: !0,
    diagramMarginX: 50,
    diagramMarginY: 10,
    c4ShapeMargin: 50,
    c4ShapePadding: 20,
    width: 216,
    height: 60,
    boxMargin: 10,
    c4ShapeInRow: 4,
    nextLinePaddingX: 0,
    c4BoundaryInRow: 2,
    personFontSize: 14,
    personFontFamily: '"Open Sans", sans-serif',
    personFontWeight: "normal",
    external_personFontSize: 14,
    external_personFontFamily: '"Open Sans", sans-serif',
    external_personFontWeight: "normal",
    systemFontSize: 14,
    systemFontFamily: '"Open Sans", sans-serif',
    systemFontWeight: "normal",
    external_systemFontSize: 14,
    external_systemFontFamily: '"Open Sans", sans-serif',
    external_systemFontWeight: "normal",
    system_dbFontSize: 14,
    system_dbFontFamily: '"Open Sans", sans-serif',
    system_dbFontWeight: "normal",
    external_system_dbFontSize: 14,
    external_system_dbFontFamily: '"Open Sans", sans-serif',
    external_system_dbFontWeight: "normal",
    system_queueFontSize: 14,
    system_queueFontFamily: '"Open Sans", sans-serif',
    system_queueFontWeight: "normal",
    external_system_queueFontSize: 14,
    external_system_queueFontFamily: '"Open Sans", sans-serif',
    external_system_queueFontWeight: "normal",
    boundaryFontSize: 14,
    boundaryFontFamily: '"Open Sans", sans-serif',
    boundaryFontWeight: "normal",
    messageFontSize: 12,
    messageFontFamily: '"Open Sans", sans-serif',
    messageFontWeight: "normal",
    containerFontSize: 14,
    containerFontFamily: '"Open Sans", sans-serif',
    containerFontWeight: "normal",
    external_containerFontSize: 14,
    external_containerFontFamily: '"Open Sans", sans-serif',
    external_containerFontWeight: "normal",
    container_dbFontSize: 14,
    container_dbFontFamily: '"Open Sans", sans-serif',
    container_dbFontWeight: "normal",
    external_container_dbFontSize: 14,
    external_container_dbFontFamily: '"Open Sans", sans-serif',
    external_container_dbFontWeight: "normal",
    container_queueFontSize: 14,
    container_queueFontFamily: '"Open Sans", sans-serif',
    container_queueFontWeight: "normal",
    external_container_queueFontSize: 14,
    external_container_queueFontFamily: '"Open Sans", sans-serif',
    external_container_queueFontWeight: "normal",
    componentFontSize: 14,
    componentFontFamily: '"Open Sans", sans-serif',
    componentFontWeight: "normal",
    external_componentFontSize: 14,
    external_componentFontFamily: '"Open Sans", sans-serif',
    external_componentFontWeight: "normal",
    component_dbFontSize: 14,
    component_dbFontFamily: '"Open Sans", sans-serif',
    component_dbFontWeight: "normal",
    external_component_dbFontSize: 14,
    external_component_dbFontFamily: '"Open Sans", sans-serif',
    external_component_dbFontWeight: "normal",
    component_queueFontSize: 14,
    component_queueFontFamily: '"Open Sans", sans-serif',
    component_queueFontWeight: "normal",
    external_component_queueFontSize: 14,
    external_component_queueFontFamily: '"Open Sans", sans-serif',
    external_component_queueFontWeight: "normal",
    wrap: !0,
    wrapPadding: 10,
    person_bg_color: "#08427B",
    person_border_color: "#073B6F",
    external_person_bg_color: "#686868",
    external_person_border_color: "#8A8A8A",
    system_bg_color: "#1168BD",
    system_border_color: "#3C7FC0",
    system_db_bg_color: "#1168BD",
    system_db_border_color: "#3C7FC0",
    system_queue_bg_color: "#1168BD",
    system_queue_border_color: "#3C7FC0",
    external_system_bg_color: "#999999",
    external_system_border_color: "#8A8A8A",
    external_system_db_bg_color: "#999999",
    external_system_db_border_color: "#8A8A8A",
    external_system_queue_bg_color: "#999999",
    external_system_queue_border_color: "#8A8A8A",
    container_bg_color: "#438DD5",
    container_border_color: "#3C7FC0",
    container_db_bg_color: "#438DD5",
    container_db_border_color: "#3C7FC0",
    container_queue_bg_color: "#438DD5",
    container_queue_border_color: "#3C7FC0",
    external_container_bg_color: "#B3B3B3",
    external_container_border_color: "#A6A6A6",
    external_container_db_bg_color: "#B3B3B3",
    external_container_db_border_color: "#A6A6A6",
    external_container_queue_bg_color: "#B3B3B3",
    external_container_queue_border_color: "#A6A6A6",
    component_bg_color: "#85BBF0",
    component_border_color: "#78A8D8",
    component_db_bg_color: "#85BBF0",
    component_db_border_color: "#78A8D8",
    component_queue_bg_color: "#85BBF0",
    component_queue_border_color: "#78A8D8",
    external_component_bg_color: "#CCCCCC",
    external_component_border_color: "#BFBFBF",
    external_component_db_bg_color: "#CCCCCC",
    external_component_db_border_color: "#BFBFBF",
    external_component_queue_bg_color: "#CCCCCC",
    external_component_queue_border_color: "#BFBFBF"
  },
  sankey: {
    useMaxWidth: !0,
    width: 600,
    height: 400,
    linkColor: "gradient",
    nodeAlignment: "justify",
    showValues: !0,
    prefix: "",
    suffix: ""
  },
  block: {
    useMaxWidth: !0,
    padding: 8
  },
  packet: {
    useMaxWidth: !0,
    rowHeight: 32,
    bitWidth: 32,
    bitsPerRow: 32,
    showBits: !0,
    paddingX: 5,
    paddingY: 5
  },
  treeView: {
    useMaxWidth: !0,
    rowIndent: 10,
    paddingX: 5,
    paddingY: 5,
    lineThickness: 1
  },
  architecture: {
    useMaxWidth: !0,
    padding: 40,
    iconSize: 80,
    fontSize: 16,
    randomize: !1
  },
  radar: {
    useMaxWidth: !0,
    width: 600,
    height: 600,
    marginTop: 50,
    marginRight: 50,
    marginBottom: 50,
    marginLeft: 50,
    axisScaleFactor: 1,
    axisLabelFactor: 1.05,
    curveTension: 0.17
  },
  venn: {
    useMaxWidth: !0,
    width: 800,
    height: 450,
    padding: 8,
    useDebugLayout: !1
  },
  theme: "default",
  look: "classic",
  handDrawnSeed: 0,
  layout: "dagre",
  maxTextSize: 5e4,
  maxEdges: 500,
  darkMode: !1,
  fontFamily: '"trebuchet ms", verdana, arial, sans-serif;',
  logLevel: 5,
  securityLevel: "strict",
  startOnLoad: !0,
  arrowMarkerAbsolute: !1,
  secure: [
    "secure",
    "securityLevel",
    "startOnLoad",
    "maxTextSize",
    "suppressErrorRendering",
    "maxEdges"
  ],
  legacyMathML: !1,
  forceLegacyMathML: !1,
  deterministicIds: !1,
  fontSize: 16,
  markdownAutoWrap: !0,
  suppressErrorRendering: !1
}, Hc = {
  ...ae,
  // Set, even though they're `undefined` so that `configKeys` finds these keys
  // TODO: Should we replace these with `null` so that they can go in the JSON Schema?
  deterministicIDSeed: void 0,
  elk: {
    // mergeEdges is needed here to be considered
    mergeEdges: !1,
    nodePlacementStrategy: "BRANDES_KOEPF",
    forceNodeModelOrder: !1,
    considerModelOrder: "NODES_AND_EDGES"
  },
  themeCSS: void 0,
  // add non-JSON default config values
  themeVariables: Ye.default.getThemeVariables(),
  sequence: {
    ...ae.sequence,
    messageFont: /* @__PURE__ */ f(function() {
      return {
        fontFamily: this.messageFontFamily,
        fontSize: this.messageFontSize,
        fontWeight: this.messageFontWeight
      };
    }, "messageFont"),
    noteFont: /* @__PURE__ */ f(function() {
      return {
        fontFamily: this.noteFontFamily,
        fontSize: this.noteFontSize,
        fontWeight: this.noteFontWeight
      };
    }, "noteFont"),
    actorFont: /* @__PURE__ */ f(function() {
      return {
        fontFamily: this.actorFontFamily,
        fontSize: this.actorFontSize,
        fontWeight: this.actorFontWeight
      };
    }, "actorFont")
  },
  class: {
    hideEmptyMembersBox: !1
  },
  gantt: {
    ...ae.gantt,
    tickInterval: void 0,
    useWidth: void 0
    // can probably be removed since `configKeys` already includes this
  },
  c4: {
    ...ae.c4,
    useWidth: void 0,
    personFont: /* @__PURE__ */ f(function() {
      return {
        fontFamily: this.personFontFamily,
        fontSize: this.personFontSize,
        fontWeight: this.personFontWeight
      };
    }, "personFont"),
    flowchart: {
      ...ae.flowchart,
      inheritDir: !1
      // default to legacy behavior
    },
    external_personFont: /* @__PURE__ */ f(function() {
      return {
        fontFamily: this.external_personFontFamily,
        fontSize: this.external_personFontSize,
        fontWeight: this.external_personFontWeight
      };
    }, "external_personFont"),
    systemFont: /* @__PURE__ */ f(function() {
      return {
        fontFamily: this.systemFontFamily,
        fontSize: this.systemFontSize,
        fontWeight: this.systemFontWeight
      };
    }, "systemFont"),
    external_systemFont: /* @__PURE__ */ f(function() {
      return {
        fontFamily: this.external_systemFontFamily,
        fontSize: this.external_systemFontSize,
        fontWeight: this.external_systemFontWeight
      };
    }, "external_systemFont"),
    system_dbFont: /* @__PURE__ */ f(function() {
      return {
        fontFamily: this.system_dbFontFamily,
        fontSize: this.system_dbFontSize,
        fontWeight: this.system_dbFontWeight
      };
    }, "system_dbFont"),
    external_system_dbFont: /* @__PURE__ */ f(function() {
      return {
        fontFamily: this.external_system_dbFontFamily,
        fontSize: this.external_system_dbFontSize,
        fontWeight: this.external_system_dbFontWeight
      };
    }, "external_system_dbFont"),
    system_queueFont: /* @__PURE__ */ f(function() {
      return {
        fontFamily: this.system_queueFontFamily,
        fontSize: this.system_queueFontSize,
        fontWeight: this.system_queueFontWeight
      };
    }, "system_queueFont"),
    external_system_queueFont: /* @__PURE__ */ f(function() {
      return {
        fontFamily: this.external_system_queueFontFamily,
        fontSize: this.external_system_queueFontSize,
        fontWeight: this.external_system_queueFontWeight
      };
    }, "external_system_queueFont"),
    containerFont: /* @__PURE__ */ f(function() {
      return {
        fontFamily: this.containerFontFamily,
        fontSize: this.containerFontSize,
        fontWeight: this.containerFontWeight
      };
    }, "containerFont"),
    external_containerFont: /* @__PURE__ */ f(function() {
      return {
        fontFamily: this.external_containerFontFamily,
        fontSize: this.external_containerFontSize,
        fontWeight: this.external_containerFontWeight
      };
    }, "external_containerFont"),
    container_dbFont: /* @__PURE__ */ f(function() {
      return {
        fontFamily: this.container_dbFontFamily,
        fontSize: this.container_dbFontSize,
        fontWeight: this.container_dbFontWeight
      };
    }, "container_dbFont"),
    external_container_dbFont: /* @__PURE__ */ f(function() {
      return {
        fontFamily: this.external_container_dbFontFamily,
        fontSize: this.external_container_dbFontSize,
        fontWeight: this.external_container_dbFontWeight
      };
    }, "external_container_dbFont"),
    container_queueFont: /* @__PURE__ */ f(function() {
      return {
        fontFamily: this.container_queueFontFamily,
        fontSize: this.container_queueFontSize,
        fontWeight: this.container_queueFontWeight
      };
    }, "container_queueFont"),
    external_container_queueFont: /* @__PURE__ */ f(function() {
      return {
        fontFamily: this.external_container_queueFontFamily,
        fontSize: this.external_container_queueFontSize,
        fontWeight: this.external_container_queueFontWeight
      };
    }, "external_container_queueFont"),
    componentFont: /* @__PURE__ */ f(function() {
      return {
        fontFamily: this.componentFontFamily,
        fontSize: this.componentFontSize,
        fontWeight: this.componentFontWeight
      };
    }, "componentFont"),
    external_componentFont: /* @__PURE__ */ f(function() {
      return {
        fontFamily: this.external_componentFontFamily,
        fontSize: this.external_componentFontSize,
        fontWeight: this.external_componentFontWeight
      };
    }, "external_componentFont"),
    component_dbFont: /* @__PURE__ */ f(function() {
      return {
        fontFamily: this.component_dbFontFamily,
        fontSize: this.component_dbFontSize,
        fontWeight: this.component_dbFontWeight
      };
    }, "component_dbFont"),
    external_component_dbFont: /* @__PURE__ */ f(function() {
      return {
        fontFamily: this.external_component_dbFontFamily,
        fontSize: this.external_component_dbFontSize,
        fontWeight: this.external_component_dbFontWeight
      };
    }, "external_component_dbFont"),
    component_queueFont: /* @__PURE__ */ f(function() {
      return {
        fontFamily: this.component_queueFontFamily,
        fontSize: this.component_queueFontSize,
        fontWeight: this.component_queueFontWeight
      };
    }, "component_queueFont"),
    external_component_queueFont: /* @__PURE__ */ f(function() {
      return {
        fontFamily: this.external_component_queueFontFamily,
        fontSize: this.external_component_queueFontSize,
        fontWeight: this.external_component_queueFontWeight
      };
    }, "external_component_queueFont"),
    boundaryFont: /* @__PURE__ */ f(function() {
      return {
        fontFamily: this.boundaryFontFamily,
        fontSize: this.boundaryFontSize,
        fontWeight: this.boundaryFontWeight
      };
    }, "boundaryFont"),
    messageFont: /* @__PURE__ */ f(function() {
      return {
        fontFamily: this.messageFontFamily,
        fontSize: this.messageFontSize,
        fontWeight: this.messageFontWeight
      };
    }, "messageFont")
  },
  pie: {
    ...ae.pie,
    useWidth: 984
  },
  xyChart: {
    ...ae.xyChart,
    useWidth: void 0
  },
  requirement: {
    ...ae.requirement,
    useWidth: void 0
  },
  packet: {
    ...ae.packet
  },
  treeView: {
    ...ae.treeView,
    useWidth: void 0
  },
  radar: {
    ...ae.radar
  },
  ishikawa: {
    ...ae.ishikawa
  },
  treemap: {
    useMaxWidth: !0,
    padding: 10,
    diagramPadding: 8,
    showValues: !0,
    nodeWidth: 100,
    nodeHeight: 40,
    borderWidth: 1,
    valueFontSize: 12,
    labelFontSize: 14,
    valueFormat: ","
  },
  venn: {
    ...ae.venn
  }
}, Yc = /* @__PURE__ */ f((e, t = "") => Object.keys(e).reduce((r, i) => Array.isArray(e[i]) ? r : typeof e[i] == "object" && e[i] !== null ? [...r, t + i, ...Yc(e[i], "")] : [...r, t + i], []), "keyify"), jx = new Set(Yc(Hc, "")), Xc = Hc, Ys = /* @__PURE__ */ f((e) => {
  if (q.debug("sanitizeDirective called with", e), !(typeof e != "object" || e == null)) {
    if (Array.isArray(e)) {
      e.forEach((t) => Ys(t));
      return;
    }
    for (const t of Object.keys(e)) {
      if (q.debug("Checking key", t), t.startsWith("__") || t.includes("proto") || t.includes("constr") || !jx.has(t) || e[t] == null) {
        q.debug("sanitize deleting key: ", t), delete e[t];
        continue;
      }
      if (typeof e[t] == "object") {
        q.debug("sanitizing object", t), Ys(e[t]);
        continue;
      }
      const r = ["themeCSS", "fontFamily", "altFontFamily"];
      for (const i of r)
        t.includes(i) && (q.debug("sanitizing css option", t), e[t] = Gx(e[t]));
    }
    if (e.themeVariables)
      for (const t of Object.keys(e.themeVariables)) {
        const r = e.themeVariables[t];
        r != null && r.match && !r.match(/^[\d "#%(),.;A-Za-z]+$/) && (e.themeVariables[t] = "");
      }
    q.debug("After sanitization", e);
  }
}, "sanitizeDirective"), Gx = /* @__PURE__ */ f((e) => {
  let t = 0, r = 0;
  for (const i of e) {
    if (t < r)
      return "{ /* ERROR: Unbalanced CSS */ }";
    i === "{" ? t++ : i === "}" && r++;
  }
  return t !== r ? "{ /* ERROR: Unbalanced CSS */ }" : e;
}, "sanitizeCss"), li = Object.freeze(Xc), Ve = /* @__PURE__ */ f((e) => !(e === !1 || ["false", "null", "0"].includes(String(e).trim().toLowerCase())), "evaluate"), te = $t({}, li), Xs, Tr = [], zi = $t({}, li), ko = /* @__PURE__ */ f((e, t) => {
  let r = $t({}, e), i = {};
  for (const s of t)
    Gc(s), i = $t(i, s);
  if (r = $t(r, i), i.theme && i.theme in Ye) {
    const s = $t({}, Xs), o = $t(
      s.themeVariables || {},
      i.themeVariables
    );
    r.theme && r.theme in Ye && (r.themeVariables = Ye[r.theme].getThemeVariables(o));
  }
  return zi = r, Zc(zi), zi;
}, "updateCurrentConfig"), Vx = /* @__PURE__ */ f((e) => (te = $t({}, li), te = $t(te, e), e.theme && Ye[e.theme] && (te.themeVariables = Ye[e.theme].getThemeVariables(e.themeVariables)), ko(te, Tr), te), "setSiteConfig"), Zx = /* @__PURE__ */ f((e) => {
  Xs = $t({}, e);
}, "saveConfigFromInitialize"), Kx = /* @__PURE__ */ f((e) => (te = $t(te, e), ko(te, Tr), te), "updateSiteConfig"), Uc = /* @__PURE__ */ f(() => $t({}, te), "getSiteConfig"), jc = /* @__PURE__ */ f((e) => (Zc(e), $t(zi, e), wt()), "setConfig"), wt = /* @__PURE__ */ f(() => $t({}, zi), "getConfig"), Gc = /* @__PURE__ */ f((e) => {
  e && (["secure", ...te.secure ?? []].forEach((t) => {
    Object.hasOwn(e, t) && (q.debug(`Denied attempt to modify a secure key ${t}`, e[t]), delete e[t]);
  }), Object.keys(e).forEach((t) => {
    t.startsWith("__") && delete e[t];
  }), Object.keys(e).forEach((t) => {
    typeof e[t] == "string" && (e[t].includes("<") || e[t].includes(">") || e[t].includes("url(data:")) && delete e[t], typeof e[t] == "object" && Gc(e[t]);
  }));
}, "sanitize"), Qx = /* @__PURE__ */ f((e) => {
  var t;
  Ys(e), e.fontFamily && !((t = e.themeVariables) != null && t.fontFamily) && (e.themeVariables = {
    ...e.themeVariables,
    fontFamily: e.fontFamily
  }), Tr.push(e), ko(te, Tr);
}, "addDirective"), Us = /* @__PURE__ */ f((e = te) => {
  Tr = [], ko(e, Tr);
}, "reset"), Jx = {
  LAZY_LOAD_DEPRECATED: "The configuration options lazyLoadedDiagrams and loadExternalDiagramsAtStartup are deprecated. Please use registerExternalDiagrams instead.",
  FLOWCHART_HTML_LABELS_DEPRECATED: "flowchart.htmlLabels is deprecated. Please use global htmlLabels instead."
}, Jl = {}, Vc = /* @__PURE__ */ f((e) => {
  Jl[e] || (q.warn(Jx[e]), Jl[e] = !0);
}, "issueWarning"), Zc = /* @__PURE__ */ f((e) => {
  e && (e.lazyLoadedDiagrams || e.loadExternalDiagramsAtStartup) && Vc("LAZY_LOAD_DEPRECATED");
}, "checkConfig"), FL = /* @__PURE__ */ f(() => {
  let e = {};
  Xs && (e = $t(e, Xs));
  for (const t of Tr)
    e = $t(e, t);
  return e;
}, "getUserDefinedConfig"), Kt = /* @__PURE__ */ f((e) => {
  var t, r;
  return ((t = e.flowchart) == null ? void 0 : t.htmlLabels) != null && Vc("FLOWCHART_HTML_LABELS_DEPRECATED"), Ve(e.htmlLabels ?? ((r = e.flowchart) == null ? void 0 : r.htmlLabels) ?? !0);
}, "getEffectiveHtmlLabels"), ns = /<br\s*\/?>/gi, tC = /* @__PURE__ */ f((e) => e ? Jc(e).replace(/\\n/g, "#br#").split("#br#") : [""], "getRows"), eC = /* @__PURE__ */ (() => {
  let e = !1;
  return () => {
    e || (Kc(), e = !0);
  };
})();
function Kc() {
  const e = "data-temp-href-target";
  ni.addHook("beforeSanitizeAttributes", (t) => {
    t.tagName === "A" && t.hasAttribute("target") && t.setAttribute(e, t.getAttribute("target") ?? "");
  }), ni.addHook("afterSanitizeAttributes", (t) => {
    t.tagName === "A" && t.hasAttribute(e) && (t.setAttribute("target", t.getAttribute(e) ?? ""), t.removeAttribute(e), t.getAttribute("target") === "_blank" && t.setAttribute("rel", "noopener"));
  });
}
f(Kc, "setupDompurifyHooks");
var Qc = /* @__PURE__ */ f((e) => (eC(), ni.sanitize(e)), "removeScript"), th = /* @__PURE__ */ f((e, t) => {
  if (Kt(t)) {
    const r = t.securityLevel;
    r === "antiscript" || r === "strict" || r === "sandbox" ? e = Qc(e) : r !== "loose" && (e = Jc(e), e = e.replace(/</g, "&lt;").replace(/>/g, "&gt;"), e = e.replace(/=/g, "&equals;"), e = oC(e));
  }
  return e;
}, "sanitizeMore"), we = /* @__PURE__ */ f((e, t) => e && (t.dompurifyConfig ? e = ni.sanitize(th(e, t), t.dompurifyConfig).toString() : e = ni.sanitize(th(e, t), {
  FORBID_TAGS: ["style"]
}).toString(), e), "sanitizeText"), rC = /* @__PURE__ */ f((e, t) => typeof e == "string" ? we(e, t) : e.flat().map((r) => we(r, t)), "sanitizeTextOrArray"), iC = /* @__PURE__ */ f((e) => ns.test(e), "hasBreaks"), sC = /* @__PURE__ */ f((e) => e.split(ns), "splitBreaks"), oC = /* @__PURE__ */ f((e) => e.replace(/#br#/g, "<br/>"), "placeholderToBreak"), Jc = /* @__PURE__ */ f((e) => e.replace(ns, "#br#"), "breakToPlaceholder"), aC = /* @__PURE__ */ f((e) => {
  let t = "";
  return e && (t = window.location.protocol + "//" + window.location.host + window.location.pathname + window.location.search, t = CSS.escape(t)), t;
}, "getUrl"), nC = /* @__PURE__ */ f(function(...e) {
  const t = e.filter((r) => !isNaN(r));
  return Math.max(...t);
}, "getMax"), lC = /* @__PURE__ */ f(function(...e) {
  const t = e.filter((r) => !isNaN(r));
  return Math.min(...t);
}, "getMin"), eh = /* @__PURE__ */ f(function(e) {
  const t = e.split(/(,)/), r = [];
  for (let i = 0; i < t.length; i++) {
    let s = t[i];
    if (s === "," && i > 0 && i + 1 < t.length) {
      const o = t[i - 1], a = t[i + 1];
      hC(o, a) && (s = o + "," + a, i++, r.pop());
    }
    r.push(cC(s));
  }
  return r.join("");
}, "parseGenericTypes"), ka = /* @__PURE__ */ f((e, t) => Math.max(0, e.split(t).length - 1), "countOccurrence"), hC = /* @__PURE__ */ f((e, t) => {
  const r = ka(e, "~"), i = ka(t, "~");
  return r === 1 && i === 1;
}, "shouldCombineSets"), cC = /* @__PURE__ */ f((e) => {
  const t = ka(e, "~");
  let r = !1;
  if (t <= 1)
    return e;
  t % 2 !== 0 && e.startsWith("~") && (e = e.substring(1), r = !0);
  const i = [...e];
  let s = i.indexOf("~"), o = i.lastIndexOf("~");
  for (; s !== -1 && o !== -1 && s !== o; )
    i[s] = "<", i[o] = ">", s = i.indexOf("~"), o = i.lastIndexOf("~");
  return r && i.unshift("~"), i.join("");
}, "processSet"), rh = /* @__PURE__ */ f(() => window.MathMLElement !== void 0, "isMathMLSupported"), Ta = /\$\$(.*)\$\$/g, ji = /* @__PURE__ */ f((e) => {
  var t;
  return (((t = e.match(Ta)) == null ? void 0 : t.length) ?? 0) > 0;
}, "hasKatex"), ML = /* @__PURE__ */ f(async (e, t) => {
  const r = document.createElement("div");
  r.innerHTML = await tu(e, t), r.id = "katex-temp", r.style.visibility = "hidden", r.style.position = "absolute", r.style.top = "0";
  const i = document.querySelector("body");
  i == null || i.insertAdjacentElement("beforeend", r);
  const s = { width: r.clientWidth, height: r.clientHeight };
  return r.remove(), s;
}, "calculateMathMLDimensions"), uC = /* @__PURE__ */ f(async (e, t) => {
  if (!ji(e))
    return e;
  if (!(rh() || t.legacyMathML || t.forceLegacyMathML))
    return e.replace(Ta, "MathML is unsupported in this environment.");
  {
    const { default: r } = await import("./excalidraw-katex.js"), i = t.forceLegacyMathML || !rh() && t.legacyMathML ? "htmlAndMathml" : "mathml";
    return e.split(ns).map(
      (s) => ji(s) ? `<div style="display: flex; align-items: center; justify-content: center; white-space: nowrap;">${s}</div>` : `<div>${s}</div>`
    ).join("").replace(
      Ta,
      (s, o) => r.renderToString(o, {
        throwOnError: !0,
        displayMode: !0,
        output: i
      }).replace(/\n/g, " ").replace(/<annotation.*<\/annotation>/g, "")
    );
  }
}, "renderKatexUnsanitized"), tu = /* @__PURE__ */ f(async (e, t) => we(await uC(e, t), t), "renderKatexSanitized"), ls = {
  getRows: tC,
  sanitizeText: we,
  sanitizeTextOrArray: rC,
  hasBreaks: iC,
  splitBreaks: sC,
  lineBreakRegex: ns,
  removeScript: Qc,
  getUrl: aC,
  evaluate: Ve,
  getMax: nC,
  getMin: lC
}, dC = /* @__PURE__ */ f(function(e, t) {
  for (let r of t)
    e.attr(r[0], r[1]);
}, "d3Attrs"), pC = /* @__PURE__ */ f(function(e, t, r) {
  let i = /* @__PURE__ */ new Map();
  return r ? (i.set("width", "100%"), i.set("style", `max-width: ${t}px;`)) : (i.set("height", e), i.set("width", t)), i;
}, "calculateSvgSizeAttrs"), eu = /* @__PURE__ */ f(function(e, t, r, i) {
  const s = pC(t, r, i);
  dC(e, s);
}, "configureSvgSize"), fC = /* @__PURE__ */ f(function(e, t, r, i) {
  const s = t.node().getBBox(), o = s.width, a = s.height;
  q.info(`SVG bounds: ${o}x${a}`, s);
  let n = 0, l = 0;
  q.info(`Graph bounds: ${n}x${l}`, e), n = o + r * 2, l = a + r * 2, q.info(`Calculated bounds: ${n}x${l}`), eu(t, l, n, i);
  const h = `${s.x - r} ${s.y - r} ${s.width + 2 * r} ${s.height + 2 * r}`;
  t.attr("viewBox", h);
}, "setupGraphViewbox"), Os = {}, gC = /* @__PURE__ */ f((e, t, r, i) => {
  let s = "";
  return e in Os && Os[e] ? s = Os[e]({ ...r, svgId: i }) : q.warn(`No theme found for ${e}`), ` & {
    font-family: ${r.fontFamily};
    font-size: ${r.fontSize};
    fill: ${r.textColor}
  }
  @keyframes edge-animation-frame {
    from {
      stroke-dashoffset: 0;
    }
  }
  @keyframes dash {
    to {
      stroke-dashoffset: 0;
    }
  }
  & .edge-animation-slow {
    stroke-dasharray: 9,5 !important;
    stroke-dashoffset: 900;
    animation: dash 50s linear infinite;
    stroke-linecap: round;
  }
  & .edge-animation-fast {
    stroke-dasharray: 9,5 !important;
    stroke-dashoffset: 900;
    animation: dash 20s linear infinite;
    stroke-linecap: round;
  }
  /* Classes common for multiple diagrams */

  & .error-icon {
    fill: ${r.errorBkgColor};
  }
  & .error-text {
    fill: ${r.errorTextColor};
    stroke: ${r.errorTextColor};
  }

  & .edge-thickness-normal {
    stroke-width: ${r.strokeWidth ?? 1}px;
  }
  & .edge-thickness-thick {
    stroke-width: 3.5px
  }
  & .edge-pattern-solid {
    stroke-dasharray: 0;
  }
  & .edge-thickness-invisible {
    stroke-width: 0;
    fill: none;
  }
  & .edge-pattern-dashed{
    stroke-dasharray: 3;
  }
  .edge-pattern-dotted {
    stroke-dasharray: 2;
  }

  & .marker {
    fill: ${r.lineColor};
    stroke: ${r.lineColor};
  }
  & .marker.cross {
    stroke: ${r.lineColor};
  }

  & svg {
    font-family: ${r.fontFamily};
    font-size: ${r.fontSize};
  }
   & p {
    margin: 0
   }

  ${s}
  .node .neo-node {
    stroke: ${r.nodeBorder};
  }

  [data-look="neo"].node rect, [data-look="neo"].cluster rect, [data-look="neo"].node polygon {
    stroke: ${r.useGradient ? "url(" + i + "-gradient)" : r.nodeBorder};
    filter: ${r.dropShadow ? r.dropShadow.replace("url(#drop-shadow)", `url(${i}-drop-shadow)`) : "none"};
  }


  [data-look="neo"].node path {
    stroke: ${r.useGradient ? "url(" + i + "-gradient)" : r.nodeBorder};
    stroke-width: ${r.strokeWidth ?? 1}px;
  }

  [data-look="neo"].node .outer-path {
    filter: ${r.dropShadow ? r.dropShadow.replace("url(#drop-shadow)", `url(${i}-drop-shadow)`) : "none"};
  }

  [data-look="neo"].node .neo-line path {
    stroke: ${r.nodeBorder};
    filter: none;
  }

  [data-look="neo"].node circle{
    stroke: ${r.useGradient ? "url(" + i + "-gradient)" : r.nodeBorder};
    filter: ${r.dropShadow ? r.dropShadow.replace("url(#drop-shadow)", `url(${i}-drop-shadow)`) : "none"};
  }

  [data-look="neo"].node circle .state-start{
    fill: #000000;
  }

  [data-look="neo"].icon-shape .icon {
    fill: ${r.useGradient ? "url(" + i + "-gradient)" : r.nodeBorder};
    filter: ${r.dropShadow ? r.dropShadow.replace("url(#drop-shadow)", `url(${i}-drop-shadow)`) : "none"};
  }

    [data-look="neo"].icon-shape .icon-neo path {
    stroke: ${r.useGradient ? "url(" + i + "-gradient)" : r.nodeBorder};
    filter: ${r.dropShadow ? r.dropShadow.replace("url(#drop-shadow)", `url(${i}-drop-shadow)`) : "none"};
  }

  ${t}
`;
}, "getStyles"), mC = /* @__PURE__ */ f((e, t) => {
  t !== void 0 && (Os[e] = t);
}, "addStylesForDiagram"), yC = gC, ru = {};
Qy(ru, {
  clear: () => xC,
  getAccDescription: () => TC,
  getAccTitle: () => bC,
  getDiagramTitle: () => wC,
  setAccDescription: () => kC,
  setAccTitle: () => CC,
  setDiagramTitle: () => SC
});
var bn = "", kn = "", Tn = "", Sn = /* @__PURE__ */ f((e) => we(e, wt()), "sanitizeText"), xC = /* @__PURE__ */ f(() => {
  bn = "", Tn = "", kn = "";
}, "clear"), CC = /* @__PURE__ */ f((e) => {
  bn = Sn(e).replace(/^\s+/g, "");
}, "setAccTitle"), bC = /* @__PURE__ */ f(() => bn, "getAccTitle"), kC = /* @__PURE__ */ f((e) => {
  Tn = Sn(e).replace(/\n\s+/g, `
`);
}, "setAccDescription"), TC = /* @__PURE__ */ f(() => Tn, "getAccDescription"), SC = /* @__PURE__ */ f((e) => {
  kn = Sn(e);
}, "setDiagramTitle"), wC = /* @__PURE__ */ f(() => kn, "getDiagramTitle"), ih = q, _C = xn, gt = wt, IL = jc, $L = li, wn = /* @__PURE__ */ f((e) => we(e, gt()), "sanitizeText"), BC = fC, vC = /* @__PURE__ */ f(() => ru, "getCommonDb"), js = {}, Gs = /* @__PURE__ */ f((e, t, r) => {
  var i;
  js[e] && ih.warn(`Diagram with id ${e} already registered. Overwriting.`), js[e] = t, r && zc(e, r), mC(e, t.styles), (i = t.injectUtils) == null || i.call(
    t,
    ih,
    _C,
    gt,
    wn,
    BC,
    vC(),
    () => {
    }
  );
}, "registerDiagram"), Sa = /* @__PURE__ */ f((e) => {
  if (e in js)
    return js[e];
  throw new LC(e);
}, "getDiagram"), si, LC = (si = class extends Error {
  constructor(t) {
    super(`Diagram ${t} not found.`);
  }
}, f(si, "DiagramNotFoundError"), si), AC = { value: () => {
} };
function iu() {
  for (var e = 0, t = arguments.length, r = {}, i; e < t; ++e) {
    if (!(i = arguments[e] + "") || i in r || /[\s.]/.test(i)) throw new Error("illegal type: " + i);
    r[i] = [];
  }
  return new Ds(r);
}
function Ds(e) {
  this._ = e;
}
function EC(e, t) {
  return e.trim().split(/^|\s+/).map(function(r) {
    var i = "", s = r.indexOf(".");
    if (s >= 0 && (i = r.slice(s + 1), r = r.slice(0, s)), r && !t.hasOwnProperty(r)) throw new Error("unknown type: " + r);
    return { type: r, name: i };
  });
}
Ds.prototype = iu.prototype = {
  constructor: Ds,
  on: function(e, t) {
    var r = this._, i = EC(e + "", r), s, o = -1, a = i.length;
    if (arguments.length < 2) {
      for (; ++o < a; ) if ((s = (e = i[o]).type) && (s = FC(r[s], e.name))) return s;
      return;
    }
    if (t != null && typeof t != "function") throw new Error("invalid callback: " + t);
    for (; ++o < a; )
      if (s = (e = i[o]).type) r[s] = sh(r[s], e.name, t);
      else if (t == null) for (s in r) r[s] = sh(r[s], e.name, null);
    return this;
  },
  copy: function() {
    var e = {}, t = this._;
    for (var r in t) e[r] = t[r].slice();
    return new Ds(e);
  },
  call: function(e, t) {
    if ((s = arguments.length - 2) > 0) for (var r = new Array(s), i = 0, s, o; i < s; ++i) r[i] = arguments[i + 2];
    if (!this._.hasOwnProperty(e)) throw new Error("unknown type: " + e);
    for (o = this._[e], i = 0, s = o.length; i < s; ++i) o[i].value.apply(t, r);
  },
  apply: function(e, t, r) {
    if (!this._.hasOwnProperty(e)) throw new Error("unknown type: " + e);
    for (var i = this._[e], s = 0, o = i.length; s < o; ++s) i[s].value.apply(t, r);
  }
};
function FC(e, t) {
  for (var r = 0, i = e.length, s; r < i; ++r)
    if ((s = e[r]).name === t)
      return s.value;
}
function sh(e, t, r) {
  for (var i = 0, s = e.length; i < s; ++i)
    if (e[i].name === t) {
      e[i] = AC, e = e.slice(0, i).concat(e.slice(i + 1));
      break;
    }
  return r != null && e.push({ name: t, value: r }), e;
}
var wa = "http://www.w3.org/1999/xhtml";
const oh = {
  svg: "http://www.w3.org/2000/svg",
  xhtml: wa,
  xlink: "http://www.w3.org/1999/xlink",
  xml: "http://www.w3.org/XML/1998/namespace",
  xmlns: "http://www.w3.org/2000/xmlns/"
};
function To(e) {
  var t = e += "", r = t.indexOf(":");
  return r >= 0 && (t = e.slice(0, r)) !== "xmlns" && (e = e.slice(r + 1)), oh.hasOwnProperty(t) ? { space: oh[t], local: e } : e;
}
function MC(e) {
  return function() {
    var t = this.ownerDocument, r = this.namespaceURI;
    return r === wa && t.documentElement.namespaceURI === wa ? t.createElement(e) : t.createElementNS(r, e);
  };
}
function IC(e) {
  return function() {
    return this.ownerDocument.createElementNS(e.space, e.local);
  };
}
function su(e) {
  var t = To(e);
  return (t.local ? IC : MC)(t);
}
function $C() {
}
function _n(e) {
  return e == null ? $C : function() {
    return this.querySelector(e);
  };
}
function OC(e) {
  typeof e != "function" && (e = _n(e));
  for (var t = this._groups, r = t.length, i = new Array(r), s = 0; s < r; ++s)
    for (var o = t[s], a = o.length, n = i[s] = new Array(a), l, h, c = 0; c < a; ++c)
      (l = o[c]) && (h = e.call(l, l.__data__, c, o)) && ("__data__" in l && (h.__data__ = l.__data__), n[c] = h);
  return new le(i, this._parents);
}
function DC(e) {
  return e == null ? [] : Array.isArray(e) ? e : Array.from(e);
}
function RC() {
  return [];
}
function ou(e) {
  return e == null ? RC : function() {
    return this.querySelectorAll(e);
  };
}
function PC(e) {
  return function() {
    return DC(e.apply(this, arguments));
  };
}
function NC(e) {
  typeof e == "function" ? e = PC(e) : e = ou(e);
  for (var t = this._groups, r = t.length, i = [], s = [], o = 0; o < r; ++o)
    for (var a = t[o], n = a.length, l, h = 0; h < n; ++h)
      (l = a[h]) && (i.push(e.call(l, l.__data__, h, a)), s.push(l));
  return new le(i, s);
}
function au(e) {
  return function() {
    return this.matches(e);
  };
}
function nu(e) {
  return function(t) {
    return t.matches(e);
  };
}
var qC = Array.prototype.find;
function WC(e) {
  return function() {
    return qC.call(this.children, e);
  };
}
function zC() {
  return this.firstElementChild;
}
function HC(e) {
  return this.select(e == null ? zC : WC(typeof e == "function" ? e : nu(e)));
}
var YC = Array.prototype.filter;
function XC() {
  return Array.from(this.children);
}
function UC(e) {
  return function() {
    return YC.call(this.children, e);
  };
}
function jC(e) {
  return this.selectAll(e == null ? XC : UC(typeof e == "function" ? e : nu(e)));
}
function GC(e) {
  typeof e != "function" && (e = au(e));
  for (var t = this._groups, r = t.length, i = new Array(r), s = 0; s < r; ++s)
    for (var o = t[s], a = o.length, n = i[s] = [], l, h = 0; h < a; ++h)
      (l = o[h]) && e.call(l, l.__data__, h, o) && n.push(l);
  return new le(i, this._parents);
}
function lu(e) {
  return new Array(e.length);
}
function VC() {
  return new le(this._enter || this._groups.map(lu), this._parents);
}
function Vs(e, t) {
  this.ownerDocument = e.ownerDocument, this.namespaceURI = e.namespaceURI, this._next = null, this._parent = e, this.__data__ = t;
}
Vs.prototype = {
  constructor: Vs,
  appendChild: function(e) {
    return this._parent.insertBefore(e, this._next);
  },
  insertBefore: function(e, t) {
    return this._parent.insertBefore(e, t);
  },
  querySelector: function(e) {
    return this._parent.querySelector(e);
  },
  querySelectorAll: function(e) {
    return this._parent.querySelectorAll(e);
  }
};
function ZC(e) {
  return function() {
    return e;
  };
}
function KC(e, t, r, i, s, o) {
  for (var a = 0, n, l = t.length, h = o.length; a < h; ++a)
    (n = t[a]) ? (n.__data__ = o[a], i[a] = n) : r[a] = new Vs(e, o[a]);
  for (; a < l; ++a)
    (n = t[a]) && (s[a] = n);
}
function QC(e, t, r, i, s, o, a) {
  var n, l, h = /* @__PURE__ */ new Map(), c = t.length, u = o.length, p = new Array(c), d;
  for (n = 0; n < c; ++n)
    (l = t[n]) && (p[n] = d = a.call(l, l.__data__, n, t) + "", h.has(d) ? s[n] = l : h.set(d, l));
  for (n = 0; n < u; ++n)
    d = a.call(e, o[n], n, o) + "", (l = h.get(d)) ? (i[n] = l, l.__data__ = o[n], h.delete(d)) : r[n] = new Vs(e, o[n]);
  for (n = 0; n < c; ++n)
    (l = t[n]) && h.get(p[n]) === l && (s[n] = l);
}
function JC(e) {
  return e.__data__;
}
function t0(e, t) {
  if (!arguments.length) return Array.from(this, JC);
  var r = t ? QC : KC, i = this._parents, s = this._groups;
  typeof e != "function" && (e = ZC(e));
  for (var o = s.length, a = new Array(o), n = new Array(o), l = new Array(o), h = 0; h < o; ++h) {
    var c = i[h], u = s[h], p = u.length, d = e0(e.call(c, c && c.__data__, h, i)), g = d.length, m = n[h] = new Array(g), y = a[h] = new Array(g), x = l[h] = new Array(p);
    r(c, u, m, y, x, d, t);
    for (var b = 0, k = 0, w, S; b < g; ++b)
      if (w = m[b]) {
        for (b >= k && (k = b + 1); !(S = y[k]) && ++k < g; ) ;
        w._next = S || null;
      }
  }
  return a = new le(a, i), a._enter = n, a._exit = l, a;
}
function e0(e) {
  return typeof e == "object" && "length" in e ? e : Array.from(e);
}
function r0() {
  return new le(this._exit || this._groups.map(lu), this._parents);
}
function i0(e, t, r) {
  var i = this.enter(), s = this, o = this.exit();
  return typeof e == "function" ? (i = e(i), i && (i = i.selection())) : i = i.append(e + ""), t != null && (s = t(s), s && (s = s.selection())), r == null ? o.remove() : r(o), i && s ? i.merge(s).order() : s;
}
function s0(e) {
  for (var t = e.selection ? e.selection() : e, r = this._groups, i = t._groups, s = r.length, o = i.length, a = Math.min(s, o), n = new Array(s), l = 0; l < a; ++l)
    for (var h = r[l], c = i[l], u = h.length, p = n[l] = new Array(u), d, g = 0; g < u; ++g)
      (d = h[g] || c[g]) && (p[g] = d);
  for (; l < s; ++l)
    n[l] = r[l];
  return new le(n, this._parents);
}
function o0() {
  for (var e = this._groups, t = -1, r = e.length; ++t < r; )
    for (var i = e[t], s = i.length - 1, o = i[s], a; --s >= 0; )
      (a = i[s]) && (o && a.compareDocumentPosition(o) ^ 4 && o.parentNode.insertBefore(a, o), o = a);
  return this;
}
function a0(e) {
  e || (e = n0);
  function t(u, p) {
    return u && p ? e(u.__data__, p.__data__) : !u - !p;
  }
  for (var r = this._groups, i = r.length, s = new Array(i), o = 0; o < i; ++o) {
    for (var a = r[o], n = a.length, l = s[o] = new Array(n), h, c = 0; c < n; ++c)
      (h = a[c]) && (l[c] = h);
    l.sort(t);
  }
  return new le(s, this._parents).order();
}
function n0(e, t) {
  return e < t ? -1 : e > t ? 1 : e >= t ? 0 : NaN;
}
function l0() {
  var e = arguments[0];
  return arguments[0] = this, e.apply(null, arguments), this;
}
function h0() {
  return Array.from(this);
}
function c0() {
  for (var e = this._groups, t = 0, r = e.length; t < r; ++t)
    for (var i = e[t], s = 0, o = i.length; s < o; ++s) {
      var a = i[s];
      if (a) return a;
    }
  return null;
}
function u0() {
  let e = 0;
  for (const t of this) ++e;
  return e;
}
function d0() {
  return !this.node();
}
function p0(e) {
  for (var t = this._groups, r = 0, i = t.length; r < i; ++r)
    for (var s = t[r], o = 0, a = s.length, n; o < a; ++o)
      (n = s[o]) && e.call(n, n.__data__, o, s);
  return this;
}
function f0(e) {
  return function() {
    this.removeAttribute(e);
  };
}
function g0(e) {
  return function() {
    this.removeAttributeNS(e.space, e.local);
  };
}
function m0(e, t) {
  return function() {
    this.setAttribute(e, t);
  };
}
function y0(e, t) {
  return function() {
    this.setAttributeNS(e.space, e.local, t);
  };
}
function x0(e, t) {
  return function() {
    var r = t.apply(this, arguments);
    r == null ? this.removeAttribute(e) : this.setAttribute(e, r);
  };
}
function C0(e, t) {
  return function() {
    var r = t.apply(this, arguments);
    r == null ? this.removeAttributeNS(e.space, e.local) : this.setAttributeNS(e.space, e.local, r);
  };
}
function b0(e, t) {
  var r = To(e);
  if (arguments.length < 2) {
    var i = this.node();
    return r.local ? i.getAttributeNS(r.space, r.local) : i.getAttribute(r);
  }
  return this.each((t == null ? r.local ? g0 : f0 : typeof t == "function" ? r.local ? C0 : x0 : r.local ? y0 : m0)(r, t));
}
function hu(e) {
  return e.ownerDocument && e.ownerDocument.defaultView || e.document && e || e.defaultView;
}
function k0(e) {
  return function() {
    this.style.removeProperty(e);
  };
}
function T0(e, t, r) {
  return function() {
    this.style.setProperty(e, t, r);
  };
}
function S0(e, t, r) {
  return function() {
    var i = t.apply(this, arguments);
    i == null ? this.style.removeProperty(e) : this.style.setProperty(e, i, r);
  };
}
function w0(e, t, r) {
  return arguments.length > 1 ? this.each((t == null ? k0 : typeof t == "function" ? S0 : T0)(e, t, r ?? "")) : hi(this.node(), e);
}
function hi(e, t) {
  return e.style.getPropertyValue(t) || hu(e).getComputedStyle(e, null).getPropertyValue(t);
}
function _0(e) {
  return function() {
    delete this[e];
  };
}
function B0(e, t) {
  return function() {
    this[e] = t;
  };
}
function v0(e, t) {
  return function() {
    var r = t.apply(this, arguments);
    r == null ? delete this[e] : this[e] = r;
  };
}
function L0(e, t) {
  return arguments.length > 1 ? this.each((t == null ? _0 : typeof t == "function" ? v0 : B0)(e, t)) : this.node()[e];
}
function cu(e) {
  return e.trim().split(/^|\s+/);
}
function Bn(e) {
  return e.classList || new uu(e);
}
function uu(e) {
  this._node = e, this._names = cu(e.getAttribute("class") || "");
}
uu.prototype = {
  add: function(e) {
    var t = this._names.indexOf(e);
    t < 0 && (this._names.push(e), this._node.setAttribute("class", this._names.join(" ")));
  },
  remove: function(e) {
    var t = this._names.indexOf(e);
    t >= 0 && (this._names.splice(t, 1), this._node.setAttribute("class", this._names.join(" ")));
  },
  contains: function(e) {
    return this._names.indexOf(e) >= 0;
  }
};
function du(e, t) {
  for (var r = Bn(e), i = -1, s = t.length; ++i < s; ) r.add(t[i]);
}
function pu(e, t) {
  for (var r = Bn(e), i = -1, s = t.length; ++i < s; ) r.remove(t[i]);
}
function A0(e) {
  return function() {
    du(this, e);
  };
}
function E0(e) {
  return function() {
    pu(this, e);
  };
}
function F0(e, t) {
  return function() {
    (t.apply(this, arguments) ? du : pu)(this, e);
  };
}
function M0(e, t) {
  var r = cu(e + "");
  if (arguments.length < 2) {
    for (var i = Bn(this.node()), s = -1, o = r.length; ++s < o; ) if (!i.contains(r[s])) return !1;
    return !0;
  }
  return this.each((typeof t == "function" ? F0 : t ? A0 : E0)(r, t));
}
function I0() {
  this.textContent = "";
}
function $0(e) {
  return function() {
    this.textContent = e;
  };
}
function O0(e) {
  return function() {
    var t = e.apply(this, arguments);
    this.textContent = t ?? "";
  };
}
function D0(e) {
  return arguments.length ? this.each(e == null ? I0 : (typeof e == "function" ? O0 : $0)(e)) : this.node().textContent;
}
function R0() {
  this.innerHTML = "";
}
function P0(e) {
  return function() {
    this.innerHTML = e;
  };
}
function N0(e) {
  return function() {
    var t = e.apply(this, arguments);
    this.innerHTML = t ?? "";
  };
}
function q0(e) {
  return arguments.length ? this.each(e == null ? R0 : (typeof e == "function" ? N0 : P0)(e)) : this.node().innerHTML;
}
function W0() {
  this.nextSibling && this.parentNode.appendChild(this);
}
function z0() {
  return this.each(W0);
}
function H0() {
  this.previousSibling && this.parentNode.insertBefore(this, this.parentNode.firstChild);
}
function Y0() {
  return this.each(H0);
}
function X0(e) {
  var t = typeof e == "function" ? e : su(e);
  return this.select(function() {
    return this.appendChild(t.apply(this, arguments));
  });
}
function U0() {
  return null;
}
function j0(e, t) {
  var r = typeof e == "function" ? e : su(e), i = t == null ? U0 : typeof t == "function" ? t : _n(t);
  return this.select(function() {
    return this.insertBefore(r.apply(this, arguments), i.apply(this, arguments) || null);
  });
}
function G0() {
  var e = this.parentNode;
  e && e.removeChild(this);
}
function V0() {
  return this.each(G0);
}
function Z0() {
  var e = this.cloneNode(!1), t = this.parentNode;
  return t ? t.insertBefore(e, this.nextSibling) : e;
}
function K0() {
  var e = this.cloneNode(!0), t = this.parentNode;
  return t ? t.insertBefore(e, this.nextSibling) : e;
}
function Q0(e) {
  return this.select(e ? K0 : Z0);
}
function J0(e) {
  return arguments.length ? this.property("__data__", e) : this.node().__data__;
}
function tb(e) {
  return function(t) {
    e.call(this, t, this.__data__);
  };
}
function eb(e) {
  return e.trim().split(/^|\s+/).map(function(t) {
    var r = "", i = t.indexOf(".");
    return i >= 0 && (r = t.slice(i + 1), t = t.slice(0, i)), { type: t, name: r };
  });
}
function rb(e) {
  return function() {
    var t = this.__on;
    if (t) {
      for (var r = 0, i = -1, s = t.length, o; r < s; ++r)
        o = t[r], (!e.type || o.type === e.type) && o.name === e.name ? this.removeEventListener(o.type, o.listener, o.options) : t[++i] = o;
      ++i ? t.length = i : delete this.__on;
    }
  };
}
function ib(e, t, r) {
  return function() {
    var i = this.__on, s, o = tb(t);
    if (i) {
      for (var a = 0, n = i.length; a < n; ++a)
        if ((s = i[a]).type === e.type && s.name === e.name) {
          this.removeEventListener(s.type, s.listener, s.options), this.addEventListener(s.type, s.listener = o, s.options = r), s.value = t;
          return;
        }
    }
    this.addEventListener(e.type, o, r), s = { type: e.type, name: e.name, value: t, listener: o, options: r }, i ? i.push(s) : this.__on = [s];
  };
}
function sb(e, t, r) {
  var i = eb(e + ""), s, o = i.length, a;
  if (arguments.length < 2) {
    var n = this.node().__on;
    if (n) {
      for (var l = 0, h = n.length, c; l < h; ++l)
        for (s = 0, c = n[l]; s < o; ++s)
          if ((a = i[s]).type === c.type && a.name === c.name)
            return c.value;
    }
    return;
  }
  for (n = t ? ib : rb, s = 0; s < o; ++s) this.each(n(i[s], t, r));
  return this;
}
function fu(e, t, r) {
  var i = hu(e), s = i.CustomEvent;
  typeof s == "function" ? s = new s(t, r) : (s = i.document.createEvent("Event"), r ? (s.initEvent(t, r.bubbles, r.cancelable), s.detail = r.detail) : s.initEvent(t, !1, !1)), e.dispatchEvent(s);
}
function ob(e, t) {
  return function() {
    return fu(this, e, t);
  };
}
function ab(e, t) {
  return function() {
    return fu(this, e, t.apply(this, arguments));
  };
}
function nb(e, t) {
  return this.each((typeof t == "function" ? ab : ob)(e, t));
}
function* lb() {
  for (var e = this._groups, t = 0, r = e.length; t < r; ++t)
    for (var i = e[t], s = 0, o = i.length, a; s < o; ++s)
      (a = i[s]) && (yield a);
}
var gu = [null];
function le(e, t) {
  this._groups = e, this._parents = t;
}
function hs() {
  return new le([[document.documentElement]], gu);
}
function hb() {
  return this;
}
le.prototype = hs.prototype = {
  constructor: le,
  select: OC,
  selectAll: NC,
  selectChild: HC,
  selectChildren: jC,
  filter: GC,
  data: t0,
  enter: VC,
  exit: r0,
  join: i0,
  merge: s0,
  selection: hb,
  order: o0,
  sort: a0,
  call: l0,
  nodes: h0,
  node: c0,
  size: u0,
  empty: d0,
  each: p0,
  attr: b0,
  style: w0,
  property: L0,
  classed: M0,
  text: D0,
  html: q0,
  raise: z0,
  lower: Y0,
  append: X0,
  insert: j0,
  remove: V0,
  clone: Q0,
  datum: J0,
  on: sb,
  dispatch: nb,
  [Symbol.iterator]: lb
};
function ct(e) {
  return typeof e == "string" ? new le([[document.querySelector(e)]], [document.documentElement]) : new le([[e]], gu);
}
function vn(e, t, r) {
  e.prototype = t.prototype = r, r.constructor = e;
}
function mu(e, t) {
  var r = Object.create(e.prototype);
  for (var i in t) r[i] = t[i];
  return r;
}
function cs() {
}
var Gi = 0.7, Zs = 1 / Gi, Yr = "\\s*([+-]?\\d+)\\s*", Vi = "\\s*([+-]?(?:\\d*\\.)?\\d+(?:[eE][+-]?\\d+)?)\\s*", $e = "\\s*([+-]?(?:\\d*\\.)?\\d+(?:[eE][+-]?\\d+)?)%\\s*", cb = /^#([0-9a-f]{3,8})$/, ub = new RegExp(`^rgb\\(${Yr},${Yr},${Yr}\\)$`), db = new RegExp(`^rgb\\(${$e},${$e},${$e}\\)$`), pb = new RegExp(`^rgba\\(${Yr},${Yr},${Yr},${Vi}\\)$`), fb = new RegExp(`^rgba\\(${$e},${$e},${$e},${Vi}\\)$`), gb = new RegExp(`^hsl\\(${Vi},${$e},${$e}\\)$`), mb = new RegExp(`^hsla\\(${Vi},${$e},${$e},${Vi}\\)$`), ah = {
  aliceblue: 15792383,
  antiquewhite: 16444375,
  aqua: 65535,
  aquamarine: 8388564,
  azure: 15794175,
  beige: 16119260,
  bisque: 16770244,
  black: 0,
  blanchedalmond: 16772045,
  blue: 255,
  blueviolet: 9055202,
  brown: 10824234,
  burlywood: 14596231,
  cadetblue: 6266528,
  chartreuse: 8388352,
  chocolate: 13789470,
  coral: 16744272,
  cornflowerblue: 6591981,
  cornsilk: 16775388,
  crimson: 14423100,
  cyan: 65535,
  darkblue: 139,
  darkcyan: 35723,
  darkgoldenrod: 12092939,
  darkgray: 11119017,
  darkgreen: 25600,
  darkgrey: 11119017,
  darkkhaki: 12433259,
  darkmagenta: 9109643,
  darkolivegreen: 5597999,
  darkorange: 16747520,
  darkorchid: 10040012,
  darkred: 9109504,
  darksalmon: 15308410,
  darkseagreen: 9419919,
  darkslateblue: 4734347,
  darkslategray: 3100495,
  darkslategrey: 3100495,
  darkturquoise: 52945,
  darkviolet: 9699539,
  deeppink: 16716947,
  deepskyblue: 49151,
  dimgray: 6908265,
  dimgrey: 6908265,
  dodgerblue: 2003199,
  firebrick: 11674146,
  floralwhite: 16775920,
  forestgreen: 2263842,
  fuchsia: 16711935,
  gainsboro: 14474460,
  ghostwhite: 16316671,
  gold: 16766720,
  goldenrod: 14329120,
  gray: 8421504,
  green: 32768,
  greenyellow: 11403055,
  grey: 8421504,
  honeydew: 15794160,
  hotpink: 16738740,
  indianred: 13458524,
  indigo: 4915330,
  ivory: 16777200,
  khaki: 15787660,
  lavender: 15132410,
  lavenderblush: 16773365,
  lawngreen: 8190976,
  lemonchiffon: 16775885,
  lightblue: 11393254,
  lightcoral: 15761536,
  lightcyan: 14745599,
  lightgoldenrodyellow: 16448210,
  lightgray: 13882323,
  lightgreen: 9498256,
  lightgrey: 13882323,
  lightpink: 16758465,
  lightsalmon: 16752762,
  lightseagreen: 2142890,
  lightskyblue: 8900346,
  lightslategray: 7833753,
  lightslategrey: 7833753,
  lightsteelblue: 11584734,
  lightyellow: 16777184,
  lime: 65280,
  limegreen: 3329330,
  linen: 16445670,
  magenta: 16711935,
  maroon: 8388608,
  mediumaquamarine: 6737322,
  mediumblue: 205,
  mediumorchid: 12211667,
  mediumpurple: 9662683,
  mediumseagreen: 3978097,
  mediumslateblue: 8087790,
  mediumspringgreen: 64154,
  mediumturquoise: 4772300,
  mediumvioletred: 13047173,
  midnightblue: 1644912,
  mintcream: 16121850,
  mistyrose: 16770273,
  moccasin: 16770229,
  navajowhite: 16768685,
  navy: 128,
  oldlace: 16643558,
  olive: 8421376,
  olivedrab: 7048739,
  orange: 16753920,
  orangered: 16729344,
  orchid: 14315734,
  palegoldenrod: 15657130,
  palegreen: 10025880,
  paleturquoise: 11529966,
  palevioletred: 14381203,
  papayawhip: 16773077,
  peachpuff: 16767673,
  peru: 13468991,
  pink: 16761035,
  plum: 14524637,
  powderblue: 11591910,
  purple: 8388736,
  rebeccapurple: 6697881,
  red: 16711680,
  rosybrown: 12357519,
  royalblue: 4286945,
  saddlebrown: 9127187,
  salmon: 16416882,
  sandybrown: 16032864,
  seagreen: 3050327,
  seashell: 16774638,
  sienna: 10506797,
  silver: 12632256,
  skyblue: 8900331,
  slateblue: 6970061,
  slategray: 7372944,
  slategrey: 7372944,
  snow: 16775930,
  springgreen: 65407,
  steelblue: 4620980,
  tan: 13808780,
  teal: 32896,
  thistle: 14204888,
  tomato: 16737095,
  turquoise: 4251856,
  violet: 15631086,
  wheat: 16113331,
  white: 16777215,
  whitesmoke: 16119285,
  yellow: 16776960,
  yellowgreen: 10145074
};
vn(cs, Zi, {
  copy(e) {
    return Object.assign(new this.constructor(), this, e);
  },
  displayable() {
    return this.rgb().displayable();
  },
  hex: nh,
  // Deprecated! Use color.formatHex.
  formatHex: nh,
  formatHex8: yb,
  formatHsl: xb,
  formatRgb: lh,
  toString: lh
});
function nh() {
  return this.rgb().formatHex();
}
function yb() {
  return this.rgb().formatHex8();
}
function xb() {
  return yu(this).formatHsl();
}
function lh() {
  return this.rgb().formatRgb();
}
function Zi(e) {
  var t, r;
  return e = (e + "").trim().toLowerCase(), (t = cb.exec(e)) ? (r = t[1].length, t = parseInt(t[1], 16), r === 6 ? hh(t) : r === 3 ? new re(t >> 8 & 15 | t >> 4 & 240, t >> 4 & 15 | t & 240, (t & 15) << 4 | t & 15, 1) : r === 8 ? ws(t >> 24 & 255, t >> 16 & 255, t >> 8 & 255, (t & 255) / 255) : r === 4 ? ws(t >> 12 & 15 | t >> 8 & 240, t >> 8 & 15 | t >> 4 & 240, t >> 4 & 15 | t & 240, ((t & 15) << 4 | t & 15) / 255) : null) : (t = ub.exec(e)) ? new re(t[1], t[2], t[3], 1) : (t = db.exec(e)) ? new re(t[1] * 255 / 100, t[2] * 255 / 100, t[3] * 255 / 100, 1) : (t = pb.exec(e)) ? ws(t[1], t[2], t[3], t[4]) : (t = fb.exec(e)) ? ws(t[1] * 255 / 100, t[2] * 255 / 100, t[3] * 255 / 100, t[4]) : (t = gb.exec(e)) ? dh(t[1], t[2] / 100, t[3] / 100, 1) : (t = mb.exec(e)) ? dh(t[1], t[2] / 100, t[3] / 100, t[4]) : ah.hasOwnProperty(e) ? hh(ah[e]) : e === "transparent" ? new re(NaN, NaN, NaN, 0) : null;
}
function hh(e) {
  return new re(e >> 16 & 255, e >> 8 & 255, e & 255, 1);
}
function ws(e, t, r, i) {
  return i <= 0 && (e = t = r = NaN), new re(e, t, r, i);
}
function Cb(e) {
  return e instanceof cs || (e = Zi(e)), e ? (e = e.rgb(), new re(e.r, e.g, e.b, e.opacity)) : new re();
}
function _a(e, t, r, i) {
  return arguments.length === 1 ? Cb(e) : new re(e, t, r, i ?? 1);
}
function re(e, t, r, i) {
  this.r = +e, this.g = +t, this.b = +r, this.opacity = +i;
}
vn(re, _a, mu(cs, {
  brighter(e) {
    return e = e == null ? Zs : Math.pow(Zs, e), new re(this.r * e, this.g * e, this.b * e, this.opacity);
  },
  darker(e) {
    return e = e == null ? Gi : Math.pow(Gi, e), new re(this.r * e, this.g * e, this.b * e, this.opacity);
  },
  rgb() {
    return this;
  },
  clamp() {
    return new re(Cr(this.r), Cr(this.g), Cr(this.b), Ks(this.opacity));
  },
  displayable() {
    return -0.5 <= this.r && this.r < 255.5 && -0.5 <= this.g && this.g < 255.5 && -0.5 <= this.b && this.b < 255.5 && 0 <= this.opacity && this.opacity <= 1;
  },
  hex: ch,
  // Deprecated! Use color.formatHex.
  formatHex: ch,
  formatHex8: bb,
  formatRgb: uh,
  toString: uh
}));
function ch() {
  return `#${dr(this.r)}${dr(this.g)}${dr(this.b)}`;
}
function bb() {
  return `#${dr(this.r)}${dr(this.g)}${dr(this.b)}${dr((isNaN(this.opacity) ? 1 : this.opacity) * 255)}`;
}
function uh() {
  const e = Ks(this.opacity);
  return `${e === 1 ? "rgb(" : "rgba("}${Cr(this.r)}, ${Cr(this.g)}, ${Cr(this.b)}${e === 1 ? ")" : `, ${e})`}`;
}
function Ks(e) {
  return isNaN(e) ? 1 : Math.max(0, Math.min(1, e));
}
function Cr(e) {
  return Math.max(0, Math.min(255, Math.round(e) || 0));
}
function dr(e) {
  return e = Cr(e), (e < 16 ? "0" : "") + e.toString(16);
}
function dh(e, t, r, i) {
  return i <= 0 ? e = t = r = NaN : r <= 0 || r >= 1 ? e = t = NaN : t <= 0 && (e = NaN), new be(e, t, r, i);
}
function yu(e) {
  if (e instanceof be) return new be(e.h, e.s, e.l, e.opacity);
  if (e instanceof cs || (e = Zi(e)), !e) return new be();
  if (e instanceof be) return e;
  e = e.rgb();
  var t = e.r / 255, r = e.g / 255, i = e.b / 255, s = Math.min(t, r, i), o = Math.max(t, r, i), a = NaN, n = o - s, l = (o + s) / 2;
  return n ? (t === o ? a = (r - i) / n + (r < i) * 6 : r === o ? a = (i - t) / n + 2 : a = (t - r) / n + 4, n /= l < 0.5 ? o + s : 2 - o - s, a *= 60) : n = l > 0 && l < 1 ? 0 : a, new be(a, n, l, e.opacity);
}
function kb(e, t, r, i) {
  return arguments.length === 1 ? yu(e) : new be(e, t, r, i ?? 1);
}
function be(e, t, r, i) {
  this.h = +e, this.s = +t, this.l = +r, this.opacity = +i;
}
vn(be, kb, mu(cs, {
  brighter(e) {
    return e = e == null ? Zs : Math.pow(Zs, e), new be(this.h, this.s, this.l * e, this.opacity);
  },
  darker(e) {
    return e = e == null ? Gi : Math.pow(Gi, e), new be(this.h, this.s, this.l * e, this.opacity);
  },
  rgb() {
    var e = this.h % 360 + (this.h < 0) * 360, t = isNaN(e) || isNaN(this.s) ? 0 : this.s, r = this.l, i = r + (r < 0.5 ? r : 1 - r) * t, s = 2 * r - i;
    return new re(
      ra(e >= 240 ? e - 240 : e + 120, s, i),
      ra(e, s, i),
      ra(e < 120 ? e + 240 : e - 120, s, i),
      this.opacity
    );
  },
  clamp() {
    return new be(ph(this.h), _s(this.s), _s(this.l), Ks(this.opacity));
  },
  displayable() {
    return (0 <= this.s && this.s <= 1 || isNaN(this.s)) && 0 <= this.l && this.l <= 1 && 0 <= this.opacity && this.opacity <= 1;
  },
  formatHsl() {
    const e = Ks(this.opacity);
    return `${e === 1 ? "hsl(" : "hsla("}${ph(this.h)}, ${_s(this.s) * 100}%, ${_s(this.l) * 100}%${e === 1 ? ")" : `, ${e})`}`;
  }
}));
function ph(e) {
  return e = (e || 0) % 360, e < 0 ? e + 360 : e;
}
function _s(e) {
  return Math.max(0, Math.min(1, e || 0));
}
function ra(e, t, r) {
  return (e < 60 ? t + (r - t) * e / 60 : e < 180 ? r : e < 240 ? t + (r - t) * (240 - e) / 60 : t) * 255;
}
const Ln = (e) => () => e;
function xu(e, t) {
  return function(r) {
    return e + r * t;
  };
}
function Tb(e, t, r) {
  return e = Math.pow(e, r), t = Math.pow(t, r) - e, r = 1 / r, function(i) {
    return Math.pow(e + i * t, r);
  };
}
function OL(e, t) {
  var r = t - e;
  return r ? xu(e, r > 180 || r < -180 ? r - 360 * Math.round(r / 360) : r) : Ln(isNaN(e) ? t : e);
}
function Sb(e) {
  return (e = +e) == 1 ? Cu : function(t, r) {
    return r - t ? Tb(t, r, e) : Ln(isNaN(t) ? r : t);
  };
}
function Cu(e, t) {
  var r = t - e;
  return r ? xu(e, r) : Ln(isNaN(e) ? t : e);
}
const fh = (function e(t) {
  var r = Sb(t);
  function i(s, o) {
    var a = r((s = _a(s)).r, (o = _a(o)).r), n = r(s.g, o.g), l = r(s.b, o.b), h = Cu(s.opacity, o.opacity);
    return function(c) {
      return s.r = a(c), s.g = n(c), s.b = l(c), s.opacity = h(c), s + "";
    };
  }
  return i.gamma = e, i;
})(1);
function Qe(e, t) {
  return e = +e, t = +t, function(r) {
    return e * (1 - r) + t * r;
  };
}
var Ba = /[-+]?(?:\d+\.?\d*|\.?\d+)(?:[eE][-+]?\d+)?/g, ia = new RegExp(Ba.source, "g");
function wb(e) {
  return function() {
    return e;
  };
}
function _b(e) {
  return function(t) {
    return e(t) + "";
  };
}
function Bb(e, t) {
  var r = Ba.lastIndex = ia.lastIndex = 0, i, s, o, a = -1, n = [], l = [];
  for (e = e + "", t = t + ""; (i = Ba.exec(e)) && (s = ia.exec(t)); )
    (o = s.index) > r && (o = t.slice(r, o), n[a] ? n[a] += o : n[++a] = o), (i = i[0]) === (s = s[0]) ? n[a] ? n[a] += s : n[++a] = s : (n[++a] = null, l.push({ i: a, x: Qe(i, s) })), r = ia.lastIndex;
  return r < t.length && (o = t.slice(r), n[a] ? n[a] += o : n[++a] = o), n.length < 2 ? l[0] ? _b(l[0].x) : wb(t) : (t = l.length, function(h) {
    for (var c = 0, u; c < t; ++c) n[(u = l[c]).i] = u.x(h);
    return n.join("");
  });
}
var gh = 180 / Math.PI, va = {
  translateX: 0,
  translateY: 0,
  rotate: 0,
  skewX: 0,
  scaleX: 1,
  scaleY: 1
};
function bu(e, t, r, i, s, o) {
  var a, n, l;
  return (a = Math.sqrt(e * e + t * t)) && (e /= a, t /= a), (l = e * r + t * i) && (r -= e * l, i -= t * l), (n = Math.sqrt(r * r + i * i)) && (r /= n, i /= n, l /= n), e * i < t * r && (e = -e, t = -t, l = -l, a = -a), {
    translateX: s,
    translateY: o,
    rotate: Math.atan2(t, e) * gh,
    skewX: Math.atan(l) * gh,
    scaleX: a,
    scaleY: n
  };
}
var Bs;
function vb(e) {
  const t = new (typeof DOMMatrix == "function" ? DOMMatrix : WebKitCSSMatrix)(e + "");
  return t.isIdentity ? va : bu(t.a, t.b, t.c, t.d, t.e, t.f);
}
function Lb(e) {
  return e == null || (Bs || (Bs = document.createElementNS("http://www.w3.org/2000/svg", "g")), Bs.setAttribute("transform", e), !(e = Bs.transform.baseVal.consolidate())) ? va : (e = e.matrix, bu(e.a, e.b, e.c, e.d, e.e, e.f));
}
function ku(e, t, r, i) {
  function s(h) {
    return h.length ? h.pop() + " " : "";
  }
  function o(h, c, u, p, d, g) {
    if (h !== u || c !== p) {
      var m = d.push("translate(", null, t, null, r);
      g.push({ i: m - 4, x: Qe(h, u) }, { i: m - 2, x: Qe(c, p) });
    } else (u || p) && d.push("translate(" + u + t + p + r);
  }
  function a(h, c, u, p) {
    h !== c ? (h - c > 180 ? c += 360 : c - h > 180 && (h += 360), p.push({ i: u.push(s(u) + "rotate(", null, i) - 2, x: Qe(h, c) })) : c && u.push(s(u) + "rotate(" + c + i);
  }
  function n(h, c, u, p) {
    h !== c ? p.push({ i: u.push(s(u) + "skewX(", null, i) - 2, x: Qe(h, c) }) : c && u.push(s(u) + "skewX(" + c + i);
  }
  function l(h, c, u, p, d, g) {
    if (h !== u || c !== p) {
      var m = d.push(s(d) + "scale(", null, ",", null, ")");
      g.push({ i: m - 4, x: Qe(h, u) }, { i: m - 2, x: Qe(c, p) });
    } else (u !== 1 || p !== 1) && d.push(s(d) + "scale(" + u + "," + p + ")");
  }
  return function(h, c) {
    var u = [], p = [];
    return h = e(h), c = e(c), o(h.translateX, h.translateY, c.translateX, c.translateY, u, p), a(h.rotate, c.rotate, u, p), n(h.skewX, c.skewX, u, p), l(h.scaleX, h.scaleY, c.scaleX, c.scaleY, u, p), h = c = null, function(d) {
      for (var g = -1, m = p.length, y; ++g < m; ) u[(y = p[g]).i] = y.x(d);
      return u.join("");
    };
  };
}
var Ab = ku(vb, "px, ", "px)", "deg)"), Eb = ku(Lb, ", ", ")", ")"), ci = 0, Ii = 0, Bi = 0, Tu = 1e3, Qs, $i, Js = 0, Sr = 0, So = 0, Ki = typeof performance == "object" && performance.now ? performance : Date, Su = typeof window == "object" && window.requestAnimationFrame ? window.requestAnimationFrame.bind(window) : function(e) {
  setTimeout(e, 17);
};
function An() {
  return Sr || (Su(Fb), Sr = Ki.now() + So);
}
function Fb() {
  Sr = 0;
}
function to() {
  this._call = this._time = this._next = null;
}
to.prototype = wu.prototype = {
  constructor: to,
  restart: function(e, t, r) {
    if (typeof e != "function") throw new TypeError("callback is not a function");
    r = (r == null ? An() : +r) + (t == null ? 0 : +t), !this._next && $i !== this && ($i ? $i._next = this : Qs = this, $i = this), this._call = e, this._time = r, La();
  },
  stop: function() {
    this._call && (this._call = null, this._time = 1 / 0, La());
  }
};
function wu(e, t, r) {
  var i = new to();
  return i.restart(e, t, r), i;
}
function Mb() {
  An(), ++ci;
  for (var e = Qs, t; e; )
    (t = Sr - e._time) >= 0 && e._call.call(void 0, t), e = e._next;
  --ci;
}
function mh() {
  Sr = (Js = Ki.now()) + So, ci = Ii = 0;
  try {
    Mb();
  } finally {
    ci = 0, $b(), Sr = 0;
  }
}
function Ib() {
  var e = Ki.now(), t = e - Js;
  t > Tu && (So -= t, Js = e);
}
function $b() {
  for (var e, t = Qs, r, i = 1 / 0; t; )
    t._call ? (i > t._time && (i = t._time), e = t, t = t._next) : (r = t._next, t._next = null, t = e ? e._next = r : Qs = r);
  $i = e, La(i);
}
function La(e) {
  if (!ci) {
    Ii && (Ii = clearTimeout(Ii));
    var t = e - Sr;
    t > 24 ? (e < 1 / 0 && (Ii = setTimeout(mh, e - Ki.now() - So)), Bi && (Bi = clearInterval(Bi))) : (Bi || (Js = Ki.now(), Bi = setInterval(Ib, Tu)), ci = 1, Su(mh));
  }
}
function yh(e, t, r) {
  var i = new to();
  return t = t == null ? 0 : +t, i.restart((s) => {
    i.stop(), e(s + t);
  }, t, r), i;
}
var Ob = iu("start", "end", "cancel", "interrupt"), Db = [], _u = 0, xh = 1, Aa = 2, Rs = 3, Ch = 4, Ea = 5, Ps = 6;
function wo(e, t, r, i, s, o) {
  var a = e.__transition;
  if (!a) e.__transition = {};
  else if (r in a) return;
  Rb(e, r, {
    name: t,
    index: i,
    // For context during callback.
    group: s,
    // For context during callback.
    on: Ob,
    tween: Db,
    time: o.time,
    delay: o.delay,
    duration: o.duration,
    ease: o.ease,
    timer: null,
    state: _u
  });
}
function En(e, t) {
  var r = Be(e, t);
  if (r.state > _u) throw new Error("too late; already scheduled");
  return r;
}
function Pe(e, t) {
  var r = Be(e, t);
  if (r.state > Rs) throw new Error("too late; already running");
  return r;
}
function Be(e, t) {
  var r = e.__transition;
  if (!r || !(r = r[t])) throw new Error("transition not found");
  return r;
}
function Rb(e, t, r) {
  var i = e.__transition, s;
  i[t] = r, r.timer = wu(o, 0, r.time);
  function o(h) {
    r.state = xh, r.timer.restart(a, r.delay, r.time), r.delay <= h && a(h - r.delay);
  }
  function a(h) {
    var c, u, p, d;
    if (r.state !== xh) return l();
    for (c in i)
      if (d = i[c], d.name === r.name) {
        if (d.state === Rs) return yh(a);
        d.state === Ch ? (d.state = Ps, d.timer.stop(), d.on.call("interrupt", e, e.__data__, d.index, d.group), delete i[c]) : +c < t && (d.state = Ps, d.timer.stop(), d.on.call("cancel", e, e.__data__, d.index, d.group), delete i[c]);
      }
    if (yh(function() {
      r.state === Rs && (r.state = Ch, r.timer.restart(n, r.delay, r.time), n(h));
    }), r.state = Aa, r.on.call("start", e, e.__data__, r.index, r.group), r.state === Aa) {
      for (r.state = Rs, s = new Array(p = r.tween.length), c = 0, u = -1; c < p; ++c)
        (d = r.tween[c].value.call(e, e.__data__, r.index, r.group)) && (s[++u] = d);
      s.length = u + 1;
    }
  }
  function n(h) {
    for (var c = h < r.duration ? r.ease.call(null, h / r.duration) : (r.timer.restart(l), r.state = Ea, 1), u = -1, p = s.length; ++u < p; )
      s[u].call(e, c);
    r.state === Ea && (r.on.call("end", e, e.__data__, r.index, r.group), l());
  }
  function l() {
    r.state = Ps, r.timer.stop(), delete i[t];
    for (var h in i) return;
    delete e.__transition;
  }
}
function Pb(e, t) {
  var r = e.__transition, i, s, o = !0, a;
  if (r) {
    t = t == null ? null : t + "";
    for (a in r) {
      if ((i = r[a]).name !== t) {
        o = !1;
        continue;
      }
      s = i.state > Aa && i.state < Ea, i.state = Ps, i.timer.stop(), i.on.call(s ? "interrupt" : "cancel", e, e.__data__, i.index, i.group), delete r[a];
    }
    o && delete e.__transition;
  }
}
function Nb(e) {
  return this.each(function() {
    Pb(this, e);
  });
}
function qb(e, t) {
  var r, i;
  return function() {
    var s = Pe(this, e), o = s.tween;
    if (o !== r) {
      i = r = o;
      for (var a = 0, n = i.length; a < n; ++a)
        if (i[a].name === t) {
          i = i.slice(), i.splice(a, 1);
          break;
        }
    }
    s.tween = i;
  };
}
function Wb(e, t, r) {
  var i, s;
  if (typeof r != "function") throw new Error();
  return function() {
    var o = Pe(this, e), a = o.tween;
    if (a !== i) {
      s = (i = a).slice();
      for (var n = { name: t, value: r }, l = 0, h = s.length; l < h; ++l)
        if (s[l].name === t) {
          s[l] = n;
          break;
        }
      l === h && s.push(n);
    }
    o.tween = s;
  };
}
function zb(e, t) {
  var r = this._id;
  if (e += "", arguments.length < 2) {
    for (var i = Be(this.node(), r).tween, s = 0, o = i.length, a; s < o; ++s)
      if ((a = i[s]).name === e)
        return a.value;
    return null;
  }
  return this.each((t == null ? qb : Wb)(r, e, t));
}
function Fn(e, t, r) {
  var i = e._id;
  return e.each(function() {
    var s = Pe(this, i);
    (s.value || (s.value = {}))[t] = r.apply(this, arguments);
  }), function(s) {
    return Be(s, i).value[t];
  };
}
function Bu(e, t) {
  var r;
  return (typeof t == "number" ? Qe : t instanceof Zi ? fh : (r = Zi(t)) ? (t = r, fh) : Bb)(e, t);
}
function Hb(e) {
  return function() {
    this.removeAttribute(e);
  };
}
function Yb(e) {
  return function() {
    this.removeAttributeNS(e.space, e.local);
  };
}
function Xb(e, t, r) {
  var i, s = r + "", o;
  return function() {
    var a = this.getAttribute(e);
    return a === s ? null : a === i ? o : o = t(i = a, r);
  };
}
function Ub(e, t, r) {
  var i, s = r + "", o;
  return function() {
    var a = this.getAttributeNS(e.space, e.local);
    return a === s ? null : a === i ? o : o = t(i = a, r);
  };
}
function jb(e, t, r) {
  var i, s, o;
  return function() {
    var a, n = r(this), l;
    return n == null ? void this.removeAttribute(e) : (a = this.getAttribute(e), l = n + "", a === l ? null : a === i && l === s ? o : (s = l, o = t(i = a, n)));
  };
}
function Gb(e, t, r) {
  var i, s, o;
  return function() {
    var a, n = r(this), l;
    return n == null ? void this.removeAttributeNS(e.space, e.local) : (a = this.getAttributeNS(e.space, e.local), l = n + "", a === l ? null : a === i && l === s ? o : (s = l, o = t(i = a, n)));
  };
}
function Vb(e, t) {
  var r = To(e), i = r === "transform" ? Eb : Bu;
  return this.attrTween(e, typeof t == "function" ? (r.local ? Gb : jb)(r, i, Fn(this, "attr." + e, t)) : t == null ? (r.local ? Yb : Hb)(r) : (r.local ? Ub : Xb)(r, i, t));
}
function Zb(e, t) {
  return function(r) {
    this.setAttribute(e, t.call(this, r));
  };
}
function Kb(e, t) {
  return function(r) {
    this.setAttributeNS(e.space, e.local, t.call(this, r));
  };
}
function Qb(e, t) {
  var r, i;
  function s() {
    var o = t.apply(this, arguments);
    return o !== i && (r = (i = o) && Kb(e, o)), r;
  }
  return s._value = t, s;
}
function Jb(e, t) {
  var r, i;
  function s() {
    var o = t.apply(this, arguments);
    return o !== i && (r = (i = o) && Zb(e, o)), r;
  }
  return s._value = t, s;
}
function tk(e, t) {
  var r = "attr." + e;
  if (arguments.length < 2) return (r = this.tween(r)) && r._value;
  if (t == null) return this.tween(r, null);
  if (typeof t != "function") throw new Error();
  var i = To(e);
  return this.tween(r, (i.local ? Qb : Jb)(i, t));
}
function ek(e, t) {
  return function() {
    En(this, e).delay = +t.apply(this, arguments);
  };
}
function rk(e, t) {
  return t = +t, function() {
    En(this, e).delay = t;
  };
}
function ik(e) {
  var t = this._id;
  return arguments.length ? this.each((typeof e == "function" ? ek : rk)(t, e)) : Be(this.node(), t).delay;
}
function sk(e, t) {
  return function() {
    Pe(this, e).duration = +t.apply(this, arguments);
  };
}
function ok(e, t) {
  return t = +t, function() {
    Pe(this, e).duration = t;
  };
}
function ak(e) {
  var t = this._id;
  return arguments.length ? this.each((typeof e == "function" ? sk : ok)(t, e)) : Be(this.node(), t).duration;
}
function nk(e, t) {
  if (typeof t != "function") throw new Error();
  return function() {
    Pe(this, e).ease = t;
  };
}
function lk(e) {
  var t = this._id;
  return arguments.length ? this.each(nk(t, e)) : Be(this.node(), t).ease;
}
function hk(e, t) {
  return function() {
    var r = t.apply(this, arguments);
    if (typeof r != "function") throw new Error();
    Pe(this, e).ease = r;
  };
}
function ck(e) {
  if (typeof e != "function") throw new Error();
  return this.each(hk(this._id, e));
}
function uk(e) {
  typeof e != "function" && (e = au(e));
  for (var t = this._groups, r = t.length, i = new Array(r), s = 0; s < r; ++s)
    for (var o = t[s], a = o.length, n = i[s] = [], l, h = 0; h < a; ++h)
      (l = o[h]) && e.call(l, l.__data__, h, o) && n.push(l);
  return new Ue(i, this._parents, this._name, this._id);
}
function dk(e) {
  if (e._id !== this._id) throw new Error();
  for (var t = this._groups, r = e._groups, i = t.length, s = r.length, o = Math.min(i, s), a = new Array(i), n = 0; n < o; ++n)
    for (var l = t[n], h = r[n], c = l.length, u = a[n] = new Array(c), p, d = 0; d < c; ++d)
      (p = l[d] || h[d]) && (u[d] = p);
  for (; n < i; ++n)
    a[n] = t[n];
  return new Ue(a, this._parents, this._name, this._id);
}
function pk(e) {
  return (e + "").trim().split(/^|\s+/).every(function(t) {
    var r = t.indexOf(".");
    return r >= 0 && (t = t.slice(0, r)), !t || t === "start";
  });
}
function fk(e, t, r) {
  var i, s, o = pk(t) ? En : Pe;
  return function() {
    var a = o(this, e), n = a.on;
    n !== i && (s = (i = n).copy()).on(t, r), a.on = s;
  };
}
function gk(e, t) {
  var r = this._id;
  return arguments.length < 2 ? Be(this.node(), r).on.on(e) : this.each(fk(r, e, t));
}
function mk(e) {
  return function() {
    var t = this.parentNode;
    for (var r in this.__transition) if (+r !== e) return;
    t && t.removeChild(this);
  };
}
function yk() {
  return this.on("end.remove", mk(this._id));
}
function xk(e) {
  var t = this._name, r = this._id;
  typeof e != "function" && (e = _n(e));
  for (var i = this._groups, s = i.length, o = new Array(s), a = 0; a < s; ++a)
    for (var n = i[a], l = n.length, h = o[a] = new Array(l), c, u, p = 0; p < l; ++p)
      (c = n[p]) && (u = e.call(c, c.__data__, p, n)) && ("__data__" in c && (u.__data__ = c.__data__), h[p] = u, wo(h[p], t, r, p, h, Be(c, r)));
  return new Ue(o, this._parents, t, r);
}
function Ck(e) {
  var t = this._name, r = this._id;
  typeof e != "function" && (e = ou(e));
  for (var i = this._groups, s = i.length, o = [], a = [], n = 0; n < s; ++n)
    for (var l = i[n], h = l.length, c, u = 0; u < h; ++u)
      if (c = l[u]) {
        for (var p = e.call(c, c.__data__, u, l), d, g = Be(c, r), m = 0, y = p.length; m < y; ++m)
          (d = p[m]) && wo(d, t, r, m, p, g);
        o.push(p), a.push(c);
      }
  return new Ue(o, a, t, r);
}
var bk = hs.prototype.constructor;
function kk() {
  return new bk(this._groups, this._parents);
}
function Tk(e, t) {
  var r, i, s;
  return function() {
    var o = hi(this, e), a = (this.style.removeProperty(e), hi(this, e));
    return o === a ? null : o === r && a === i ? s : s = t(r = o, i = a);
  };
}
function vu(e) {
  return function() {
    this.style.removeProperty(e);
  };
}
function Sk(e, t, r) {
  var i, s = r + "", o;
  return function() {
    var a = hi(this, e);
    return a === s ? null : a === i ? o : o = t(i = a, r);
  };
}
function wk(e, t, r) {
  var i, s, o;
  return function() {
    var a = hi(this, e), n = r(this), l = n + "";
    return n == null && (l = n = (this.style.removeProperty(e), hi(this, e))), a === l ? null : a === i && l === s ? o : (s = l, o = t(i = a, n));
  };
}
function _k(e, t) {
  var r, i, s, o = "style." + t, a = "end." + o, n;
  return function() {
    var l = Pe(this, e), h = l.on, c = l.value[o] == null ? n || (n = vu(t)) : void 0;
    (h !== r || s !== c) && (i = (r = h).copy()).on(a, s = c), l.on = i;
  };
}
function Bk(e, t, r) {
  var i = (e += "") == "transform" ? Ab : Bu;
  return t == null ? this.styleTween(e, Tk(e, i)).on("end.style." + e, vu(e)) : typeof t == "function" ? this.styleTween(e, wk(e, i, Fn(this, "style." + e, t))).each(_k(this._id, e)) : this.styleTween(e, Sk(e, i, t), r).on("end.style." + e, null);
}
function vk(e, t, r) {
  return function(i) {
    this.style.setProperty(e, t.call(this, i), r);
  };
}
function Lk(e, t, r) {
  var i, s;
  function o() {
    var a = t.apply(this, arguments);
    return a !== s && (i = (s = a) && vk(e, a, r)), i;
  }
  return o._value = t, o;
}
function Ak(e, t, r) {
  var i = "style." + (e += "");
  if (arguments.length < 2) return (i = this.tween(i)) && i._value;
  if (t == null) return this.tween(i, null);
  if (typeof t != "function") throw new Error();
  return this.tween(i, Lk(e, t, r ?? ""));
}
function Ek(e) {
  return function() {
    this.textContent = e;
  };
}
function Fk(e) {
  return function() {
    var t = e(this);
    this.textContent = t ?? "";
  };
}
function Mk(e) {
  return this.tween("text", typeof e == "function" ? Fk(Fn(this, "text", e)) : Ek(e == null ? "" : e + ""));
}
function Ik(e) {
  return function(t) {
    this.textContent = e.call(this, t);
  };
}
function $k(e) {
  var t, r;
  function i() {
    var s = e.apply(this, arguments);
    return s !== r && (t = (r = s) && Ik(s)), t;
  }
  return i._value = e, i;
}
function Ok(e) {
  var t = "text";
  if (arguments.length < 1) return (t = this.tween(t)) && t._value;
  if (e == null) return this.tween(t, null);
  if (typeof e != "function") throw new Error();
  return this.tween(t, $k(e));
}
function Dk() {
  for (var e = this._name, t = this._id, r = Lu(), i = this._groups, s = i.length, o = 0; o < s; ++o)
    for (var a = i[o], n = a.length, l, h = 0; h < n; ++h)
      if (l = a[h]) {
        var c = Be(l, t);
        wo(l, e, r, h, a, {
          time: c.time + c.delay + c.duration,
          delay: 0,
          duration: c.duration,
          ease: c.ease
        });
      }
  return new Ue(i, this._parents, e, r);
}
function Rk() {
  var e, t, r = this, i = r._id, s = r.size();
  return new Promise(function(o, a) {
    var n = { value: a }, l = { value: function() {
      --s === 0 && o();
    } };
    r.each(function() {
      var h = Pe(this, i), c = h.on;
      c !== e && (t = (e = c).copy(), t._.cancel.push(n), t._.interrupt.push(n), t._.end.push(l)), h.on = t;
    }), s === 0 && o();
  });
}
var Pk = 0;
function Ue(e, t, r, i) {
  this._groups = e, this._parents = t, this._name = r, this._id = i;
}
function Lu() {
  return ++Pk;
}
var We = hs.prototype;
Ue.prototype = {
  constructor: Ue,
  select: xk,
  selectAll: Ck,
  selectChild: We.selectChild,
  selectChildren: We.selectChildren,
  filter: uk,
  merge: dk,
  selection: kk,
  transition: Dk,
  call: We.call,
  nodes: We.nodes,
  node: We.node,
  size: We.size,
  empty: We.empty,
  each: We.each,
  on: gk,
  attr: Vb,
  attrTween: tk,
  style: Bk,
  styleTween: Ak,
  text: Mk,
  textTween: Ok,
  remove: yk,
  tween: zb,
  delay: ik,
  duration: ak,
  ease: lk,
  easeVarying: ck,
  end: Rk,
  [Symbol.iterator]: We[Symbol.iterator]
};
function Nk(e) {
  return ((e *= 2) <= 1 ? e * e * e : (e -= 2) * e * e + 2) / 2;
}
var qk = {
  time: null,
  // Set on use.
  delay: 0,
  duration: 250,
  ease: Nk
};
function Wk(e, t) {
  for (var r; !(r = e.__transition) || !(r = r[t]); )
    if (!(e = e.parentNode))
      throw new Error(`transition ${t} not found`);
  return r;
}
function zk(e) {
  var t, r;
  e instanceof Ue ? (t = e._id, e = e._name) : (t = Lu(), (r = qk).time = An(), e = e == null ? null : e + "");
  for (var i = this._groups, s = i.length, o = 0; o < s; ++o)
    for (var a = i[o], n = a.length, l, h = 0; h < n; ++h)
      (l = a[h]) && wo(l, e, t, h, a, r || Wk(l, t));
  return new Ue(i, this._parents, e, t);
}
hs.prototype.interrupt = Nb;
hs.prototype.transition = zk;
const Fa = Math.PI, Ma = 2 * Fa, ur = 1e-6, Hk = Ma - ur;
function Au(e) {
  this._ += e[0];
  for (let t = 1, r = e.length; t < r; ++t)
    this._ += arguments[t] + e[t];
}
function Yk(e) {
  let t = Math.floor(e);
  if (!(t >= 0)) throw new Error(`invalid digits: ${e}`);
  if (t > 15) return Au;
  const r = 10 ** t;
  return function(i) {
    this._ += i[0];
    for (let s = 1, o = i.length; s < o; ++s)
      this._ += Math.round(arguments[s] * r) / r + i[s];
  };
}
class Xk {
  constructor(t) {
    this._x0 = this._y0 = // start of current subpath
    this._x1 = this._y1 = null, this._ = "", this._append = t == null ? Au : Yk(t);
  }
  moveTo(t, r) {
    this._append`M${this._x0 = this._x1 = +t},${this._y0 = this._y1 = +r}`;
  }
  closePath() {
    this._x1 !== null && (this._x1 = this._x0, this._y1 = this._y0, this._append`Z`);
  }
  lineTo(t, r) {
    this._append`L${this._x1 = +t},${this._y1 = +r}`;
  }
  quadraticCurveTo(t, r, i, s) {
    this._append`Q${+t},${+r},${this._x1 = +i},${this._y1 = +s}`;
  }
  bezierCurveTo(t, r, i, s, o, a) {
    this._append`C${+t},${+r},${+i},${+s},${this._x1 = +o},${this._y1 = +a}`;
  }
  arcTo(t, r, i, s, o) {
    if (t = +t, r = +r, i = +i, s = +s, o = +o, o < 0) throw new Error(`negative radius: ${o}`);
    let a = this._x1, n = this._y1, l = i - t, h = s - r, c = a - t, u = n - r, p = c * c + u * u;
    if (this._x1 === null)
      this._append`M${this._x1 = t},${this._y1 = r}`;
    else if (p > ur) if (!(Math.abs(u * l - h * c) > ur) || !o)
      this._append`L${this._x1 = t},${this._y1 = r}`;
    else {
      let d = i - a, g = s - n, m = l * l + h * h, y = d * d + g * g, x = Math.sqrt(m), b = Math.sqrt(p), k = o * Math.tan((Fa - Math.acos((m + p - y) / (2 * x * b))) / 2), w = k / b, S = k / x;
      Math.abs(w - 1) > ur && this._append`L${t + w * c},${r + w * u}`, this._append`A${o},${o},0,0,${+(u * d > c * g)},${this._x1 = t + S * l},${this._y1 = r + S * h}`;
    }
  }
  arc(t, r, i, s, o, a) {
    if (t = +t, r = +r, i = +i, a = !!a, i < 0) throw new Error(`negative radius: ${i}`);
    let n = i * Math.cos(s), l = i * Math.sin(s), h = t + n, c = r + l, u = 1 ^ a, p = a ? s - o : o - s;
    this._x1 === null ? this._append`M${h},${c}` : (Math.abs(this._x1 - h) > ur || Math.abs(this._y1 - c) > ur) && this._append`L${h},${c}`, i && (p < 0 && (p = p % Ma + Ma), p > Hk ? this._append`A${i},${i},0,1,${u},${t - n},${r - l}A${i},${i},0,1,${u},${this._x1 = h},${this._y1 = c}` : p > ur && this._append`A${i},${i},0,${+(p >= Fa)},${u},${this._x1 = t + i * Math.cos(o)},${this._y1 = r + i * Math.sin(o)}`);
  }
  rect(t, r, i, s) {
    this._append`M${this._x0 = this._x1 = +t},${this._y0 = this._y1 = +r}h${i = +i}v${+s}h${-i}Z`;
  }
  toString() {
    return this._;
  }
}
function Or(e) {
  return function() {
    return e;
  };
}
const DL = Math.abs, RL = Math.atan2, PL = Math.cos, NL = Math.max, qL = Math.min, WL = Math.sin, zL = Math.sqrt, bh = 1e-12, Mn = Math.PI, kh = Mn / 2, HL = 2 * Mn;
function YL(e) {
  return e > 1 ? 0 : e < -1 ? Mn : Math.acos(e);
}
function XL(e) {
  return e >= 1 ? kh : e <= -1 ? -kh : Math.asin(e);
}
function Uk(e) {
  let t = 3;
  return e.digits = function(r) {
    if (!arguments.length) return t;
    if (r == null)
      t = null;
    else {
      const i = Math.floor(r);
      if (!(i >= 0)) throw new RangeError(`invalid digits: ${r}`);
      t = i;
    }
    return e;
  }, () => new Xk(t);
}
function jk(e) {
  return typeof e == "object" && "length" in e ? e : Array.from(e);
}
function Eu(e) {
  this._context = e;
}
Eu.prototype = {
  areaStart: function() {
    this._line = 0;
  },
  areaEnd: function() {
    this._line = NaN;
  },
  lineStart: function() {
    this._point = 0;
  },
  lineEnd: function() {
    (this._line || this._line !== 0 && this._point === 1) && this._context.closePath(), this._line = 1 - this._line;
  },
  point: function(e, t) {
    switch (e = +e, t = +t, this._point) {
      case 0:
        this._point = 1, this._line ? this._context.lineTo(e, t) : this._context.moveTo(e, t);
        break;
      case 1:
        this._point = 2;
      // falls through
      default:
        this._context.lineTo(e, t);
        break;
    }
  }
};
function Hi(e) {
  return new Eu(e);
}
function Gk(e) {
  return e[0];
}
function Vk(e) {
  return e[1];
}
function Zk(e, t) {
  var r = Or(!0), i = null, s = Hi, o = null, a = Uk(n);
  e = typeof e == "function" ? e : e === void 0 ? Gk : Or(e), t = typeof t == "function" ? t : t === void 0 ? Vk : Or(t);
  function n(l) {
    var h, c = (l = jk(l)).length, u, p = !1, d;
    for (i == null && (o = s(d = a())), h = 0; h <= c; ++h)
      !(h < c && r(u = l[h], h, l)) === p && ((p = !p) ? o.lineStart() : o.lineEnd()), p && o.point(+e(u, h, l), +t(u, h, l));
    if (d) return o = null, d + "" || null;
  }
  return n.x = function(l) {
    return arguments.length ? (e = typeof l == "function" ? l : Or(+l), n) : e;
  }, n.y = function(l) {
    return arguments.length ? (t = typeof l == "function" ? l : Or(+l), n) : t;
  }, n.defined = function(l) {
    return arguments.length ? (r = typeof l == "function" ? l : Or(!!l), n) : r;
  }, n.curve = function(l) {
    return arguments.length ? (s = l, i != null && (o = s(i)), n) : s;
  }, n.context = function(l) {
    return arguments.length ? (l == null ? i = o = null : o = s(i = l), n) : i;
  }, n;
}
class Fu {
  constructor(t, r) {
    this._context = t, this._x = r;
  }
  areaStart() {
    this._line = 0;
  }
  areaEnd() {
    this._line = NaN;
  }
  lineStart() {
    this._point = 0;
  }
  lineEnd() {
    (this._line || this._line !== 0 && this._point === 1) && this._context.closePath(), this._line = 1 - this._line;
  }
  point(t, r) {
    switch (t = +t, r = +r, this._point) {
      case 0: {
        this._point = 1, this._line ? this._context.lineTo(t, r) : this._context.moveTo(t, r);
        break;
      }
      case 1:
        this._point = 2;
      // falls through
      default: {
        this._x ? this._context.bezierCurveTo(this._x0 = (this._x0 + t) / 2, this._y0, this._x0, r, t, r) : this._context.bezierCurveTo(this._x0, this._y0 = (this._y0 + r) / 2, t, this._y0, t, r);
        break;
      }
    }
    this._x0 = t, this._y0 = r;
  }
}
function Mu(e) {
  return new Fu(e, !0);
}
function Iu(e) {
  return new Fu(e, !1);
}
function ir() {
}
function eo(e, t, r) {
  e._context.bezierCurveTo(
    (2 * e._x0 + e._x1) / 3,
    (2 * e._y0 + e._y1) / 3,
    (e._x0 + 2 * e._x1) / 3,
    (e._y0 + 2 * e._y1) / 3,
    (e._x0 + 4 * e._x1 + t) / 6,
    (e._y0 + 4 * e._y1 + r) / 6
  );
}
function _o(e) {
  this._context = e;
}
_o.prototype = {
  areaStart: function() {
    this._line = 0;
  },
  areaEnd: function() {
    this._line = NaN;
  },
  lineStart: function() {
    this._x0 = this._x1 = this._y0 = this._y1 = NaN, this._point = 0;
  },
  lineEnd: function() {
    switch (this._point) {
      case 3:
        eo(this, this._x1, this._y1);
      // falls through
      case 2:
        this._context.lineTo(this._x1, this._y1);
        break;
    }
    (this._line || this._line !== 0 && this._point === 1) && this._context.closePath(), this._line = 1 - this._line;
  },
  point: function(e, t) {
    switch (e = +e, t = +t, this._point) {
      case 0:
        this._point = 1, this._line ? this._context.lineTo(e, t) : this._context.moveTo(e, t);
        break;
      case 1:
        this._point = 2;
        break;
      case 2:
        this._point = 3, this._context.lineTo((5 * this._x0 + this._x1) / 6, (5 * this._y0 + this._y1) / 6);
      // falls through
      default:
        eo(this, e, t);
        break;
    }
    this._x0 = this._x1, this._x1 = e, this._y0 = this._y1, this._y1 = t;
  }
};
function Ia(e) {
  return new _o(e);
}
function $u(e) {
  this._context = e;
}
$u.prototype = {
  areaStart: ir,
  areaEnd: ir,
  lineStart: function() {
    this._x0 = this._x1 = this._x2 = this._x3 = this._x4 = this._y0 = this._y1 = this._y2 = this._y3 = this._y4 = NaN, this._point = 0;
  },
  lineEnd: function() {
    switch (this._point) {
      case 1: {
        this._context.moveTo(this._x2, this._y2), this._context.closePath();
        break;
      }
      case 2: {
        this._context.moveTo((this._x2 + 2 * this._x3) / 3, (this._y2 + 2 * this._y3) / 3), this._context.lineTo((this._x3 + 2 * this._x2) / 3, (this._y3 + 2 * this._y2) / 3), this._context.closePath();
        break;
      }
      case 3: {
        this.point(this._x2, this._y2), this.point(this._x3, this._y3), this.point(this._x4, this._y4);
        break;
      }
    }
  },
  point: function(e, t) {
    switch (e = +e, t = +t, this._point) {
      case 0:
        this._point = 1, this._x2 = e, this._y2 = t;
        break;
      case 1:
        this._point = 2, this._x3 = e, this._y3 = t;
        break;
      case 2:
        this._point = 3, this._x4 = e, this._y4 = t, this._context.moveTo((this._x0 + 4 * this._x1 + e) / 6, (this._y0 + 4 * this._y1 + t) / 6);
        break;
      default:
        eo(this, e, t);
        break;
    }
    this._x0 = this._x1, this._x1 = e, this._y0 = this._y1, this._y1 = t;
  }
};
function Kk(e) {
  return new $u(e);
}
function Ou(e) {
  this._context = e;
}
Ou.prototype = {
  areaStart: function() {
    this._line = 0;
  },
  areaEnd: function() {
    this._line = NaN;
  },
  lineStart: function() {
    this._x0 = this._x1 = this._y0 = this._y1 = NaN, this._point = 0;
  },
  lineEnd: function() {
    (this._line || this._line !== 0 && this._point === 3) && this._context.closePath(), this._line = 1 - this._line;
  },
  point: function(e, t) {
    switch (e = +e, t = +t, this._point) {
      case 0:
        this._point = 1;
        break;
      case 1:
        this._point = 2;
        break;
      case 2:
        this._point = 3;
        var r = (this._x0 + 4 * this._x1 + e) / 6, i = (this._y0 + 4 * this._y1 + t) / 6;
        this._line ? this._context.lineTo(r, i) : this._context.moveTo(r, i);
        break;
      case 3:
        this._point = 4;
      // falls through
      default:
        eo(this, e, t);
        break;
    }
    this._x0 = this._x1, this._x1 = e, this._y0 = this._y1, this._y1 = t;
  }
};
function Qk(e) {
  return new Ou(e);
}
function Du(e, t) {
  this._basis = new _o(e), this._beta = t;
}
Du.prototype = {
  lineStart: function() {
    this._x = [], this._y = [], this._basis.lineStart();
  },
  lineEnd: function() {
    var e = this._x, t = this._y, r = e.length - 1;
    if (r > 0)
      for (var i = e[0], s = t[0], o = e[r] - i, a = t[r] - s, n = -1, l; ++n <= r; )
        l = n / r, this._basis.point(
          this._beta * e[n] + (1 - this._beta) * (i + l * o),
          this._beta * t[n] + (1 - this._beta) * (s + l * a)
        );
    this._x = this._y = null, this._basis.lineEnd();
  },
  point: function(e, t) {
    this._x.push(+e), this._y.push(+t);
  }
};
const Jk = (function e(t) {
  function r(i) {
    return t === 1 ? new _o(i) : new Du(i, t);
  }
  return r.beta = function(i) {
    return e(+i);
  }, r;
})(0.85);
function ro(e, t, r) {
  e._context.bezierCurveTo(
    e._x1 + e._k * (e._x2 - e._x0),
    e._y1 + e._k * (e._y2 - e._y0),
    e._x2 + e._k * (e._x1 - t),
    e._y2 + e._k * (e._y1 - r),
    e._x2,
    e._y2
  );
}
function In(e, t) {
  this._context = e, this._k = (1 - t) / 6;
}
In.prototype = {
  areaStart: function() {
    this._line = 0;
  },
  areaEnd: function() {
    this._line = NaN;
  },
  lineStart: function() {
    this._x0 = this._x1 = this._x2 = this._y0 = this._y1 = this._y2 = NaN, this._point = 0;
  },
  lineEnd: function() {
    switch (this._point) {
      case 2:
        this._context.lineTo(this._x2, this._y2);
        break;
      case 3:
        ro(this, this._x1, this._y1);
        break;
    }
    (this._line || this._line !== 0 && this._point === 1) && this._context.closePath(), this._line = 1 - this._line;
  },
  point: function(e, t) {
    switch (e = +e, t = +t, this._point) {
      case 0:
        this._point = 1, this._line ? this._context.lineTo(e, t) : this._context.moveTo(e, t);
        break;
      case 1:
        this._point = 2, this._x1 = e, this._y1 = t;
        break;
      case 2:
        this._point = 3;
      // falls through
      default:
        ro(this, e, t);
        break;
    }
    this._x0 = this._x1, this._x1 = this._x2, this._x2 = e, this._y0 = this._y1, this._y1 = this._y2, this._y2 = t;
  }
};
const Ru = (function e(t) {
  function r(i) {
    return new In(i, t);
  }
  return r.tension = function(i) {
    return e(+i);
  }, r;
})(0);
function $n(e, t) {
  this._context = e, this._k = (1 - t) / 6;
}
$n.prototype = {
  areaStart: ir,
  areaEnd: ir,
  lineStart: function() {
    this._x0 = this._x1 = this._x2 = this._x3 = this._x4 = this._x5 = this._y0 = this._y1 = this._y2 = this._y3 = this._y4 = this._y5 = NaN, this._point = 0;
  },
  lineEnd: function() {
    switch (this._point) {
      case 1: {
        this._context.moveTo(this._x3, this._y3), this._context.closePath();
        break;
      }
      case 2: {
        this._context.lineTo(this._x3, this._y3), this._context.closePath();
        break;
      }
      case 3: {
        this.point(this._x3, this._y3), this.point(this._x4, this._y4), this.point(this._x5, this._y5);
        break;
      }
    }
  },
  point: function(e, t) {
    switch (e = +e, t = +t, this._point) {
      case 0:
        this._point = 1, this._x3 = e, this._y3 = t;
        break;
      case 1:
        this._point = 2, this._context.moveTo(this._x4 = e, this._y4 = t);
        break;
      case 2:
        this._point = 3, this._x5 = e, this._y5 = t;
        break;
      default:
        ro(this, e, t);
        break;
    }
    this._x0 = this._x1, this._x1 = this._x2, this._x2 = e, this._y0 = this._y1, this._y1 = this._y2, this._y2 = t;
  }
};
const t1 = (function e(t) {
  function r(i) {
    return new $n(i, t);
  }
  return r.tension = function(i) {
    return e(+i);
  }, r;
})(0);
function On(e, t) {
  this._context = e, this._k = (1 - t) / 6;
}
On.prototype = {
  areaStart: function() {
    this._line = 0;
  },
  areaEnd: function() {
    this._line = NaN;
  },
  lineStart: function() {
    this._x0 = this._x1 = this._x2 = this._y0 = this._y1 = this._y2 = NaN, this._point = 0;
  },
  lineEnd: function() {
    (this._line || this._line !== 0 && this._point === 3) && this._context.closePath(), this._line = 1 - this._line;
  },
  point: function(e, t) {
    switch (e = +e, t = +t, this._point) {
      case 0:
        this._point = 1;
        break;
      case 1:
        this._point = 2;
        break;
      case 2:
        this._point = 3, this._line ? this._context.lineTo(this._x2, this._y2) : this._context.moveTo(this._x2, this._y2);
        break;
      case 3:
        this._point = 4;
      // falls through
      default:
        ro(this, e, t);
        break;
    }
    this._x0 = this._x1, this._x1 = this._x2, this._x2 = e, this._y0 = this._y1, this._y1 = this._y2, this._y2 = t;
  }
};
const e1 = (function e(t) {
  function r(i) {
    return new On(i, t);
  }
  return r.tension = function(i) {
    return e(+i);
  }, r;
})(0);
function Dn(e, t, r) {
  var i = e._x1, s = e._y1, o = e._x2, a = e._y2;
  if (e._l01_a > bh) {
    var n = 2 * e._l01_2a + 3 * e._l01_a * e._l12_a + e._l12_2a, l = 3 * e._l01_a * (e._l01_a + e._l12_a);
    i = (i * n - e._x0 * e._l12_2a + e._x2 * e._l01_2a) / l, s = (s * n - e._y0 * e._l12_2a + e._y2 * e._l01_2a) / l;
  }
  if (e._l23_a > bh) {
    var h = 2 * e._l23_2a + 3 * e._l23_a * e._l12_a + e._l12_2a, c = 3 * e._l23_a * (e._l23_a + e._l12_a);
    o = (o * h + e._x1 * e._l23_2a - t * e._l12_2a) / c, a = (a * h + e._y1 * e._l23_2a - r * e._l12_2a) / c;
  }
  e._context.bezierCurveTo(i, s, o, a, e._x2, e._y2);
}
function Pu(e, t) {
  this._context = e, this._alpha = t;
}
Pu.prototype = {
  areaStart: function() {
    this._line = 0;
  },
  areaEnd: function() {
    this._line = NaN;
  },
  lineStart: function() {
    this._x0 = this._x1 = this._x2 = this._y0 = this._y1 = this._y2 = NaN, this._l01_a = this._l12_a = this._l23_a = this._l01_2a = this._l12_2a = this._l23_2a = this._point = 0;
  },
  lineEnd: function() {
    switch (this._point) {
      case 2:
        this._context.lineTo(this._x2, this._y2);
        break;
      case 3:
        this.point(this._x2, this._y2);
        break;
    }
    (this._line || this._line !== 0 && this._point === 1) && this._context.closePath(), this._line = 1 - this._line;
  },
  point: function(e, t) {
    if (e = +e, t = +t, this._point) {
      var r = this._x2 - e, i = this._y2 - t;
      this._l23_a = Math.sqrt(this._l23_2a = Math.pow(r * r + i * i, this._alpha));
    }
    switch (this._point) {
      case 0:
        this._point = 1, this._line ? this._context.lineTo(e, t) : this._context.moveTo(e, t);
        break;
      case 1:
        this._point = 2;
        break;
      case 2:
        this._point = 3;
      // falls through
      default:
        Dn(this, e, t);
        break;
    }
    this._l01_a = this._l12_a, this._l12_a = this._l23_a, this._l01_2a = this._l12_2a, this._l12_2a = this._l23_2a, this._x0 = this._x1, this._x1 = this._x2, this._x2 = e, this._y0 = this._y1, this._y1 = this._y2, this._y2 = t;
  }
};
const Nu = (function e(t) {
  function r(i) {
    return t ? new Pu(i, t) : new In(i, 0);
  }
  return r.alpha = function(i) {
    return e(+i);
  }, r;
})(0.5);
function qu(e, t) {
  this._context = e, this._alpha = t;
}
qu.prototype = {
  areaStart: ir,
  areaEnd: ir,
  lineStart: function() {
    this._x0 = this._x1 = this._x2 = this._x3 = this._x4 = this._x5 = this._y0 = this._y1 = this._y2 = this._y3 = this._y4 = this._y5 = NaN, this._l01_a = this._l12_a = this._l23_a = this._l01_2a = this._l12_2a = this._l23_2a = this._point = 0;
  },
  lineEnd: function() {
    switch (this._point) {
      case 1: {
        this._context.moveTo(this._x3, this._y3), this._context.closePath();
        break;
      }
      case 2: {
        this._context.lineTo(this._x3, this._y3), this._context.closePath();
        break;
      }
      case 3: {
        this.point(this._x3, this._y3), this.point(this._x4, this._y4), this.point(this._x5, this._y5);
        break;
      }
    }
  },
  point: function(e, t) {
    if (e = +e, t = +t, this._point) {
      var r = this._x2 - e, i = this._y2 - t;
      this._l23_a = Math.sqrt(this._l23_2a = Math.pow(r * r + i * i, this._alpha));
    }
    switch (this._point) {
      case 0:
        this._point = 1, this._x3 = e, this._y3 = t;
        break;
      case 1:
        this._point = 2, this._context.moveTo(this._x4 = e, this._y4 = t);
        break;
      case 2:
        this._point = 3, this._x5 = e, this._y5 = t;
        break;
      default:
        Dn(this, e, t);
        break;
    }
    this._l01_a = this._l12_a, this._l12_a = this._l23_a, this._l01_2a = this._l12_2a, this._l12_2a = this._l23_2a, this._x0 = this._x1, this._x1 = this._x2, this._x2 = e, this._y0 = this._y1, this._y1 = this._y2, this._y2 = t;
  }
};
const r1 = (function e(t) {
  function r(i) {
    return t ? new qu(i, t) : new $n(i, 0);
  }
  return r.alpha = function(i) {
    return e(+i);
  }, r;
})(0.5);
function Wu(e, t) {
  this._context = e, this._alpha = t;
}
Wu.prototype = {
  areaStart: function() {
    this._line = 0;
  },
  areaEnd: function() {
    this._line = NaN;
  },
  lineStart: function() {
    this._x0 = this._x1 = this._x2 = this._y0 = this._y1 = this._y2 = NaN, this._l01_a = this._l12_a = this._l23_a = this._l01_2a = this._l12_2a = this._l23_2a = this._point = 0;
  },
  lineEnd: function() {
    (this._line || this._line !== 0 && this._point === 3) && this._context.closePath(), this._line = 1 - this._line;
  },
  point: function(e, t) {
    if (e = +e, t = +t, this._point) {
      var r = this._x2 - e, i = this._y2 - t;
      this._l23_a = Math.sqrt(this._l23_2a = Math.pow(r * r + i * i, this._alpha));
    }
    switch (this._point) {
      case 0:
        this._point = 1;
        break;
      case 1:
        this._point = 2;
        break;
      case 2:
        this._point = 3, this._line ? this._context.lineTo(this._x2, this._y2) : this._context.moveTo(this._x2, this._y2);
        break;
      case 3:
        this._point = 4;
      // falls through
      default:
        Dn(this, e, t);
        break;
    }
    this._l01_a = this._l12_a, this._l12_a = this._l23_a, this._l01_2a = this._l12_2a, this._l12_2a = this._l23_2a, this._x0 = this._x1, this._x1 = this._x2, this._x2 = e, this._y0 = this._y1, this._y1 = this._y2, this._y2 = t;
  }
};
const i1 = (function e(t) {
  function r(i) {
    return t ? new Wu(i, t) : new On(i, 0);
  }
  return r.alpha = function(i) {
    return e(+i);
  }, r;
})(0.5);
function zu(e) {
  this._context = e;
}
zu.prototype = {
  areaStart: ir,
  areaEnd: ir,
  lineStart: function() {
    this._point = 0;
  },
  lineEnd: function() {
    this._point && this._context.closePath();
  },
  point: function(e, t) {
    e = +e, t = +t, this._point ? this._context.lineTo(e, t) : (this._point = 1, this._context.moveTo(e, t));
  }
};
function s1(e) {
  return new zu(e);
}
function Th(e) {
  return e < 0 ? -1 : 1;
}
function Sh(e, t, r) {
  var i = e._x1 - e._x0, s = t - e._x1, o = (e._y1 - e._y0) / (i || s < 0 && -0), a = (r - e._y1) / (s || i < 0 && -0), n = (o * s + a * i) / (i + s);
  return (Th(o) + Th(a)) * Math.min(Math.abs(o), Math.abs(a), 0.5 * Math.abs(n)) || 0;
}
function wh(e, t) {
  var r = e._x1 - e._x0;
  return r ? (3 * (e._y1 - e._y0) / r - t) / 2 : t;
}
function sa(e, t, r) {
  var i = e._x0, s = e._y0, o = e._x1, a = e._y1, n = (o - i) / 3;
  e._context.bezierCurveTo(i + n, s + n * t, o - n, a - n * r, o, a);
}
function io(e) {
  this._context = e;
}
io.prototype = {
  areaStart: function() {
    this._line = 0;
  },
  areaEnd: function() {
    this._line = NaN;
  },
  lineStart: function() {
    this._x0 = this._x1 = this._y0 = this._y1 = this._t0 = NaN, this._point = 0;
  },
  lineEnd: function() {
    switch (this._point) {
      case 2:
        this._context.lineTo(this._x1, this._y1);
        break;
      case 3:
        sa(this, this._t0, wh(this, this._t0));
        break;
    }
    (this._line || this._line !== 0 && this._point === 1) && this._context.closePath(), this._line = 1 - this._line;
  },
  point: function(e, t) {
    var r = NaN;
    if (e = +e, t = +t, !(e === this._x1 && t === this._y1)) {
      switch (this._point) {
        case 0:
          this._point = 1, this._line ? this._context.lineTo(e, t) : this._context.moveTo(e, t);
          break;
        case 1:
          this._point = 2;
          break;
        case 2:
          this._point = 3, sa(this, wh(this, r = Sh(this, e, t)), r);
          break;
        default:
          sa(this, this._t0, r = Sh(this, e, t));
          break;
      }
      this._x0 = this._x1, this._x1 = e, this._y0 = this._y1, this._y1 = t, this._t0 = r;
    }
  }
};
function Hu(e) {
  this._context = new Yu(e);
}
(Hu.prototype = Object.create(io.prototype)).point = function(e, t) {
  io.prototype.point.call(this, t, e);
};
function Yu(e) {
  this._context = e;
}
Yu.prototype = {
  moveTo: function(e, t) {
    this._context.moveTo(t, e);
  },
  closePath: function() {
    this._context.closePath();
  },
  lineTo: function(e, t) {
    this._context.lineTo(t, e);
  },
  bezierCurveTo: function(e, t, r, i, s, o) {
    this._context.bezierCurveTo(t, e, i, r, o, s);
  }
};
function Xu(e) {
  return new io(e);
}
function Uu(e) {
  return new Hu(e);
}
function ju(e) {
  this._context = e;
}
ju.prototype = {
  areaStart: function() {
    this._line = 0;
  },
  areaEnd: function() {
    this._line = NaN;
  },
  lineStart: function() {
    this._x = [], this._y = [];
  },
  lineEnd: function() {
    var e = this._x, t = this._y, r = e.length;
    if (r)
      if (this._line ? this._context.lineTo(e[0], t[0]) : this._context.moveTo(e[0], t[0]), r === 2)
        this._context.lineTo(e[1], t[1]);
      else
        for (var i = _h(e), s = _h(t), o = 0, a = 1; a < r; ++o, ++a)
          this._context.bezierCurveTo(i[0][o], s[0][o], i[1][o], s[1][o], e[a], t[a]);
    (this._line || this._line !== 0 && r === 1) && this._context.closePath(), this._line = 1 - this._line, this._x = this._y = null;
  },
  point: function(e, t) {
    this._x.push(+e), this._y.push(+t);
  }
};
function _h(e) {
  var t, r = e.length - 1, i, s = new Array(r), o = new Array(r), a = new Array(r);
  for (s[0] = 0, o[0] = 2, a[0] = e[0] + 2 * e[1], t = 1; t < r - 1; ++t) s[t] = 1, o[t] = 4, a[t] = 4 * e[t] + 2 * e[t + 1];
  for (s[r - 1] = 2, o[r - 1] = 7, a[r - 1] = 8 * e[r - 1] + e[r], t = 1; t < r; ++t) i = s[t] / o[t - 1], o[t] -= i, a[t] -= i * a[t - 1];
  for (s[r - 1] = a[r - 1] / o[r - 1], t = r - 2; t >= 0; --t) s[t] = (a[t] - s[t + 1]) / o[t];
  for (o[r - 1] = (e[r] + s[r - 1]) / 2, t = 0; t < r - 1; ++t) o[t] = 2 * e[t + 1] - s[t + 1];
  return [s, o];
}
function Gu(e) {
  return new ju(e);
}
function Bo(e, t) {
  this._context = e, this._t = t;
}
Bo.prototype = {
  areaStart: function() {
    this._line = 0;
  },
  areaEnd: function() {
    this._line = NaN;
  },
  lineStart: function() {
    this._x = this._y = NaN, this._point = 0;
  },
  lineEnd: function() {
    0 < this._t && this._t < 1 && this._point === 2 && this._context.lineTo(this._x, this._y), (this._line || this._line !== 0 && this._point === 1) && this._context.closePath(), this._line >= 0 && (this._t = 1 - this._t, this._line = 1 - this._line);
  },
  point: function(e, t) {
    switch (e = +e, t = +t, this._point) {
      case 0:
        this._point = 1, this._line ? this._context.lineTo(e, t) : this._context.moveTo(e, t);
        break;
      case 1:
        this._point = 2;
      // falls through
      default: {
        if (this._t <= 0)
          this._context.lineTo(this._x, t), this._context.lineTo(e, t);
        else {
          var r = this._x * (1 - this._t) + e * this._t;
          this._context.lineTo(r, this._y), this._context.lineTo(r, t);
        }
        break;
      }
    }
    this._x = e, this._y = t;
  }
};
function Vu(e) {
  return new Bo(e, 0.5);
}
function Zu(e) {
  return new Bo(e, 0);
}
function Ku(e) {
  return new Bo(e, 1);
}
function Oi(e, t, r) {
  this.k = e, this.x = t, this.y = r;
}
Oi.prototype = {
  constructor: Oi,
  scale: function(e) {
    return e === 1 ? this : new Oi(this.k * e, this.x, this.y);
  },
  translate: function(e, t) {
    return e === 0 & t === 0 ? this : new Oi(this.k, this.x + this.k * e, this.y + this.k * t);
  },
  apply: function(e) {
    return [e[0] * this.k + this.x, e[1] * this.k + this.y];
  },
  applyX: function(e) {
    return e * this.k + this.x;
  },
  applyY: function(e) {
    return e * this.k + this.y;
  },
  invert: function(e) {
    return [(e[0] - this.x) / this.k, (e[1] - this.y) / this.k];
  },
  invertX: function(e) {
    return (e - this.x) / this.k;
  },
  invertY: function(e) {
    return (e - this.y) / this.k;
  },
  rescaleX: function(e) {
    return e.copy().domain(e.range().map(this.invertX, this).map(e.invert, e));
  },
  rescaleY: function(e) {
    return e.copy().domain(e.range().map(this.invertY, this).map(e.invert, e));
  },
  toString: function() {
    return "translate(" + this.x + "," + this.y + ") scale(" + this.k + ")";
  }
};
Oi.prototype;
var o1 = /* @__PURE__ */ f((e) => {
  var s;
  const { securityLevel: t } = gt();
  let r = ct("body");
  if (t === "sandbox") {
    const a = ((s = ct(`#i${e}`).node()) == null ? void 0 : s.contentDocument) ?? document;
    r = ct(a.body);
  }
  return r.select(`#${e}`);
}, "selectSvgElement");
function Rn(e) {
  return typeof e > "u" || e === null;
}
f(Rn, "isNothing");
function Qu(e) {
  return typeof e == "object" && e !== null;
}
f(Qu, "isObject");
function Ju(e) {
  return Array.isArray(e) ? e : Rn(e) ? [] : [e];
}
f(Ju, "toArray");
function td(e, t) {
  var r, i, s, o;
  if (t)
    for (o = Object.keys(t), r = 0, i = o.length; r < i; r += 1)
      s = o[r], e[s] = t[s];
  return e;
}
f(td, "extend");
function ed(e, t) {
  var r = "", i;
  for (i = 0; i < t; i += 1)
    r += e;
  return r;
}
f(ed, "repeat");
function rd(e) {
  return e === 0 && Number.NEGATIVE_INFINITY === 1 / e;
}
f(rd, "isNegativeZero");
var a1 = Rn, n1 = Qu, l1 = Ju, h1 = ed, c1 = rd, u1 = td, Ot = {
  isNothing: a1,
  isObject: n1,
  toArray: l1,
  repeat: h1,
  isNegativeZero: c1,
  extend: u1
};
function Pn(e, t) {
  var r = "", i = e.reason || "(unknown reason)";
  return e.mark ? (e.mark.name && (r += 'in "' + e.mark.name + '" '), r += "(" + (e.mark.line + 1) + ":" + (e.mark.column + 1) + ")", !t && e.mark.snippet && (r += `

` + e.mark.snippet), i + " " + r) : i;
}
f(Pn, "formatError");
function ui(e, t) {
  Error.call(this), this.name = "YAMLException", this.reason = e, this.mark = t, this.message = Pn(this, !1), Error.captureStackTrace ? Error.captureStackTrace(this, this.constructor) : this.stack = new Error().stack || "";
}
f(ui, "YAMLException$1");
ui.prototype = Object.create(Error.prototype);
ui.prototype.constructor = ui;
ui.prototype.toString = /* @__PURE__ */ f(function(t) {
  return this.name + ": " + Pn(this, t);
}, "toString");
var ee = ui;
function Ns(e, t, r, i, s) {
  var o = "", a = "", n = Math.floor(s / 2) - 1;
  return i - t > n && (o = " ... ", t = i - n + o.length), r - i > n && (a = " ...", r = i + n - a.length), {
    str: o + e.slice(t, r).replace(/\t/g, "→") + a,
    pos: i - t + o.length
    // relative position
  };
}
f(Ns, "getLine");
function qs(e, t) {
  return Ot.repeat(" ", t - e.length) + e;
}
f(qs, "padStart");
function id(e, t) {
  if (t = Object.create(t || null), !e.buffer) return null;
  t.maxLength || (t.maxLength = 79), typeof t.indent != "number" && (t.indent = 1), typeof t.linesBefore != "number" && (t.linesBefore = 3), typeof t.linesAfter != "number" && (t.linesAfter = 2);
  for (var r = /\r?\n|\r|\0/g, i = [0], s = [], o, a = -1; o = r.exec(e.buffer); )
    s.push(o.index), i.push(o.index + o[0].length), e.position <= o.index && a < 0 && (a = i.length - 2);
  a < 0 && (a = i.length - 1);
  var n = "", l, h, c = Math.min(e.line + t.linesAfter, s.length).toString().length, u = t.maxLength - (t.indent + c + 3);
  for (l = 1; l <= t.linesBefore && !(a - l < 0); l++)
    h = Ns(
      e.buffer,
      i[a - l],
      s[a - l],
      e.position - (i[a] - i[a - l]),
      u
    ), n = Ot.repeat(" ", t.indent) + qs((e.line - l + 1).toString(), c) + " | " + h.str + `
` + n;
  for (h = Ns(e.buffer, i[a], s[a], e.position, u), n += Ot.repeat(" ", t.indent) + qs((e.line + 1).toString(), c) + " | " + h.str + `
`, n += Ot.repeat("-", t.indent + c + 3 + h.pos) + `^
`, l = 1; l <= t.linesAfter && !(a + l >= s.length); l++)
    h = Ns(
      e.buffer,
      i[a + l],
      s[a + l],
      e.position - (i[a] - i[a + l]),
      u
    ), n += Ot.repeat(" ", t.indent) + qs((e.line + l + 1).toString(), c) + " | " + h.str + `
`;
  return n.replace(/\n$/, "");
}
f(id, "makeSnippet");
var d1 = id, p1 = [
  "kind",
  "multi",
  "resolve",
  "construct",
  "instanceOf",
  "predicate",
  "represent",
  "representName",
  "defaultStyle",
  "styleAliases"
], f1 = [
  "scalar",
  "sequence",
  "mapping"
];
function sd(e) {
  var t = {};
  return e !== null && Object.keys(e).forEach(function(r) {
    e[r].forEach(function(i) {
      t[String(i)] = r;
    });
  }), t;
}
f(sd, "compileStyleAliases");
function od(e, t) {
  if (t = t || {}, Object.keys(t).forEach(function(r) {
    if (p1.indexOf(r) === -1)
      throw new ee('Unknown option "' + r + '" is met in definition of "' + e + '" YAML type.');
  }), this.options = t, this.tag = e, this.kind = t.kind || null, this.resolve = t.resolve || function() {
    return !0;
  }, this.construct = t.construct || function(r) {
    return r;
  }, this.instanceOf = t.instanceOf || null, this.predicate = t.predicate || null, this.represent = t.represent || null, this.representName = t.representName || null, this.defaultStyle = t.defaultStyle || null, this.multi = t.multi || !1, this.styleAliases = sd(t.styleAliases || null), f1.indexOf(this.kind) === -1)
    throw new ee('Unknown kind "' + this.kind + '" is specified for "' + e + '" YAML type.');
}
f(od, "Type$1");
var Yt = od;
function $a(e, t) {
  var r = [];
  return e[t].forEach(function(i) {
    var s = r.length;
    r.forEach(function(o, a) {
      o.tag === i.tag && o.kind === i.kind && o.multi === i.multi && (s = a);
    }), r[s] = i;
  }), r;
}
f($a, "compileList");
function ad() {
  var e = {
    scalar: {},
    sequence: {},
    mapping: {},
    fallback: {},
    multi: {
      scalar: [],
      sequence: [],
      mapping: [],
      fallback: []
    }
  }, t, r;
  function i(s) {
    s.multi ? (e.multi[s.kind].push(s), e.multi.fallback.push(s)) : e[s.kind][s.tag] = e.fallback[s.tag] = s;
  }
  for (f(i, "collectType"), t = 0, r = arguments.length; t < r; t += 1)
    arguments[t].forEach(i);
  return e;
}
f(ad, "compileMap");
function so(e) {
  return this.extend(e);
}
f(so, "Schema$1");
so.prototype.extend = /* @__PURE__ */ f(function(t) {
  var r = [], i = [];
  if (t instanceof Yt)
    i.push(t);
  else if (Array.isArray(t))
    i = i.concat(t);
  else if (t && (Array.isArray(t.implicit) || Array.isArray(t.explicit)))
    t.implicit && (r = r.concat(t.implicit)), t.explicit && (i = i.concat(t.explicit));
  else
    throw new ee("Schema.extend argument should be a Type, [ Type ], or a schema definition ({ implicit: [...], explicit: [...] })");
  r.forEach(function(o) {
    if (!(o instanceof Yt))
      throw new ee("Specified list of YAML types (or a single Type object) contains a non-Type object.");
    if (o.loadKind && o.loadKind !== "scalar")
      throw new ee("There is a non-scalar type in the implicit list of a schema. Implicit resolving of such types is not supported.");
    if (o.multi)
      throw new ee("There is a multi type in the implicit list of a schema. Multi tags can only be listed as explicit.");
  }), i.forEach(function(o) {
    if (!(o instanceof Yt))
      throw new ee("Specified list of YAML types (or a single Type object) contains a non-Type object.");
  });
  var s = Object.create(so.prototype);
  return s.implicit = (this.implicit || []).concat(r), s.explicit = (this.explicit || []).concat(i), s.compiledImplicit = $a(s, "implicit"), s.compiledExplicit = $a(s, "explicit"), s.compiledTypeMap = ad(s.compiledImplicit, s.compiledExplicit), s;
}, "extend");
var g1 = so, m1 = new Yt("tag:yaml.org,2002:str", {
  kind: "scalar",
  construct: /* @__PURE__ */ f(function(e) {
    return e !== null ? e : "";
  }, "construct")
}), y1 = new Yt("tag:yaml.org,2002:seq", {
  kind: "sequence",
  construct: /* @__PURE__ */ f(function(e) {
    return e !== null ? e : [];
  }, "construct")
}), x1 = new Yt("tag:yaml.org,2002:map", {
  kind: "mapping",
  construct: /* @__PURE__ */ f(function(e) {
    return e !== null ? e : {};
  }, "construct")
}), C1 = new g1({
  explicit: [
    m1,
    y1,
    x1
  ]
});
function nd(e) {
  if (e === null) return !0;
  var t = e.length;
  return t === 1 && e === "~" || t === 4 && (e === "null" || e === "Null" || e === "NULL");
}
f(nd, "resolveYamlNull");
function ld() {
  return null;
}
f(ld, "constructYamlNull");
function hd(e) {
  return e === null;
}
f(hd, "isNull");
var b1 = new Yt("tag:yaml.org,2002:null", {
  kind: "scalar",
  resolve: nd,
  construct: ld,
  predicate: hd,
  represent: {
    canonical: /* @__PURE__ */ f(function() {
      return "~";
    }, "canonical"),
    lowercase: /* @__PURE__ */ f(function() {
      return "null";
    }, "lowercase"),
    uppercase: /* @__PURE__ */ f(function() {
      return "NULL";
    }, "uppercase"),
    camelcase: /* @__PURE__ */ f(function() {
      return "Null";
    }, "camelcase"),
    empty: /* @__PURE__ */ f(function() {
      return "";
    }, "empty")
  },
  defaultStyle: "lowercase"
});
function cd(e) {
  if (e === null) return !1;
  var t = e.length;
  return t === 4 && (e === "true" || e === "True" || e === "TRUE") || t === 5 && (e === "false" || e === "False" || e === "FALSE");
}
f(cd, "resolveYamlBoolean");
function ud(e) {
  return e === "true" || e === "True" || e === "TRUE";
}
f(ud, "constructYamlBoolean");
function dd(e) {
  return Object.prototype.toString.call(e) === "[object Boolean]";
}
f(dd, "isBoolean");
var k1 = new Yt("tag:yaml.org,2002:bool", {
  kind: "scalar",
  resolve: cd,
  construct: ud,
  predicate: dd,
  represent: {
    lowercase: /* @__PURE__ */ f(function(e) {
      return e ? "true" : "false";
    }, "lowercase"),
    uppercase: /* @__PURE__ */ f(function(e) {
      return e ? "TRUE" : "FALSE";
    }, "uppercase"),
    camelcase: /* @__PURE__ */ f(function(e) {
      return e ? "True" : "False";
    }, "camelcase")
  },
  defaultStyle: "lowercase"
});
function pd(e) {
  return 48 <= e && e <= 57 || 65 <= e && e <= 70 || 97 <= e && e <= 102;
}
f(pd, "isHexCode");
function fd(e) {
  return 48 <= e && e <= 55;
}
f(fd, "isOctCode");
function gd(e) {
  return 48 <= e && e <= 57;
}
f(gd, "isDecCode");
function md(e) {
  if (e === null) return !1;
  var t = e.length, r = 0, i = !1, s;
  if (!t) return !1;
  if (s = e[r], (s === "-" || s === "+") && (s = e[++r]), s === "0") {
    if (r + 1 === t) return !0;
    if (s = e[++r], s === "b") {
      for (r++; r < t; r++)
        if (s = e[r], s !== "_") {
          if (s !== "0" && s !== "1") return !1;
          i = !0;
        }
      return i && s !== "_";
    }
    if (s === "x") {
      for (r++; r < t; r++)
        if (s = e[r], s !== "_") {
          if (!pd(e.charCodeAt(r))) return !1;
          i = !0;
        }
      return i && s !== "_";
    }
    if (s === "o") {
      for (r++; r < t; r++)
        if (s = e[r], s !== "_") {
          if (!fd(e.charCodeAt(r))) return !1;
          i = !0;
        }
      return i && s !== "_";
    }
  }
  if (s === "_") return !1;
  for (; r < t; r++)
    if (s = e[r], s !== "_") {
      if (!gd(e.charCodeAt(r)))
        return !1;
      i = !0;
    }
  return !(!i || s === "_");
}
f(md, "resolveYamlInteger");
function yd(e) {
  var t = e, r = 1, i;
  if (t.indexOf("_") !== -1 && (t = t.replace(/_/g, "")), i = t[0], (i === "-" || i === "+") && (i === "-" && (r = -1), t = t.slice(1), i = t[0]), t === "0") return 0;
  if (i === "0") {
    if (t[1] === "b") return r * parseInt(t.slice(2), 2);
    if (t[1] === "x") return r * parseInt(t.slice(2), 16);
    if (t[1] === "o") return r * parseInt(t.slice(2), 8);
  }
  return r * parseInt(t, 10);
}
f(yd, "constructYamlInteger");
function xd(e) {
  return Object.prototype.toString.call(e) === "[object Number]" && e % 1 === 0 && !Ot.isNegativeZero(e);
}
f(xd, "isInteger");
var T1 = new Yt("tag:yaml.org,2002:int", {
  kind: "scalar",
  resolve: md,
  construct: yd,
  predicate: xd,
  represent: {
    binary: /* @__PURE__ */ f(function(e) {
      return e >= 0 ? "0b" + e.toString(2) : "-0b" + e.toString(2).slice(1);
    }, "binary"),
    octal: /* @__PURE__ */ f(function(e) {
      return e >= 0 ? "0o" + e.toString(8) : "-0o" + e.toString(8).slice(1);
    }, "octal"),
    decimal: /* @__PURE__ */ f(function(e) {
      return e.toString(10);
    }, "decimal"),
    /* eslint-disable max-len */
    hexadecimal: /* @__PURE__ */ f(function(e) {
      return e >= 0 ? "0x" + e.toString(16).toUpperCase() : "-0x" + e.toString(16).toUpperCase().slice(1);
    }, "hexadecimal")
  },
  defaultStyle: "decimal",
  styleAliases: {
    binary: [2, "bin"],
    octal: [8, "oct"],
    decimal: [10, "dec"],
    hexadecimal: [16, "hex"]
  }
}), S1 = new RegExp(
  // 2.5e4, 2.5 and integers
  "^(?:[-+]?(?:[0-9][0-9_]*)(?:\\.[0-9_]*)?(?:[eE][-+]?[0-9]+)?|\\.[0-9_]+(?:[eE][-+]?[0-9]+)?|[-+]?\\.(?:inf|Inf|INF)|\\.(?:nan|NaN|NAN))$"
);
function Cd(e) {
  return !(e === null || !S1.test(e) || // Quick hack to not allow integers end with `_`
  // Probably should update regexp & check speed
  e[e.length - 1] === "_");
}
f(Cd, "resolveYamlFloat");
function bd(e) {
  var t, r;
  return t = e.replace(/_/g, "").toLowerCase(), r = t[0] === "-" ? -1 : 1, "+-".indexOf(t[0]) >= 0 && (t = t.slice(1)), t === ".inf" ? r === 1 ? Number.POSITIVE_INFINITY : Number.NEGATIVE_INFINITY : t === ".nan" ? NaN : r * parseFloat(t, 10);
}
f(bd, "constructYamlFloat");
var w1 = /^[-+]?[0-9]+e/;
function kd(e, t) {
  var r;
  if (isNaN(e))
    switch (t) {
      case "lowercase":
        return ".nan";
      case "uppercase":
        return ".NAN";
      case "camelcase":
        return ".NaN";
    }
  else if (Number.POSITIVE_INFINITY === e)
    switch (t) {
      case "lowercase":
        return ".inf";
      case "uppercase":
        return ".INF";
      case "camelcase":
        return ".Inf";
    }
  else if (Number.NEGATIVE_INFINITY === e)
    switch (t) {
      case "lowercase":
        return "-.inf";
      case "uppercase":
        return "-.INF";
      case "camelcase":
        return "-.Inf";
    }
  else if (Ot.isNegativeZero(e))
    return "-0.0";
  return r = e.toString(10), w1.test(r) ? r.replace("e", ".e") : r;
}
f(kd, "representYamlFloat");
function Td(e) {
  return Object.prototype.toString.call(e) === "[object Number]" && (e % 1 !== 0 || Ot.isNegativeZero(e));
}
f(Td, "isFloat");
var _1 = new Yt("tag:yaml.org,2002:float", {
  kind: "scalar",
  resolve: Cd,
  construct: bd,
  predicate: Td,
  represent: kd,
  defaultStyle: "lowercase"
}), Sd = C1.extend({
  implicit: [
    b1,
    k1,
    T1,
    _1
  ]
}), B1 = Sd, wd = new RegExp(
  "^([0-9][0-9][0-9][0-9])-([0-9][0-9])-([0-9][0-9])$"
), _d = new RegExp(
  "^([0-9][0-9][0-9][0-9])-([0-9][0-9]?)-([0-9][0-9]?)(?:[Tt]|[ \\t]+)([0-9][0-9]?):([0-9][0-9]):([0-9][0-9])(?:\\.([0-9]*))?(?:[ \\t]*(Z|([-+])([0-9][0-9]?)(?::([0-9][0-9]))?))?$"
);
function Bd(e) {
  return e === null ? !1 : wd.exec(e) !== null || _d.exec(e) !== null;
}
f(Bd, "resolveYamlTimestamp");
function vd(e) {
  var t, r, i, s, o, a, n, l = 0, h = null, c, u, p;
  if (t = wd.exec(e), t === null && (t = _d.exec(e)), t === null) throw new Error("Date resolve error");
  if (r = +t[1], i = +t[2] - 1, s = +t[3], !t[4])
    return new Date(Date.UTC(r, i, s));
  if (o = +t[4], a = +t[5], n = +t[6], t[7]) {
    for (l = t[7].slice(0, 3); l.length < 3; )
      l += "0";
    l = +l;
  }
  return t[9] && (c = +t[10], u = +(t[11] || 0), h = (c * 60 + u) * 6e4, t[9] === "-" && (h = -h)), p = new Date(Date.UTC(r, i, s, o, a, n, l)), h && p.setTime(p.getTime() - h), p;
}
f(vd, "constructYamlTimestamp");
function Ld(e) {
  return e.toISOString();
}
f(Ld, "representYamlTimestamp");
var v1 = new Yt("tag:yaml.org,2002:timestamp", {
  kind: "scalar",
  resolve: Bd,
  construct: vd,
  instanceOf: Date,
  represent: Ld
});
function Ad(e) {
  return e === "<<" || e === null;
}
f(Ad, "resolveYamlMerge");
var L1 = new Yt("tag:yaml.org,2002:merge", {
  kind: "scalar",
  resolve: Ad
}), Nn = `ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=
\r`;
function Ed(e) {
  if (e === null) return !1;
  var t, r, i = 0, s = e.length, o = Nn;
  for (r = 0; r < s; r++)
    if (t = o.indexOf(e.charAt(r)), !(t > 64)) {
      if (t < 0) return !1;
      i += 6;
    }
  return i % 8 === 0;
}
f(Ed, "resolveYamlBinary");
function Fd(e) {
  var t, r, i = e.replace(/[\r\n=]/g, ""), s = i.length, o = Nn, a = 0, n = [];
  for (t = 0; t < s; t++)
    t % 4 === 0 && t && (n.push(a >> 16 & 255), n.push(a >> 8 & 255), n.push(a & 255)), a = a << 6 | o.indexOf(i.charAt(t));
  return r = s % 4 * 6, r === 0 ? (n.push(a >> 16 & 255), n.push(a >> 8 & 255), n.push(a & 255)) : r === 18 ? (n.push(a >> 10 & 255), n.push(a >> 2 & 255)) : r === 12 && n.push(a >> 4 & 255), new Uint8Array(n);
}
f(Fd, "constructYamlBinary");
function Md(e) {
  var t = "", r = 0, i, s, o = e.length, a = Nn;
  for (i = 0; i < o; i++)
    i % 3 === 0 && i && (t += a[r >> 18 & 63], t += a[r >> 12 & 63], t += a[r >> 6 & 63], t += a[r & 63]), r = (r << 8) + e[i];
  return s = o % 3, s === 0 ? (t += a[r >> 18 & 63], t += a[r >> 12 & 63], t += a[r >> 6 & 63], t += a[r & 63]) : s === 2 ? (t += a[r >> 10 & 63], t += a[r >> 4 & 63], t += a[r << 2 & 63], t += a[64]) : s === 1 && (t += a[r >> 2 & 63], t += a[r << 4 & 63], t += a[64], t += a[64]), t;
}
f(Md, "representYamlBinary");
function Id(e) {
  return Object.prototype.toString.call(e) === "[object Uint8Array]";
}
f(Id, "isBinary");
var A1 = new Yt("tag:yaml.org,2002:binary", {
  kind: "scalar",
  resolve: Ed,
  construct: Fd,
  predicate: Id,
  represent: Md
}), E1 = Object.prototype.hasOwnProperty, F1 = Object.prototype.toString;
function $d(e) {
  if (e === null) return !0;
  var t = [], r, i, s, o, a, n = e;
  for (r = 0, i = n.length; r < i; r += 1) {
    if (s = n[r], a = !1, F1.call(s) !== "[object Object]") return !1;
    for (o in s)
      if (E1.call(s, o))
        if (!a) a = !0;
        else return !1;
    if (!a) return !1;
    if (t.indexOf(o) === -1) t.push(o);
    else return !1;
  }
  return !0;
}
f($d, "resolveYamlOmap");
function Od(e) {
  return e !== null ? e : [];
}
f(Od, "constructYamlOmap");
var M1 = new Yt("tag:yaml.org,2002:omap", {
  kind: "sequence",
  resolve: $d,
  construct: Od
}), I1 = Object.prototype.toString;
function Dd(e) {
  if (e === null) return !0;
  var t, r, i, s, o, a = e;
  for (o = new Array(a.length), t = 0, r = a.length; t < r; t += 1) {
    if (i = a[t], I1.call(i) !== "[object Object]" || (s = Object.keys(i), s.length !== 1)) return !1;
    o[t] = [s[0], i[s[0]]];
  }
  return !0;
}
f(Dd, "resolveYamlPairs");
function Rd(e) {
  if (e === null) return [];
  var t, r, i, s, o, a = e;
  for (o = new Array(a.length), t = 0, r = a.length; t < r; t += 1)
    i = a[t], s = Object.keys(i), o[t] = [s[0], i[s[0]]];
  return o;
}
f(Rd, "constructYamlPairs");
var $1 = new Yt("tag:yaml.org,2002:pairs", {
  kind: "sequence",
  resolve: Dd,
  construct: Rd
}), O1 = Object.prototype.hasOwnProperty;
function Pd(e) {
  if (e === null) return !0;
  var t, r = e;
  for (t in r)
    if (O1.call(r, t) && r[t] !== null)
      return !1;
  return !0;
}
f(Pd, "resolveYamlSet");
function Nd(e) {
  return e !== null ? e : {};
}
f(Nd, "constructYamlSet");
var D1 = new Yt("tag:yaml.org,2002:set", {
  kind: "mapping",
  resolve: Pd,
  construct: Nd
}), qd = B1.extend({
  implicit: [
    v1,
    L1
  ],
  explicit: [
    A1,
    M1,
    $1,
    D1
  ]
}), sr = Object.prototype.hasOwnProperty, oo = 1, Wd = 2, zd = 3, ao = 4, oa = 1, R1 = 2, Bh = 3, P1 = /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x84\x86-\x9F\uFFFE\uFFFF]|[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?:[^\uD800-\uDBFF]|^)[\uDC00-\uDFFF]/, N1 = /[\x85\u2028\u2029]/, q1 = /[,\[\]\{\}]/, Hd = /^(?:!|!!|![a-z\-]+!)$/i, Yd = /^(?:!|[^,\[\]\{\}])(?:%[0-9a-f]{2}|[0-9a-z\-#;\/\?:@&=\+\$,_\.!~\*'\(\)\[\]])*$/i;
function Oa(e) {
  return Object.prototype.toString.call(e);
}
f(Oa, "_class");
function Te(e) {
  return e === 10 || e === 13;
}
f(Te, "is_EOL");
function rr(e) {
  return e === 9 || e === 32;
}
f(rr, "is_WHITE_SPACE");
function Gt(e) {
  return e === 9 || e === 32 || e === 10 || e === 13;
}
f(Gt, "is_WS_OR_EOL");
function pr(e) {
  return e === 44 || e === 91 || e === 93 || e === 123 || e === 125;
}
f(pr, "is_FLOW_INDICATOR");
function Xd(e) {
  var t;
  return 48 <= e && e <= 57 ? e - 48 : (t = e | 32, 97 <= t && t <= 102 ? t - 97 + 10 : -1);
}
f(Xd, "fromHexCode");
function Ud(e) {
  return e === 120 ? 2 : e === 117 ? 4 : e === 85 ? 8 : 0;
}
f(Ud, "escapedHexLen");
function jd(e) {
  return 48 <= e && e <= 57 ? e - 48 : -1;
}
f(jd, "fromDecimalCode");
function Da(e) {
  return e === 48 ? "\0" : e === 97 ? "\x07" : e === 98 ? "\b" : e === 116 || e === 9 ? "	" : e === 110 ? `
` : e === 118 ? "\v" : e === 102 ? "\f" : e === 114 ? "\r" : e === 101 ? "\x1B" : e === 32 ? " " : e === 34 ? '"' : e === 47 ? "/" : e === 92 ? "\\" : e === 78 ? "" : e === 95 ? " " : e === 76 ? "\u2028" : e === 80 ? "\u2029" : "";
}
f(Da, "simpleEscapeSequence");
function Gd(e) {
  return e <= 65535 ? String.fromCharCode(e) : String.fromCharCode(
    (e - 65536 >> 10) + 55296,
    (e - 65536 & 1023) + 56320
  );
}
f(Gd, "charFromCodepoint");
function qn(e, t, r) {
  t === "__proto__" ? Object.defineProperty(e, t, {
    configurable: !0,
    enumerable: !0,
    writable: !0,
    value: r
  }) : e[t] = r;
}
f(qn, "setProperty");
var Vd = new Array(256), Zd = new Array(256);
for (hr = 0; hr < 256; hr++)
  Vd[hr] = Da(hr) ? 1 : 0, Zd[hr] = Da(hr);
var hr;
function Kd(e, t) {
  this.input = e, this.filename = t.filename || null, this.schema = t.schema || qd, this.onWarning = t.onWarning || null, this.legacy = t.legacy || !1, this.json = t.json || !1, this.listener = t.listener || null, this.implicitTypes = this.schema.compiledImplicit, this.typeMap = this.schema.compiledTypeMap, this.length = e.length, this.position = 0, this.line = 0, this.lineStart = 0, this.lineIndent = 0, this.firstTabInLine = -1, this.documents = [];
}
f(Kd, "State$1");
function Wn(e, t) {
  var r = {
    name: e.filename,
    buffer: e.input.slice(0, -1),
    // omit trailing \0
    position: e.position,
    line: e.line,
    column: e.position - e.lineStart
  };
  return r.snippet = d1(r), new ee(t, r);
}
f(Wn, "generateError");
function et(e, t) {
  throw Wn(e, t);
}
f(et, "throwError");
function Qi(e, t) {
  e.onWarning && e.onWarning.call(null, Wn(e, t));
}
f(Qi, "throwWarning");
var vh = {
  YAML: /* @__PURE__ */ f(function(t, r, i) {
    var s, o, a;
    t.version !== null && et(t, "duplication of %YAML directive"), i.length !== 1 && et(t, "YAML directive accepts exactly one argument"), s = /^([0-9]+)\.([0-9]+)$/.exec(i[0]), s === null && et(t, "ill-formed argument of the YAML directive"), o = parseInt(s[1], 10), a = parseInt(s[2], 10), o !== 1 && et(t, "unacceptable YAML version of the document"), t.version = i[0], t.checkLineBreaks = a < 2, a !== 1 && a !== 2 && Qi(t, "unsupported YAML version of the document");
  }, "handleYamlDirective"),
  TAG: /* @__PURE__ */ f(function(t, r, i) {
    var s, o;
    i.length !== 2 && et(t, "TAG directive accepts exactly two arguments"), s = i[0], o = i[1], Hd.test(s) || et(t, "ill-formed tag handle (first argument) of the TAG directive"), sr.call(t.tagMap, s) && et(t, 'there is a previously declared suffix for "' + s + '" tag handle'), Yd.test(o) || et(t, "ill-formed tag prefix (second argument) of the TAG directive");
    try {
      o = decodeURIComponent(o);
    } catch {
      et(t, "tag prefix is malformed: " + o);
    }
    t.tagMap[s] = o;
  }, "handleTagDirective")
};
function Xe(e, t, r, i) {
  var s, o, a, n;
  if (t < r) {
    if (n = e.input.slice(t, r), i)
      for (s = 0, o = n.length; s < o; s += 1)
        a = n.charCodeAt(s), a === 9 || 32 <= a && a <= 1114111 || et(e, "expected valid JSON character");
    else P1.test(n) && et(e, "the stream contains non-printable characters");
    e.result += n;
  }
}
f(Xe, "captureSegment");
function Ra(e, t, r, i) {
  var s, o, a, n;
  for (Ot.isObject(r) || et(e, "cannot merge mappings; the provided source object is unacceptable"), s = Object.keys(r), a = 0, n = s.length; a < n; a += 1)
    o = s[a], sr.call(t, o) || (qn(t, o, r[o]), i[o] = !0);
}
f(Ra, "mergeMappings");
function fr(e, t, r, i, s, o, a, n, l) {
  var h, c;
  if (Array.isArray(s))
    for (s = Array.prototype.slice.call(s), h = 0, c = s.length; h < c; h += 1)
      Array.isArray(s[h]) && et(e, "nested arrays are not supported inside keys"), typeof s == "object" && Oa(s[h]) === "[object Object]" && (s[h] = "[object Object]");
  if (typeof s == "object" && Oa(s) === "[object Object]" && (s = "[object Object]"), s = String(s), t === null && (t = {}), i === "tag:yaml.org,2002:merge")
    if (Array.isArray(o))
      for (h = 0, c = o.length; h < c; h += 1)
        Ra(e, t, o[h], r);
    else
      Ra(e, t, o, r);
  else
    !e.json && !sr.call(r, s) && sr.call(t, s) && (e.line = a || e.line, e.lineStart = n || e.lineStart, e.position = l || e.position, et(e, "duplicated mapping key")), qn(t, s, o), delete r[s];
  return t;
}
f(fr, "storeMappingPair");
function vo(e) {
  var t;
  t = e.input.charCodeAt(e.position), t === 10 ? e.position++ : t === 13 ? (e.position++, e.input.charCodeAt(e.position) === 10 && e.position++) : et(e, "a line break is expected"), e.line += 1, e.lineStart = e.position, e.firstTabInLine = -1;
}
f(vo, "readLineBreak");
function Lt(e, t, r) {
  for (var i = 0, s = e.input.charCodeAt(e.position); s !== 0; ) {
    for (; rr(s); )
      s === 9 && e.firstTabInLine === -1 && (e.firstTabInLine = e.position), s = e.input.charCodeAt(++e.position);
    if (t && s === 35)
      do
        s = e.input.charCodeAt(++e.position);
      while (s !== 10 && s !== 13 && s !== 0);
    if (Te(s))
      for (vo(e), s = e.input.charCodeAt(e.position), i++, e.lineIndent = 0; s === 32; )
        e.lineIndent++, s = e.input.charCodeAt(++e.position);
    else
      break;
  }
  return r !== -1 && i !== 0 && e.lineIndent < r && Qi(e, "deficient indentation"), i;
}
f(Lt, "skipSeparationSpace");
function us(e) {
  var t = e.position, r;
  return r = e.input.charCodeAt(t), !!((r === 45 || r === 46) && r === e.input.charCodeAt(t + 1) && r === e.input.charCodeAt(t + 2) && (t += 3, r = e.input.charCodeAt(t), r === 0 || Gt(r)));
}
f(us, "testDocumentSeparator");
function Lo(e, t) {
  t === 1 ? e.result += " " : t > 1 && (e.result += Ot.repeat(`
`, t - 1));
}
f(Lo, "writeFoldedLines");
function Qd(e, t, r) {
  var i, s, o, a, n, l, h, c, u = e.kind, p = e.result, d;
  if (d = e.input.charCodeAt(e.position), Gt(d) || pr(d) || d === 35 || d === 38 || d === 42 || d === 33 || d === 124 || d === 62 || d === 39 || d === 34 || d === 37 || d === 64 || d === 96 || (d === 63 || d === 45) && (s = e.input.charCodeAt(e.position + 1), Gt(s) || r && pr(s)))
    return !1;
  for (e.kind = "scalar", e.result = "", o = a = e.position, n = !1; d !== 0; ) {
    if (d === 58) {
      if (s = e.input.charCodeAt(e.position + 1), Gt(s) || r && pr(s))
        break;
    } else if (d === 35) {
      if (i = e.input.charCodeAt(e.position - 1), Gt(i))
        break;
    } else {
      if (e.position === e.lineStart && us(e) || r && pr(d))
        break;
      if (Te(d))
        if (l = e.line, h = e.lineStart, c = e.lineIndent, Lt(e, !1, -1), e.lineIndent >= t) {
          n = !0, d = e.input.charCodeAt(e.position);
          continue;
        } else {
          e.position = a, e.line = l, e.lineStart = h, e.lineIndent = c;
          break;
        }
    }
    n && (Xe(e, o, a, !1), Lo(e, e.line - l), o = a = e.position, n = !1), rr(d) || (a = e.position + 1), d = e.input.charCodeAt(++e.position);
  }
  return Xe(e, o, a, !1), e.result ? !0 : (e.kind = u, e.result = p, !1);
}
f(Qd, "readPlainScalar");
function Jd(e, t) {
  var r, i, s;
  if (r = e.input.charCodeAt(e.position), r !== 39)
    return !1;
  for (e.kind = "scalar", e.result = "", e.position++, i = s = e.position; (r = e.input.charCodeAt(e.position)) !== 0; )
    if (r === 39)
      if (Xe(e, i, e.position, !0), r = e.input.charCodeAt(++e.position), r === 39)
        i = e.position, e.position++, s = e.position;
      else
        return !0;
    else Te(r) ? (Xe(e, i, s, !0), Lo(e, Lt(e, !1, t)), i = s = e.position) : e.position === e.lineStart && us(e) ? et(e, "unexpected end of the document within a single quoted scalar") : (e.position++, s = e.position);
  et(e, "unexpected end of the stream within a single quoted scalar");
}
f(Jd, "readSingleQuotedScalar");
function tp(e, t) {
  var r, i, s, o, a, n;
  if (n = e.input.charCodeAt(e.position), n !== 34)
    return !1;
  for (e.kind = "scalar", e.result = "", e.position++, r = i = e.position; (n = e.input.charCodeAt(e.position)) !== 0; ) {
    if (n === 34)
      return Xe(e, r, e.position, !0), e.position++, !0;
    if (n === 92) {
      if (Xe(e, r, e.position, !0), n = e.input.charCodeAt(++e.position), Te(n))
        Lt(e, !1, t);
      else if (n < 256 && Vd[n])
        e.result += Zd[n], e.position++;
      else if ((a = Ud(n)) > 0) {
        for (s = a, o = 0; s > 0; s--)
          n = e.input.charCodeAt(++e.position), (a = Xd(n)) >= 0 ? o = (o << 4) + a : et(e, "expected hexadecimal character");
        e.result += Gd(o), e.position++;
      } else
        et(e, "unknown escape sequence");
      r = i = e.position;
    } else Te(n) ? (Xe(e, r, i, !0), Lo(e, Lt(e, !1, t)), r = i = e.position) : e.position === e.lineStart && us(e) ? et(e, "unexpected end of the document within a double quoted scalar") : (e.position++, i = e.position);
  }
  et(e, "unexpected end of the stream within a double quoted scalar");
}
f(tp, "readDoubleQuotedScalar");
function ep(e, t) {
  var r = !0, i, s, o, a = e.tag, n, l = e.anchor, h, c, u, p, d, g = /* @__PURE__ */ Object.create(null), m, y, x, b;
  if (b = e.input.charCodeAt(e.position), b === 91)
    c = 93, d = !1, n = [];
  else if (b === 123)
    c = 125, d = !0, n = {};
  else
    return !1;
  for (e.anchor !== null && (e.anchorMap[e.anchor] = n), b = e.input.charCodeAt(++e.position); b !== 0; ) {
    if (Lt(e, !0, t), b = e.input.charCodeAt(e.position), b === c)
      return e.position++, e.tag = a, e.anchor = l, e.kind = d ? "mapping" : "sequence", e.result = n, !0;
    r ? b === 44 && et(e, "expected the node content, but found ','") : et(e, "missed comma between flow collection entries"), y = m = x = null, u = p = !1, b === 63 && (h = e.input.charCodeAt(e.position + 1), Gt(h) && (u = p = !0, e.position++, Lt(e, !0, t))), i = e.line, s = e.lineStart, o = e.position, wr(e, t, oo, !1, !0), y = e.tag, m = e.result, Lt(e, !0, t), b = e.input.charCodeAt(e.position), (p || e.line === i) && b === 58 && (u = !0, b = e.input.charCodeAt(++e.position), Lt(e, !0, t), wr(e, t, oo, !1, !0), x = e.result), d ? fr(e, n, g, y, m, x, i, s, o) : u ? n.push(fr(e, null, g, y, m, x, i, s, o)) : n.push(m), Lt(e, !0, t), b = e.input.charCodeAt(e.position), b === 44 ? (r = !0, b = e.input.charCodeAt(++e.position)) : r = !1;
  }
  et(e, "unexpected end of the stream within a flow collection");
}
f(ep, "readFlowCollection");
function rp(e, t) {
  var r, i, s = oa, o = !1, a = !1, n = t, l = 0, h = !1, c, u;
  if (u = e.input.charCodeAt(e.position), u === 124)
    i = !1;
  else if (u === 62)
    i = !0;
  else
    return !1;
  for (e.kind = "scalar", e.result = ""; u !== 0; )
    if (u = e.input.charCodeAt(++e.position), u === 43 || u === 45)
      oa === s ? s = u === 43 ? Bh : R1 : et(e, "repeat of a chomping mode identifier");
    else if ((c = jd(u)) >= 0)
      c === 0 ? et(e, "bad explicit indentation width of a block scalar; it cannot be less than one") : a ? et(e, "repeat of an indentation width identifier") : (n = t + c - 1, a = !0);
    else
      break;
  if (rr(u)) {
    do
      u = e.input.charCodeAt(++e.position);
    while (rr(u));
    if (u === 35)
      do
        u = e.input.charCodeAt(++e.position);
      while (!Te(u) && u !== 0);
  }
  for (; u !== 0; ) {
    for (vo(e), e.lineIndent = 0, u = e.input.charCodeAt(e.position); (!a || e.lineIndent < n) && u === 32; )
      e.lineIndent++, u = e.input.charCodeAt(++e.position);
    if (!a && e.lineIndent > n && (n = e.lineIndent), Te(u)) {
      l++;
      continue;
    }
    if (e.lineIndent < n) {
      s === Bh ? e.result += Ot.repeat(`
`, o ? 1 + l : l) : s === oa && o && (e.result += `
`);
      break;
    }
    for (i ? rr(u) ? (h = !0, e.result += Ot.repeat(`
`, o ? 1 + l : l)) : h ? (h = !1, e.result += Ot.repeat(`
`, l + 1)) : l === 0 ? o && (e.result += " ") : e.result += Ot.repeat(`
`, l) : e.result += Ot.repeat(`
`, o ? 1 + l : l), o = !0, a = !0, l = 0, r = e.position; !Te(u) && u !== 0; )
      u = e.input.charCodeAt(++e.position);
    Xe(e, r, e.position, !1);
  }
  return !0;
}
f(rp, "readBlockScalar");
function Pa(e, t) {
  var r, i = e.tag, s = e.anchor, o = [], a, n = !1, l;
  if (e.firstTabInLine !== -1) return !1;
  for (e.anchor !== null && (e.anchorMap[e.anchor] = o), l = e.input.charCodeAt(e.position); l !== 0 && (e.firstTabInLine !== -1 && (e.position = e.firstTabInLine, et(e, "tab characters must not be used in indentation")), !(l !== 45 || (a = e.input.charCodeAt(e.position + 1), !Gt(a)))); ) {
    if (n = !0, e.position++, Lt(e, !0, -1) && e.lineIndent <= t) {
      o.push(null), l = e.input.charCodeAt(e.position);
      continue;
    }
    if (r = e.line, wr(e, t, zd, !1, !0), o.push(e.result), Lt(e, !0, -1), l = e.input.charCodeAt(e.position), (e.line === r || e.lineIndent > t) && l !== 0)
      et(e, "bad indentation of a sequence entry");
    else if (e.lineIndent < t)
      break;
  }
  return n ? (e.tag = i, e.anchor = s, e.kind = "sequence", e.result = o, !0) : !1;
}
f(Pa, "readBlockSequence");
function ip(e, t, r) {
  var i, s, o, a, n, l, h = e.tag, c = e.anchor, u = {}, p = /* @__PURE__ */ Object.create(null), d = null, g = null, m = null, y = !1, x = !1, b;
  if (e.firstTabInLine !== -1) return !1;
  for (e.anchor !== null && (e.anchorMap[e.anchor] = u), b = e.input.charCodeAt(e.position); b !== 0; ) {
    if (!y && e.firstTabInLine !== -1 && (e.position = e.firstTabInLine, et(e, "tab characters must not be used in indentation")), i = e.input.charCodeAt(e.position + 1), o = e.line, (b === 63 || b === 58) && Gt(i))
      b === 63 ? (y && (fr(e, u, p, d, g, null, a, n, l), d = g = m = null), x = !0, y = !0, s = !0) : y ? (y = !1, s = !0) : et(e, "incomplete explicit mapping pair; a key node is missed; or followed by a non-tabulated empty line"), e.position += 1, b = i;
    else {
      if (a = e.line, n = e.lineStart, l = e.position, !wr(e, r, Wd, !1, !0))
        break;
      if (e.line === o) {
        for (b = e.input.charCodeAt(e.position); rr(b); )
          b = e.input.charCodeAt(++e.position);
        if (b === 58)
          b = e.input.charCodeAt(++e.position), Gt(b) || et(e, "a whitespace character is expected after the key-value separator within a block mapping"), y && (fr(e, u, p, d, g, null, a, n, l), d = g = m = null), x = !0, y = !1, s = !1, d = e.tag, g = e.result;
        else if (x)
          et(e, "can not read an implicit mapping pair; a colon is missed");
        else
          return e.tag = h, e.anchor = c, !0;
      } else if (x)
        et(e, "can not read a block mapping entry; a multiline key may not be an implicit key");
      else
        return e.tag = h, e.anchor = c, !0;
    }
    if ((e.line === o || e.lineIndent > t) && (y && (a = e.line, n = e.lineStart, l = e.position), wr(e, t, ao, !0, s) && (y ? g = e.result : m = e.result), y || (fr(e, u, p, d, g, m, a, n, l), d = g = m = null), Lt(e, !0, -1), b = e.input.charCodeAt(e.position)), (e.line === o || e.lineIndent > t) && b !== 0)
      et(e, "bad indentation of a mapping entry");
    else if (e.lineIndent < t)
      break;
  }
  return y && fr(e, u, p, d, g, null, a, n, l), x && (e.tag = h, e.anchor = c, e.kind = "mapping", e.result = u), x;
}
f(ip, "readBlockMapping");
function sp(e) {
  var t, r = !1, i = !1, s, o, a;
  if (a = e.input.charCodeAt(e.position), a !== 33) return !1;
  if (e.tag !== null && et(e, "duplication of a tag property"), a = e.input.charCodeAt(++e.position), a === 60 ? (r = !0, a = e.input.charCodeAt(++e.position)) : a === 33 ? (i = !0, s = "!!", a = e.input.charCodeAt(++e.position)) : s = "!", t = e.position, r) {
    do
      a = e.input.charCodeAt(++e.position);
    while (a !== 0 && a !== 62);
    e.position < e.length ? (o = e.input.slice(t, e.position), a = e.input.charCodeAt(++e.position)) : et(e, "unexpected end of the stream within a verbatim tag");
  } else {
    for (; a !== 0 && !Gt(a); )
      a === 33 && (i ? et(e, "tag suffix cannot contain exclamation marks") : (s = e.input.slice(t - 1, e.position + 1), Hd.test(s) || et(e, "named tag handle cannot contain such characters"), i = !0, t = e.position + 1)), a = e.input.charCodeAt(++e.position);
    o = e.input.slice(t, e.position), q1.test(o) && et(e, "tag suffix cannot contain flow indicator characters");
  }
  o && !Yd.test(o) && et(e, "tag name cannot contain such characters: " + o);
  try {
    o = decodeURIComponent(o);
  } catch {
    et(e, "tag name is malformed: " + o);
  }
  return r ? e.tag = o : sr.call(e.tagMap, s) ? e.tag = e.tagMap[s] + o : s === "!" ? e.tag = "!" + o : s === "!!" ? e.tag = "tag:yaml.org,2002:" + o : et(e, 'undeclared tag handle "' + s + '"'), !0;
}
f(sp, "readTagProperty");
function op(e) {
  var t, r;
  if (r = e.input.charCodeAt(e.position), r !== 38) return !1;
  for (e.anchor !== null && et(e, "duplication of an anchor property"), r = e.input.charCodeAt(++e.position), t = e.position; r !== 0 && !Gt(r) && !pr(r); )
    r = e.input.charCodeAt(++e.position);
  return e.position === t && et(e, "name of an anchor node must contain at least one character"), e.anchor = e.input.slice(t, e.position), !0;
}
f(op, "readAnchorProperty");
function ap(e) {
  var t, r, i;
  if (i = e.input.charCodeAt(e.position), i !== 42) return !1;
  for (i = e.input.charCodeAt(++e.position), t = e.position; i !== 0 && !Gt(i) && !pr(i); )
    i = e.input.charCodeAt(++e.position);
  return e.position === t && et(e, "name of an alias node must contain at least one character"), r = e.input.slice(t, e.position), sr.call(e.anchorMap, r) || et(e, 'unidentified alias "' + r + '"'), e.result = e.anchorMap[r], Lt(e, !0, -1), !0;
}
f(ap, "readAlias");
function wr(e, t, r, i, s) {
  var o, a, n, l = 1, h = !1, c = !1, u, p, d, g, m, y;
  if (e.listener !== null && e.listener("open", e), e.tag = null, e.anchor = null, e.kind = null, e.result = null, o = a = n = ao === r || zd === r, i && Lt(e, !0, -1) && (h = !0, e.lineIndent > t ? l = 1 : e.lineIndent === t ? l = 0 : e.lineIndent < t && (l = -1)), l === 1)
    for (; sp(e) || op(e); )
      Lt(e, !0, -1) ? (h = !0, n = o, e.lineIndent > t ? l = 1 : e.lineIndent === t ? l = 0 : e.lineIndent < t && (l = -1)) : n = !1;
  if (n && (n = h || s), (l === 1 || ao === r) && (oo === r || Wd === r ? m = t : m = t + 1, y = e.position - e.lineStart, l === 1 ? n && (Pa(e, y) || ip(e, y, m)) || ep(e, m) ? c = !0 : (a && rp(e, m) || Jd(e, m) || tp(e, m) ? c = !0 : ap(e) ? (c = !0, (e.tag !== null || e.anchor !== null) && et(e, "alias node should not have any properties")) : Qd(e, m, oo === r) && (c = !0, e.tag === null && (e.tag = "?")), e.anchor !== null && (e.anchorMap[e.anchor] = e.result)) : l === 0 && (c = n && Pa(e, y))), e.tag === null)
    e.anchor !== null && (e.anchorMap[e.anchor] = e.result);
  else if (e.tag === "?") {
    for (e.result !== null && e.kind !== "scalar" && et(e, 'unacceptable node kind for !<?> tag; it should be "scalar", not "' + e.kind + '"'), u = 0, p = e.implicitTypes.length; u < p; u += 1)
      if (g = e.implicitTypes[u], g.resolve(e.result)) {
        e.result = g.construct(e.result), e.tag = g.tag, e.anchor !== null && (e.anchorMap[e.anchor] = e.result);
        break;
      }
  } else if (e.tag !== "!") {
    if (sr.call(e.typeMap[e.kind || "fallback"], e.tag))
      g = e.typeMap[e.kind || "fallback"][e.tag];
    else
      for (g = null, d = e.typeMap.multi[e.kind || "fallback"], u = 0, p = d.length; u < p; u += 1)
        if (e.tag.slice(0, d[u].tag.length) === d[u].tag) {
          g = d[u];
          break;
        }
    g || et(e, "unknown tag !<" + e.tag + ">"), e.result !== null && g.kind !== e.kind && et(e, "unacceptable node kind for !<" + e.tag + '> tag; it should be "' + g.kind + '", not "' + e.kind + '"'), g.resolve(e.result, e.tag) ? (e.result = g.construct(e.result, e.tag), e.anchor !== null && (e.anchorMap[e.anchor] = e.result)) : et(e, "cannot resolve a node with !<" + e.tag + "> explicit tag");
  }
  return e.listener !== null && e.listener("close", e), e.tag !== null || e.anchor !== null || c;
}
f(wr, "composeNode");
function np(e) {
  var t = e.position, r, i, s, o = !1, a;
  for (e.version = null, e.checkLineBreaks = e.legacy, e.tagMap = /* @__PURE__ */ Object.create(null), e.anchorMap = /* @__PURE__ */ Object.create(null); (a = e.input.charCodeAt(e.position)) !== 0 && (Lt(e, !0, -1), a = e.input.charCodeAt(e.position), !(e.lineIndent > 0 || a !== 37)); ) {
    for (o = !0, a = e.input.charCodeAt(++e.position), r = e.position; a !== 0 && !Gt(a); )
      a = e.input.charCodeAt(++e.position);
    for (i = e.input.slice(r, e.position), s = [], i.length < 1 && et(e, "directive name must not be less than one character in length"); a !== 0; ) {
      for (; rr(a); )
        a = e.input.charCodeAt(++e.position);
      if (a === 35) {
        do
          a = e.input.charCodeAt(++e.position);
        while (a !== 0 && !Te(a));
        break;
      }
      if (Te(a)) break;
      for (r = e.position; a !== 0 && !Gt(a); )
        a = e.input.charCodeAt(++e.position);
      s.push(e.input.slice(r, e.position));
    }
    a !== 0 && vo(e), sr.call(vh, i) ? vh[i](e, i, s) : Qi(e, 'unknown document directive "' + i + '"');
  }
  if (Lt(e, !0, -1), e.lineIndent === 0 && e.input.charCodeAt(e.position) === 45 && e.input.charCodeAt(e.position + 1) === 45 && e.input.charCodeAt(e.position + 2) === 45 ? (e.position += 3, Lt(e, !0, -1)) : o && et(e, "directives end mark is expected"), wr(e, e.lineIndent - 1, ao, !1, !0), Lt(e, !0, -1), e.checkLineBreaks && N1.test(e.input.slice(t, e.position)) && Qi(e, "non-ASCII line breaks are interpreted as content"), e.documents.push(e.result), e.position === e.lineStart && us(e)) {
    e.input.charCodeAt(e.position) === 46 && (e.position += 3, Lt(e, !0, -1));
    return;
  }
  if (e.position < e.length - 1)
    et(e, "end of the stream or a document separator is expected");
  else
    return;
}
f(np, "readDocument");
function zn(e, t) {
  e = String(e), t = t || {}, e.length !== 0 && (e.charCodeAt(e.length - 1) !== 10 && e.charCodeAt(e.length - 1) !== 13 && (e += `
`), e.charCodeAt(0) === 65279 && (e = e.slice(1)));
  var r = new Kd(e, t), i = e.indexOf("\0");
  for (i !== -1 && (r.position = i, et(r, "null byte is not allowed in input")), r.input += "\0"; r.input.charCodeAt(r.position) === 32; )
    r.lineIndent += 1, r.position += 1;
  for (; r.position < r.length - 1; )
    np(r);
  return r.documents;
}
f(zn, "loadDocuments");
function W1(e, t, r) {
  t !== null && typeof t == "object" && typeof r > "u" && (r = t, t = null);
  var i = zn(e, r);
  if (typeof t != "function")
    return i;
  for (var s = 0, o = i.length; s < o; s += 1)
    t(i[s]);
}
f(W1, "loadAll$1");
function lp(e, t) {
  var r = zn(e, t);
  if (r.length !== 0) {
    if (r.length === 1)
      return r[0];
    throw new ee("expected a single document in the stream, but found more");
  }
}
f(lp, "load$1");
var z1 = lp, H1 = {
  load: z1
}, hp = Object.prototype.toString, cp = Object.prototype.hasOwnProperty, Hn = 65279, Y1 = 9, Ji = 10, X1 = 13, U1 = 32, j1 = 33, G1 = 34, Na = 35, V1 = 37, Z1 = 38, K1 = 39, Q1 = 42, up = 44, J1 = 45, no = 58, t2 = 61, e2 = 62, r2 = 63, i2 = 64, dp = 91, pp = 93, s2 = 96, fp = 123, o2 = 124, gp = 125, Xt = {};
Xt[0] = "\\0";
Xt[7] = "\\a";
Xt[8] = "\\b";
Xt[9] = "\\t";
Xt[10] = "\\n";
Xt[11] = "\\v";
Xt[12] = "\\f";
Xt[13] = "\\r";
Xt[27] = "\\e";
Xt[34] = '\\"';
Xt[92] = "\\\\";
Xt[133] = "\\N";
Xt[160] = "\\_";
Xt[8232] = "\\L";
Xt[8233] = "\\P";
var a2 = [
  "y",
  "Y",
  "yes",
  "Yes",
  "YES",
  "on",
  "On",
  "ON",
  "n",
  "N",
  "no",
  "No",
  "NO",
  "off",
  "Off",
  "OFF"
], n2 = /^[-+]?[0-9_]+(?::[0-9_]+)+(?:\.[0-9_]*)?$/;
function mp(e, t) {
  var r, i, s, o, a, n, l;
  if (t === null) return {};
  for (r = {}, i = Object.keys(t), s = 0, o = i.length; s < o; s += 1)
    a = i[s], n = String(t[a]), a.slice(0, 2) === "!!" && (a = "tag:yaml.org,2002:" + a.slice(2)), l = e.compiledTypeMap.fallback[a], l && cp.call(l.styleAliases, n) && (n = l.styleAliases[n]), r[a] = n;
  return r;
}
f(mp, "compileStyleMap");
function yp(e) {
  var t, r, i;
  if (t = e.toString(16).toUpperCase(), e <= 255)
    r = "x", i = 2;
  else if (e <= 65535)
    r = "u", i = 4;
  else if (e <= 4294967295)
    r = "U", i = 8;
  else
    throw new ee("code point within a string may not be greater than 0xFFFFFFFF");
  return "\\" + r + Ot.repeat("0", i - t.length) + t;
}
f(yp, "encodeHex");
var l2 = 1, ts = 2;
function xp(e) {
  this.schema = e.schema || qd, this.indent = Math.max(1, e.indent || 2), this.noArrayIndent = e.noArrayIndent || !1, this.skipInvalid = e.skipInvalid || !1, this.flowLevel = Ot.isNothing(e.flowLevel) ? -1 : e.flowLevel, this.styleMap = mp(this.schema, e.styles || null), this.sortKeys = e.sortKeys || !1, this.lineWidth = e.lineWidth || 80, this.noRefs = e.noRefs || !1, this.noCompatMode = e.noCompatMode || !1, this.condenseFlow = e.condenseFlow || !1, this.quotingType = e.quotingType === '"' ? ts : l2, this.forceQuotes = e.forceQuotes || !1, this.replacer = typeof e.replacer == "function" ? e.replacer : null, this.implicitTypes = this.schema.compiledImplicit, this.explicitTypes = this.schema.compiledExplicit, this.tag = null, this.result = "", this.duplicates = [], this.usedDuplicates = null;
}
f(xp, "State");
function qa(e, t) {
  for (var r = Ot.repeat(" ", t), i = 0, s = -1, o = "", a, n = e.length; i < n; )
    s = e.indexOf(`
`, i), s === -1 ? (a = e.slice(i), i = n) : (a = e.slice(i, s + 1), i = s + 1), a.length && a !== `
` && (o += r), o += a;
  return o;
}
f(qa, "indentString");
function lo(e, t) {
  return `
` + Ot.repeat(" ", e.indent * t);
}
f(lo, "generateNextLine");
function Cp(e, t) {
  var r, i, s;
  for (r = 0, i = e.implicitTypes.length; r < i; r += 1)
    if (s = e.implicitTypes[r], s.resolve(t))
      return !0;
  return !1;
}
f(Cp, "testImplicitResolving");
function es(e) {
  return e === U1 || e === Y1;
}
f(es, "isWhitespace");
function di(e) {
  return 32 <= e && e <= 126 || 161 <= e && e <= 55295 && e !== 8232 && e !== 8233 || 57344 <= e && e <= 65533 && e !== Hn || 65536 <= e && e <= 1114111;
}
f(di, "isPrintable");
function Wa(e) {
  return di(e) && e !== Hn && e !== X1 && e !== Ji;
}
f(Wa, "isNsCharOrWhitespace");
function za(e, t, r) {
  var i = Wa(e), s = i && !es(e);
  return (
    // ns-plain-safe
    (r ? (
      // c = flow-in
      i
    ) : i && e !== up && e !== dp && e !== pp && e !== fp && e !== gp) && e !== Na && !(t === no && !s) || Wa(t) && !es(t) && e === Na || t === no && s
  );
}
f(za, "isPlainSafe");
function bp(e) {
  return di(e) && e !== Hn && !es(e) && e !== J1 && e !== r2 && e !== no && e !== up && e !== dp && e !== pp && e !== fp && e !== gp && e !== Na && e !== Z1 && e !== Q1 && e !== j1 && e !== o2 && e !== t2 && e !== e2 && e !== K1 && e !== G1 && e !== V1 && e !== i2 && e !== s2;
}
f(bp, "isPlainSafeFirst");
function kp(e) {
  return !es(e) && e !== no;
}
f(kp, "isPlainSafeLast");
function Hr(e, t) {
  var r = e.charCodeAt(t), i;
  return r >= 55296 && r <= 56319 && t + 1 < e.length && (i = e.charCodeAt(t + 1), i >= 56320 && i <= 57343) ? (r - 55296) * 1024 + i - 56320 + 65536 : r;
}
f(Hr, "codePointAt");
function Yn(e) {
  var t = /^\n* /;
  return t.test(e);
}
f(Yn, "needIndentIndicator");
var Tp = 1, Ha = 2, Sp = 3, wp = 4, Nr = 5;
function _p(e, t, r, i, s, o, a, n) {
  var l, h = 0, c = null, u = !1, p = !1, d = i !== -1, g = -1, m = bp(Hr(e, 0)) && kp(Hr(e, e.length - 1));
  if (t || a)
    for (l = 0; l < e.length; h >= 65536 ? l += 2 : l++) {
      if (h = Hr(e, l), !di(h))
        return Nr;
      m = m && za(h, c, n), c = h;
    }
  else {
    for (l = 0; l < e.length; h >= 65536 ? l += 2 : l++) {
      if (h = Hr(e, l), h === Ji)
        u = !0, d && (p = p || // Foldable line = too long, and not more-indented.
        l - g - 1 > i && e[g + 1] !== " ", g = l);
      else if (!di(h))
        return Nr;
      m = m && za(h, c, n), c = h;
    }
    p = p || d && l - g - 1 > i && e[g + 1] !== " ";
  }
  return !u && !p ? m && !a && !s(e) ? Tp : o === ts ? Nr : Ha : r > 9 && Yn(e) ? Nr : a ? o === ts ? Nr : Ha : p ? wp : Sp;
}
f(_p, "chooseScalarStyle");
function Bp(e, t, r, i, s) {
  e.dump = (function() {
    if (t.length === 0)
      return e.quotingType === ts ? '""' : "''";
    if (!e.noCompatMode && (a2.indexOf(t) !== -1 || n2.test(t)))
      return e.quotingType === ts ? '"' + t + '"' : "'" + t + "'";
    var o = e.indent * Math.max(1, r), a = e.lineWidth === -1 ? -1 : Math.max(Math.min(e.lineWidth, 40), e.lineWidth - o), n = i || e.flowLevel > -1 && r >= e.flowLevel;
    function l(h) {
      return Cp(e, h);
    }
    switch (f(l, "testAmbiguity"), _p(
      t,
      n,
      e.indent,
      a,
      l,
      e.quotingType,
      e.forceQuotes && !i,
      s
    )) {
      case Tp:
        return t;
      case Ha:
        return "'" + t.replace(/'/g, "''") + "'";
      case Sp:
        return "|" + Ya(t, e.indent) + Xa(qa(t, o));
      case wp:
        return ">" + Ya(t, e.indent) + Xa(qa(vp(t, a), o));
      case Nr:
        return '"' + Lp(t) + '"';
      default:
        throw new ee("impossible error: invalid scalar style");
    }
  })();
}
f(Bp, "writeScalar");
function Ya(e, t) {
  var r = Yn(e) ? String(t) : "", i = e[e.length - 1] === `
`, s = i && (e[e.length - 2] === `
` || e === `
`), o = s ? "+" : i ? "" : "-";
  return r + o + `
`;
}
f(Ya, "blockHeader");
function Xa(e) {
  return e[e.length - 1] === `
` ? e.slice(0, -1) : e;
}
f(Xa, "dropEndingNewline");
function vp(e, t) {
  for (var r = /(\n+)([^\n]*)/g, i = (function() {
    var h = e.indexOf(`
`);
    return h = h !== -1 ? h : e.length, r.lastIndex = h, Ua(e.slice(0, h), t);
  })(), s = e[0] === `
` || e[0] === " ", o, a; a = r.exec(e); ) {
    var n = a[1], l = a[2];
    o = l[0] === " ", i += n + (!s && !o && l !== "" ? `
` : "") + Ua(l, t), s = o;
  }
  return i;
}
f(vp, "foldString");
function Ua(e, t) {
  if (e === "" || e[0] === " ") return e;
  for (var r = / [^ ]/g, i, s = 0, o, a = 0, n = 0, l = ""; i = r.exec(e); )
    n = i.index, n - s > t && (o = a > s ? a : n, l += `
` + e.slice(s, o), s = o + 1), a = n;
  return l += `
`, e.length - s > t && a > s ? l += e.slice(s, a) + `
` + e.slice(a + 1) : l += e.slice(s), l.slice(1);
}
f(Ua, "foldLine");
function Lp(e) {
  for (var t = "", r = 0, i, s = 0; s < e.length; r >= 65536 ? s += 2 : s++)
    r = Hr(e, s), i = Xt[r], !i && di(r) ? (t += e[s], r >= 65536 && (t += e[s + 1])) : t += i || yp(r);
  return t;
}
f(Lp, "escapeString");
function Ap(e, t, r) {
  var i = "", s = e.tag, o, a, n;
  for (o = 0, a = r.length; o < a; o += 1)
    n = r[o], e.replacer && (n = e.replacer.call(r, String(o), n)), (Oe(e, t, n, !1, !1) || typeof n > "u" && Oe(e, t, null, !1, !1)) && (i !== "" && (i += "," + (e.condenseFlow ? "" : " ")), i += e.dump);
  e.tag = s, e.dump = "[" + i + "]";
}
f(Ap, "writeFlowSequence");
function ja(e, t, r, i) {
  var s = "", o = e.tag, a, n, l;
  for (a = 0, n = r.length; a < n; a += 1)
    l = r[a], e.replacer && (l = e.replacer.call(r, String(a), l)), (Oe(e, t + 1, l, !0, !0, !1, !0) || typeof l > "u" && Oe(e, t + 1, null, !0, !0, !1, !0)) && ((!i || s !== "") && (s += lo(e, t)), e.dump && Ji === e.dump.charCodeAt(0) ? s += "-" : s += "- ", s += e.dump);
  e.tag = o, e.dump = s || "[]";
}
f(ja, "writeBlockSequence");
function Ep(e, t, r) {
  var i = "", s = e.tag, o = Object.keys(r), a, n, l, h, c;
  for (a = 0, n = o.length; a < n; a += 1)
    c = "", i !== "" && (c += ", "), e.condenseFlow && (c += '"'), l = o[a], h = r[l], e.replacer && (h = e.replacer.call(r, l, h)), Oe(e, t, l, !1, !1) && (e.dump.length > 1024 && (c += "? "), c += e.dump + (e.condenseFlow ? '"' : "") + ":" + (e.condenseFlow ? "" : " "), Oe(e, t, h, !1, !1) && (c += e.dump, i += c));
  e.tag = s, e.dump = "{" + i + "}";
}
f(Ep, "writeFlowMapping");
function Fp(e, t, r, i) {
  var s = "", o = e.tag, a = Object.keys(r), n, l, h, c, u, p;
  if (e.sortKeys === !0)
    a.sort();
  else if (typeof e.sortKeys == "function")
    a.sort(e.sortKeys);
  else if (e.sortKeys)
    throw new ee("sortKeys must be a boolean or a function");
  for (n = 0, l = a.length; n < l; n += 1)
    p = "", (!i || s !== "") && (p += lo(e, t)), h = a[n], c = r[h], e.replacer && (c = e.replacer.call(r, h, c)), Oe(e, t + 1, h, !0, !0, !0) && (u = e.tag !== null && e.tag !== "?" || e.dump && e.dump.length > 1024, u && (e.dump && Ji === e.dump.charCodeAt(0) ? p += "?" : p += "? "), p += e.dump, u && (p += lo(e, t)), Oe(e, t + 1, c, !0, u) && (e.dump && Ji === e.dump.charCodeAt(0) ? p += ":" : p += ": ", p += e.dump, s += p));
  e.tag = o, e.dump = s || "{}";
}
f(Fp, "writeBlockMapping");
function Ga(e, t, r) {
  var i, s, o, a, n, l;
  for (s = r ? e.explicitTypes : e.implicitTypes, o = 0, a = s.length; o < a; o += 1)
    if (n = s[o], (n.instanceOf || n.predicate) && (!n.instanceOf || typeof t == "object" && t instanceof n.instanceOf) && (!n.predicate || n.predicate(t))) {
      if (r ? n.multi && n.representName ? e.tag = n.representName(t) : e.tag = n.tag : e.tag = "?", n.represent) {
        if (l = e.styleMap[n.tag] || n.defaultStyle, hp.call(n.represent) === "[object Function]")
          i = n.represent(t, l);
        else if (cp.call(n.represent, l))
          i = n.represent[l](t, l);
        else
          throw new ee("!<" + n.tag + '> tag resolver accepts not "' + l + '" style');
        e.dump = i;
      }
      return !0;
    }
  return !1;
}
f(Ga, "detectType");
function Oe(e, t, r, i, s, o, a) {
  e.tag = null, e.dump = r, Ga(e, r, !1) || Ga(e, r, !0);
  var n = hp.call(e.dump), l = i, h;
  i && (i = e.flowLevel < 0 || e.flowLevel > t);
  var c = n === "[object Object]" || n === "[object Array]", u, p;
  if (c && (u = e.duplicates.indexOf(r), p = u !== -1), (e.tag !== null && e.tag !== "?" || p || e.indent !== 2 && t > 0) && (s = !1), p && e.usedDuplicates[u])
    e.dump = "*ref_" + u;
  else {
    if (c && p && !e.usedDuplicates[u] && (e.usedDuplicates[u] = !0), n === "[object Object]")
      i && Object.keys(e.dump).length !== 0 ? (Fp(e, t, e.dump, s), p && (e.dump = "&ref_" + u + e.dump)) : (Ep(e, t, e.dump), p && (e.dump = "&ref_" + u + " " + e.dump));
    else if (n === "[object Array]")
      i && e.dump.length !== 0 ? (e.noArrayIndent && !a && t > 0 ? ja(e, t - 1, e.dump, s) : ja(e, t, e.dump, s), p && (e.dump = "&ref_" + u + e.dump)) : (Ap(e, t, e.dump), p && (e.dump = "&ref_" + u + " " + e.dump));
    else if (n === "[object String]")
      e.tag !== "?" && Bp(e, e.dump, t, o, l);
    else {
      if (n === "[object Undefined]")
        return !1;
      if (e.skipInvalid) return !1;
      throw new ee("unacceptable kind of an object to dump " + n);
    }
    e.tag !== null && e.tag !== "?" && (h = encodeURI(
      e.tag[0] === "!" ? e.tag.slice(1) : e.tag
    ).replace(/!/g, "%21"), e.tag[0] === "!" ? h = "!" + h : h.slice(0, 18) === "tag:yaml.org,2002:" ? h = "!!" + h.slice(18) : h = "!<" + h + ">", e.dump = h + " " + e.dump);
  }
  return !0;
}
f(Oe, "writeNode");
function Mp(e, t) {
  var r = [], i = [], s, o;
  for (ho(e, r, i), s = 0, o = i.length; s < o; s += 1)
    t.duplicates.push(r[i[s]]);
  t.usedDuplicates = new Array(o);
}
f(Mp, "getDuplicateReferences");
function ho(e, t, r) {
  var i, s, o;
  if (e !== null && typeof e == "object")
    if (s = t.indexOf(e), s !== -1)
      r.indexOf(s) === -1 && r.push(s);
    else if (t.push(e), Array.isArray(e))
      for (s = 0, o = e.length; s < o; s += 1)
        ho(e[s], t, r);
    else
      for (i = Object.keys(e), s = 0, o = i.length; s < o; s += 1)
        ho(e[i[s]], t, r);
}
f(ho, "inspectNode");
function h2(e, t) {
  t = t || {};
  var r = new xp(t);
  r.noRefs || Mp(e, r);
  var i = e;
  return r.replacer && (i = r.replacer.call({ "": i }, "", i)), Oe(r, 0, i, !0, !0) ? r.dump + `
` : "";
}
f(h2, "dump$1");
function c2(e, t) {
  return function() {
    throw new Error("Function yaml." + e + " is removed in js-yaml 4. Use yaml." + t + " instead, which is now safe by default.");
  };
}
f(c2, "renamed");
var u2 = Sd, d2 = H1.load;
/*! Bundled license information:

js-yaml/dist/js-yaml.mjs:
  (*! js-yaml 4.1.1 https://github.com/nodeca/js-yaml @license MIT *)
*/
var vi = /* @__PURE__ */ f((e, t) => {
  if (t)
    return "translate(" + -e.width / 2 + ", " + -e.height / 2 + ")";
  const r = e.x ?? 0, i = e.y ?? 0;
  return "translate(" + -(r + e.width / 2) + ", " + -(i + e.height / 2) + ")";
}, "computeLabelTransform"), Ht = {
  aggregation: 17.25,
  extension: 17.25,
  composition: 17.25,
  dependency: 6,
  lollipop: 13.5,
  arrow_point: 4,
  arrow_barb: 0,
  arrow_barb_neo: 5.5
  //arrow_cross: 24,
}, Lh = {
  arrow_point: 4,
  arrow_cross: 12.5,
  arrow_circle: 12.5
};
function Di(e, t) {
  if (e === void 0 || t === void 0)
    return { angle: 0, deltaX: 0, deltaY: 0 };
  e = St(e), t = St(t);
  const [r, i] = [e.x, e.y], [s, o] = [t.x, t.y], a = s - r, n = o - i;
  return { angle: Math.atan(n / a), deltaX: a, deltaY: n };
}
f(Di, "calculateDeltaAndAngle");
var St = /* @__PURE__ */ f((e) => Array.isArray(e) ? { x: e[0], y: e[1] } : e, "pointTransformer"), p2 = /* @__PURE__ */ f((e) => ({
  x: /* @__PURE__ */ f(function(t, r, i) {
    let s = 0;
    const o = St(i[0]).x < St(i[i.length - 1]).x ? "left" : "right";
    if (r === 0 && Object.hasOwn(Ht, e.arrowTypeStart)) {
      const { angle: d, deltaX: g } = Di(i[0], i[1]);
      s = Ht[e.arrowTypeStart] * Math.cos(d) * (g >= 0 ? 1 : -1);
    } else if (r === i.length - 1 && Object.hasOwn(Ht, e.arrowTypeEnd)) {
      const { angle: d, deltaX: g } = Di(
        i[i.length - 1],
        i[i.length - 2]
      );
      s = Ht[e.arrowTypeEnd] * Math.cos(d) * (g >= 0 ? 1 : -1);
    }
    const a = Math.abs(
      St(t).x - St(i[i.length - 1]).x
    ), n = Math.abs(
      St(t).y - St(i[i.length - 1]).y
    ), l = Math.abs(St(t).x - St(i[0]).x), h = Math.abs(St(t).y - St(i[0]).y), c = Ht[e.arrowTypeStart], u = Ht[e.arrowTypeEnd], p = 1;
    if (a < u && a > 0 && n < u) {
      let d = u + p - a;
      d *= o === "right" ? -1 : 1, s -= d;
    }
    if (l < c && l > 0 && h < c) {
      let d = c + p - l;
      d *= o === "right" ? -1 : 1, s += d;
    }
    return St(t).x + s;
  }, "x"),
  y: /* @__PURE__ */ f(function(t, r, i) {
    let s = 0;
    const o = St(i[0]).y < St(i[i.length - 1]).y ? "down" : "up";
    if (r === 0 && Object.hasOwn(Ht, e.arrowTypeStart)) {
      const { angle: d, deltaY: g } = Di(i[0], i[1]);
      s = Ht[e.arrowTypeStart] * Math.abs(Math.sin(d)) * (g >= 0 ? 1 : -1);
    } else if (r === i.length - 1 && Object.hasOwn(Ht, e.arrowTypeEnd)) {
      const { angle: d, deltaY: g } = Di(
        i[i.length - 1],
        i[i.length - 2]
      );
      s = Ht[e.arrowTypeEnd] * Math.abs(Math.sin(d)) * (g >= 0 ? 1 : -1);
    }
    const a = Math.abs(
      St(t).y - St(i[i.length - 1]).y
    ), n = Math.abs(
      St(t).x - St(i[i.length - 1]).x
    ), l = Math.abs(St(t).y - St(i[0]).y), h = Math.abs(St(t).x - St(i[0]).x), c = Ht[e.arrowTypeStart], u = Ht[e.arrowTypeEnd], p = 1;
    if (a < u && a > 0 && n < u) {
      let d = u + p - a;
      d *= o === "up" ? -1 : 1, s -= d;
    }
    if (l < c && l > 0 && h < c) {
      let d = c + p - l;
      d *= o === "up" ? -1 : 1, s += d;
    }
    return St(t).y + s;
  }, "y")
}), "getLineFunctionsWithOffset"), vs = {}, It = {}, Ah;
function f2() {
  return Ah || (Ah = 1, Object.defineProperty(It, "__esModule", { value: !0 }), It.BLANK_URL = It.relativeFirstCharacters = It.whitespaceEscapeCharsRegex = It.urlSchemeRegex = It.ctrlCharactersRegex = It.htmlCtrlEntityRegex = It.htmlEntitiesRegex = It.invalidProtocolRegex = void 0, It.invalidProtocolRegex = /^([^\w]*)(javascript|data|vbscript)/im, It.htmlEntitiesRegex = /&#(\w+)(^\w|;)?/g, It.htmlCtrlEntityRegex = /&(newline|tab);/gi, It.ctrlCharactersRegex = /[\u0000-\u001F\u007F-\u009F\u2000-\u200D\uFEFF]/gim, It.urlSchemeRegex = /^.+(:|&colon;)/gim, It.whitespaceEscapeCharsRegex = /(\\|%5[cC])((%(6[eE]|72|74))|[nrt])/g, It.relativeFirstCharacters = [".", "/"], It.BLANK_URL = "about:blank"), It;
}
var Eh;
function g2() {
  if (Eh) return vs;
  Eh = 1, Object.defineProperty(vs, "__esModule", { value: !0 }), vs.sanitizeUrl = o;
  var e = f2();
  function t(a) {
    return e.relativeFirstCharacters.indexOf(a[0]) > -1;
  }
  function r(a) {
    var n = a.replace(e.ctrlCharactersRegex, "");
    return n.replace(e.htmlEntitiesRegex, function(l, h) {
      return String.fromCharCode(h);
    });
  }
  function i(a) {
    return URL.canParse(a);
  }
  function s(a) {
    try {
      return decodeURIComponent(a);
    } catch {
      return a;
    }
  }
  function o(a) {
    if (!a)
      return e.BLANK_URL;
    var n, l = s(a.trim());
    do
      l = r(l).replace(e.htmlCtrlEntityRegex, "").replace(e.ctrlCharactersRegex, "").replace(e.whitespaceEscapeCharsRegex, "").trim(), l = s(l), n = l.match(e.ctrlCharactersRegex) || l.match(e.htmlEntitiesRegex) || l.match(e.htmlCtrlEntityRegex) || l.match(e.whitespaceEscapeCharsRegex);
    while (n && n.length > 0);
    var h = l;
    if (!h)
      return e.BLANK_URL;
    if (t(h))
      return h;
    var c = h.trimStart(), u = c.match(e.urlSchemeRegex);
    if (!u)
      return h;
    var p = u[0].toLowerCase().trim();
    if (e.invalidProtocolRegex.test(p))
      return e.BLANK_URL;
    var d = c.replace(/\\/g, "/");
    if (p === "mailto:" || p.includes("://"))
      return d;
    if (p === "http:" || p === "https:") {
      if (!i(d))
        return e.BLANK_URL;
      var g = new URL(d);
      return g.protocol = g.protocol.toLowerCase(), g.hostname = g.hostname.toLowerCase(), g.toString();
    }
    return d;
  }
  return vs;
}
var m2 = g2(), y2 = "​", x2 = {
  curveBasis: Ia,
  curveBasisClosed: Kk,
  curveBasisOpen: Qk,
  curveBumpX: Mu,
  curveBumpY: Iu,
  curveBundle: Jk,
  curveCardinalClosed: t1,
  curveCardinalOpen: e1,
  curveCardinal: Ru,
  curveCatmullRomClosed: r1,
  curveCatmullRomOpen: i1,
  curveCatmullRom: Nu,
  curveLinear: Hi,
  curveLinearClosed: s1,
  curveMonotoneX: Xu,
  curveMonotoneY: Uu,
  curveNatural: Gu,
  curveStep: Vu,
  curveStepAfter: Ku,
  curveStepBefore: Zu
}, C2 = /\s*(?:(\w+)(?=:):|(\w+))\s*(?:(\w+)|((?:(?!}%{2}).|\r?\n)*))?\s*(?:}%{2})?/gi, b2 = /* @__PURE__ */ f(function(e, t) {
  const r = Ip(e, /(?:init\b)|(?:initialize\b)/);
  let i = {};
  if (Array.isArray(r)) {
    const a = r.map((n) => n.args);
    Ys(a), i = $t(i, [...a]);
  } else
    i = r.args;
  if (!i)
    return;
  let s = Cn(e, t);
  const o = "config";
  return i[o] !== void 0 && (s === "flowchart-v2" && (s = "flowchart"), i[s] = i[o], delete i[o]), i;
}, "detectInit"), Ip = /* @__PURE__ */ f(function(e, t = null) {
  var r, i;
  try {
    const s = new RegExp(
      `[%]{2}(?![{]${C2.source})(?=[}][%]{2}).*
`,
      "ig"
    );
    e = e.trim().replace(s, "").replace(/'/gm, '"'), q.debug(
      `Detecting diagram directive${t !== null ? " type:" + t : ""} based on the text:${e}`
    );
    let o;
    const a = [];
    for (; (o = Wi.exec(e)) !== null; )
      if (o.index === Wi.lastIndex && Wi.lastIndex++, o && !t || t && ((r = o[1]) != null && r.match(t)) || t && ((i = o[2]) != null && i.match(t))) {
        const n = o[1] ? o[1] : o[2], l = o[3] ? o[3].trim() : o[4] ? JSON.parse(o[4].trim()) : null;
        a.push({ type: n, args: l });
      }
    return a.length === 0 ? { type: e, args: null } : a.length === 1 ? a[0] : a;
  } catch (s) {
    return q.error(
      `ERROR: ${s.message} - Unable to parse directive type: '${t}' based on the text: '${e}'`
    ), { type: void 0, args: null };
  }
}, "detectDirective"), k2 = /* @__PURE__ */ f(function(e) {
  return e.replace(Wi, "");
}, "removeDirectives"), T2 = /* @__PURE__ */ f(function(e, t) {
  for (const [r, i] of t.entries())
    if (i.match(e))
      return r;
  return -1;
}, "isSubstringInArray");
function Xn(e, t) {
  if (!e)
    return t;
  const r = `curve${e.charAt(0).toUpperCase() + e.slice(1)}`;
  return x2[r] ?? t;
}
f(Xn, "interpolateToCurve");
function $p(e, t) {
  const r = e.trim();
  if (r)
    return t.securityLevel !== "loose" ? m2.sanitizeUrl(r) : r;
}
f($p, "formatUrl");
var S2 = /* @__PURE__ */ f((e, ...t) => {
  const r = e.split("."), i = r.length - 1, s = r[i];
  let o = window;
  for (let a = 0; a < i; a++)
    if (o = o[r[a]], !o) {
      q.error(`Function name: ${e} not found in window`);
      return;
    }
  o[s](...t);
}, "runFunc");
function Un(e, t) {
  return !e || !t ? 0 : Math.sqrt(Math.pow(t.x - e.x, 2) + Math.pow(t.y - e.y, 2));
}
f(Un, "distance");
function Op(e) {
  let t, r = 0;
  e.forEach((s) => {
    r += Un(s, t), t = s;
  });
  const i = r / 2;
  return jn(e, i);
}
f(Op, "traverseEdge");
function Dp(e) {
  return e.length === 1 ? e[0] : Op(e);
}
f(Dp, "calcLabelPosition");
var Fh = /* @__PURE__ */ f((e, t = 2) => {
  const r = Math.pow(10, t);
  return Math.round(e * r) / r;
}, "roundNumber"), jn = /* @__PURE__ */ f((e, t) => {
  let r, i = t;
  for (const s of e) {
    if (r) {
      const o = Un(s, r);
      if (o === 0)
        return r;
      if (o < i)
        i -= o;
      else {
        const a = i / o;
        if (a <= 0)
          return r;
        if (a >= 1)
          return { x: s.x, y: s.y };
        if (a > 0 && a < 1)
          return {
            x: Fh((1 - a) * r.x + a * s.x, 5),
            y: Fh((1 - a) * r.y + a * s.y, 5)
          };
      }
    }
    r = s;
  }
  throw new Error("Could not find a suitable point for the given distance");
}, "calculatePoint"), w2 = /* @__PURE__ */ f((e, t, r) => {
  q.info(`our points ${JSON.stringify(t)}`), t[0] !== r && (t = t.reverse());
  const s = jn(t, 25), o = e ? 10 : 5, a = Math.atan2(t[0].y - s.y, t[0].x - s.x), n = { x: 0, y: 0 };
  return n.x = Math.sin(a) * o + (t[0].x + s.x) / 2, n.y = -Math.cos(a) * o + (t[0].y + s.y) / 2, n;
}, "calcCardinalityPosition");
function Rp(e, t, r) {
  const i = structuredClone(r);
  q.info("our points", i), t !== "start_left" && t !== "start_right" && i.reverse();
  const s = 25 + e, o = jn(i, s), a = 10 + e * 0.5, n = Math.atan2(i[0].y - o.y, i[0].x - o.x), l = { x: 0, y: 0 };
  return t === "start_left" ? (l.x = Math.sin(n + Math.PI) * a + (i[0].x + o.x) / 2, l.y = -Math.cos(n + Math.PI) * a + (i[0].y + o.y) / 2) : t === "end_right" ? (l.x = Math.sin(n - Math.PI) * a + (i[0].x + o.x) / 2 - 5, l.y = -Math.cos(n - Math.PI) * a + (i[0].y + o.y) / 2 - 5) : t === "end_left" ? (l.x = Math.sin(n) * a + (i[0].x + o.x) / 2 - 5, l.y = -Math.cos(n) * a + (i[0].y + o.y) / 2 - 5) : (l.x = Math.sin(n) * a + (i[0].x + o.x) / 2, l.y = -Math.cos(n) * a + (i[0].y + o.y) / 2), l;
}
f(Rp, "calcTerminalLabelPosition");
function Pp(e) {
  let t = "", r = "";
  for (const i of e)
    i !== void 0 && (i.startsWith("color:") || i.startsWith("text-align:") ? r = r + i + ";" : t = t + i + ";");
  return { style: t, labelStyle: r };
}
f(Pp, "getStylesFromArray");
var Mh = 0, _2 = /* @__PURE__ */ f(() => (Mh++, "id-" + Math.random().toString(36).substr(2, 12) + "-" + Mh), "generateId");
function Np(e) {
  let t = "";
  const r = "0123456789abcdef", i = r.length;
  for (let s = 0; s < e; s++)
    t += r.charAt(Math.floor(Math.random() * i));
  return t;
}
f(Np, "makeRandomHex");
var B2 = /* @__PURE__ */ f((e) => Np(e.length), "random"), v2 = /* @__PURE__ */ f(function() {
  return {
    x: 0,
    y: 0,
    fill: void 0,
    anchor: "start",
    style: "#666",
    width: 100,
    height: 100,
    textMargin: 0,
    rx: 0,
    ry: 0,
    valign: void 0,
    text: ""
  };
}, "getTextObj"), L2 = /* @__PURE__ */ f(function(e, t) {
  const r = t.text.replace(ls.lineBreakRegex, " "), [, i] = Ao(t.fontSize), s = e.append("text");
  s.attr("x", t.x), s.attr("y", t.y), s.style("text-anchor", t.anchor), s.style("font-family", t.fontFamily), s.style("font-size", i), s.style("font-weight", t.fontWeight), s.attr("fill", t.fill), t.class !== void 0 && s.attr("class", t.class);
  const o = s.append("tspan");
  return o.attr("x", t.x + t.textMargin * 2), o.attr("fill", t.fill), o.text(r), s;
}, "drawSimpleText"), A2 = pn(
  (e, t, r) => {
    if (!e || (r = Object.assign(
      { fontSize: 12, fontWeight: 400, fontFamily: "Arial", joinWith: "<br/>" },
      r
    ), ls.lineBreakRegex.test(e)))
      return e;
    const i = e.split(" ").filter(Boolean), s = [];
    let o = "";
    return i.forEach((a, n) => {
      const l = je(`${a} `, r), h = je(o, r);
      if (l > t) {
        const { hyphenatedStrings: p, remainingWord: d } = E2(a, t, "-", r);
        s.push(o, ...p), o = d;
      } else h + l >= t ? (s.push(o), o = a) : o = [o, a].filter(Boolean).join(" ");
      n + 1 === i.length && s.push(o);
    }), s.filter((a) => a !== "").join(r.joinWith);
  },
  (e, t, r) => `${e}${t}${r.fontSize}${r.fontWeight}${r.fontFamily}${r.joinWith}`
), E2 = pn(
  (e, t, r = "-", i) => {
    i = Object.assign(
      { fontSize: 12, fontWeight: 400, fontFamily: "Arial", margin: 0 },
      i
    );
    const s = [...e], o = [];
    let a = "";
    return s.forEach((n, l) => {
      const h = `${a}${n}`;
      if (je(h, i) >= t) {
        const u = l + 1, p = s.length === u, d = `${h}${r}`;
        o.push(p ? h : d), a = "";
      } else
        a = h;
    }), { hyphenatedStrings: o, remainingWord: a };
  },
  (e, t, r = "-", i) => `${e}${t}${r}${i.fontSize}${i.fontWeight}${i.fontFamily}`
);
function qp(e, t) {
  return Gn(e, t).height;
}
f(qp, "calculateTextHeight");
function je(e, t) {
  return Gn(e, t).width;
}
f(je, "calculateTextWidth");
var Gn = pn(
  (e, t) => {
    const { fontSize: r = 12, fontFamily: i = "Arial", fontWeight: s = 400 } = t;
    if (!e)
      return { width: 0, height: 0 };
    const [, o] = Ao(r), a = ["sans-serif", i], n = e.split(ls.lineBreakRegex), l = [], h = ct("body");
    if (!h.remove)
      return { width: 0, height: 0, lineHeight: 0 };
    const c = h.append("svg");
    for (const p of a) {
      let d = 0;
      const g = { width: 0, height: 0, lineHeight: 0 };
      for (const m of n) {
        const y = v2();
        y.text = m || y2;
        const x = L2(c, y).style("font-size", o).style("font-weight", s).style("font-family", p), b = (x._groups || x)[0][0].getBBox();
        if (b.width === 0 && b.height === 0)
          throw new Error("svg element not in render tree");
        g.width = Math.round(Math.max(g.width, b.width)), d = Math.round(b.height), g.height += d, g.lineHeight = Math.round(Math.max(g.lineHeight, d));
      }
      l.push(g);
    }
    c.remove();
    const u = isNaN(l[1].height) || isNaN(l[1].width) || isNaN(l[1].lineHeight) || l[0].height > l[1].height && l[0].width > l[1].width && l[0].lineHeight > l[1].lineHeight ? 0 : 1;
    return l[u];
  },
  (e, t) => `${e}${t.fontSize}${t.fontWeight}${t.fontFamily}`
), oi, F2 = (oi = class {
  constructor(t = !1, r) {
    this.count = 0, this.count = r ? r.length : 0, this.next = t ? () => this.count++ : () => Date.now();
  }
}, f(oi, "InitIDGenerator"), oi), Ls, M2 = /* @__PURE__ */ f(function(e) {
  return Ls = Ls || document.createElement("div"), e = escape(e).replace(/%26/g, "&").replace(/%23/g, "#").replace(/%3B/g, ";"), Ls.innerHTML = e, unescape(Ls.textContent);
}, "entityDecode");
function Vn(e) {
  return "str" in e;
}
f(Vn, "isDetailedError");
var I2 = /* @__PURE__ */ f((e, t, r, i) => {
  var o;
  if (!i)
    return;
  const s = (o = e.node()) == null ? void 0 : o.getBBox();
  s && e.append("text").text(i).attr("text-anchor", "middle").attr("x", s.x + s.width / 2).attr("y", -r).attr("class", t);
}, "insertTitle"), Ao = /* @__PURE__ */ f((e) => {
  if (typeof e == "number")
    return [e, e + "px"];
  const t = parseInt(e ?? "", 10);
  return Number.isNaN(t) ? [void 0, void 0] : e === String(t) ? [t, e + "px"] : [t, e];
}, "parseFontSize");
function Zn(e, t) {
  return oy({}, e, t);
}
f(Zn, "cleanAndMerge");
var ke = {
  assignWithDepth: $t,
  wrapLabel: A2,
  calculateTextHeight: qp,
  calculateTextWidth: je,
  calculateTextDimensions: Gn,
  cleanAndMerge: Zn,
  detectInit: b2,
  detectDirective: Ip,
  isSubstringInArray: T2,
  interpolateToCurve: Xn,
  calcLabelPosition: Dp,
  calcCardinalityPosition: w2,
  calcTerminalLabelPosition: Rp,
  formatUrl: $p,
  getStylesFromArray: Pp,
  generateId: _2,
  random: B2,
  runFunc: S2,
  entityDecode: M2,
  insertTitle: I2,
  isLabelCoordinateInPath: Wp,
  parseFontSize: Ao,
  InitIDGenerator: F2
}, $2 = /* @__PURE__ */ f(function(e) {
  let t = e;
  return t = t.replace(/style.*:\S*#.*;/g, function(r) {
    return r.substring(0, r.length - 1);
  }), t = t.replace(/classDef.*:\S*#.*;/g, function(r) {
    return r.substring(0, r.length - 1);
  }), t = t.replace(/#\w+;/g, function(r) {
    const i = r.substring(1, r.length - 1);
    return /^\+?\d+$/.test(i) ? "ﬂ°°" + i + "¶ß" : "ﬂ°" + i + "¶ß";
  }), t;
}, "encodeEntities"), _r = /* @__PURE__ */ f(function(e) {
  return e.replace(/ﬂ°°/g, "&#").replace(/ﬂ°/g, "&").replace(/¶ß/g, ";");
}, "decodeEntities"), UL = /* @__PURE__ */ f((e, t, {
  counter: r = 0,
  prefix: i,
  suffix: s
}, o) => o || `${i ? `${i}_` : ""}${e}_${t}_${r}${s ? `_${s}` : ""}`, "getEdgeId");
function Rt(e) {
  return e ?? null;
}
f(Rt, "handleUndefinedAttr");
function Wp(e, t) {
  const r = Math.round(e.x), i = Math.round(e.y), s = t.replace(
    /(\d+\.\d+)/g,
    (o) => Math.round(parseFloat(o)).toString()
  );
  return s.includes(r.toString()) || s.includes(i.toString());
}
f(Wp, "isLabelCoordinateInPath");
var Kn = /* @__PURE__ */ f(({
  flowchart: e
}) => {
  var s, o;
  const t = ((s = e == null ? void 0 : e.subGraphTitleMargin) == null ? void 0 : s.top) ?? 0, r = ((o = e == null ? void 0 : e.subGraphTitleMargin) == null ? void 0 : o.bottom) ?? 0, i = t + r;
  return {
    subGraphTitleTopMargin: t,
    subGraphTitleBottomMargin: r,
    subGraphTitleTotalMargin: i
  };
}, "getSubGraphTitleMargins");
async function zp(e, t) {
  const r = e.getElementsByTagName("img");
  if (!r || r.length === 0)
    return;
  const i = t.replace(/<img[^>]*>/g, "").trim() === "";
  await Promise.all(
    [...r].map(
      (s) => new Promise((o) => {
        function a() {
          if (s.style.display = "flex", s.style.flexDirection = "column", i) {
            const n = gt().fontSize ? gt().fontSize : window.getComputedStyle(document.body).fontSize, l = 5, [h = Xc.fontSize] = Ao(n), c = h * l + "px";
            s.style.minWidth = c, s.style.maxWidth = c;
          } else
            s.style.width = "100%";
          o(s);
        }
        f(a, "setupImage"), setTimeout(() => {
          s.complete && a();
        }), s.addEventListener("error", a), s.addEventListener("load", a);
      })
    )
  );
}
f(zp, "configureLabelImages");
var O2 = /* @__PURE__ */ f((e) => {
  const { handDrawnSeed: t } = gt();
  return {
    fill: e,
    hachureAngle: 120,
    // angle of hachure,
    hachureGap: 4,
    fillWeight: 2,
    roughness: 0.7,
    stroke: e,
    seed: t
  };
}, "solidStateFill"), mi = /* @__PURE__ */ f((e) => {
  const t = D2([
    ...e.cssCompiledStyles || [],
    ...e.cssStyles || [],
    ...e.labelStyle || []
  ]);
  return { stylesMap: t, stylesArray: [...t] };
}, "compileStyles"), D2 = /* @__PURE__ */ f((e) => {
  const t = /* @__PURE__ */ new Map();
  return e.forEach((r) => {
    const [i, s] = r.split(":");
    t.set(i.trim(), s == null ? void 0 : s.trim());
  }), t;
}, "styles2Map"), Hp = /* @__PURE__ */ f((e) => e === "color" || e === "font-size" || e === "font-family" || e === "font-weight" || e === "font-style" || e === "text-decoration" || e === "text-align" || e === "text-transform" || e === "line-height" || e === "letter-spacing" || e === "word-spacing" || e === "text-shadow" || e === "text-overflow" || e === "white-space" || e === "word-wrap" || e === "word-break" || e === "overflow-wrap" || e === "hyphens", "isLabelStyle"), K = /* @__PURE__ */ f((e) => {
  const { stylesArray: t } = mi(e), r = [], i = [], s = [], o = [];
  return t.forEach((a) => {
    const n = a[0];
    Hp(n) ? r.push(a.join(":") + " !important") : (i.push(a.join(":") + " !important"), n.includes("stroke") && s.push(a.join(":") + " !important"), n === "fill" && o.push(a.join(":") + " !important"));
  }), {
    labelStyles: r.join(";"),
    nodeStyles: i.join(";"),
    stylesArray: t,
    borderStyles: s,
    backgroundStyles: o
  };
}, "styles2String"), Z = /* @__PURE__ */ f((e, t) => {
  var l;
  const { themeVariables: r, handDrawnSeed: i } = gt(), { nodeBorder: s, mainBkg: o } = r, { stylesMap: a } = mi(e);
  return Object.assign(
    {
      roughness: 0.7,
      fill: a.get("fill") || o,
      fillStyle: "hachure",
      // solid fill
      fillWeight: 4,
      hachureGap: 5.2,
      stroke: a.get("stroke") || s,
      seed: i,
      strokeWidth: ((l = a.get("stroke-width")) == null ? void 0 : l.replace("px", "")) || 1.3,
      fillLineDash: [0, 0],
      strokeLineDash: R2(a.get("stroke-dasharray"))
    },
    t
  );
}, "userNodeOverrides"), R2 = /* @__PURE__ */ f((e) => {
  if (!e)
    return [0, 0];
  const t = e.trim().split(/\s+/).map(Number);
  if (t.length === 1) {
    const s = isNaN(t[0]) ? 0 : t[0];
    return [s, s];
  }
  const r = isNaN(t[0]) ? 0 : t[0], i = isNaN(t[1]) ? 0 : t[1];
  return [r, i];
}, "getStrokeDashArray");
const P2 = Object.freeze({
  left: 0,
  top: 0,
  width: 16,
  height: 16
}), co = Object.freeze({
  rotate: 0,
  vFlip: !1,
  hFlip: !1
}), Yp = Object.freeze({
  ...P2,
  ...co
}), N2 = Object.freeze({
  ...Yp,
  body: "",
  hidden: !1
}), q2 = Object.freeze({
  width: null,
  height: null
}), W2 = Object.freeze({
  ...q2,
  ...co
}), z2 = (e, t, r, i = "") => {
  const s = e.split(":");
  if (e.slice(0, 1) === "@") {
    if (s.length < 2 || s.length > 3) return null;
    i = s.shift().slice(1);
  }
  if (s.length > 3 || !s.length) return null;
  if (s.length > 1) {
    const n = s.pop(), l = s.pop(), h = {
      provider: s.length > 0 ? s[0] : i,
      prefix: l,
      name: n
    };
    return aa(h) ? h : null;
  }
  const o = s[0], a = o.split("-");
  if (a.length > 1) {
    const n = {
      provider: i,
      prefix: a.shift(),
      name: a.join("-")
    };
    return aa(n) ? n : null;
  }
  if (r && i === "") {
    const n = {
      provider: i,
      prefix: "",
      name: o
    };
    return aa(n, r) ? n : null;
  }
  return null;
}, aa = (e, t) => e ? !!((t && e.prefix === "" || e.prefix) && e.name) : !1;
function H2(e, t) {
  const r = {};
  !e.hFlip != !t.hFlip && (r.hFlip = !0), !e.vFlip != !t.vFlip && (r.vFlip = !0);
  const i = ((e.rotate || 0) + (t.rotate || 0)) % 4;
  return i && (r.rotate = i), r;
}
function Ih(e, t) {
  const r = H2(e, t);
  for (const i in N2) i in co ? i in e && !(i in r) && (r[i] = co[i]) : i in t ? r[i] = t[i] : i in e && (r[i] = e[i]);
  return r;
}
function Y2(e, t) {
  const r = e.icons, i = e.aliases || /* @__PURE__ */ Object.create(null), s = /* @__PURE__ */ Object.create(null);
  function o(a) {
    if (r[a]) return s[a] = [];
    if (!(a in s)) {
      s[a] = null;
      const n = i[a] && i[a].parent, l = n && o(n);
      l && (s[a] = [n].concat(l));
    }
    return s[a];
  }
  return (t || Object.keys(r).concat(Object.keys(i))).forEach(o), s;
}
function $h(e, t, r) {
  const i = e.icons, s = e.aliases || /* @__PURE__ */ Object.create(null);
  let o = {};
  function a(n) {
    o = Ih(i[n] || s[n], o);
  }
  return a(t), r.forEach(a), Ih(e, o);
}
function X2(e, t) {
  if (e.icons[t]) return $h(e, t, []);
  const r = Y2(e, [t])[t];
  return r ? $h(e, t, r) : null;
}
const U2 = /(-?[0-9.]*[0-9]+[0-9.]*)/g, j2 = /^-?[0-9.]*[0-9]+[0-9.]*$/g;
function Oh(e, t, r) {
  if (t === 1) return e;
  if (r = r || 100, typeof e == "number") return Math.ceil(e * t * r) / r;
  if (typeof e != "string") return e;
  const i = e.split(U2);
  if (i === null || !i.length) return e;
  const s = [];
  let o = i.shift(), a = j2.test(o);
  for (; ; ) {
    if (a) {
      const n = parseFloat(o);
      isNaN(n) ? s.push(o) : s.push(Math.ceil(n * t * r) / r);
    } else s.push(o);
    if (o = i.shift(), o === void 0) return s.join("");
    a = !a;
  }
}
function G2(e, t = "defs") {
  let r = "";
  const i = e.indexOf("<" + t);
  for (; i >= 0; ) {
    const s = e.indexOf(">", i), o = e.indexOf("</" + t);
    if (s === -1 || o === -1) break;
    const a = e.indexOf(">", o);
    if (a === -1) break;
    r += e.slice(s + 1, o).trim(), e = e.slice(0, i).trim() + e.slice(a + 1);
  }
  return {
    defs: r,
    content: e
  };
}
function V2(e, t) {
  return e ? "<defs>" + e + "</defs>" + t : t;
}
function Z2(e, t, r) {
  const i = G2(e);
  return V2(i.defs, t + i.content + r);
}
const K2 = (e) => e === "unset" || e === "undefined" || e === "none";
function Q2(e, t) {
  const r = {
    ...Yp,
    ...e
  }, i = {
    ...W2,
    ...t
  }, s = {
    left: r.left,
    top: r.top,
    width: r.width,
    height: r.height
  };
  let o = r.body;
  [r, i].forEach((m) => {
    const y = [], x = m.hFlip, b = m.vFlip;
    let k = m.rotate;
    x ? b ? k += 2 : (y.push("translate(" + (s.width + s.left).toString() + " " + (0 - s.top).toString() + ")"), y.push("scale(-1 1)"), s.top = s.left = 0) : b && (y.push("translate(" + (0 - s.left).toString() + " " + (s.height + s.top).toString() + ")"), y.push("scale(1 -1)"), s.top = s.left = 0);
    let w;
    switch (k < 0 && (k -= Math.floor(k / 4) * 4), k = k % 4, k) {
      case 1:
        w = s.height / 2 + s.top, y.unshift("rotate(90 " + w.toString() + " " + w.toString() + ")");
        break;
      case 2:
        y.unshift("rotate(180 " + (s.width / 2 + s.left).toString() + " " + (s.height / 2 + s.top).toString() + ")");
        break;
      case 3:
        w = s.width / 2 + s.left, y.unshift("rotate(-90 " + w.toString() + " " + w.toString() + ")");
        break;
    }
    k % 2 === 1 && (s.left !== s.top && (w = s.left, s.left = s.top, s.top = w), s.width !== s.height && (w = s.width, s.width = s.height, s.height = w)), y.length && (o = Z2(o, '<g transform="' + y.join(" ") + '">', "</g>"));
  });
  const a = i.width, n = i.height, l = s.width, h = s.height;
  let c, u;
  a === null ? (u = n === null ? "1em" : n === "auto" ? h : n, c = Oh(u, l / h)) : (c = a === "auto" ? l : a, u = n === null ? Oh(c, h / l) : n === "auto" ? h : n);
  const p = {}, d = (m, y) => {
    K2(y) || (p[m] = y.toString());
  };
  d("width", c), d("height", u);
  const g = [
    s.left,
    s.top,
    l,
    h
  ];
  return p.viewBox = g.join(" "), {
    attributes: p,
    viewBox: g,
    body: o
  };
}
const J2 = /\sid="(\S+)"/g, Dh = /* @__PURE__ */ new Map();
function tT(e) {
  e = e.replace(/[0-9]+$/, "") || "a";
  const t = Dh.get(e) || 0;
  return Dh.set(e, t + 1), t ? `${e}${t}` : e;
}
function eT(e) {
  const t = [];
  let r;
  for (; r = J2.exec(e); ) t.push(r[1]);
  if (!t.length) return e;
  const i = "suffix" + (Math.random() * 16777216 | Date.now()).toString(16);
  return t.forEach((s) => {
    const o = tT(s), a = s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    e = e.replace(new RegExp('([#;"])(' + a + ')([")]|\\.[a-z])', "g"), "$1" + o + i + "$3");
  }), e = e.replace(new RegExp(i, "g"), ""), e;
}
function rT(e, t) {
  let r = e.indexOf("xlink:") === -1 ? "" : ' xmlns:xlink="http://www.w3.org/1999/xlink"';
  for (const i in t) r += " " + i + '="' + t[i] + '"';
  return '<svg xmlns="http://www.w3.org/2000/svg"' + r + ">" + e + "</svg>";
}
function Qn() {
  return { async: !1, breaks: !1, extensions: null, gfm: !0, hooks: null, pedantic: !1, renderer: null, silent: !1, tokenizer: null, walkTokens: null };
}
var Ar = Qn();
function Xp(e) {
  Ar = e;
}
var Yi = { exec: () => null };
function mt(e, t = "") {
  let r = typeof e == "string" ? e : e.source, i = { replace: (s, o) => {
    let a = typeof o == "string" ? o : o.source;
    return a = a.replace(Vt.caret, "$1"), r = r.replace(s, a), i;
  }, getRegex: () => new RegExp(r, t) };
  return i;
}
var iT = (() => {
  try {
    return !!new RegExp("(?<=1)(?<!1)");
  } catch {
    return !1;
  }
})(), Vt = { codeRemoveIndent: /^(?: {1,4}| {0,3}\t)/gm, outputLinkReplace: /\\([\[\]])/g, indentCodeCompensation: /^(\s+)(?:```)/, beginningSpace: /^\s+/, endingHash: /#$/, startingSpaceChar: /^ /, endingSpaceChar: / $/, nonSpaceChar: /[^ ]/, newLineCharGlobal: /\n/g, tabCharGlobal: /\t/g, multipleSpaceGlobal: /\s+/g, blankLine: /^[ \t]*$/, doubleBlankLine: /\n[ \t]*\n[ \t]*$/, blockquoteStart: /^ {0,3}>/, blockquoteSetextReplace: /\n {0,3}((?:=+|-+) *)(?=\n|$)/g, blockquoteSetextReplace2: /^ {0,3}>[ \t]?/gm, listReplaceTabs: /^\t+/, listReplaceNesting: /^ {1,4}(?=( {4})*[^ ])/g, listIsTask: /^\[[ xX]\] /, listReplaceTask: /^\[[ xX]\] +/, anyLine: /\n.*\n/, hrefBrackets: /^<(.*)>$/, tableDelimiter: /[:|]/, tableAlignChars: /^\||\| *$/g, tableRowBlankLine: /\n[ \t]*$/, tableAlignRight: /^ *-+: *$/, tableAlignCenter: /^ *:-+: *$/, tableAlignLeft: /^ *:-+ *$/, startATag: /^<a /i, endATag: /^<\/a>/i, startPreScriptTag: /^<(pre|code|kbd|script)(\s|>)/i, endPreScriptTag: /^<\/(pre|code|kbd|script)(\s|>)/i, startAngleBracket: /^</, endAngleBracket: />$/, pedanticHrefTitle: /^([^'"]*[^\s])\s+(['"])(.*)\2/, unicodeAlphaNumeric: /[\p{L}\p{N}]/u, escapeTest: /[&<>"']/, escapeReplace: /[&<>"']/g, escapeTestNoEncode: /[<>"']|&(?!(#\d{1,7}|#[Xx][a-fA-F0-9]{1,6}|\w+);)/, escapeReplaceNoEncode: /[<>"']|&(?!(#\d{1,7}|#[Xx][a-fA-F0-9]{1,6}|\w+);)/g, unescapeTest: /&(#(?:\d+)|(?:#x[0-9A-Fa-f]+)|(?:\w+));?/ig, caret: /(^|[^\[])\^/g, percentDecode: /%25/g, findPipe: /\|/g, splitPipe: / \|/, slashPipe: /\\\|/g, carriageReturn: /\r\n|\r/g, spaceLine: /^ +$/gm, notSpaceStart: /^\S*/, endingNewline: /\n$/, listItemRegex: (e) => new RegExp(`^( {0,3}${e})((?:[	 ][^\\n]*)?(?:\\n|$))`), nextBulletRegex: (e) => new RegExp(`^ {0,${Math.min(3, e - 1)}}(?:[*+-]|\\d{1,9}[.)])((?:[ 	][^\\n]*)?(?:\\n|$))`), hrRegex: (e) => new RegExp(`^ {0,${Math.min(3, e - 1)}}((?:- *){3,}|(?:_ *){3,}|(?:\\* *){3,})(?:\\n+|$)`), fencesBeginRegex: (e) => new RegExp(`^ {0,${Math.min(3, e - 1)}}(?:\`\`\`|~~~)`), headingBeginRegex: (e) => new RegExp(`^ {0,${Math.min(3, e - 1)}}#`), htmlBeginRegex: (e) => new RegExp(`^ {0,${Math.min(3, e - 1)}}<(?:[a-z].*>|!--)`, "i") }, sT = /^(?:[ \t]*(?:\n|$))+/, oT = /^((?: {4}| {0,3}\t)[^\n]+(?:\n(?:[ \t]*(?:\n|$))*)?)+/, aT = /^ {0,3}(`{3,}(?=[^`\n]*(?:\n|$))|~{3,})([^\n]*)(?:\n|$)(?:|([\s\S]*?)(?:\n|$))(?: {0,3}\1[~`]* *(?=\n|$)|$)/, ds = /^ {0,3}((?:-[\t ]*){3,}|(?:_[ \t]*){3,}|(?:\*[ \t]*){3,})(?:\n+|$)/, nT = /^ {0,3}(#{1,6})(?=\s|$)(.*)(?:\n+|$)/, Jn = /(?:[*+-]|\d{1,9}[.)])/, Up = /^(?!bull |blockCode|fences|blockquote|heading|html|table)((?:.|\n(?!\s*?\n|bull |blockCode|fences|blockquote|heading|html|table))+?)\n {0,3}(=+|-+) *(?:\n+|$)/, jp = mt(Up).replace(/bull/g, Jn).replace(/blockCode/g, /(?: {4}| {0,3}\t)/).replace(/fences/g, / {0,3}(?:`{3,}|~{3,})/).replace(/blockquote/g, / {0,3}>/).replace(/heading/g, / {0,3}#{1,6}/).replace(/html/g, / {0,3}<[^\n>]+>\n/).replace(/\|table/g, "").getRegex(), lT = mt(Up).replace(/bull/g, Jn).replace(/blockCode/g, /(?: {4}| {0,3}\t)/).replace(/fences/g, / {0,3}(?:`{3,}|~{3,})/).replace(/blockquote/g, / {0,3}>/).replace(/heading/g, / {0,3}#{1,6}/).replace(/html/g, / {0,3}<[^\n>]+>\n/).replace(/table/g, / {0,3}\|?(?:[:\- ]*\|)+[\:\- ]*\n/).getRegex(), tl = /^([^\n]+(?:\n(?!hr|heading|lheading|blockquote|fences|list|html|table| +\n)[^\n]+)*)/, hT = /^[^\n]+/, el = /(?!\s*\])(?:\\[\s\S]|[^\[\]\\])+/, cT = mt(/^ {0,3}\[(label)\]: *(?:\n[ \t]*)?([^<\s][^\s]*|<.*?>)(?:(?: +(?:\n[ \t]*)?| *\n[ \t]*)(title))? *(?:\n+|$)/).replace("label", el).replace("title", /(?:"(?:\\"?|[^"\\])*"|'[^'\n]*(?:\n[^'\n]+)*\n?'|\([^()]*\))/).getRegex(), uT = mt(/^( {0,3}bull)([ \t][^\n]+?)?(?:\n|$)/).replace(/bull/g, Jn).getRegex(), Eo = "address|article|aside|base|basefont|blockquote|body|caption|center|col|colgroup|dd|details|dialog|dir|div|dl|dt|fieldset|figcaption|figure|footer|form|frame|frameset|h[1-6]|head|header|hr|html|iframe|legend|li|link|main|menu|menuitem|meta|nav|noframes|ol|optgroup|option|p|param|search|section|summary|table|tbody|td|tfoot|th|thead|title|tr|track|ul", rl = /<!--(?:-?>|[\s\S]*?(?:-->|$))/, dT = mt("^ {0,3}(?:<(script|pre|style|textarea)[\\s>][\\s\\S]*?(?:</\\1>[^\\n]*\\n+|$)|comment[^\\n]*(\\n+|$)|<\\?[\\s\\S]*?(?:\\?>\\n*|$)|<![A-Z][\\s\\S]*?(?:>\\n*|$)|<!\\[CDATA\\[[\\s\\S]*?(?:\\]\\]>\\n*|$)|</?(tag)(?: +|\\n|/?>)[\\s\\S]*?(?:(?:\\n[ 	]*)+\\n|$)|<(?!script|pre|style|textarea)([a-z][\\w-]*)(?:attribute)*? */?>(?=[ \\t]*(?:\\n|$))[\\s\\S]*?(?:(?:\\n[ 	]*)+\\n|$)|</(?!script|pre|style|textarea)[a-z][\\w-]*\\s*>(?=[ \\t]*(?:\\n|$))[\\s\\S]*?(?:(?:\\n[ 	]*)+\\n|$))", "i").replace("comment", rl).replace("tag", Eo).replace("attribute", / +[a-zA-Z:_][\w.:-]*(?: *= *"[^"\n]*"| *= *'[^'\n]*'| *= *[^\s"'=<>`]+)?/).getRegex(), Gp = mt(tl).replace("hr", ds).replace("heading", " {0,3}#{1,6}(?:\\s|$)").replace("|lheading", "").replace("|table", "").replace("blockquote", " {0,3}>").replace("fences", " {0,3}(?:`{3,}(?=[^`\\n]*\\n)|~{3,})[^\\n]*\\n").replace("list", " {0,3}(?:[*+-]|1[.)]) ").replace("html", "</?(?:tag)(?: +|\\n|/?>)|<(?:script|pre|style|textarea|!--)").replace("tag", Eo).getRegex(), pT = mt(/^( {0,3}> ?(paragraph|[^\n]*)(?:\n|$))+/).replace("paragraph", Gp).getRegex(), il = { blockquote: pT, code: oT, def: cT, fences: aT, heading: nT, hr: ds, html: dT, lheading: jp, list: uT, newline: sT, paragraph: Gp, table: Yi, text: hT }, Rh = mt("^ *([^\\n ].*)\\n {0,3}((?:\\| *)?:?-+:? *(?:\\| *:?-+:? *)*(?:\\| *)?)(?:\\n((?:(?! *\\n|hr|heading|blockquote|code|fences|list|html).*(?:\\n|$))*)\\n*|$)").replace("hr", ds).replace("heading", " {0,3}#{1,6}(?:\\s|$)").replace("blockquote", " {0,3}>").replace("code", "(?: {4}| {0,3}	)[^\\n]").replace("fences", " {0,3}(?:`{3,}(?=[^`\\n]*\\n)|~{3,})[^\\n]*\\n").replace("list", " {0,3}(?:[*+-]|1[.)]) ").replace("html", "</?(?:tag)(?: +|\\n|/?>)|<(?:script|pre|style|textarea|!--)").replace("tag", Eo).getRegex(), fT = { ...il, lheading: lT, table: Rh, paragraph: mt(tl).replace("hr", ds).replace("heading", " {0,3}#{1,6}(?:\\s|$)").replace("|lheading", "").replace("table", Rh).replace("blockquote", " {0,3}>").replace("fences", " {0,3}(?:`{3,}(?=[^`\\n]*\\n)|~{3,})[^\\n]*\\n").replace("list", " {0,3}(?:[*+-]|1[.)]) ").replace("html", "</?(?:tag)(?: +|\\n|/?>)|<(?:script|pre|style|textarea|!--)").replace("tag", Eo).getRegex() }, gT = { ...il, html: mt(`^ *(?:comment *(?:\\n|\\s*$)|<(tag)[\\s\\S]+?</\\1> *(?:\\n{2,}|\\s*$)|<tag(?:"[^"]*"|'[^']*'|\\s[^'"/>\\s]*)*?/?> *(?:\\n{2,}|\\s*$))`).replace("comment", rl).replace(/tag/g, "(?!(?:a|em|strong|small|s|cite|q|dfn|abbr|data|time|code|var|samp|kbd|sub|sup|i|b|u|mark|ruby|rt|rp|bdi|bdo|span|br|wbr|ins|del|img)\\b)\\w+(?!:|[^\\w\\s@]*@)\\b").getRegex(), def: /^ *\[([^\]]+)\]: *<?([^\s>]+)>?(?: +(["(][^\n]+[")]))? *(?:\n+|$)/, heading: /^(#{1,6})(.*)(?:\n+|$)/, fences: Yi, lheading: /^(.+?)\n {0,3}(=+|-+) *(?:\n+|$)/, paragraph: mt(tl).replace("hr", ds).replace("heading", ` *#{1,6} *[^
]`).replace("lheading", jp).replace("|table", "").replace("blockquote", " {0,3}>").replace("|fences", "").replace("|list", "").replace("|html", "").replace("|tag", "").getRegex() }, mT = /^\\([!"#$%&'()*+,\-./:;<=>?@\[\]\\^_`{|}~])/, yT = /^(`+)([^`]|[^`][\s\S]*?[^`])\1(?!`)/, Vp = /^( {2,}|\\)\n(?!\s*$)/, xT = /^(`+|[^`])(?:(?= {2,}\n)|[\s\S]*?(?:(?=[\\<!\[`*_]|\b_|$)|[^ ](?= {2,}\n)))/, Fo = /[\p{P}\p{S}]/u, sl = /[\s\p{P}\p{S}]/u, Zp = /[^\s\p{P}\p{S}]/u, CT = mt(/^((?![*_])punctSpace)/, "u").replace(/punctSpace/g, sl).getRegex(), Kp = /(?!~)[\p{P}\p{S}]/u, bT = /(?!~)[\s\p{P}\p{S}]/u, kT = /(?:[^\s\p{P}\p{S}]|~)/u, TT = mt(/link|precode-code|html/, "g").replace("link", /\[(?:[^\[\]`]|(?<a>`+)[^`]+\k<a>(?!`))*?\]\((?:\\[\s\S]|[^\\\(\)]|\((?:\\[\s\S]|[^\\\(\)])*\))*\)/).replace("precode-", iT ? "(?<!`)()" : "(^^|[^`])").replace("code", /(?<b>`+)[^`]+\k<b>(?!`)/).replace("html", /<(?! )[^<>]*?>/).getRegex(), Qp = /^(?:\*+(?:((?!\*)punct)|[^\s*]))|^_+(?:((?!_)punct)|([^\s_]))/, ST = mt(Qp, "u").replace(/punct/g, Fo).getRegex(), wT = mt(Qp, "u").replace(/punct/g, Kp).getRegex(), Jp = "^[^_*]*?__[^_*]*?\\*[^_*]*?(?=__)|[^*]+(?=[^*])|(?!\\*)punct(\\*+)(?=[\\s]|$)|notPunctSpace(\\*+)(?!\\*)(?=punctSpace|$)|(?!\\*)punctSpace(\\*+)(?=notPunctSpace)|[\\s](\\*+)(?!\\*)(?=punct)|(?!\\*)punct(\\*+)(?!\\*)(?=punct)|notPunctSpace(\\*+)(?=notPunctSpace)", _T = mt(Jp, "gu").replace(/notPunctSpace/g, Zp).replace(/punctSpace/g, sl).replace(/punct/g, Fo).getRegex(), BT = mt(Jp, "gu").replace(/notPunctSpace/g, kT).replace(/punctSpace/g, bT).replace(/punct/g, Kp).getRegex(), vT = mt("^[^_*]*?\\*\\*[^_*]*?_[^_*]*?(?=\\*\\*)|[^_]+(?=[^_])|(?!_)punct(_+)(?=[\\s]|$)|notPunctSpace(_+)(?!_)(?=punctSpace|$)|(?!_)punctSpace(_+)(?=notPunctSpace)|[\\s](_+)(?!_)(?=punct)|(?!_)punct(_+)(?!_)(?=punct)", "gu").replace(/notPunctSpace/g, Zp).replace(/punctSpace/g, sl).replace(/punct/g, Fo).getRegex(), LT = mt(/\\(punct)/, "gu").replace(/punct/g, Fo).getRegex(), AT = mt(/^<(scheme:[^\s\x00-\x1f<>]*|email)>/).replace("scheme", /[a-zA-Z][a-zA-Z0-9+.-]{1,31}/).replace("email", /[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+(@)[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+(?![-_])/).getRegex(), ET = mt(rl).replace("(?:-->|$)", "-->").getRegex(), FT = mt("^comment|^</[a-zA-Z][\\w:-]*\\s*>|^<[a-zA-Z][\\w-]*(?:attribute)*?\\s*/?>|^<\\?[\\s\\S]*?\\?>|^<![a-zA-Z]+\\s[\\s\\S]*?>|^<!\\[CDATA\\[[\\s\\S]*?\\]\\]>").replace("comment", ET).replace("attribute", /\s+[a-zA-Z:_][\w.:-]*(?:\s*=\s*"[^"]*"|\s*=\s*'[^']*'|\s*=\s*[^\s"'=<>`]+)?/).getRegex(), uo = /(?:\[(?:\\[\s\S]|[^\[\]\\])*\]|\\[\s\S]|`+[^`]*?`+(?!`)|[^\[\]\\`])*?/, MT = mt(/^!?\[(label)\]\(\s*(href)(?:(?:[ \t]*(?:\n[ \t]*)?)(title))?\s*\)/).replace("label", uo).replace("href", /<(?:\\.|[^\n<>\\])+>|[^ \t\n\x00-\x1f]*/).replace("title", /"(?:\\"?|[^"\\])*"|'(?:\\'?|[^'\\])*'|\((?:\\\)?|[^)\\])*\)/).getRegex(), tf = mt(/^!?\[(label)\]\[(ref)\]/).replace("label", uo).replace("ref", el).getRegex(), ef = mt(/^!?\[(ref)\](?:\[\])?/).replace("ref", el).getRegex(), IT = mt("reflink|nolink(?!\\()", "g").replace("reflink", tf).replace("nolink", ef).getRegex(), Ph = /[hH][tT][tT][pP][sS]?|[fF][tT][pP]/, ol = { _backpedal: Yi, anyPunctuation: LT, autolink: AT, blockSkip: TT, br: Vp, code: yT, del: Yi, emStrongLDelim: ST, emStrongRDelimAst: _T, emStrongRDelimUnd: vT, escape: mT, link: MT, nolink: ef, punctuation: CT, reflink: tf, reflinkSearch: IT, tag: FT, text: xT, url: Yi }, $T = { ...ol, link: mt(/^!?\[(label)\]\((.*?)\)/).replace("label", uo).getRegex(), reflink: mt(/^!?\[(label)\]\s*\[([^\]]*)\]/).replace("label", uo).getRegex() }, Va = { ...ol, emStrongRDelimAst: BT, emStrongLDelim: wT, url: mt(/^((?:protocol):\/\/|www\.)(?:[a-zA-Z0-9\-]+\.?)+[^\s<]*|^email/).replace("protocol", Ph).replace("email", /[A-Za-z0-9._+-]+(@)[a-zA-Z0-9-_]+(?:\.[a-zA-Z0-9-_]*[a-zA-Z0-9])+(?![-_])/).getRegex(), _backpedal: /(?:[^?!.,:;*_'"~()&]+|\([^)]*\)|&(?![a-zA-Z0-9]+;$)|[?!.,:;*_'"~)]+(?!$))+/, del: /^(~~?)(?=[^\s~])((?:\\[\s\S]|[^\\])*?(?:\\[\s\S]|[^\s~\\]))\1(?=[^~]|$)/, text: mt(/^([`~]+|[^`~])(?:(?= {2,}\n)|(?=[a-zA-Z0-9.!#$%&'*+\/=?_`{\|}~-]+@)|[\s\S]*?(?:(?=[\\<!\[`*~_]|\b_|protocol:\/\/|www\.|$)|[^ ](?= {2,}\n)|[^a-zA-Z0-9.!#$%&'*+\/=?_`{\|}~-](?=[a-zA-Z0-9.!#$%&'*+\/=?_`{\|}~-]+@)))/).replace("protocol", Ph).getRegex() }, OT = { ...Va, br: mt(Vp).replace("{2,}", "*").getRegex(), text: mt(Va.text).replace("\\b_", "\\b_| {2,}\\n").replace(/\{2,\}/g, "*").getRegex() }, As = { normal: il, gfm: fT, pedantic: gT }, Li = { normal: ol, gfm: Va, breaks: OT, pedantic: $T }, DT = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }, Nh = (e) => DT[e];
function Ee(e, t) {
  if (t) {
    if (Vt.escapeTest.test(e)) return e.replace(Vt.escapeReplace, Nh);
  } else if (Vt.escapeTestNoEncode.test(e)) return e.replace(Vt.escapeReplaceNoEncode, Nh);
  return e;
}
function qh(e) {
  try {
    e = encodeURI(e).replace(Vt.percentDecode, "%");
  } catch {
    return null;
  }
  return e;
}
function Wh(e, t) {
  var o;
  let r = e.replace(Vt.findPipe, (a, n, l) => {
    let h = !1, c = n;
    for (; --c >= 0 && l[c] === "\\"; ) h = !h;
    return h ? "|" : " |";
  }), i = r.split(Vt.splitPipe), s = 0;
  if (i[0].trim() || i.shift(), i.length > 0 && !((o = i.at(-1)) != null && o.trim()) && i.pop(), t) if (i.length > t) i.splice(t);
  else for (; i.length < t; ) i.push("");
  for (; s < i.length; s++) i[s] = i[s].trim().replace(Vt.slashPipe, "|");
  return i;
}
function Ai(e, t, r) {
  let i = e.length;
  if (i === 0) return "";
  let s = 0;
  for (; s < i && e.charAt(i - s - 1) === t; )
    s++;
  return e.slice(0, i - s);
}
function RT(e, t) {
  if (e.indexOf(t[1]) === -1) return -1;
  let r = 0;
  for (let i = 0; i < e.length; i++) if (e[i] === "\\") i++;
  else if (e[i] === t[0]) r++;
  else if (e[i] === t[1] && (r--, r < 0)) return i;
  return r > 0 ? -2 : -1;
}
function zh(e, t, r, i, s) {
  let o = t.href, a = t.title || null, n = e[1].replace(s.other.outputLinkReplace, "$1");
  i.state.inLink = !0;
  let l = { type: e[0].charAt(0) === "!" ? "image" : "link", raw: r, href: o, title: a, text: n, tokens: i.inlineTokens(n) };
  return i.state.inLink = !1, l;
}
function PT(e, t, r) {
  let i = e.match(r.other.indentCodeCompensation);
  if (i === null) return t;
  let s = i[1];
  return t.split(`
`).map((o) => {
    let a = o.match(r.other.beginningSpace);
    if (a === null) return o;
    let [n] = a;
    return n.length >= s.length ? o.slice(s.length) : o;
  }).join(`
`);
}
var po = class {
  constructor(e) {
    bt(this, "options");
    bt(this, "rules");
    bt(this, "lexer");
    this.options = e || Ar;
  }
  space(e) {
    let t = this.rules.block.newline.exec(e);
    if (t && t[0].length > 0) return { type: "space", raw: t[0] };
  }
  code(e) {
    let t = this.rules.block.code.exec(e);
    if (t) {
      let r = t[0].replace(this.rules.other.codeRemoveIndent, "");
      return { type: "code", raw: t[0], codeBlockStyle: "indented", text: this.options.pedantic ? r : Ai(r, `
`) };
    }
  }
  fences(e) {
    let t = this.rules.block.fences.exec(e);
    if (t) {
      let r = t[0], i = PT(r, t[3] || "", this.rules);
      return { type: "code", raw: r, lang: t[2] ? t[2].trim().replace(this.rules.inline.anyPunctuation, "$1") : t[2], text: i };
    }
  }
  heading(e) {
    let t = this.rules.block.heading.exec(e);
    if (t) {
      let r = t[2].trim();
      if (this.rules.other.endingHash.test(r)) {
        let i = Ai(r, "#");
        (this.options.pedantic || !i || this.rules.other.endingSpaceChar.test(i)) && (r = i.trim());
      }
      return { type: "heading", raw: t[0], depth: t[1].length, text: r, tokens: this.lexer.inline(r) };
    }
  }
  hr(e) {
    let t = this.rules.block.hr.exec(e);
    if (t) return { type: "hr", raw: Ai(t[0], `
`) };
  }
  blockquote(e) {
    let t = this.rules.block.blockquote.exec(e);
    if (t) {
      let r = Ai(t[0], `
`).split(`
`), i = "", s = "", o = [];
      for (; r.length > 0; ) {
        let a = !1, n = [], l;
        for (l = 0; l < r.length; l++) if (this.rules.other.blockquoteStart.test(r[l])) n.push(r[l]), a = !0;
        else if (!a) n.push(r[l]);
        else break;
        r = r.slice(l);
        let h = n.join(`
`), c = h.replace(this.rules.other.blockquoteSetextReplace, `
    $1`).replace(this.rules.other.blockquoteSetextReplace2, "");
        i = i ? `${i}
${h}` : h, s = s ? `${s}
${c}` : c;
        let u = this.lexer.state.top;
        if (this.lexer.state.top = !0, this.lexer.blockTokens(c, o, !0), this.lexer.state.top = u, r.length === 0) break;
        let p = o.at(-1);
        if ((p == null ? void 0 : p.type) === "code") break;
        if ((p == null ? void 0 : p.type) === "blockquote") {
          let d = p, g = d.raw + `
` + r.join(`
`), m = this.blockquote(g);
          o[o.length - 1] = m, i = i.substring(0, i.length - d.raw.length) + m.raw, s = s.substring(0, s.length - d.text.length) + m.text;
          break;
        } else if ((p == null ? void 0 : p.type) === "list") {
          let d = p, g = d.raw + `
` + r.join(`
`), m = this.list(g);
          o[o.length - 1] = m, i = i.substring(0, i.length - p.raw.length) + m.raw, s = s.substring(0, s.length - d.raw.length) + m.raw, r = g.substring(o.at(-1).raw.length).split(`
`);
          continue;
        }
      }
      return { type: "blockquote", raw: i, tokens: o, text: s };
    }
  }
  list(e) {
    let t = this.rules.block.list.exec(e);
    if (t) {
      let r = t[1].trim(), i = r.length > 1, s = { type: "list", raw: "", ordered: i, start: i ? +r.slice(0, -1) : "", loose: !1, items: [] };
      r = i ? `\\d{1,9}\\${r.slice(-1)}` : `\\${r}`, this.options.pedantic && (r = i ? r : "[*+-]");
      let o = this.rules.other.listItemRegex(r), a = !1;
      for (; e; ) {
        let l = !1, h = "", c = "";
        if (!(t = o.exec(e)) || this.rules.block.hr.test(e)) break;
        h = t[0], e = e.substring(h.length);
        let u = t[2].split(`
`, 1)[0].replace(this.rules.other.listReplaceTabs, (x) => " ".repeat(3 * x.length)), p = e.split(`
`, 1)[0], d = !u.trim(), g = 0;
        if (this.options.pedantic ? (g = 2, c = u.trimStart()) : d ? g = t[1].length + 1 : (g = t[2].search(this.rules.other.nonSpaceChar), g = g > 4 ? 1 : g, c = u.slice(g), g += t[1].length), d && this.rules.other.blankLine.test(p) && (h += p + `
`, e = e.substring(p.length + 1), l = !0), !l) {
          let x = this.rules.other.nextBulletRegex(g), b = this.rules.other.hrRegex(g), k = this.rules.other.fencesBeginRegex(g), w = this.rules.other.headingBeginRegex(g), S = this.rules.other.htmlBeginRegex(g);
          for (; e; ) {
            let L = e.split(`
`, 1)[0], T;
            if (p = L, this.options.pedantic ? (p = p.replace(this.rules.other.listReplaceNesting, "  "), T = p) : T = p.replace(this.rules.other.tabCharGlobal, "    "), k.test(p) || w.test(p) || S.test(p) || x.test(p) || b.test(p)) break;
            if (T.search(this.rules.other.nonSpaceChar) >= g || !p.trim()) c += `
` + T.slice(g);
            else {
              if (d || u.replace(this.rules.other.tabCharGlobal, "    ").search(this.rules.other.nonSpaceChar) >= 4 || k.test(u) || w.test(u) || b.test(u)) break;
              c += `
` + p;
            }
            !d && !p.trim() && (d = !0), h += L + `
`, e = e.substring(L.length + 1), u = T.slice(g);
          }
        }
        s.loose || (a ? s.loose = !0 : this.rules.other.doubleBlankLine.test(h) && (a = !0));
        let m = null, y;
        this.options.gfm && (m = this.rules.other.listIsTask.exec(c), m && (y = m[0] !== "[ ] ", c = c.replace(this.rules.other.listReplaceTask, ""))), s.items.push({ type: "list_item", raw: h, task: !!m, checked: y, loose: !1, text: c, tokens: [] }), s.raw += h;
      }
      let n = s.items.at(-1);
      if (n) n.raw = n.raw.trimEnd(), n.text = n.text.trimEnd();
      else return;
      s.raw = s.raw.trimEnd();
      for (let l = 0; l < s.items.length; l++) if (this.lexer.state.top = !1, s.items[l].tokens = this.lexer.blockTokens(s.items[l].text, []), !s.loose) {
        let h = s.items[l].tokens.filter((u) => u.type === "space"), c = h.length > 0 && h.some((u) => this.rules.other.anyLine.test(u.raw));
        s.loose = c;
      }
      if (s.loose) for (let l = 0; l < s.items.length; l++) s.items[l].loose = !0;
      return s;
    }
  }
  html(e) {
    let t = this.rules.block.html.exec(e);
    if (t) return { type: "html", block: !0, raw: t[0], pre: t[1] === "pre" || t[1] === "script" || t[1] === "style", text: t[0] };
  }
  def(e) {
    let t = this.rules.block.def.exec(e);
    if (t) {
      let r = t[1].toLowerCase().replace(this.rules.other.multipleSpaceGlobal, " "), i = t[2] ? t[2].replace(this.rules.other.hrefBrackets, "$1").replace(this.rules.inline.anyPunctuation, "$1") : "", s = t[3] ? t[3].substring(1, t[3].length - 1).replace(this.rules.inline.anyPunctuation, "$1") : t[3];
      return { type: "def", tag: r, raw: t[0], href: i, title: s };
    }
  }
  table(e) {
    var a;
    let t = this.rules.block.table.exec(e);
    if (!t || !this.rules.other.tableDelimiter.test(t[2])) return;
    let r = Wh(t[1]), i = t[2].replace(this.rules.other.tableAlignChars, "").split("|"), s = (a = t[3]) != null && a.trim() ? t[3].replace(this.rules.other.tableRowBlankLine, "").split(`
`) : [], o = { type: "table", raw: t[0], header: [], align: [], rows: [] };
    if (r.length === i.length) {
      for (let n of i) this.rules.other.tableAlignRight.test(n) ? o.align.push("right") : this.rules.other.tableAlignCenter.test(n) ? o.align.push("center") : this.rules.other.tableAlignLeft.test(n) ? o.align.push("left") : o.align.push(null);
      for (let n = 0; n < r.length; n++) o.header.push({ text: r[n], tokens: this.lexer.inline(r[n]), header: !0, align: o.align[n] });
      for (let n of s) o.rows.push(Wh(n, o.header.length).map((l, h) => ({ text: l, tokens: this.lexer.inline(l), header: !1, align: o.align[h] })));
      return o;
    }
  }
  lheading(e) {
    let t = this.rules.block.lheading.exec(e);
    if (t) return { type: "heading", raw: t[0], depth: t[2].charAt(0) === "=" ? 1 : 2, text: t[1], tokens: this.lexer.inline(t[1]) };
  }
  paragraph(e) {
    let t = this.rules.block.paragraph.exec(e);
    if (t) {
      let r = t[1].charAt(t[1].length - 1) === `
` ? t[1].slice(0, -1) : t[1];
      return { type: "paragraph", raw: t[0], text: r, tokens: this.lexer.inline(r) };
    }
  }
  text(e) {
    let t = this.rules.block.text.exec(e);
    if (t) return { type: "text", raw: t[0], text: t[0], tokens: this.lexer.inline(t[0]) };
  }
  escape(e) {
    let t = this.rules.inline.escape.exec(e);
    if (t) return { type: "escape", raw: t[0], text: t[1] };
  }
  tag(e) {
    let t = this.rules.inline.tag.exec(e);
    if (t) return !this.lexer.state.inLink && this.rules.other.startATag.test(t[0]) ? this.lexer.state.inLink = !0 : this.lexer.state.inLink && this.rules.other.endATag.test(t[0]) && (this.lexer.state.inLink = !1), !this.lexer.state.inRawBlock && this.rules.other.startPreScriptTag.test(t[0]) ? this.lexer.state.inRawBlock = !0 : this.lexer.state.inRawBlock && this.rules.other.endPreScriptTag.test(t[0]) && (this.lexer.state.inRawBlock = !1), { type: "html", raw: t[0], inLink: this.lexer.state.inLink, inRawBlock: this.lexer.state.inRawBlock, block: !1, text: t[0] };
  }
  link(e) {
    let t = this.rules.inline.link.exec(e);
    if (t) {
      let r = t[2].trim();
      if (!this.options.pedantic && this.rules.other.startAngleBracket.test(r)) {
        if (!this.rules.other.endAngleBracket.test(r)) return;
        let o = Ai(r.slice(0, -1), "\\");
        if ((r.length - o.length) % 2 === 0) return;
      } else {
        let o = RT(t[2], "()");
        if (o === -2) return;
        if (o > -1) {
          let a = (t[0].indexOf("!") === 0 ? 5 : 4) + t[1].length + o;
          t[2] = t[2].substring(0, o), t[0] = t[0].substring(0, a).trim(), t[3] = "";
        }
      }
      let i = t[2], s = "";
      if (this.options.pedantic) {
        let o = this.rules.other.pedanticHrefTitle.exec(i);
        o && (i = o[1], s = o[3]);
      } else s = t[3] ? t[3].slice(1, -1) : "";
      return i = i.trim(), this.rules.other.startAngleBracket.test(i) && (this.options.pedantic && !this.rules.other.endAngleBracket.test(r) ? i = i.slice(1) : i = i.slice(1, -1)), zh(t, { href: i && i.replace(this.rules.inline.anyPunctuation, "$1"), title: s && s.replace(this.rules.inline.anyPunctuation, "$1") }, t[0], this.lexer, this.rules);
    }
  }
  reflink(e, t) {
    let r;
    if ((r = this.rules.inline.reflink.exec(e)) || (r = this.rules.inline.nolink.exec(e))) {
      let i = (r[2] || r[1]).replace(this.rules.other.multipleSpaceGlobal, " "), s = t[i.toLowerCase()];
      if (!s) {
        let o = r[0].charAt(0);
        return { type: "text", raw: o, text: o };
      }
      return zh(r, s, r[0], this.lexer, this.rules);
    }
  }
  emStrong(e, t, r = "") {
    let i = this.rules.inline.emStrongLDelim.exec(e);
    if (!(!i || i[3] && r.match(this.rules.other.unicodeAlphaNumeric)) && (!(i[1] || i[2]) || !r || this.rules.inline.punctuation.exec(r))) {
      let s = [...i[0]].length - 1, o, a, n = s, l = 0, h = i[0][0] === "*" ? this.rules.inline.emStrongRDelimAst : this.rules.inline.emStrongRDelimUnd;
      for (h.lastIndex = 0, t = t.slice(-1 * e.length + s); (i = h.exec(t)) != null; ) {
        if (o = i[1] || i[2] || i[3] || i[4] || i[5] || i[6], !o) continue;
        if (a = [...o].length, i[3] || i[4]) {
          n += a;
          continue;
        } else if ((i[5] || i[6]) && s % 3 && !((s + a) % 3)) {
          l += a;
          continue;
        }
        if (n -= a, n > 0) continue;
        a = Math.min(a, a + n + l);
        let c = [...i[0]][0].length, u = e.slice(0, s + i.index + c + a);
        if (Math.min(s, a) % 2) {
          let d = u.slice(1, -1);
          return { type: "em", raw: u, text: d, tokens: this.lexer.inlineTokens(d) };
        }
        let p = u.slice(2, -2);
        return { type: "strong", raw: u, text: p, tokens: this.lexer.inlineTokens(p) };
      }
    }
  }
  codespan(e) {
    let t = this.rules.inline.code.exec(e);
    if (t) {
      let r = t[2].replace(this.rules.other.newLineCharGlobal, " "), i = this.rules.other.nonSpaceChar.test(r), s = this.rules.other.startingSpaceChar.test(r) && this.rules.other.endingSpaceChar.test(r);
      return i && s && (r = r.substring(1, r.length - 1)), { type: "codespan", raw: t[0], text: r };
    }
  }
  br(e) {
    let t = this.rules.inline.br.exec(e);
    if (t) return { type: "br", raw: t[0] };
  }
  del(e) {
    let t = this.rules.inline.del.exec(e);
    if (t) return { type: "del", raw: t[0], text: t[2], tokens: this.lexer.inlineTokens(t[2]) };
  }
  autolink(e) {
    let t = this.rules.inline.autolink.exec(e);
    if (t) {
      let r, i;
      return t[2] === "@" ? (r = t[1], i = "mailto:" + r) : (r = t[1], i = r), { type: "link", raw: t[0], text: r, href: i, tokens: [{ type: "text", raw: r, text: r }] };
    }
  }
  url(e) {
    var r;
    let t;
    if (t = this.rules.inline.url.exec(e)) {
      let i, s;
      if (t[2] === "@") i = t[0], s = "mailto:" + i;
      else {
        let o;
        do
          o = t[0], t[0] = ((r = this.rules.inline._backpedal.exec(t[0])) == null ? void 0 : r[0]) ?? "";
        while (o !== t[0]);
        i = t[0], t[1] === "www." ? s = "http://" + t[0] : s = t[0];
      }
      return { type: "link", raw: t[0], text: i, href: s, tokens: [{ type: "text", raw: i, text: i }] };
    }
  }
  inlineText(e) {
    let t = this.rules.inline.text.exec(e);
    if (t) {
      let r = this.lexer.state.inRawBlock;
      return { type: "text", raw: t[0], text: t[0], escaped: r };
    }
  }
}, xe = class Za {
  constructor(t) {
    bt(this, "tokens");
    bt(this, "options");
    bt(this, "state");
    bt(this, "tokenizer");
    bt(this, "inlineQueue");
    this.tokens = [], this.tokens.links = /* @__PURE__ */ Object.create(null), this.options = t || Ar, this.options.tokenizer = this.options.tokenizer || new po(), this.tokenizer = this.options.tokenizer, this.tokenizer.options = this.options, this.tokenizer.lexer = this, this.inlineQueue = [], this.state = { inLink: !1, inRawBlock: !1, top: !0 };
    let r = { other: Vt, block: As.normal, inline: Li.normal };
    this.options.pedantic ? (r.block = As.pedantic, r.inline = Li.pedantic) : this.options.gfm && (r.block = As.gfm, this.options.breaks ? r.inline = Li.breaks : r.inline = Li.gfm), this.tokenizer.rules = r;
  }
  static get rules() {
    return { block: As, inline: Li };
  }
  static lex(t, r) {
    return new Za(r).lex(t);
  }
  static lexInline(t, r) {
    return new Za(r).inlineTokens(t);
  }
  lex(t) {
    t = t.replace(Vt.carriageReturn, `
`), this.blockTokens(t, this.tokens);
    for (let r = 0; r < this.inlineQueue.length; r++) {
      let i = this.inlineQueue[r];
      this.inlineTokens(i.src, i.tokens);
    }
    return this.inlineQueue = [], this.tokens;
  }
  blockTokens(t, r = [], i = !1) {
    var s, o, a;
    for (this.options.pedantic && (t = t.replace(Vt.tabCharGlobal, "    ").replace(Vt.spaceLine, "")); t; ) {
      let n;
      if ((o = (s = this.options.extensions) == null ? void 0 : s.block) != null && o.some((h) => (n = h.call({ lexer: this }, t, r)) ? (t = t.substring(n.raw.length), r.push(n), !0) : !1)) continue;
      if (n = this.tokenizer.space(t)) {
        t = t.substring(n.raw.length);
        let h = r.at(-1);
        n.raw.length === 1 && h !== void 0 ? h.raw += `
` : r.push(n);
        continue;
      }
      if (n = this.tokenizer.code(t)) {
        t = t.substring(n.raw.length);
        let h = r.at(-1);
        (h == null ? void 0 : h.type) === "paragraph" || (h == null ? void 0 : h.type) === "text" ? (h.raw += (h.raw.endsWith(`
`) ? "" : `
`) + n.raw, h.text += `
` + n.text, this.inlineQueue.at(-1).src = h.text) : r.push(n);
        continue;
      }
      if (n = this.tokenizer.fences(t)) {
        t = t.substring(n.raw.length), r.push(n);
        continue;
      }
      if (n = this.tokenizer.heading(t)) {
        t = t.substring(n.raw.length), r.push(n);
        continue;
      }
      if (n = this.tokenizer.hr(t)) {
        t = t.substring(n.raw.length), r.push(n);
        continue;
      }
      if (n = this.tokenizer.blockquote(t)) {
        t = t.substring(n.raw.length), r.push(n);
        continue;
      }
      if (n = this.tokenizer.list(t)) {
        t = t.substring(n.raw.length), r.push(n);
        continue;
      }
      if (n = this.tokenizer.html(t)) {
        t = t.substring(n.raw.length), r.push(n);
        continue;
      }
      if (n = this.tokenizer.def(t)) {
        t = t.substring(n.raw.length);
        let h = r.at(-1);
        (h == null ? void 0 : h.type) === "paragraph" || (h == null ? void 0 : h.type) === "text" ? (h.raw += (h.raw.endsWith(`
`) ? "" : `
`) + n.raw, h.text += `
` + n.raw, this.inlineQueue.at(-1).src = h.text) : this.tokens.links[n.tag] || (this.tokens.links[n.tag] = { href: n.href, title: n.title }, r.push(n));
        continue;
      }
      if (n = this.tokenizer.table(t)) {
        t = t.substring(n.raw.length), r.push(n);
        continue;
      }
      if (n = this.tokenizer.lheading(t)) {
        t = t.substring(n.raw.length), r.push(n);
        continue;
      }
      let l = t;
      if ((a = this.options.extensions) != null && a.startBlock) {
        let h = 1 / 0, c = t.slice(1), u;
        this.options.extensions.startBlock.forEach((p) => {
          u = p.call({ lexer: this }, c), typeof u == "number" && u >= 0 && (h = Math.min(h, u));
        }), h < 1 / 0 && h >= 0 && (l = t.substring(0, h + 1));
      }
      if (this.state.top && (n = this.tokenizer.paragraph(l))) {
        let h = r.at(-1);
        i && (h == null ? void 0 : h.type) === "paragraph" ? (h.raw += (h.raw.endsWith(`
`) ? "" : `
`) + n.raw, h.text += `
` + n.text, this.inlineQueue.pop(), this.inlineQueue.at(-1).src = h.text) : r.push(n), i = l.length !== t.length, t = t.substring(n.raw.length);
        continue;
      }
      if (n = this.tokenizer.text(t)) {
        t = t.substring(n.raw.length);
        let h = r.at(-1);
        (h == null ? void 0 : h.type) === "text" ? (h.raw += (h.raw.endsWith(`
`) ? "" : `
`) + n.raw, h.text += `
` + n.text, this.inlineQueue.pop(), this.inlineQueue.at(-1).src = h.text) : r.push(n);
        continue;
      }
      if (t) {
        let h = "Infinite loop on byte: " + t.charCodeAt(0);
        if (this.options.silent) {
          console.error(h);
          break;
        } else throw new Error(h);
      }
    }
    return this.state.top = !0, r;
  }
  inline(t, r = []) {
    return this.inlineQueue.push({ src: t, tokens: r }), r;
  }
  inlineTokens(t, r = []) {
    var l, h, c, u, p;
    let i = t, s = null;
    if (this.tokens.links) {
      let d = Object.keys(this.tokens.links);
      if (d.length > 0) for (; (s = this.tokenizer.rules.inline.reflinkSearch.exec(i)) != null; ) d.includes(s[0].slice(s[0].lastIndexOf("[") + 1, -1)) && (i = i.slice(0, s.index) + "[" + "a".repeat(s[0].length - 2) + "]" + i.slice(this.tokenizer.rules.inline.reflinkSearch.lastIndex));
    }
    for (; (s = this.tokenizer.rules.inline.anyPunctuation.exec(i)) != null; ) i = i.slice(0, s.index) + "++" + i.slice(this.tokenizer.rules.inline.anyPunctuation.lastIndex);
    let o;
    for (; (s = this.tokenizer.rules.inline.blockSkip.exec(i)) != null; ) o = s[2] ? s[2].length : 0, i = i.slice(0, s.index + o) + "[" + "a".repeat(s[0].length - o - 2) + "]" + i.slice(this.tokenizer.rules.inline.blockSkip.lastIndex);
    i = ((h = (l = this.options.hooks) == null ? void 0 : l.emStrongMask) == null ? void 0 : h.call({ lexer: this }, i)) ?? i;
    let a = !1, n = "";
    for (; t; ) {
      a || (n = ""), a = !1;
      let d;
      if ((u = (c = this.options.extensions) == null ? void 0 : c.inline) != null && u.some((m) => (d = m.call({ lexer: this }, t, r)) ? (t = t.substring(d.raw.length), r.push(d), !0) : !1)) continue;
      if (d = this.tokenizer.escape(t)) {
        t = t.substring(d.raw.length), r.push(d);
        continue;
      }
      if (d = this.tokenizer.tag(t)) {
        t = t.substring(d.raw.length), r.push(d);
        continue;
      }
      if (d = this.tokenizer.link(t)) {
        t = t.substring(d.raw.length), r.push(d);
        continue;
      }
      if (d = this.tokenizer.reflink(t, this.tokens.links)) {
        t = t.substring(d.raw.length);
        let m = r.at(-1);
        d.type === "text" && (m == null ? void 0 : m.type) === "text" ? (m.raw += d.raw, m.text += d.text) : r.push(d);
        continue;
      }
      if (d = this.tokenizer.emStrong(t, i, n)) {
        t = t.substring(d.raw.length), r.push(d);
        continue;
      }
      if (d = this.tokenizer.codespan(t)) {
        t = t.substring(d.raw.length), r.push(d);
        continue;
      }
      if (d = this.tokenizer.br(t)) {
        t = t.substring(d.raw.length), r.push(d);
        continue;
      }
      if (d = this.tokenizer.del(t)) {
        t = t.substring(d.raw.length), r.push(d);
        continue;
      }
      if (d = this.tokenizer.autolink(t)) {
        t = t.substring(d.raw.length), r.push(d);
        continue;
      }
      if (!this.state.inLink && (d = this.tokenizer.url(t))) {
        t = t.substring(d.raw.length), r.push(d);
        continue;
      }
      let g = t;
      if ((p = this.options.extensions) != null && p.startInline) {
        let m = 1 / 0, y = t.slice(1), x;
        this.options.extensions.startInline.forEach((b) => {
          x = b.call({ lexer: this }, y), typeof x == "number" && x >= 0 && (m = Math.min(m, x));
        }), m < 1 / 0 && m >= 0 && (g = t.substring(0, m + 1));
      }
      if (d = this.tokenizer.inlineText(g)) {
        t = t.substring(d.raw.length), d.raw.slice(-1) !== "_" && (n = d.raw.slice(-1)), a = !0;
        let m = r.at(-1);
        (m == null ? void 0 : m.type) === "text" ? (m.raw += d.raw, m.text += d.text) : r.push(d);
        continue;
      }
      if (t) {
        let m = "Infinite loop on byte: " + t.charCodeAt(0);
        if (this.options.silent) {
          console.error(m);
          break;
        } else throw new Error(m);
      }
    }
    return r;
  }
}, fo = class {
  constructor(e) {
    bt(this, "options");
    bt(this, "parser");
    this.options = e || Ar;
  }
  space(e) {
    return "";
  }
  code({ text: e, lang: t, escaped: r }) {
    var o;
    let i = (o = (t || "").match(Vt.notSpaceStart)) == null ? void 0 : o[0], s = e.replace(Vt.endingNewline, "") + `
`;
    return i ? '<pre><code class="language-' + Ee(i) + '">' + (r ? s : Ee(s, !0)) + `</code></pre>
` : "<pre><code>" + (r ? s : Ee(s, !0)) + `</code></pre>
`;
  }
  blockquote({ tokens: e }) {
    return `<blockquote>
${this.parser.parse(e)}</blockquote>
`;
  }
  html({ text: e }) {
    return e;
  }
  def(e) {
    return "";
  }
  heading({ tokens: e, depth: t }) {
    return `<h${t}>${this.parser.parseInline(e)}</h${t}>
`;
  }
  hr(e) {
    return `<hr>
`;
  }
  list(e) {
    let t = e.ordered, r = e.start, i = "";
    for (let a = 0; a < e.items.length; a++) {
      let n = e.items[a];
      i += this.listitem(n);
    }
    let s = t ? "ol" : "ul", o = t && r !== 1 ? ' start="' + r + '"' : "";
    return "<" + s + o + `>
` + i + "</" + s + `>
`;
  }
  listitem(e) {
    var r;
    let t = "";
    if (e.task) {
      let i = this.checkbox({ checked: !!e.checked });
      e.loose ? ((r = e.tokens[0]) == null ? void 0 : r.type) === "paragraph" ? (e.tokens[0].text = i + " " + e.tokens[0].text, e.tokens[0].tokens && e.tokens[0].tokens.length > 0 && e.tokens[0].tokens[0].type === "text" && (e.tokens[0].tokens[0].text = i + " " + Ee(e.tokens[0].tokens[0].text), e.tokens[0].tokens[0].escaped = !0)) : e.tokens.unshift({ type: "text", raw: i + " ", text: i + " ", escaped: !0 }) : t += i + " ";
    }
    return t += this.parser.parse(e.tokens, !!e.loose), `<li>${t}</li>
`;
  }
  checkbox({ checked: e }) {
    return "<input " + (e ? 'checked="" ' : "") + 'disabled="" type="checkbox">';
  }
  paragraph({ tokens: e }) {
    return `<p>${this.parser.parseInline(e)}</p>
`;
  }
  table(e) {
    let t = "", r = "";
    for (let s = 0; s < e.header.length; s++) r += this.tablecell(e.header[s]);
    t += this.tablerow({ text: r });
    let i = "";
    for (let s = 0; s < e.rows.length; s++) {
      let o = e.rows[s];
      r = "";
      for (let a = 0; a < o.length; a++) r += this.tablecell(o[a]);
      i += this.tablerow({ text: r });
    }
    return i && (i = `<tbody>${i}</tbody>`), `<table>
<thead>
` + t + `</thead>
` + i + `</table>
`;
  }
  tablerow({ text: e }) {
    return `<tr>
${e}</tr>
`;
  }
  tablecell(e) {
    let t = this.parser.parseInline(e.tokens), r = e.header ? "th" : "td";
    return (e.align ? `<${r} align="${e.align}">` : `<${r}>`) + t + `</${r}>
`;
  }
  strong({ tokens: e }) {
    return `<strong>${this.parser.parseInline(e)}</strong>`;
  }
  em({ tokens: e }) {
    return `<em>${this.parser.parseInline(e)}</em>`;
  }
  codespan({ text: e }) {
    return `<code>${Ee(e, !0)}</code>`;
  }
  br(e) {
    return "<br>";
  }
  del({ tokens: e }) {
    return `<del>${this.parser.parseInline(e)}</del>`;
  }
  link({ href: e, title: t, tokens: r }) {
    let i = this.parser.parseInline(r), s = qh(e);
    if (s === null) return i;
    e = s;
    let o = '<a href="' + e + '"';
    return t && (o += ' title="' + Ee(t) + '"'), o += ">" + i + "</a>", o;
  }
  image({ href: e, title: t, text: r, tokens: i }) {
    i && (r = this.parser.parseInline(i, this.parser.textRenderer));
    let s = qh(e);
    if (s === null) return Ee(r);
    e = s;
    let o = `<img src="${e}" alt="${r}"`;
    return t && (o += ` title="${Ee(t)}"`), o += ">", o;
  }
  text(e) {
    return "tokens" in e && e.tokens ? this.parser.parseInline(e.tokens) : "escaped" in e && e.escaped ? e.text : Ee(e.text);
  }
}, al = class {
  strong({ text: e }) {
    return e;
  }
  em({ text: e }) {
    return e;
  }
  codespan({ text: e }) {
    return e;
  }
  del({ text: e }) {
    return e;
  }
  html({ text: e }) {
    return e;
  }
  text({ text: e }) {
    return e;
  }
  link({ text: e }) {
    return "" + e;
  }
  image({ text: e }) {
    return "" + e;
  }
  br() {
    return "";
  }
}, Ce = class Ka {
  constructor(t) {
    bt(this, "options");
    bt(this, "renderer");
    bt(this, "textRenderer");
    this.options = t || Ar, this.options.renderer = this.options.renderer || new fo(), this.renderer = this.options.renderer, this.renderer.options = this.options, this.renderer.parser = this, this.textRenderer = new al();
  }
  static parse(t, r) {
    return new Ka(r).parse(t);
  }
  static parseInline(t, r) {
    return new Ka(r).parseInline(t);
  }
  parse(t, r = !0) {
    var s, o;
    let i = "";
    for (let a = 0; a < t.length; a++) {
      let n = t[a];
      if ((o = (s = this.options.extensions) == null ? void 0 : s.renderers) != null && o[n.type]) {
        let h = n, c = this.options.extensions.renderers[h.type].call({ parser: this }, h);
        if (c !== !1 || !["space", "hr", "heading", "code", "table", "blockquote", "list", "html", "def", "paragraph", "text"].includes(h.type)) {
          i += c || "";
          continue;
        }
      }
      let l = n;
      switch (l.type) {
        case "space": {
          i += this.renderer.space(l);
          continue;
        }
        case "hr": {
          i += this.renderer.hr(l);
          continue;
        }
        case "heading": {
          i += this.renderer.heading(l);
          continue;
        }
        case "code": {
          i += this.renderer.code(l);
          continue;
        }
        case "table": {
          i += this.renderer.table(l);
          continue;
        }
        case "blockquote": {
          i += this.renderer.blockquote(l);
          continue;
        }
        case "list": {
          i += this.renderer.list(l);
          continue;
        }
        case "html": {
          i += this.renderer.html(l);
          continue;
        }
        case "def": {
          i += this.renderer.def(l);
          continue;
        }
        case "paragraph": {
          i += this.renderer.paragraph(l);
          continue;
        }
        case "text": {
          let h = l, c = this.renderer.text(h);
          for (; a + 1 < t.length && t[a + 1].type === "text"; ) h = t[++a], c += `
` + this.renderer.text(h);
          r ? i += this.renderer.paragraph({ type: "paragraph", raw: c, text: c, tokens: [{ type: "text", raw: c, text: c, escaped: !0 }] }) : i += c;
          continue;
        }
        default: {
          let h = 'Token with "' + l.type + '" type was not found.';
          if (this.options.silent) return console.error(h), "";
          throw new Error(h);
        }
      }
    }
    return i;
  }
  parseInline(t, r = this.renderer) {
    var s, o;
    let i = "";
    for (let a = 0; a < t.length; a++) {
      let n = t[a];
      if ((o = (s = this.options.extensions) == null ? void 0 : s.renderers) != null && o[n.type]) {
        let h = this.options.extensions.renderers[n.type].call({ parser: this }, n);
        if (h !== !1 || !["escape", "html", "link", "image", "strong", "em", "codespan", "br", "del", "text"].includes(n.type)) {
          i += h || "";
          continue;
        }
      }
      let l = n;
      switch (l.type) {
        case "escape": {
          i += r.text(l);
          break;
        }
        case "html": {
          i += r.html(l);
          break;
        }
        case "link": {
          i += r.link(l);
          break;
        }
        case "image": {
          i += r.image(l);
          break;
        }
        case "strong": {
          i += r.strong(l);
          break;
        }
        case "em": {
          i += r.em(l);
          break;
        }
        case "codespan": {
          i += r.codespan(l);
          break;
        }
        case "br": {
          i += r.br(l);
          break;
        }
        case "del": {
          i += r.del(l);
          break;
        }
        case "text": {
          i += r.text(l);
          break;
        }
        default: {
          let h = 'Token with "' + l.type + '" type was not found.';
          if (this.options.silent) return console.error(h), "";
          throw new Error(h);
        }
      }
    }
    return i;
  }
}, Is, Ri = (Is = class {
  constructor(e) {
    bt(this, "options");
    bt(this, "block");
    this.options = e || Ar;
  }
  preprocess(e) {
    return e;
  }
  postprocess(e) {
    return e;
  }
  processAllTokens(e) {
    return e;
  }
  emStrongMask(e) {
    return e;
  }
  provideLexer() {
    return this.block ? xe.lex : xe.lexInline;
  }
  provideParser() {
    return this.block ? Ce.parse : Ce.parseInline;
  }
}, bt(Is, "passThroughHooks", /* @__PURE__ */ new Set(["preprocess", "postprocess", "processAllTokens", "emStrongMask"])), bt(Is, "passThroughHooksRespectAsync", /* @__PURE__ */ new Set(["preprocess", "postprocess", "processAllTokens"])), Is), NT = class {
  constructor(...e) {
    bt(this, "defaults", Qn());
    bt(this, "options", this.setOptions);
    bt(this, "parse", this.parseMarkdown(!0));
    bt(this, "parseInline", this.parseMarkdown(!1));
    bt(this, "Parser", Ce);
    bt(this, "Renderer", fo);
    bt(this, "TextRenderer", al);
    bt(this, "Lexer", xe);
    bt(this, "Tokenizer", po);
    bt(this, "Hooks", Ri);
    this.use(...e);
  }
  walkTokens(e, t) {
    var i, s;
    let r = [];
    for (let o of e) switch (r = r.concat(t.call(this, o)), o.type) {
      case "table": {
        let a = o;
        for (let n of a.header) r = r.concat(this.walkTokens(n.tokens, t));
        for (let n of a.rows) for (let l of n) r = r.concat(this.walkTokens(l.tokens, t));
        break;
      }
      case "list": {
        let a = o;
        r = r.concat(this.walkTokens(a.items, t));
        break;
      }
      default: {
        let a = o;
        (s = (i = this.defaults.extensions) == null ? void 0 : i.childTokens) != null && s[a.type] ? this.defaults.extensions.childTokens[a.type].forEach((n) => {
          let l = a[n].flat(1 / 0);
          r = r.concat(this.walkTokens(l, t));
        }) : a.tokens && (r = r.concat(this.walkTokens(a.tokens, t)));
      }
    }
    return r;
  }
  use(...e) {
    let t = this.defaults.extensions || { renderers: {}, childTokens: {} };
    return e.forEach((r) => {
      let i = { ...r };
      if (i.async = this.defaults.async || i.async || !1, r.extensions && (r.extensions.forEach((s) => {
        if (!s.name) throw new Error("extension name required");
        if ("renderer" in s) {
          let o = t.renderers[s.name];
          o ? t.renderers[s.name] = function(...a) {
            let n = s.renderer.apply(this, a);
            return n === !1 && (n = o.apply(this, a)), n;
          } : t.renderers[s.name] = s.renderer;
        }
        if ("tokenizer" in s) {
          if (!s.level || s.level !== "block" && s.level !== "inline") throw new Error("extension level must be 'block' or 'inline'");
          let o = t[s.level];
          o ? o.unshift(s.tokenizer) : t[s.level] = [s.tokenizer], s.start && (s.level === "block" ? t.startBlock ? t.startBlock.push(s.start) : t.startBlock = [s.start] : s.level === "inline" && (t.startInline ? t.startInline.push(s.start) : t.startInline = [s.start]));
        }
        "childTokens" in s && s.childTokens && (t.childTokens[s.name] = s.childTokens);
      }), i.extensions = t), r.renderer) {
        let s = this.defaults.renderer || new fo(this.defaults);
        for (let o in r.renderer) {
          if (!(o in s)) throw new Error(`renderer '${o}' does not exist`);
          if (["options", "parser"].includes(o)) continue;
          let a = o, n = r.renderer[a], l = s[a];
          s[a] = (...h) => {
            let c = n.apply(s, h);
            return c === !1 && (c = l.apply(s, h)), c || "";
          };
        }
        i.renderer = s;
      }
      if (r.tokenizer) {
        let s = this.defaults.tokenizer || new po(this.defaults);
        for (let o in r.tokenizer) {
          if (!(o in s)) throw new Error(`tokenizer '${o}' does not exist`);
          if (["options", "rules", "lexer"].includes(o)) continue;
          let a = o, n = r.tokenizer[a], l = s[a];
          s[a] = (...h) => {
            let c = n.apply(s, h);
            return c === !1 && (c = l.apply(s, h)), c;
          };
        }
        i.tokenizer = s;
      }
      if (r.hooks) {
        let s = this.defaults.hooks || new Ri();
        for (let o in r.hooks) {
          if (!(o in s)) throw new Error(`hook '${o}' does not exist`);
          if (["options", "block"].includes(o)) continue;
          let a = o, n = r.hooks[a], l = s[a];
          Ri.passThroughHooks.has(o) ? s[a] = (h) => {
            if (this.defaults.async && Ri.passThroughHooksRespectAsync.has(o)) return (async () => {
              let u = await n.call(s, h);
              return l.call(s, u);
            })();
            let c = n.call(s, h);
            return l.call(s, c);
          } : s[a] = (...h) => {
            if (this.defaults.async) return (async () => {
              let u = await n.apply(s, h);
              return u === !1 && (u = await l.apply(s, h)), u;
            })();
            let c = n.apply(s, h);
            return c === !1 && (c = l.apply(s, h)), c;
          };
        }
        i.hooks = s;
      }
      if (r.walkTokens) {
        let s = this.defaults.walkTokens, o = r.walkTokens;
        i.walkTokens = function(a) {
          let n = [];
          return n.push(o.call(this, a)), s && (n = n.concat(s.call(this, a))), n;
        };
      }
      this.defaults = { ...this.defaults, ...i };
    }), this;
  }
  setOptions(e) {
    return this.defaults = { ...this.defaults, ...e }, this;
  }
  lexer(e, t) {
    return xe.lex(e, t ?? this.defaults);
  }
  parser(e, t) {
    return Ce.parse(e, t ?? this.defaults);
  }
  parseMarkdown(e) {
    return (t, r) => {
      let i = { ...r }, s = { ...this.defaults, ...i }, o = this.onError(!!s.silent, !!s.async);
      if (this.defaults.async === !0 && i.async === !1) return o(new Error("marked(): The async option was set to true by an extension. Remove async: false from the parse options object to return a Promise."));
      if (typeof t > "u" || t === null) return o(new Error("marked(): input parameter is undefined or null"));
      if (typeof t != "string") return o(new Error("marked(): input parameter is of type " + Object.prototype.toString.call(t) + ", string expected"));
      if (s.hooks && (s.hooks.options = s, s.hooks.block = e), s.async) return (async () => {
        let a = s.hooks ? await s.hooks.preprocess(t) : t, n = await (s.hooks ? await s.hooks.provideLexer() : e ? xe.lex : xe.lexInline)(a, s), l = s.hooks ? await s.hooks.processAllTokens(n) : n;
        s.walkTokens && await Promise.all(this.walkTokens(l, s.walkTokens));
        let h = await (s.hooks ? await s.hooks.provideParser() : e ? Ce.parse : Ce.parseInline)(l, s);
        return s.hooks ? await s.hooks.postprocess(h) : h;
      })().catch(o);
      try {
        s.hooks && (t = s.hooks.preprocess(t));
        let a = (s.hooks ? s.hooks.provideLexer() : e ? xe.lex : xe.lexInline)(t, s);
        s.hooks && (a = s.hooks.processAllTokens(a)), s.walkTokens && this.walkTokens(a, s.walkTokens);
        let n = (s.hooks ? s.hooks.provideParser() : e ? Ce.parse : Ce.parseInline)(a, s);
        return s.hooks && (n = s.hooks.postprocess(n)), n;
      } catch (a) {
        return o(a);
      }
    };
  }
  onError(e, t) {
    return (r) => {
      if (r.message += `
Please report this to https://github.com/markedjs/marked.`, e) {
        let i = "<p>An error occurred:</p><pre>" + Ee(r.message + "", !0) + "</pre>";
        return t ? Promise.resolve(i) : i;
      }
      if (t) return Promise.reject(r);
      throw r;
    };
  }
}, Br = new NT();
function yt(e, t) {
  return Br.parse(e, t);
}
yt.options = yt.setOptions = function(e) {
  return Br.setOptions(e), yt.defaults = Br.defaults, Xp(yt.defaults), yt;
};
yt.getDefaults = Qn;
yt.defaults = Ar;
yt.use = function(...e) {
  return Br.use(...e), yt.defaults = Br.defaults, Xp(yt.defaults), yt;
};
yt.walkTokens = function(e, t) {
  return Br.walkTokens(e, t);
};
yt.parseInline = Br.parseInline;
yt.Parser = Ce;
yt.parser = Ce.parse;
yt.Renderer = fo;
yt.TextRenderer = al;
yt.Lexer = xe;
yt.lexer = xe.lex;
yt.Tokenizer = po;
yt.Hooks = Ri;
yt.parse = yt;
yt.options;
yt.setOptions;
yt.use;
yt.walkTokens;
yt.parseInline;
Ce.parse;
xe.lex;
function rf(e) {
  for (var t = [], r = 1; r < arguments.length; r++)
    t[r - 1] = arguments[r];
  var i = Array.from(typeof e == "string" ? [e] : e);
  i[i.length - 1] = i[i.length - 1].replace(/\r?\n([\t ]*)$/, "");
  var s = i.reduce(function(n, l) {
    var h = l.match(/\n([\t ]+|(?!\s).)/g);
    return h ? n.concat(h.map(function(c) {
      var u, p;
      return (p = (u = c.match(/[\t ]/g)) === null || u === void 0 ? void 0 : u.length) !== null && p !== void 0 ? p : 0;
    })) : n;
  }, []);
  if (s.length) {
    var o = new RegExp(`
[	 ]{` + Math.min.apply(Math, s) + "}", "g");
    i = i.map(function(n) {
      return n.replace(o, `
`);
    });
  }
  i[0] = i[0].replace(/^\r?\n/, "");
  var a = i[0];
  return t.forEach(function(n, l) {
    var h = a.match(/(?:^|\n)( *)$/), c = h ? h[1] : "", u = n;
    typeof n == "string" && n.includes(`
`) && (u = String(n).split(`
`).map(function(p, d) {
      return d === 0 ? p : "" + c + p;
    }).join(`
`)), a += u + i[l + 1];
  }), a;
}
var qT = {
  body: '<g><rect width="80" height="80" style="fill: #087ebf; stroke-width: 0px;"/><text transform="translate(21.16 64.67)" style="fill: #fff; font-family: ArialMT, Arial; font-size: 67.75px;"><tspan x="0" y="0">?</tspan></text></g>',
  height: 80,
  width: 80
}, Qa = /* @__PURE__ */ new Map(), sf = /* @__PURE__ */ new Map(), WT = /* @__PURE__ */ f((e) => {
  for (const t of e) {
    if (!t.name)
      throw new Error(
        'Invalid icon loader. Must have a "name" property with non-empty string value.'
      );
    if (q.debug("Registering icon pack:", t.name), "loader" in t)
      sf.set(t.name, t.loader);
    else if ("icons" in t)
      Qa.set(t.name, t.icons);
    else
      throw q.error("Invalid icon loader:", t), new Error('Invalid icon loader. Must have either "icons" or "loader" property.');
  }
}, "registerIconPacks"), of = /* @__PURE__ */ f(async (e, t) => {
  const r = z2(e, !0, t !== void 0);
  if (!r)
    throw new Error(`Invalid icon name: ${e}`);
  const i = r.prefix || t;
  if (!i)
    throw new Error(`Icon name must contain a prefix: ${e}`);
  let s = Qa.get(i);
  if (!s) {
    const a = sf.get(i);
    if (!a)
      throw new Error(`Icon set not found: ${r.prefix}`);
    try {
      s = { ...await a(), prefix: i }, Qa.set(i, s);
    } catch (n) {
      throw q.error(n), new Error(`Failed to load icon set: ${r.prefix}`);
    }
  }
  const o = X2(s, r.name);
  if (!o)
    throw new Error(`Icon not found: ${e}`);
  return o;
}, "getRegisteredIconData"), zT = /* @__PURE__ */ f(async (e) => {
  try {
    return await of(e), !0;
  } catch {
    return !1;
  }
}, "isIconAvailable"), ps = /* @__PURE__ */ f(async (e, t, r) => {
  let i;
  try {
    i = await of(e, t == null ? void 0 : t.fallbackPrefix);
  } catch (a) {
    q.error(a), i = qT;
  }
  const s = Q2(i, t), o = rT(eT(s.body), {
    ...s.attributes,
    ...r
  });
  return we(o, wt());
}, "getIconSVG");
function af(e, { markdownAutoWrap: t }) {
  const i = e.replace(/<br\/>/g, `
`).replace(/\n{2,}/g, `
`);
  return rf(i);
}
f(af, "preprocessMarkdown");
function nf(e) {
  return e.split(/\\n|\n|<br\s*\/?>/gi).map(
    (t) => {
      var r;
      return ((r = t.trim().match(/<[^>]+>|[^\s<>]+/g)) == null ? void 0 : r.map((i) => ({ content: i, type: "normal" }))) ?? [];
    }
  );
}
f(nf, "nonMarkdownToLines");
function lf(e, t = {}) {
  const r = af(e, t), i = yt.lexer(r), s = [[]];
  let o = 0;
  function a(n, l = "normal") {
    n.type === "text" ? n.text.split(`
`).forEach((c, u) => {
      u !== 0 && (o++, s.push([])), c.split(" ").forEach((p) => {
        p = p.replace(/&#39;/g, "'"), p && s[o].push({ content: p, type: l });
      });
    }) : n.type === "strong" || n.type === "em" ? n.tokens.forEach((h) => {
      a(h, n.type);
    }) : n.type === "html" && s[o].push({ content: n.text, type: "normal" });
  }
  return f(a, "processNode"), i.forEach((n) => {
    var l;
    n.type === "paragraph" ? (l = n.tokens) == null || l.forEach((h) => {
      a(h);
    }) : n.type === "html" ? s[o].push({ content: n.text, type: "normal" }) : s[o].push({ content: n.raw, type: "normal" });
  }), s;
}
f(lf, "markdownToLines");
function hf(e) {
  return e ? `<p>${/**
  * Replace new lines with <br /> tags.
  *
  * Unlike in markdown text, `\n` sequences are treated as line breaks here.
  */
  e.replace(/\\n|\n/g, "<br />")}</p>` : "";
}
f(hf, "nonMarkdownToHTML");
function cf(e, { markdownAutoWrap: t } = {}) {
  const r = yt.lexer(e);
  function i(s) {
    var o, a, n;
    return s.type === "text" ? t === !1 ? s.text.replace(/\n */g, "<br/>").replace(/ /g, "&nbsp;") : s.text.replace(/\n */g, "<br/>") : s.type === "strong" ? `<strong>${(o = s.tokens) == null ? void 0 : o.map(i).join("")}</strong>` : s.type === "em" ? `<em>${(a = s.tokens) == null ? void 0 : a.map(i).join("")}</em>` : s.type === "paragraph" ? `<p>${(n = s.tokens) == null ? void 0 : n.map(i).join("")}</p>` : s.type === "space" ? "" : s.type === "html" ? `${s.text}` : s.type === "escape" ? s.text : (q.warn(`Unsupported markdown: ${s.type}`), s.raw);
  }
  return f(i, "output"), r.map(i).join("");
}
f(cf, "markdownToHTML");
function uf(e) {
  return Intl.Segmenter ? [...new Intl.Segmenter().segment(e)].map((t) => t.segment) : [...e];
}
f(uf, "splitTextToChars");
function df(e, t) {
  const r = uf(t.content);
  return nl(e, [], r, t.type);
}
f(df, "splitWordToFitWidth");
function nl(e, t, r, i) {
  if (r.length === 0)
    return [
      { content: t.join(""), type: i },
      { content: "", type: i }
    ];
  const [s, ...o] = r, a = [...t, s];
  return e([{ content: a.join(""), type: i }]) ? nl(e, a, o, i) : (t.length === 0 && s && (t.push(s), r.shift()), [
    { content: t.join(""), type: i },
    { content: r.join(""), type: i }
  ]);
}
f(nl, "splitWordToFitWidthRecursion");
function pf(e, t) {
  if (e.some(({ content: r }) => r.includes(`
`)))
    throw new Error("splitLineToFitWidth does not support newlines in the line");
  return go(e, t);
}
f(pf, "splitLineToFitWidth");
function go(e, t, r = [], i = []) {
  if (e.length === 0)
    return i.length > 0 && r.push(i), r.length > 0 ? r : [];
  let s = "";
  e[0].content === " " && (s = " ", e.shift());
  const o = e.shift() ?? { content: " ", type: "normal" }, a = [...i];
  if (s !== "" && a.push({ content: s, type: "normal" }), a.push(o), t(a))
    return go(e, t, r, a);
  if (i.length > 0)
    r.push(i), e.unshift(o);
  else if (o.content) {
    const [n, l] = df(t, o);
    r.push([n]), l.content && e.unshift(l);
  }
  return go(e, t, r);
}
f(go, "splitLineToFitWidthRecursion");
function Ja(e, t) {
  t && e.attr("style", t);
}
f(Ja, "applyStyle");
var Hh = 16384;
async function ff(e, t, r, i, s = !1, o = wt()) {
  const a = e.append("foreignObject");
  a.attr("width", `${Math.min(10 * r, Hh)}px`), a.attr("height", `${Math.min(10 * r, Hh)}px`);
  const n = a.append("xhtml:div"), l = ji(t.label) ? await tu(t.label.replace(ls.lineBreakRegex, `
`), o) : we(t.label, o), h = t.isNode ? "nodeLabel" : "edgeLabel", c = n.append("span");
  c.html(l), Ja(c, t.labelStyle), c.attr("class", `${h} ${i}`), Ja(n, t.labelStyle), n.style("display", "table-cell"), n.style("white-space", "nowrap"), n.style("line-height", "1.5"), r !== Number.POSITIVE_INFINITY && (n.style("max-width", r + "px"), n.style("text-align", "center")), n.attr("xmlns", "http://www.w3.org/1999/xhtml"), s && n.attr("class", "labelBkg");
  let u = n.node().getBoundingClientRect();
  return u.width === r && (n.style("display", "table"), n.style("white-space", "break-spaces"), n.style("width", r + "px"), u = n.node().getBoundingClientRect()), a.node();
}
f(ff, "addHtmlSpan");
function Mo(e, t, r, i = !1) {
  const s = e.append("tspan").attr("class", "text-outer-tspan").attr("x", 0).attr("y", t * r - 0.1 + "em").attr("dy", r + "em");
  return i && s.attr("text-anchor", "middle"), s;
}
f(Mo, "createTspan");
function gf(e, t, r) {
  const i = e.append("text"), s = Mo(i, 1, t);
  Io(s, r);
  const o = s.node().getComputedTextLength();
  return i.remove(), o;
}
f(gf, "computeWidthOfText");
function HT(e, t, r) {
  var a;
  const i = e.append("text"), s = Mo(i, 1, t);
  Io(s, [{ content: r, type: "normal" }]);
  const o = (a = s.node()) == null ? void 0 : a.getBoundingClientRect();
  return o && i.remove(), o;
}
f(HT, "computeDimensionOfText");
function mf(e, t, r, i = !1, s = !1) {
  const a = t.append("g"), n = a.insert("rect").attr("class", "background").attr("style", "stroke: none"), l = a.append("text").attr("y", "-10.1");
  s && l.attr("text-anchor", "middle");
  let h = 0;
  for (const c of r) {
    const u = /* @__PURE__ */ f((d) => gf(a, 1.1, d) <= e, "checkWidth"), p = u(c) ? [c] : pf(c, u);
    for (const d of p) {
      const g = Mo(l, h, 1.1, s);
      Io(g, d), h++;
    }
  }
  if (i) {
    const c = l.node().getBBox(), u = 2;
    return n.attr("x", c.x - u).attr("y", c.y - u).attr("width", c.width + 2 * u).attr("height", c.height + 2 * u), a.node();
  } else
    return l.node();
}
f(mf, "createFormattedText");
function tn(e) {
  const t = /&(amp|lt|gt);/g;
  return e.replace(t, (r, i) => {
    switch (i) {
      case "amp":
        return "&";
      case "lt":
        return "<";
      case "gt":
        return ">";
      default:
        return r;
    }
  });
}
f(tn, "decodeHTMLEntities");
function Io(e, t) {
  e.text(""), t.forEach((r, i) => {
    const s = e.append("tspan").attr("font-style", r.type === "em" ? "italic" : "normal").attr("class", "text-inner-tspan").attr("font-weight", r.type === "strong" ? "bold" : "normal");
    i === 0 ? s.text(tn(r.content)) : s.text(" " + tn(r.content));
  });
}
f(Io, "updateTextContentAndStyles");
async function yf(e, t = {}) {
  const r = [];
  e.replace(/(fa[bklrs]?):fa-([\w-]+)/g, (s, o, a) => (r.push(
    (async () => {
      const n = `${o}:${a}`;
      return await zT(n) ? await ps(n, void 0, { class: "label-icon" }) : `<i class='${we(s, t).replace(":", " ")}'></i>`;
    })()
  ), s));
  const i = await Promise.all(r);
  return e.replace(/(fa[bklrs]?):fa-([\w-]+)/g, () => i.shift() ?? "");
}
f(yf, "replaceIconSubstring");
var Ze = /* @__PURE__ */ f(async (e, t = "", {
  style: r = "",
  isTitle: i = !1,
  classes: s = "",
  useHtmlLabels: o = !0,
  markdown: a = !0,
  isNode: n = !0,
  /**
   * The width to wrap the text within. Set to `Number.POSITIVE_INFINITY` for no wrapping.
   */
  width: l = 200,
  addSvgBackground: h = !1
} = {}, c) => {
  if (q.debug(
    "XYZ createText",
    t,
    r,
    i,
    s,
    o,
    n,
    "addSvgBackground: ",
    h
  ), o) {
    const u = a ? cf(t, c) : hf(t), p = await yf(_r(u), c), d = t.replace(/\\\\/g, "\\"), g = {
      isNode: n,
      label: ji(t) ? d : p,
      labelStyle: r.replace("fill:", "color:")
    };
    return await ff(e, g, l, s, h, c);
  } else {
    const u = _r(t.replace(/<br\s*\/?>/g, "<br/>")), p = a ? lf(u.replace("<br>", "<br/>"), c) : nf(u), d = mf(
      l,
      e,
      p,
      t ? h : !1,
      !n
    );
    if (n) {
      /stroke:/.exec(r) && (r = r.replace("stroke:", "lineColor:"));
      const g = r.replace(/stroke:[^;]+;?/g, "").replace(/stroke-width:[^;]+;?/g, "").replace(/fill:[^;]+;?/g, "").replace(/color:/g, "fill:");
      ct(d).attr("style", g);
    } else {
      const g = r.replace(/stroke:[^;]+;?/g, "").replace(/stroke-width:[^;]+;?/g, "").replace(/fill:[^;]+;?/g, "").replace(/background:/g, "fill:");
      ct(d).select("rect").attr("style", g.replace(/background:/g, "fill:"));
      const m = r.replace(/stroke:[^;]+;?/g, "").replace(/stroke-width:[^;]+;?/g, "").replace(/fill:[^;]+;?/g, "").replace(/color:/g, "fill:");
      ct(d).select("text").attr("style", m);
    }
    return i ? ct(d).selectAll("tspan.text-outer-tspan").classed("title-row", !0) : ct(d).selectAll("tspan.text-outer-tspan").classed("row", !0), d;
  }
}, "createText"), at = /* @__PURE__ */ f(async (e, t, r) => {
  var d, g;
  let i;
  const s = t.useHtmlLabels || Ve((d = gt()) == null ? void 0 : d.htmlLabels);
  r ? i = r : i = "node default";
  const o = e.insert("g").attr("class", i).attr("id", t.domId || t.id), a = o.insert("g").attr("class", "label").attr("style", Rt(t.labelStyle));
  let n;
  t.label === void 0 ? n = "" : n = typeof t.label == "string" ? t.label : t.label[0];
  const l = !!t.icon || !!t.img, h = t.labelType === "markdown", c = await Ze(
    a,
    we(_r(n), gt()),
    {
      useHtmlLabels: s,
      width: t.width || ((g = gt().flowchart) == null ? void 0 : g.wrappingWidth),
      classes: h ? "markdown-node-label" : "",
      style: t.labelStyle,
      addSvgBackground: l,
      markdown: h
    },
    gt()
  );
  let u = c.getBBox();
  const p = ((t == null ? void 0 : t.padding) ?? 0) / 2;
  if (s) {
    const m = c.children[0], y = ct(c);
    await zp(m, n), u = m.getBoundingClientRect(), y.attr("width", u.width), y.attr("height", u.height);
  }
  return s ? a.attr("transform", "translate(" + -u.width / 2 + ", " + -u.height / 2 + ")") : a.attr("transform", "translate(0, " + -u.height / 2 + ")"), t.centerLabel && a.attr("transform", "translate(" + -u.width / 2 + ", " + -u.height / 2 + ")"), a.insert("rect", ":first-child"), { shapeSvg: o, bbox: u, halfPadding: p, label: a };
}, "labelHelper"), na = /* @__PURE__ */ f(async (e, t, r) => {
  var l, h;
  const i = r.useHtmlLabels ?? Kt(gt()), s = e.insert("g").attr("class", "label").attr("style", r.labelStyle || ""), o = await Ze(s, we(_r(t), gt()), {
    useHtmlLabels: i,
    width: r.width || ((h = (l = gt()) == null ? void 0 : l.flowchart) == null ? void 0 : h.wrappingWidth),
    style: r.labelStyle,
    addSvgBackground: !!r.icon || !!r.img
  });
  let a = o.getBBox();
  const n = r.padding / 2;
  if (Kt(gt())) {
    const c = o.children[0], u = ct(o);
    a = c.getBoundingClientRect(), u.attr("width", a.width), u.attr("height", a.height);
  }
  return i ? s.attr("transform", "translate(" + -a.width / 2 + ", " + -a.height / 2 + ")") : s.attr("transform", "translate(0, " + -a.height / 2 + ")"), r.centerLabel && s.attr("transform", "translate(" + -a.width / 2 + ", " + -a.height / 2 + ")"), s.insert("rect", ":first-child"), { shapeSvg: e, bbox: a, halfPadding: n, label: s };
}, "insertLabel"), Q = /* @__PURE__ */ f((e, t) => {
  const r = t.node().getBBox();
  e.width = r.width, e.height = r.height;
}, "updateNodeBounds"), it = /* @__PURE__ */ f((e, t) => (e.look === "handDrawn" ? "rough-node" : "node") + " " + e.cssClasses + " " + (t || ""), "getNodeClasses");
function pt(e) {
  const t = e.map((r, i) => `${i === 0 ? "M" : "L"}${r.x},${r.y}`);
  return t.push("Z"), t.join(" ");
}
f(pt, "createPathFromPoints");
function or(e, t, r, i, s, o) {
  const a = [], l = r - e, h = i - t, c = l / o, u = 2 * Math.PI / c, p = t + h / 2;
  for (let d = 0; d <= 50; d++) {
    const g = d / 50, m = e + g * l, y = p + s * Math.sin(u * (m - e));
    a.push({ x: m, y });
  }
  return a;
}
f(or, "generateFullSineWavePoints");
function rs(e, t, r, i, s, o) {
  const a = [], n = s * Math.PI / 180, c = (o * Math.PI / 180 - n) / (i - 1);
  for (let u = 0; u < i; u++) {
    const p = n + u * c, d = e + r * Math.cos(p), g = t + r * Math.sin(p);
    a.push({ x: -d, y: -g });
  }
  return a;
}
f(rs, "generateCirclePoints");
function en(e) {
  const t = Array.from(e.childNodes).filter(
    (l) => l.tagName === "path"
  ), r = document.createElementNS("http://www.w3.org/2000/svg", "path"), i = t.map((l) => l.getAttribute("d")).filter((l) => l !== null).join(" ");
  r.setAttribute("d", i);
  const s = t.find((l) => l.getAttribute("fill") !== "none"), o = t.find((l) => l.getAttribute("stroke") !== "none"), a = /* @__PURE__ */ f((l, h) => (l == null ? void 0 : l.getAttribute(h)) ?? void 0, "getAttr");
  if (s) {
    const l = {
      fill: a(s, "fill"),
      "fill-opacity": a(s, "fill-opacity") ?? "1"
    };
    Object.entries(l).forEach(([h, c]) => {
      c && r.setAttribute(h, c);
    });
  }
  if (o) {
    const l = {
      stroke: a(o, "stroke"),
      "stroke-width": a(o, "stroke-width") ?? "1",
      "stroke-opacity": a(o, "stroke-opacity") ?? "1"
    };
    Object.entries(l).forEach(([h, c]) => {
      c && r.setAttribute(h, c);
    });
  }
  const n = document.createElementNS("http://www.w3.org/2000/svg", "g");
  return n.appendChild(r), n;
}
f(en, "mergePaths");
var YT = /* @__PURE__ */ f((e, t) => {
  var r = e.x, i = e.y, s = t.x - r, o = t.y - i, a = e.width / 2, n = e.height / 2, l, h;
  return Math.abs(o) * a > Math.abs(s) * n ? (o < 0 && (n = -n), l = o === 0 ? 0 : n * s / o, h = n) : (s < 0 && (a = -a), l = a, h = s === 0 ? 0 : a * o / s), { x: r + l, y: i + h };
}, "intersectRect"), yi = YT, XT = /* @__PURE__ */ f(async (e, t, r, i = !1, s = !1) => {
  let o = t || "";
  typeof o == "object" && (o = o[0]);
  const a = gt(), n = Kt(a);
  return await Ze(
    e,
    o,
    {
      style: r,
      isTitle: i,
      useHtmlLabels: n,
      markdown: !1,
      isNode: s,
      width: Number.POSITIVE_INFINITY
    },
    a
  );
}, "createLabel"), tr = XT, ar = /* @__PURE__ */ f((e, t, r, i, s) => [
  "M",
  e + s,
  t,
  // Move to the first point
  "H",
  e + r - s,
  // Draw horizontal line to the beginning of the right corner
  "A",
  s,
  s,
  0,
  0,
  1,
  e + r,
  t + s,
  // Draw arc to the right top corner
  "V",
  t + i - s,
  // Draw vertical line down to the beginning of the right bottom corner
  "A",
  s,
  s,
  0,
  0,
  1,
  e + r - s,
  t + i,
  // Draw arc to the right bottom corner
  "H",
  e + s,
  // Draw horizontal line to the beginning of the left bottom corner
  "A",
  s,
  s,
  0,
  0,
  1,
  e,
  t + i - s,
  // Draw arc to the left bottom corner
  "V",
  t + s,
  // Draw vertical line up to the beginning of the left top corner
  "A",
  s,
  s,
  0,
  0,
  1,
  e + s,
  t,
  // Draw arc to the left top corner
  "Z"
  // Close the path
].join(" "), "createRoundedRectPathD"), xf = /* @__PURE__ */ f(async (e, t) => {
  q.info("Creating subgraph rect for ", t.id, t);
  const r = gt(), { themeVariables: i, handDrawnSeed: s } = r, { clusterBkg: o, clusterBorder: a } = i, { labelStyles: n, nodeStyles: l, borderStyles: h, backgroundStyles: c } = K(t), u = e.insert("g").attr("class", "cluster " + t.cssClasses).attr("id", t.domId).attr("data-look", t.look), p = Kt(r), d = u.insert("g").attr("class", "cluster-label ");
  let g;
  t.labelType === "markdown" ? g = await Ze(d, t.label, {
    style: t.labelStyle,
    useHtmlLabels: p,
    isNode: !0,
    width: t.width
  }) : g = await tr(d, t.label, t.labelStyle || "", !1, !0);
  let m = g.getBBox();
  if (Kt(r)) {
    const T = g.children[0], B = ct(g);
    m = T.getBoundingClientRect(), B.attr("width", m.width), B.attr("height", m.height);
  }
  const y = t.width <= m.width + t.padding ? m.width + t.padding : t.width;
  t.width <= m.width + t.padding ? t.diff = (y - t.width) / 2 - t.padding : t.diff = -t.padding;
  const x = t.height, b = t.x - y / 2, k = t.y - x / 2;
  q.trace("Data ", t, JSON.stringify(t));
  let w;
  if (t.look === "handDrawn") {
    const T = G.svg(u), B = Z(t, {
      roughness: 0.7,
      fill: o,
      // fill: 'red',
      stroke: a,
      fillWeight: 3,
      seed: s
    }), N = T.path(ar(b, k, y, x, 0), B);
    w = u.insert(() => (q.debug("Rough node insert CXC", N), N), ":first-child"), w.select("path:nth-child(2)").attr("style", h.join(";")), w.select("path").attr("style", c.join(";").replace("fill", "stroke"));
  } else
    w = u.insert("rect", ":first-child"), w.attr("style", l).attr("rx", t.rx).attr("ry", t.ry).attr("x", b).attr("y", k).attr("width", y).attr("height", x);
  const { subGraphTitleTopMargin: S } = Kn(r);
  if (d.attr(
    "transform",
    // This puts the label on top of the box instead of inside it
    `translate(${t.x - m.width / 2}, ${t.y - t.height / 2 + S})`
  ), n) {
    const T = d.select("span");
    T && T.attr("style", n);
  }
  const L = w.node().getBBox();
  return t.offsetX = 0, t.width = L.width, t.height = L.height, t.offsetY = m.height - t.padding / 2, t.intersect = function(T) {
    return yi(t, T);
  }, { cluster: u, labelBBox: m };
}, "rect"), UT = /* @__PURE__ */ f((e, t) => {
  const r = e.insert("g").attr("class", "note-cluster").attr("id", t.domId), i = r.insert("rect", ":first-child"), s = 0 * t.padding, o = s / 2;
  i.attr("rx", t.rx).attr("ry", t.ry).attr("x", t.x - t.width / 2 - o).attr("y", t.y - t.height / 2 - o).attr("width", t.width + s).attr("height", t.height + s).attr("fill", "none");
  const a = i.node().getBBox();
  return t.width = a.width, t.height = a.height, t.intersect = function(n) {
    return yi(t, n);
  }, { cluster: r, labelBBox: { width: 0, height: 0 } };
}, "noteGroup"), jT = /* @__PURE__ */ f(async (e, t) => {
  const r = gt(), { themeVariables: i, handDrawnSeed: s } = r, { altBackground: o, compositeBackground: a, compositeTitleBackground: n, nodeBorder: l } = i, h = e.insert("g").attr("class", t.cssClasses).attr("id", t.domId).attr("data-id", t.id).attr("data-look", t.look), c = h.insert("g", ":first-child"), u = h.insert("g").attr("class", "cluster-label");
  let p = h.append("rect");
  const d = await tr(u, t.label, t.labelStyle, void 0, !0);
  let g = d.getBBox();
  if (Kt(r)) {
    const N = d.children[0], O = ct(d);
    g = N.getBoundingClientRect(), O.attr("width", g.width), O.attr("height", g.height);
  }
  const m = 0 * t.padding, y = m / 2, x = (t.width <= g.width + t.padding ? g.width + t.padding : t.width) + m;
  t.width <= g.width + t.padding ? t.diff = (x - t.width) / 2 - t.padding : t.diff = -t.padding;
  const b = t.height + m, k = t.height + m - g.height - 6, w = t.x - x / 2, S = t.y - b / 2;
  t.width = x;
  const L = t.y - t.height / 2 - y + g.height + 2;
  let T;
  if (t.look === "handDrawn") {
    const N = t.cssClasses.includes("statediagram-cluster-alt"), O = G.svg(h), F = t.rx || t.ry ? O.path(ar(w, S, x, b, 10), {
      roughness: 0.7,
      fill: n,
      fillStyle: "solid",
      stroke: l,
      seed: s
    }) : O.rectangle(w, S, x, b, { seed: s });
    T = h.insert(() => F, ":first-child");
    const Y = O.rectangle(w, L, x, k, {
      fill: N ? o : a,
      fillStyle: N ? "hachure" : "solid",
      stroke: l,
      seed: s
    });
    T = h.insert(() => F, ":first-child"), p = h.insert(() => Y);
  } else
    T = c.insert("rect", ":first-child"), T.attr("class", "outer").attr("x", w).attr("y", S).attr("width", x).attr("height", b).attr("data-look", t.look), p.attr("class", "inner").attr("x", w).attr("y", L).attr("width", x).attr("height", k);
  u.attr(
    "transform",
    `translate(${t.x - g.width / 2}, ${S + 1 - (Kt(r) ? 0 : 3)})`
  );
  const B = T.node().getBBox();
  return t.height = B.height, t.offsetX = 0, t.offsetY = g.height - t.padding / 2, t.labelBBox = g, t.intersect = function(N) {
    return yi(t, N);
  }, { cluster: h, labelBBox: g };
}, "roundedWithTitle"), GT = /* @__PURE__ */ f(async (e, t) => {
  q.info("Creating subgraph rect for ", t.id, t);
  const r = gt(), { themeVariables: i, handDrawnSeed: s } = r, { clusterBkg: o, clusterBorder: a } = i, { labelStyles: n, nodeStyles: l, borderStyles: h, backgroundStyles: c } = K(t), u = e.insert("g").attr("class", "cluster " + t.cssClasses).attr("id", t.domId).attr("data-look", t.look), p = Kt(r), d = u.insert("g").attr("class", "cluster-label "), g = await Ze(d, t.label, {
    style: t.labelStyle,
    useHtmlLabels: p,
    isNode: !0,
    width: t.width
  });
  let m = g.getBBox();
  if (Kt(r)) {
    const T = g.children[0], B = ct(g);
    m = T.getBoundingClientRect(), B.attr("width", m.width), B.attr("height", m.height);
  }
  const y = t.width <= m.width + t.padding ? m.width + t.padding : t.width;
  t.width <= m.width + t.padding ? t.diff = (y - t.width) / 2 - t.padding : t.diff = -t.padding;
  const x = t.height, b = t.x - y / 2, k = t.y - x / 2;
  q.trace("Data ", t, JSON.stringify(t));
  let w;
  if (t.look === "handDrawn") {
    const T = G.svg(u), B = Z(t, {
      roughness: 0.7,
      fill: o,
      // fill: 'red',
      stroke: a,
      fillWeight: 4,
      seed: s
    }), N = T.path(ar(b, k, y, x, t.rx), B);
    w = u.insert(() => (q.debug("Rough node insert CXC", N), N), ":first-child"), w.select("path:nth-child(2)").attr("style", h.join(";")), w.select("path").attr("style", c.join(";").replace("fill", "stroke"));
  } else
    w = u.insert("rect", ":first-child"), w.attr("style", l).attr("rx", t.rx).attr("ry", t.ry).attr("x", b).attr("y", k).attr("width", y).attr("height", x);
  const { subGraphTitleTopMargin: S } = Kn(r);
  if (d.attr(
    "transform",
    // This puts the label on top of the box instead of inside it
    `translate(${t.x - m.width / 2}, ${t.y - t.height / 2 + S})`
  ), n) {
    const T = d.select("span");
    T && T.attr("style", n);
  }
  const L = w.node().getBBox();
  return t.offsetX = 0, t.width = L.width, t.height = L.height, t.offsetY = m.height - t.padding / 2, t.intersect = function(T) {
    return yi(t, T);
  }, { cluster: u, labelBBox: m };
}, "kanbanSection"), VT = /* @__PURE__ */ f((e, t) => {
  const r = gt(), { themeVariables: i, handDrawnSeed: s } = r, { nodeBorder: o } = i, a = e.insert("g").attr("class", t.cssClasses).attr("id", t.domId).attr("data-look", t.look), n = a.insert("g", ":first-child"), l = 0 * t.padding, h = t.width + l;
  t.diff = -t.padding;
  const c = t.height + l, u = t.x - h / 2, p = t.y - c / 2;
  t.width = h;
  let d;
  if (t.look === "handDrawn") {
    const y = G.svg(a).rectangle(u, p, h, c, {
      fill: "lightgrey",
      roughness: 0.5,
      strokeLineDash: [5],
      stroke: o,
      seed: s
    });
    d = a.insert(() => y, ":first-child");
  } else {
    d = n.insert("rect", ":first-child");
    let m = "outer";
    t.look, m = "divider", d.attr("class", m).attr("x", u).attr("y", p).attr("width", h).attr("height", c).attr("data-look", t.look);
  }
  const g = d.node().getBBox();
  return t.height = g.height, t.offsetX = 0, t.offsetY = 0, t.intersect = function(m) {
    return yi(t, m);
  }, { cluster: a, labelBBox: {} };
}, "divider"), ZT = xf, KT = {
  rect: xf,
  squareRect: ZT,
  roundedWithTitle: jT,
  noteGroup: UT,
  divider: VT,
  kanbanSection: GT
}, Cf = /* @__PURE__ */ new Map(), QT = /* @__PURE__ */ f(async (e, t) => {
  const r = t.shape || "rect", i = await KT[r](e, t);
  return Cf.set(t.id, i), i;
}, "insertCluster"), jL = /* @__PURE__ */ f(() => {
  Cf = /* @__PURE__ */ new Map();
}, "clear");
function bf(e, t) {
  return e.intersect(t);
}
f(bf, "intersectNode");
var JT = bf;
function kf(e, t, r, i) {
  var s = e.x, o = e.y, a = s - i.x, n = o - i.y, l = Math.sqrt(t * t * n * n + r * r * a * a), h = Math.abs(t * r * a / l);
  i.x < s && (h = -h);
  var c = Math.abs(t * r * n / l);
  return i.y < o && (c = -c), { x: s + h, y: o + c };
}
f(kf, "intersectEllipse");
var Tf = kf;
function Sf(e, t, r) {
  return Tf(e, t, t, r);
}
f(Sf, "intersectCircle");
var tS = Sf;
function wf(e, t, r, i) {
  {
    const s = t.y - e.y, o = e.x - t.x, a = t.x * e.y - e.x * t.y, n = s * r.x + o * r.y + a, l = s * i.x + o * i.y + a, h = 1e-6;
    if (n !== 0 && l !== 0 && rn(n, l))
      return;
    const c = i.y - r.y, u = r.x - i.x, p = i.x * r.y - r.x * i.y, d = c * e.x + u * e.y + p, g = c * t.x + u * t.y + p;
    if (Math.abs(d) < h && Math.abs(g) < h && rn(d, g))
      return;
    const m = s * u - c * o;
    if (m === 0)
      return;
    const y = Math.abs(m / 2);
    let x = o * p - u * a;
    const b = x < 0 ? (x - y) / m : (x + y) / m;
    x = c * a - s * p;
    const k = x < 0 ? (x - y) / m : (x + y) / m;
    return { x: b, y: k };
  }
}
f(wf, "intersectLine");
function rn(e, t) {
  return e * t > 0;
}
f(rn, "sameSign");
var eS = wf;
function _f(e, t, r) {
  let i = e.x, s = e.y, o = [], a = Number.POSITIVE_INFINITY, n = Number.POSITIVE_INFINITY;
  typeof t.forEach == "function" ? t.forEach(function(c) {
    a = Math.min(a, c.x), n = Math.min(n, c.y);
  }) : (a = Math.min(a, t.x), n = Math.min(n, t.y));
  let l = i - e.width / 2 - a, h = s - e.height / 2 - n;
  for (let c = 0; c < t.length; c++) {
    let u = t[c], p = t[c < t.length - 1 ? c + 1 : 0], d = eS(
      e,
      r,
      { x: l + u.x, y: h + u.y },
      { x: l + p.x, y: h + p.y }
    );
    d && o.push(d);
  }
  return o.length ? (o.length > 1 && o.sort(function(c, u) {
    let p = c.x - r.x, d = c.y - r.y, g = Math.sqrt(p * p + d * d), m = u.x - r.x, y = u.y - r.y, x = Math.sqrt(m * m + y * y);
    return g < x ? -1 : g === x ? 0 : 1;
  }), o[0]) : e;
}
f(_f, "intersectPolygon");
var rS = _f, U = {
  node: JT,
  circle: tS,
  ellipse: Tf,
  polygon: rS,
  rect: yi
};
function Bf(e, t) {
  const { labelStyles: r } = K(t);
  t.labelStyle = r;
  const i = it(t);
  let s = i;
  i || (s = "anchor");
  const o = e.insert("g").attr("class", s).attr("id", t.domId || t.id), a = 1, { cssStyles: n } = t, l = G.svg(o), h = Z(t, { fill: "black", stroke: "none", fillStyle: "solid" });
  t.look !== "handDrawn" && (h.roughness = 0);
  const c = l.circle(0, 0, a * 2, h), u = o.insert(() => c, ":first-child");
  return u.attr("class", "anchor").attr("style", Rt(n)), Q(t, u), t.intersect = function(p) {
    return q.info("Circle intersect", t, a, p), U.circle(t, a, p);
  }, o;
}
f(Bf, "anchor");
function sn(e, t, r, i, s, o, a) {
  const l = (e + r) / 2, h = (t + i) / 2, c = Math.atan2(i - t, r - e), u = (r - e) / 2, p = (i - t) / 2, d = u / s, g = p / o, m = Math.sqrt(d ** 2 + g ** 2);
  if (m > 1)
    throw new Error("The given radii are too small to create an arc between the points.");
  const y = Math.sqrt(1 - m ** 2), x = l + y * o * Math.sin(c) * (a ? -1 : 1), b = h - y * s * Math.cos(c) * (a ? -1 : 1), k = Math.atan2((t - b) / o, (e - x) / s);
  let S = Math.atan2((i - b) / o, (r - x) / s) - k;
  a && S < 0 && (S += 2 * Math.PI), !a && S > 0 && (S -= 2 * Math.PI);
  const L = [];
  for (let T = 0; T < 20; T++) {
    const B = T / 19, N = k + B * S, O = x + s * Math.cos(N), F = b + o * Math.sin(N);
    L.push({ x: O, y: F });
  }
  return L;
}
f(sn, "generateArcPoints");
function vf(e, t, r) {
  const [i, s] = [t, r].sort((o, a) => a - o);
  return s * (1 - Math.sqrt(1 - (e / i / 2) ** 2));
}
f(vf, "calculateArcSagitta");
async function Lf(e, t) {
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.labelStyle = r;
  const s = t.padding ?? 0, o = t.look === "neo" ? 16 : s, a = t.look === "neo" ? 12 : s, n = /* @__PURE__ */ f((N) => N + a, "calcTotalHeight"), l = /* @__PURE__ */ f((N) => {
    const O = N / 2;
    return [O / (2.5 + N / 50), O];
  }, "calcEllipseRadius"), { shapeSvg: h, bbox: c } = await at(e, t, it(t)), u = n(t != null && t.height ? t == null ? void 0 : t.height : c.height), [p, d] = l(u), g = vf(u, p, d), y = (t != null && t.width ? t == null ? void 0 : t.width : c.width) + o * 2 + g - g, x = u, { cssStyles: b } = t, k = [
    { x: y / 2, y: -x / 2 },
    { x: -y / 2, y: -x / 2 },
    ...sn(-y / 2, -x / 2, -y / 2, x / 2, p, d, !1),
    { x: y / 2, y: x / 2 },
    ...sn(y / 2, x / 2, y / 2, -x / 2, p, d, !0)
  ], w = G.svg(h), S = Z(t, {});
  t.look !== "handDrawn" && (S.roughness = 0, S.fillStyle = "solid");
  const L = pt(k), T = w.path(L, S), B = h.insert(() => T, ":first-child");
  return B.attr("class", "basic label-container outer-path"), b && t.look !== "handDrawn" && B.selectAll("path").attr("style", b), i && t.look !== "handDrawn" && B.selectAll("path").attr("style", i), B.attr("transform", `translate(${p / 2}, 0)`), Q(t, B), t.intersect = function(N) {
    return U.polygon(t, k, N);
  }, h;
}
f(Lf, "bowTieRect");
function Ke(e, t, r, i) {
  return e.insert("polygon", ":first-child").attr(
    "points",
    i.map(function(s) {
      return s.x + "," + s.y;
    }).join(" ")
  ).attr("class", "label-container").attr("transform", "translate(" + -t / 2 + "," + r / 2 + ")");
}
f(Ke, "insertPolygonShape");
var Es = 12;
async function Af(e, t) {
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.labelStyle = r;
  const s = t.padding ?? 0, o = t.look === "neo" ? 28 : s, a = t.look === "neo" ? 24 : s, { shapeSvg: n, bbox: l } = await at(e, t, it(t)), h = ((t == null ? void 0 : t.width) ?? l.width) + (t.look === "neo" ? o * 2 : o + Es), c = ((t == null ? void 0 : t.height) ?? l.height) + (t.look === "neo" ? a * 2 : a), u = 0, p = h, d = -c, g = 0, m = [
    { x: u + Es, y: d },
    { x: p, y: d },
    { x: p, y: g },
    { x: u, y: g },
    { x: u, y: d + Es },
    { x: u + Es, y: d }
  ];
  let y;
  const { cssStyles: x } = t;
  if (t.look === "handDrawn") {
    const b = G.svg(n), k = Z(t, {}), w = pt(m), S = b.path(w, k);
    y = n.insert(() => S, ":first-child").attr("transform", `translate(${-h / 2}, ${c / 2})`), x && y.attr("style", x);
  } else
    y = Ke(n, h, c, m);
  return i && y.attr("style", i), Q(t, y), t.intersect = function(b) {
    return U.polygon(t, m, b);
  }, n;
}
f(Af, "card");
function Ef(e, t) {
  const { nodeStyles: r } = K(t);
  t.label = "";
  const i = e.insert("g").attr("class", it(t)).attr("id", t.domId ?? t.id), { cssStyles: s } = t, o = Math.max(28, t.width ?? 0), a = [
    { x: 0, y: o / 2 },
    { x: o / 2, y: 0 },
    { x: 0, y: -o / 2 },
    { x: -o / 2, y: 0 }
  ], n = G.svg(i), l = Z(t, {});
  t.look !== "handDrawn" && (l.roughness = 0, l.fillStyle = "solid");
  const h = pt(a), c = n.path(h, l), u = i.insert(() => c, ":first-child");
  return s && t.look !== "handDrawn" && u.selectAll("path").attr("style", s), r && t.look !== "handDrawn" && u.selectAll("path").attr("style", r), t.width = 28, t.height = 28, t.intersect = function(p) {
    return U.polygon(t, a, p);
  }, i;
}
f(Ef, "choice");
async function ll(e, t, r) {
  const { labelStyles: i, nodeStyles: s } = K(t);
  t.labelStyle = i;
  const { shapeSvg: o, bbox: a, halfPadding: n } = await at(e, t, it(t)), l = 16, h = (r == null ? void 0 : r.padding) ?? n, c = t.look === "neo" ? a.width / 2 + l * 2 : a.width / 2 + h;
  let u;
  const { cssStyles: p } = t;
  if (t.look === "handDrawn") {
    const d = G.svg(o), g = Z(t, {}), m = d.circle(0, 0, c * 2, g);
    u = o.insert(() => m, ":first-child"), u.attr("class", "basic label-container").attr("style", Rt(p));
  } else
    u = o.insert("circle", ":first-child").attr("class", "basic label-container").attr("style", s).attr("r", c).attr("cx", 0).attr("cy", 0);
  return Q(t, u), t.calcIntersect = function(d, g) {
    const m = d.width / 2;
    return U.circle(d, m, g);
  }, t.intersect = function(d) {
    return q.info("Circle intersect", t, c, d), U.circle(t, c, d);
  }, o;
}
f(ll, "circle");
function Ff(e) {
  const t = Math.cos(Math.PI / 4), r = Math.sin(Math.PI / 4), i = e * 2, s = { x: i / 2 * t, y: i / 2 * r }, o = { x: -(i / 2) * t, y: i / 2 * r }, a = { x: -(i / 2) * t, y: -(i / 2) * r }, n = { x: i / 2 * t, y: -(i / 2) * r };
  return `M ${o.x},${o.y} L ${n.x},${n.y}
                   M ${s.x},${s.y} L ${a.x},${a.y}`;
}
f(Ff, "createLine");
function Mf(e, t) {
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.labelStyle = r, t.label = "";
  const s = e.insert("g").attr("class", it(t)).attr("id", t.domId ?? t.id), o = Math.max(30, (t == null ? void 0 : t.width) ?? 0), { cssStyles: a } = t, n = G.svg(s), l = Z(t, {});
  t.look !== "handDrawn" && (l.roughness = 0, l.fillStyle = "solid");
  const h = n.circle(0, 0, o * 2, l), c = Ff(o), u = n.path(c, l), p = s.insert(() => h, ":first-child");
  return p.insert(() => u), p.attr("class", "outer-path"), a && t.look !== "handDrawn" && p.selectAll("path").attr("style", a), i && t.look !== "handDrawn" && p.selectAll("path").attr("style", i), Q(t, p), t.intersect = function(d) {
    return q.info("crossedCircle intersect", t, { radius: o, point: d }), U.circle(t, o, d);
  }, s;
}
f(Mf, "crossedCircle");
function ze(e, t, r, i = 100, s = 0, o = 180) {
  const a = [], n = s * Math.PI / 180, c = (o * Math.PI / 180 - n) / (i - 1);
  for (let u = 0; u < i; u++) {
    const p = n + u * c, d = e + r * Math.cos(p), g = t + r * Math.sin(p);
    a.push({ x: -d, y: -g });
  }
  return a;
}
f(ze, "generateCirclePoints");
async function If(e, t) {
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.labelStyle = r;
  const { shapeSvg: s, bbox: o, label: a } = await at(e, t, it(t)), n = t.look === "neo" ? 18 : t.padding ?? 0, l = t.look === "neo" ? 12 : t.padding ?? 0, h = o.width + n, c = o.height + l, u = Math.max(5, c * 0.1), { cssStyles: p } = t, d = [
    ...ze(h / 2, -c / 2, u, 30, -90, 0),
    { x: -h / 2 - u, y: u },
    ...ze(h / 2 + u * 2, -u, u, 20, -180, -270),
    ...ze(h / 2 + u * 2, u, u, 20, -90, -180),
    { x: -h / 2 - u, y: -c / 2 },
    ...ze(h / 2, c / 2, u, 20, 0, 90)
  ], g = [
    { x: h / 2, y: -c / 2 - u },
    { x: -h / 2, y: -c / 2 - u },
    ...ze(h / 2, -c / 2, u, 20, -90, 0),
    { x: -h / 2 - u, y: -u },
    ...ze(h / 2 + h * 0.1, -u, u, 20, -180, -270),
    ...ze(h / 2 + h * 0.1, u, u, 20, -90, -180),
    { x: -h / 2 - u, y: c / 2 },
    ...ze(h / 2, c / 2, u, 20, 0, 90),
    { x: -h / 2, y: c / 2 + u },
    { x: h / 2, y: c / 2 + u }
  ], m = G.svg(s), y = Z(t, { fill: "none" });
  t.look !== "handDrawn" && (y.roughness = 0, y.fillStyle = "solid");
  const b = pt(d).replace("Z", ""), k = m.path(b, y), w = pt(g), S = m.path(w, { ...y }), L = s.insert("g", ":first-child");
  return L.insert(() => S, ":first-child").attr("stroke-opacity", 0), L.insert(() => k, ":first-child"), L.attr("class", "text"), p && t.look !== "handDrawn" && L.selectAll("path").attr("style", p), i && t.look !== "handDrawn" && L.selectAll("path").attr("style", i), L.attr("transform", `translate(${u}, 0)`), a.attr(
    "transform",
    `translate(${-h / 2 + u - (o.x - (o.left ?? 0))},${-c / 2 + (t.padding ?? 0) / 2 - (o.y - (o.top ?? 0))})`
  ), Q(t, L), t.intersect = function(T) {
    return U.polygon(t, g, T);
  }, s;
}
f(If, "curlyBraceLeft");
function He(e, t, r, i = 100, s = 0, o = 180) {
  const a = [], n = s * Math.PI / 180, c = (o * Math.PI / 180 - n) / (i - 1);
  for (let u = 0; u < i; u++) {
    const p = n + u * c, d = e + r * Math.cos(p), g = t + r * Math.sin(p);
    a.push({ x: d, y: g });
  }
  return a;
}
f(He, "generateCirclePoints");
async function $f(e, t) {
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.labelStyle = r;
  const { shapeSvg: s, bbox: o, label: a } = await at(e, t, it(t)), n = t.look === "neo" ? 18 : t.padding ?? 0, l = t.look === "neo" ? 12 : t.padding ?? 0, h = o.width + (t.look === "neo" ? n * 2 : n), c = o.height + (t.look === "neo" ? l * 2 : l), u = Math.max(5, c * 0.1), { cssStyles: p } = t, d = [
    ...He(h / 2, -c / 2, u, 20, -90, 0),
    { x: h / 2 + u, y: -u },
    ...He(h / 2 + u * 2, -u, u, 20, -180, -270),
    ...He(h / 2 + u * 2, u, u, 20, -90, -180),
    { x: h / 2 + u, y: c / 2 },
    ...He(h / 2, c / 2, u, 20, 0, 90)
  ], g = [
    { x: -h / 2, y: -c / 2 - u },
    { x: h / 2, y: -c / 2 - u },
    ...He(h / 2, -c / 2, u, 20, -90, 0),
    { x: h / 2 + u, y: -u },
    ...He(h / 2 + u * 2, -u, u, 20, -180, -270),
    ...He(h / 2 + u * 2, u, u, 20, -90, -180),
    { x: h / 2 + u, y: c / 2 },
    ...He(h / 2, c / 2, u, 20, 0, 90),
    { x: h / 2, y: c / 2 + u },
    { x: -h / 2, y: c / 2 + u }
  ], m = G.svg(s), y = Z(t, { fill: "none" });
  t.look !== "handDrawn" && (y.roughness = 0, y.fillStyle = "solid");
  const b = pt(d).replace("Z", ""), k = m.path(b, y), w = pt(g), S = m.path(w, { ...y }), L = s.insert("g", ":first-child");
  return L.insert(() => S, ":first-child").attr("stroke-opacity", 0), L.insert(() => k, ":first-child"), L.attr("class", "text"), p && t.look !== "handDrawn" && L.selectAll("path").attr("style", p), i && t.look !== "handDrawn" && L.selectAll("path").attr("style", i), L.attr("transform", `translate(${-u}, 0)`), a.attr(
    "transform",
    `translate(${-h / 2 + (t.padding ?? 0) / 2 - (o.x - (o.left ?? 0))},${-c / 2 + (t.padding ?? 0) / 2 - (o.y - (o.top ?? 0))})`
  ), Q(t, L), t.intersect = function(T) {
    return U.polygon(t, g, T);
  }, s;
}
f($f, "curlyBraceRight");
function Nt(e, t, r, i = 100, s = 0, o = 180) {
  const a = [], n = s * Math.PI / 180, c = (o * Math.PI / 180 - n) / (i - 1);
  for (let u = 0; u < i; u++) {
    const p = n + u * c, d = e + r * Math.cos(p), g = t + r * Math.sin(p);
    a.push({ x: -d, y: -g });
  }
  return a;
}
f(Nt, "generateCirclePoints");
async function Of(e, t) {
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.labelStyle = r;
  const { shapeSvg: s, bbox: o, label: a } = await at(e, t, it(t)), n = t.look === "neo" ? 18 : t.padding ?? 0, l = t.look === "neo" ? 12 : t.padding ?? 0, h = o.width + (t.look === "neo" ? n * 2 : n), c = o.height + (t.look === "neo" ? l * 2 : l), u = Math.max(5, c * 0.1), { cssStyles: p } = t, d = [
    ...Nt(h / 2, -c / 2, u, 30, -90, 0),
    { x: -h / 2 - u, y: u },
    ...Nt(h / 2 + u * 2, -u, u, 20, -180, -270),
    ...Nt(h / 2 + u * 2, u, u, 20, -90, -180),
    { x: -h / 2 - u, y: -c / 2 },
    ...Nt(h / 2, c / 2, u, 20, 0, 90)
  ], g = [
    ...Nt(-h / 2 + u + u / 2, -c / 2, u, 20, -90, -180),
    { x: h / 2 - u / 2, y: u },
    ...Nt(-h / 2 - u / 2, -u, u, 20, 0, 90),
    ...Nt(-h / 2 - u / 2, u, u, 20, -90, 0),
    { x: h / 2 - u / 2, y: -u },
    ...Nt(-h / 2 + u + u / 2, c / 2, u, 30, -180, -270)
  ], m = [
    { x: h / 2, y: -c / 2 - u },
    { x: -h / 2, y: -c / 2 - u },
    ...Nt(h / 2, -c / 2, u, 20, -90, 0),
    { x: -h / 2 - u, y: -u },
    ...Nt(h / 2 + u * 2, -u, u, 20, -180, -270),
    ...Nt(h / 2 + u * 2, u, u, 20, -90, -180),
    { x: -h / 2 - u, y: c / 2 },
    ...Nt(h / 2, c / 2, u, 20, 0, 90),
    { x: -h / 2, y: c / 2 + u },
    { x: h / 2 - u - u / 2, y: c / 2 + u },
    ...Nt(-h / 2 + u + u / 2, -c / 2, u, 20, -90, -180),
    { x: h / 2 - u / 2, y: u },
    ...Nt(-h / 2 - u / 2, -u, u, 20, 0, 90),
    ...Nt(-h / 2 - u / 2, u, u, 20, -90, 0),
    { x: h / 2 - u / 2, y: -u },
    ...Nt(-h / 2 + u + u / 2, c / 2, u, 30, -180, -270)
  ], y = G.svg(s), x = Z(t, { fill: "none" });
  t.look !== "handDrawn" && (x.roughness = 0, x.fillStyle = "solid");
  const k = pt(d).replace("Z", ""), w = y.path(k, x), L = pt(g).replace("Z", ""), T = y.path(L, x), B = pt(m), N = y.path(B, { ...x }), O = s.insert("g", ":first-child");
  return O.insert(() => N, ":first-child").attr("stroke-opacity", 0), O.insert(() => w, ":first-child"), O.insert(() => T, ":first-child"), O.attr("class", "text"), p && t.look !== "handDrawn" && O.selectAll("path").attr("style", p), i && t.look !== "handDrawn" && O.selectAll("path").attr("style", i), O.attr("transform", `translate(${u - u / 4}, 0)`), a.attr(
    "transform",
    `translate(${-h / 2 + (t.padding ?? 0) / 2 - (o.x - (o.left ?? 0))},${-c / 2 + (t.padding ?? 0) / 2 - (o.y - (o.top ?? 0))})`
  ), Q(t, O), t.intersect = function(F) {
    return U.polygon(t, m, F);
  }, s;
}
f(Of, "curlyBraces");
async function Df(e, t) {
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.labelStyle = r;
  const s = t.padding ?? 0, o = t.look === "neo" ? 16 : s, a = t.look === "neo" ? 12 : s, n = 20, l = 5, { shapeSvg: h, bbox: c } = await at(e, t, it(t)), u = Math.max(n, (c.width + o * 2) * 1.25, (t == null ? void 0 : t.width) ?? 0), p = Math.max(l, c.height + a * 2, (t == null ? void 0 : t.height) ?? 0), d = p / 2, { cssStyles: g } = t, m = G.svg(h), y = Z(t, {});
  t.look !== "handDrawn" && (y.roughness = 0, y.fillStyle = "solid");
  const x = u, b = p, k = x - d, w = b / 4, S = [
    { x: k, y: 0 },
    { x: w, y: 0 },
    { x: 0, y: b / 2 },
    { x: w, y: b },
    { x: k, y: b },
    ...rs(-k, -b / 2, d, 50, 270, 90)
  ], L = pt(S), T = m.path(L, y), B = h.insert(() => T, ":first-child");
  return B.attr("class", "basic label-container outer-path"), g && t.look !== "handDrawn" && B.selectChildren("path").attr("style", g), i && t.look !== "handDrawn" && B.selectChildren("path").attr("style", i), B.attr("transform", `translate(${-u / 2}, ${-p / 2})`), Q(t, B), t.intersect = function(N) {
    return U.polygon(t, S, N);
  }, h;
}
f(Df, "curvedTrapezoid");
var iS = /* @__PURE__ */ f((e, t, r, i, s, o) => [
  `M${e},${t + o}`,
  `a${s},${o} 0,0,0 ${r},0`,
  `a${s},${o} 0,0,0 ${-r},0`,
  `l0,${i}`,
  `a${s},${o} 0,0,0 ${r},0`,
  `l0,${-i}`
].join(" "), "createCylinderPathD"), sS = /* @__PURE__ */ f((e, t, r, i, s, o) => [
  `M${e},${t + o}`,
  `M${e + r},${t + o}`,
  `a${s},${o} 0,0,0 ${-r},0`,
  `l0,${i}`,
  `a${s},${o} 0,0,0 ${r},0`,
  `l0,${-i}`
].join(" "), "createOuterCylinderPathD"), oS = /* @__PURE__ */ f((e, t, r, i, s, o) => [`M${e - r / 2},${-i / 2}`, `a${s},${o} 0,0,0 ${r},0`].join(" "), "createInnerCylinderPathD"), Yh = 8, Xh = 8;
async function Rf(e, t) {
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.labelStyle = r;
  const s = t.padding ?? 0, o = t.look === "neo" ? 24 : s, a = t.look === "neo" ? 24 : s;
  if (t.width || t.height) {
    const y = t.width ?? 0;
    t.width = (t.width ?? 0) - a, t.width < Xh && (t.width = Xh);
    const b = y / 2 / (2.5 + y / 50);
    t.height = (t.height ?? 0) - o - b * 3, t.height < Yh && (t.height = Yh);
  }
  const { shapeSvg: n, bbox: l, label: h } = await at(e, t, it(t)), c = (t.width ? t.width : l.width) + a, u = c / 2, p = u / (2.5 + c / 50), d = (t.height ? t.height : l.height) + o + p;
  let g;
  const { cssStyles: m } = t;
  if (t.look === "handDrawn") {
    const y = G.svg(n), x = sS(0, 0, c, d, u, p), b = oS(0, p, c, d, u, p), k = Z(t, {}), w = y.path(x, k), S = y.path(b, Z(t, { fill: "none" }));
    g = n.insert(() => S, ":first-child"), g = n.insert(() => w, ":first-child"), g.attr("class", "basic label-container"), m && g.attr("style", m);
  } else {
    const y = iS(0, 0, c, d, u, p);
    g = n.insert("path", ":first-child").attr("d", y).attr("class", "basic label-container outer-path").attr("style", Rt(m)).attr("style", i);
  }
  return g.attr("label-offset-y", p), g.attr("transform", `translate(${-c / 2}, ${-(d / 2 + p)})`), Q(t, g), h.attr(
    "transform",
    `translate(${-(l.width / 2) - (l.x - (l.left ?? 0))}, ${-(l.height / 2) + (t.padding ?? 0) / 1.5 - (l.y - (l.top ?? 0))})`
  ), t.intersect = function(y) {
    const x = U.rect(t, y), b = x.x - (t.x ?? 0);
    if (u != 0 && (Math.abs(b) < (t.width ?? 0) / 2 || Math.abs(b) == (t.width ?? 0) / 2 && Math.abs(x.y - (t.y ?? 0)) > (t.height ?? 0) / 2 - p)) {
      let k = p * p * (1 - b * b / (u * u));
      k > 0 && (k = Math.sqrt(k)), k = p - k, y.y - (t.y ?? 0) > 0 && (k = -k), x.y += k;
    }
    return x;
  }, n;
}
f(Rf, "cylinder");
async function Pf(e, t) {
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.labelStyle = r;
  const s = t.look === "neo" ? 16 : t.padding ?? 0, o = t.look === "neo" ? 16 : t.padding ?? 0, { shapeSvg: a, bbox: n, label: l } = await at(e, t, it(t)), h = n.width + s, c = n.height + o, u = c * 0.2, p = -h / 2, d = -c / 2 - u / 2, { cssStyles: g } = t, m = G.svg(a), y = Z(t, {});
  t.look !== "handDrawn" && (y.roughness = 0, y.fillStyle = "solid");
  const x = [
    { x: p, y: d + u },
    { x: -p, y: d + u },
    { x: -p, y: -d },
    { x: p, y: -d },
    { x: p, y: d },
    { x: -p, y: d },
    { x: -p, y: d + u }
  ], b = m.polygon(
    x.map((w) => [w.x, w.y]),
    y
  ), k = a.insert(() => b, ":first-child");
  return k.attr("class", "basic label-container outer-path"), g && t.look !== "handDrawn" && k.selectAll("path").attr("style", g), i && t.look !== "handDrawn" && k.selectAll("path").attr("style", i), l.attr(
    "transform",
    `translate(${p + (t.padding ?? 0) / 2 - (n.x - (n.left ?? 0))}, ${d + u + (t.padding ?? 0) / 2 - (n.y - (n.top ?? 0))})`
  ), Q(t, k), t.intersect = function(w) {
    return U.rect(t, w);
  }, a;
}
f(Pf, "dividedRectangle");
async function Nf(e, t) {
  var d, g;
  const { labelStyles: r, nodeStyles: i } = K(t), s = t.look === "neo" ? 12 : 5;
  t.labelStyle = r;
  const o = t.padding ?? 0, a = t.look === "neo" ? 16 : o, { shapeSvg: n, bbox: l } = await at(e, t, it(t)), h = (t != null && t.width ? (t == null ? void 0 : t.width) / 2 : l.width / 2) + (a ?? 0), c = h - s;
  let u;
  const { cssStyles: p } = t;
  if (t.look === "handDrawn") {
    const m = G.svg(n), y = Z(t, { roughness: 0.2, strokeWidth: 2.5 }), x = Z(t, { roughness: 0.2, strokeWidth: 1.5 }), b = m.circle(0, 0, h * 2, y), k = m.circle(0, 0, c * 2, x);
    u = n.insert("g", ":first-child"), u.attr("class", Rt(t.cssClasses)).attr("style", Rt(p)), (d = u.node()) == null || d.appendChild(b), (g = u.node()) == null || g.appendChild(k);
  } else {
    u = n.insert("g", ":first-child");
    const m = u.insert("circle", ":first-child"), y = u.insert("circle");
    u.attr("class", "basic label-container").attr("style", i), m.attr("class", "outer-circle").attr("style", i).attr("r", h).attr("cx", 0).attr("cy", 0), y.attr("class", "inner-circle").attr("style", i).attr("r", c).attr("cx", 0).attr("cy", 0);
  }
  return Q(t, u), t.intersect = function(m) {
    return q.info("DoubleCircle intersect", t, h, m), U.circle(t, h, m);
  }, n;
}
f(Nf, "doublecircle");
function qf(e, t, { config: { themeVariables: r } }) {
  const { labelStyles: i, nodeStyles: s } = K(t);
  t.label = "", t.labelStyle = i;
  const o = e.insert("g").attr("class", it(t)).attr("id", t.domId ?? t.id), a = 7, { cssStyles: n } = t, l = G.svg(o), { nodeBorder: h } = r, c = Z(t, { fillStyle: "solid" });
  t.look !== "handDrawn" && (c.roughness = 0);
  const u = l.circle(0, 0, a * 2, c), p = o.insert(() => u, ":first-child");
  return p.selectAll("path").attr("style", `fill: ${h} !important;`), n && n.length > 0 && t.look !== "handDrawn" && p.selectAll("path").attr("style", n), s && t.look !== "handDrawn" && p.selectAll("path").attr("style", s), Q(t, p), t.intersect = function(d) {
    return q.info("filledCircle intersect", t, { radius: a, point: d }), U.circle(t, a, d);
  }, o;
}
f(qf, "filledCircle");
var Uh = 10, jh = 10;
async function Wf(e, t) {
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.labelStyle = r;
  const s = t.padding ?? 0, o = t.look === "neo" ? s * 2 : s;
  (t.width || t.height) && (t.height = (t == null ? void 0 : t.height) ?? 0, t.height < Uh && (t.height = Uh), t.width = ((t == null ? void 0 : t.width) ?? 0) - o - o / 2, t.width < jh && (t.width = jh));
  const { shapeSvg: a, bbox: n, label: l } = await at(e, t, it(t)), h = (t != null && t.width ? t == null ? void 0 : t.width : n.width) + (o ?? 0), c = t != null && t.height ? t == null ? void 0 : t.height : h + n.height, u = c, p = [
    { x: 0, y: -c },
    { x: u, y: -c },
    { x: u / 2, y: 0 }
  ], { cssStyles: d } = t, g = G.svg(a), m = Z(t, {});
  t.look !== "handDrawn" && (m.roughness = 0, m.fillStyle = "solid");
  const y = pt(p), x = g.path(y, m), b = a.insert(() => x, ":first-child").attr("transform", `translate(${-c / 2}, ${c / 2})`).attr("class", "outer-path");
  return d && t.look !== "handDrawn" && b.selectChildren("path").attr("style", d), i && t.look !== "handDrawn" && b.selectChildren("path").attr("style", i), t.width = h, t.height = c, Q(t, b), l.attr(
    "transform",
    `translate(${-n.width / 2 - (n.x - (n.left ?? 0))}, ${-c / 2 + (t.padding ?? 0) / 2 + (n.y - (n.top ?? 0))})`
  ), t.intersect = function(k) {
    return q.info("Triangle intersect", t, p, k), U.polygon(t, p, k);
  }, a;
}
f(Wf, "flippedTriangle");
function zf(e, t, { dir: r, config: { state: i, themeVariables: s } }) {
  const { nodeStyles: o } = K(t);
  t.label = "";
  const a = e.insert("g").attr("class", it(t)).attr("id", t.domId ?? t.id), { cssStyles: n } = t;
  let l = Math.max(70, (t == null ? void 0 : t.width) ?? 0), h = Math.max(10, (t == null ? void 0 : t.height) ?? 0);
  r === "LR" && (l = Math.max(10, (t == null ? void 0 : t.width) ?? 0), h = Math.max(70, (t == null ? void 0 : t.height) ?? 0));
  const c = -1 * l / 2, u = -1 * h / 2, p = G.svg(a), d = Z(t, {
    stroke: s.lineColor,
    fill: s.lineColor
  });
  t.look !== "handDrawn" && (d.roughness = 0, d.fillStyle = "solid");
  const g = p.rectangle(c, u, l, h, d), m = a.insert(() => g, ":first-child");
  n && t.look !== "handDrawn" && m.selectAll("path").attr("style", n), o && t.look !== "handDrawn" && m.selectAll("path").attr("style", o), Q(t, m);
  const y = (i == null ? void 0 : i.padding) ?? 0;
  return t.width && t.height && (t.width += y / 2 || 0, t.height += y / 2 || 0), t.intersect = function(x) {
    return U.rect(t, x);
  }, a;
}
f(zf, "forkJoin");
async function Hf(e, t) {
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.labelStyle = r;
  const s = 15, o = 10, a = t.look === "neo" ? 16 : t.padding ?? 0, n = t.look === "neo" ? 12 : t.padding ?? 0;
  (t.width || t.height) && (t.height = ((t == null ? void 0 : t.height) ?? 0) - n * 2, t.height < o && (t.height = o), t.width = ((t == null ? void 0 : t.width) ?? 0) - a * 2, t.width < s && (t.width = s));
  const { shapeSvg: l, bbox: h } = await at(e, t, it(t)), c = (t != null && t.width ? t == null ? void 0 : t.width : Math.max(s, h.width)) + a * 2, u = (t != null && t.height ? t == null ? void 0 : t.height : Math.max(o, h.height)) + n * 2, p = u / 2, { cssStyles: d } = t, g = G.svg(l), m = Z(t, {});
  t.look !== "handDrawn" && (m.roughness = 0, m.fillStyle = "solid");
  const y = [
    { x: -c / 2, y: -u / 2 },
    { x: c / 2 - p, y: -u / 2 },
    ...rs(-c / 2 + p, 0, p, 50, 90, 270),
    { x: c / 2 - p, y: u / 2 },
    { x: -c / 2, y: u / 2 }
  ], x = pt(y), b = g.path(x, m), k = l.insert(() => b, ":first-child");
  return k.attr("class", "basic label-container outer-path"), d && t.look !== "handDrawn" && k.selectChildren("path").attr("style", d), i && t.look !== "handDrawn" && k.selectChildren("path").attr("style", i), Q(t, k), t.intersect = function(w) {
    return q.info("Pill intersect", t, { radius: p, point: w }), U.polygon(t, y, w);
  }, l;
}
f(Hf, "halfRoundedRectangle");
var aS = /* @__PURE__ */ f((e, t, r, i, s) => [
  `M${e + s},${t}`,
  `L${e + r - s},${t}`,
  `L${e + r},${t - i / 2}`,
  `L${e + r - s},${t - i}`,
  `L${e + s},${t - i}`,
  `L${e},${t - i / 2}`,
  "Z"
].join(" "), "createHexagonPathD");
async function Yf(e, t) {
  const { labelStyles: r, nodeStyles: i } = K(t), s = t.look === "neo" ? 3.5 : 4;
  t.labelStyle = r;
  const o = t.padding ?? 0, a = 70, n = 32, l = t.look === "neo" ? a : o, h = t.look === "neo" ? n : o;
  if (t.width || t.height) {
    const k = (t.height ?? 0) / s;
    t.width = ((t == null ? void 0 : t.width) ?? 0) - 2 * k - h, t.height = (t.height ?? 0) - l;
  }
  const { shapeSvg: c, bbox: u } = await at(e, t, it(t)), p = (t != null && t.height ? t == null ? void 0 : t.height : u.height) + l, d = p / s, g = (t != null && t.width ? t == null ? void 0 : t.width : u.width) + 2 * d + h, m = [
    { x: d, y: 0 },
    { x: g - d, y: 0 },
    { x: g, y: -p / 2 },
    { x: g - d, y: -p },
    { x: d, y: -p },
    { x: 0, y: -p / 2 }
  ];
  let y;
  const { cssStyles: x } = t;
  if (t.look === "handDrawn") {
    const b = G.svg(c), k = Z(t, {}), w = aS(0, 0, g, p, d), S = b.path(w, k);
    y = c.insert(() => S, ":first-child").attr("transform", `translate(${-g / 2}, ${p / 2})`), x && y.attr("style", x);
  } else
    y = Ke(c, g, p, m);
  return i && y.attr("style", i), t.width = g, t.height = p, Q(t, y), t.intersect = function(b) {
    return U.polygon(t, m, b);
  }, c;
}
f(Yf, "hexagon");
async function Xf(e, t) {
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.label = "", t.labelStyle = r;
  const { shapeSvg: s } = await at(e, t, it(t)), o = Math.max(30, (t == null ? void 0 : t.width) ?? 0), a = Math.max(30, (t == null ? void 0 : t.height) ?? 0), { cssStyles: n } = t, l = G.svg(s), h = Z(t, {});
  t.look !== "handDrawn" && (h.roughness = 0, h.fillStyle = "solid");
  const c = [
    { x: 0, y: 0 },
    { x: o, y: 0 },
    { x: 0, y: a },
    { x: o, y: a }
  ], u = pt(c), p = l.path(u, h), d = s.insert(() => p, ":first-child");
  return d.attr("class", "basic label-container outer-path"), n && t.look !== "handDrawn" && d.selectChildren("path").attr("style", n), i && t.look !== "handDrawn" && d.selectChildren("path").attr("style", i), d.attr("transform", `translate(${-o / 2}, ${-a / 2})`), Q(t, d), t.intersect = function(g) {
    return q.info("Pill intersect", t, { points: c }), U.polygon(t, c, g);
  }, s;
}
f(Xf, "hourglass");
async function Uf(e, t, { config: { themeVariables: r, flowchart: i } }) {
  const { labelStyles: s } = K(t);
  t.labelStyle = s;
  const o = t.assetHeight ?? 48, a = t.assetWidth ?? 48, n = Math.max(o, a), l = i == null ? void 0 : i.wrappingWidth;
  t.width = Math.max(n, l ?? 0);
  const { shapeSvg: h, bbox: c, label: u } = await at(e, t, "icon-shape default"), p = t.pos === "t", d = n, g = n, { nodeBorder: m } = r, { stylesMap: y } = mi(t), x = -g / 2, b = -d / 2, k = t.label ? 8 : 0, w = G.svg(h), S = Z(t, { stroke: "none", fill: "none" });
  t.look !== "handDrawn" && (S.roughness = 0, S.fillStyle = "solid");
  const L = w.rectangle(x, b, g, d, S), T = Math.max(g, c.width), B = d + c.height + k, N = w.rectangle(-T / 2, -B / 2, T, B, {
    ...S,
    fill: "transparent",
    stroke: "none"
  }), O = h.insert(() => L, ":first-child"), F = h.insert(() => N);
  if (t.icon) {
    const Y = h.append("g");
    Y.html(
      `<g>${await ps(t.icon, {
        height: n,
        width: n,
        fallbackPrefix: ""
      })}</g>`
    );
    const H = Y.node().getBBox(), P = H.width, M = H.height, E = H.x, D = H.y;
    Y.attr(
      "transform",
      `translate(${-P / 2 - E},${p ? c.height / 2 + k / 2 - M / 2 - D : -c.height / 2 - k / 2 - M / 2 - D})`
    ), Y.attr("style", `color: ${y.get("stroke") ?? m};`);
  }
  return u.attr(
    "transform",
    `translate(${-c.width / 2 - (c.x - (c.left ?? 0))},${p ? -B / 2 : B / 2 - c.height})`
  ), O.attr(
    "transform",
    `translate(0,${p ? c.height / 2 + k / 2 : -c.height / 2 - k / 2})`
  ), Q(t, F), t.intersect = function(Y) {
    if (q.info("iconSquare intersect", t, Y), !t.label)
      return U.rect(t, Y);
    const H = t.x ?? 0, P = t.y ?? 0, M = t.height ?? 0;
    let E = [];
    return p ? E = [
      { x: H - c.width / 2, y: P - M / 2 },
      { x: H + c.width / 2, y: P - M / 2 },
      { x: H + c.width / 2, y: P - M / 2 + c.height + k },
      { x: H + g / 2, y: P - M / 2 + c.height + k },
      { x: H + g / 2, y: P + M / 2 },
      { x: H - g / 2, y: P + M / 2 },
      { x: H - g / 2, y: P - M / 2 + c.height + k },
      { x: H - c.width / 2, y: P - M / 2 + c.height + k }
    ] : E = [
      { x: H - g / 2, y: P - M / 2 },
      { x: H + g / 2, y: P - M / 2 },
      { x: H + g / 2, y: P - M / 2 + d },
      { x: H + c.width / 2, y: P - M / 2 + d },
      { x: H + c.width / 2 / 2, y: P + M / 2 },
      { x: H - c.width / 2, y: P + M / 2 },
      { x: H - c.width / 2, y: P - M / 2 + d },
      { x: H - g / 2, y: P - M / 2 + d }
    ], U.polygon(t, E, Y);
  }, h;
}
f(Uf, "icon");
async function jf(e, t, { config: { themeVariables: r, flowchart: i } }) {
  const { labelStyles: s } = K(t);
  t.labelStyle = s;
  const o = t.assetHeight ?? 48, a = t.assetWidth ?? 48, n = Math.max(o, a), l = i == null ? void 0 : i.wrappingWidth;
  t.width = Math.max(n, l ?? 0);
  const { shapeSvg: h, bbox: c, label: u } = await at(e, t, "icon-shape default"), p = 20, d = t.label ? 8 : 0, g = t.pos === "t", { nodeBorder: m, mainBkg: y } = r, { stylesMap: x } = mi(t), b = G.svg(h), k = Z(t, {});
  t.look !== "handDrawn" && (k.roughness = 0, k.fillStyle = "solid");
  const w = x.get("fill");
  k.stroke = w ?? y;
  const S = h.append("g");
  t.icon && S.html(
    `<g>${await ps(t.icon, {
      height: n,
      width: n,
      fallbackPrefix: ""
    })}</g>`
  );
  const L = S.node().getBBox(), T = L.width, B = L.height, N = L.x, O = L.y, F = Math.max(T, B) * Math.SQRT2 + p * 2, Y = b.circle(0, 0, F, k), H = Math.max(F, c.width), P = F + c.height + d, M = b.rectangle(-H / 2, -P / 2, H, P, {
    ...k,
    fill: "transparent",
    stroke: "none"
  }), E = h.insert(() => Y, ":first-child"), D = h.insert(() => M);
  return S.attr(
    "transform",
    `translate(${-T / 2 - N},${g ? c.height / 2 + d / 2 - B / 2 - O : -c.height / 2 - d / 2 - B / 2 - O})`
  ), S.attr("style", `color: ${x.get("stroke") ?? m};`), u.attr(
    "transform",
    `translate(${-c.width / 2 - (c.x - (c.left ?? 0))},${g ? -P / 2 : P / 2 - c.height})`
  ), E.attr(
    "transform",
    `translate(0,${g ? c.height / 2 + d / 2 : -c.height / 2 - d / 2})`
  ), Q(t, D), t.intersect = function(v) {
    return q.info("iconSquare intersect", t, v), U.rect(t, v);
  }, h;
}
f(jf, "iconCircle");
async function Gf(e, t, { config: { themeVariables: r, flowchart: i } }) {
  const { labelStyles: s } = K(t);
  t.labelStyle = s;
  const o = t.assetHeight ?? 48, a = t.assetWidth ?? 48, n = Math.max(o, a), l = i == null ? void 0 : i.wrappingWidth;
  t.width = Math.max(n, l ?? 0);
  const { shapeSvg: h, bbox: c, halfPadding: u, label: p } = await at(
    e,
    t,
    "icon-shape default"
  ), d = t.pos === "t", g = n + u * 2, m = n + u * 2, { nodeBorder: y, mainBkg: x } = r, { stylesMap: b } = mi(t), k = -m / 2, w = -g / 2, S = t.label ? 8 : 0, L = G.svg(h), T = Z(t, {});
  t.look !== "handDrawn" && (T.roughness = 0, T.fillStyle = "solid");
  const B = b.get("fill");
  T.stroke = B ?? x;
  const N = L.path(ar(k, w, m, g, 5), T), O = Math.max(m, c.width), F = g + c.height + S, Y = L.rectangle(-O / 2, -F / 2, O, F, {
    ...T,
    fill: "transparent",
    stroke: "none"
  }), H = h.insert(() => N, ":first-child").attr("class", "icon-shape2"), P = h.insert(() => Y);
  if (t.icon) {
    const M = h.append("g");
    M.html(
      `<g>${await ps(t.icon, {
        height: n,
        width: n,
        fallbackPrefix: ""
      })}</g>`
    );
    const E = M.node().getBBox(), D = E.width, v = E.height, R = E.x, z = E.y;
    M.attr(
      "transform",
      `translate(${-D / 2 - R},${d ? c.height / 2 + S / 2 - v / 2 - z : -c.height / 2 - S / 2 - v / 2 - z})`
    ), M.attr("style", `color: ${b.get("stroke") ?? y};`);
  }
  return p.attr(
    "transform",
    `translate(${-c.width / 2 - (c.x - (c.left ?? 0))},${d ? -F / 2 : F / 2 - c.height})`
  ), H.attr(
    "transform",
    `translate(0,${d ? c.height / 2 + S / 2 : -c.height / 2 - S / 2})`
  ), Q(t, P), t.intersect = function(M) {
    if (q.info("iconSquare intersect", t, M), !t.label)
      return U.rect(t, M);
    const E = t.x ?? 0, D = t.y ?? 0, v = t.height ?? 0;
    let R = [];
    return d ? R = [
      { x: E - c.width / 2, y: D - v / 2 },
      { x: E + c.width / 2, y: D - v / 2 },
      { x: E + c.width / 2, y: D - v / 2 + c.height + S },
      { x: E + m / 2, y: D - v / 2 + c.height + S },
      { x: E + m / 2, y: D + v / 2 },
      { x: E - m / 2, y: D + v / 2 },
      { x: E - m / 2, y: D - v / 2 + c.height + S },
      { x: E - c.width / 2, y: D - v / 2 + c.height + S }
    ] : R = [
      { x: E - m / 2, y: D - v / 2 },
      { x: E + m / 2, y: D - v / 2 },
      { x: E + m / 2, y: D - v / 2 + g },
      { x: E + c.width / 2, y: D - v / 2 + g },
      { x: E + c.width / 2 / 2, y: D + v / 2 },
      { x: E - c.width / 2, y: D + v / 2 },
      { x: E - c.width / 2, y: D - v / 2 + g },
      { x: E - m / 2, y: D - v / 2 + g }
    ], U.polygon(t, R, M);
  }, h;
}
f(Gf, "iconRounded");
async function Vf(e, t, { config: { themeVariables: r, flowchart: i } }) {
  const { labelStyles: s } = K(t);
  t.labelStyle = s;
  const o = t.assetHeight ?? 48, a = t.assetWidth ?? 48, n = Math.max(o, a), l = i == null ? void 0 : i.wrappingWidth;
  t.width = Math.max(n, l ?? 0);
  const { shapeSvg: h, bbox: c, halfPadding: u, label: p } = await at(
    e,
    t,
    "icon-shape default"
  ), d = t.pos === "t", g = n + u * 2, m = n + u * 2, { nodeBorder: y, mainBkg: x } = r, { stylesMap: b } = mi(t), k = -m / 2, w = -g / 2, S = t.label ? 8 : 0, L = G.svg(h), T = Z(t, {});
  t.look !== "handDrawn" && (T.roughness = 0, T.fillStyle = "solid");
  const B = b.get("fill");
  T.stroke = B ?? x;
  const N = L.path(ar(k, w, m, g, 0.1), T), O = Math.max(m, c.width), F = g + c.height + S, Y = L.rectangle(-O / 2, -F / 2, O, F, {
    ...T,
    fill: "transparent",
    stroke: "none"
  }), H = h.insert(() => N, ":first-child"), P = h.insert(() => Y);
  if (t.icon) {
    const M = h.append("g");
    M.html(
      `<g>${await ps(t.icon, {
        height: n,
        width: n,
        fallbackPrefix: ""
      })}</g>`
    );
    const E = M.node().getBBox(), D = E.width, v = E.height, R = E.x, z = E.y;
    M.attr(
      "transform",
      `translate(${-D / 2 - R},${d ? c.height / 2 + S / 2 - v / 2 - z : -c.height / 2 - S / 2 - v / 2 - z})`
    ), M.attr("style", `color: ${b.get("stroke") ?? y};`);
  }
  return p.attr(
    "transform",
    `translate(${-c.width / 2 - (c.x - (c.left ?? 0))},${d ? -F / 2 : F / 2 - c.height})`
  ), H.attr(
    "transform",
    `translate(0,${d ? c.height / 2 + S / 2 : -c.height / 2 - S / 2})`
  ), Q(t, P), t.intersect = function(M) {
    if (q.info("iconSquare intersect", t, M), !t.label)
      return U.rect(t, M);
    const E = t.x ?? 0, D = t.y ?? 0, v = t.height ?? 0;
    let R = [];
    return d ? R = [
      { x: E - c.width / 2, y: D - v / 2 },
      { x: E + c.width / 2, y: D - v / 2 },
      { x: E + c.width / 2, y: D - v / 2 + c.height + S },
      { x: E + m / 2, y: D - v / 2 + c.height + S },
      { x: E + m / 2, y: D + v / 2 },
      { x: E - m / 2, y: D + v / 2 },
      { x: E - m / 2, y: D - v / 2 + c.height + S },
      { x: E - c.width / 2, y: D - v / 2 + c.height + S }
    ] : R = [
      { x: E - m / 2, y: D - v / 2 },
      { x: E + m / 2, y: D - v / 2 },
      { x: E + m / 2, y: D - v / 2 + g },
      { x: E + c.width / 2, y: D - v / 2 + g },
      { x: E + c.width / 2 / 2, y: D + v / 2 },
      { x: E - c.width / 2, y: D + v / 2 },
      { x: E - c.width / 2, y: D - v / 2 + g },
      { x: E - m / 2, y: D - v / 2 + g }
    ], U.polygon(t, R, M);
  }, h;
}
f(Vf, "iconSquare");
async function Zf(e, t, { config: { flowchart: r } }) {
  const i = new Image();
  i.src = (t == null ? void 0 : t.img) ?? "", await i.decode();
  const s = Number(i.naturalWidth.toString().replace("px", "")), o = Number(i.naturalHeight.toString().replace("px", ""));
  t.imageAspectRatio = s / o;
  const { labelStyles: a } = K(t);
  t.labelStyle = a;
  const n = r == null ? void 0 : r.wrappingWidth;
  t.defaultWidth = r == null ? void 0 : r.wrappingWidth;
  const l = Math.max(
    t.label ? n ?? 0 : 0,
    (t == null ? void 0 : t.assetWidth) ?? s
  ), h = t.constraint === "on" && t != null && t.assetHeight ? t.assetHeight * t.imageAspectRatio : l, c = t.constraint === "on" ? h / t.imageAspectRatio : (t == null ? void 0 : t.assetHeight) ?? o;
  t.width = Math.max(h, n ?? 0);
  const { shapeSvg: u, bbox: p, label: d } = await at(e, t, "image-shape default"), g = t.pos === "t", m = -h / 2, y = -c / 2, x = t.label ? 8 : 0, b = G.svg(u), k = Z(t, {});
  t.look !== "handDrawn" && (k.roughness = 0, k.fillStyle = "solid");
  const w = b.rectangle(m, y, h, c, k), S = Math.max(h, p.width), L = c + p.height + x, T = b.rectangle(-S / 2, -L / 2, S, L, {
    ...k,
    fill: "none",
    stroke: "none"
  }), B = u.insert(() => w, ":first-child"), N = u.insert(() => T);
  if (t.img) {
    const O = u.append("image");
    O.attr("href", t.img), O.attr("width", h), O.attr("height", c), O.attr("preserveAspectRatio", "none"), O.attr(
      "transform",
      `translate(${-h / 2},${g ? L / 2 - c : -L / 2})`
    );
  }
  return d.attr(
    "transform",
    `translate(${-p.width / 2 - (p.x - (p.left ?? 0))},${g ? -c / 2 - p.height / 2 - x / 2 : c / 2 - p.height / 2 + x / 2})`
  ), B.attr(
    "transform",
    `translate(0,${g ? p.height / 2 + x / 2 : -p.height / 2 - x / 2})`
  ), Q(t, N), t.intersect = function(O) {
    if (q.info("iconSquare intersect", t, O), !t.label)
      return U.rect(t, O);
    const F = t.x ?? 0, Y = t.y ?? 0, H = t.height ?? 0;
    let P = [];
    return g ? P = [
      { x: F - p.width / 2, y: Y - H / 2 },
      { x: F + p.width / 2, y: Y - H / 2 },
      { x: F + p.width / 2, y: Y - H / 2 + p.height + x },
      { x: F + h / 2, y: Y - H / 2 + p.height + x },
      { x: F + h / 2, y: Y + H / 2 },
      { x: F - h / 2, y: Y + H / 2 },
      { x: F - h / 2, y: Y - H / 2 + p.height + x },
      { x: F - p.width / 2, y: Y - H / 2 + p.height + x }
    ] : P = [
      { x: F - h / 2, y: Y - H / 2 },
      { x: F + h / 2, y: Y - H / 2 },
      { x: F + h / 2, y: Y - H / 2 + c },
      { x: F + p.width / 2, y: Y - H / 2 + c },
      { x: F + p.width / 2 / 2, y: Y + H / 2 },
      { x: F - p.width / 2, y: Y + H / 2 },
      { x: F - p.width / 2, y: Y - H / 2 + c },
      { x: F - h / 2, y: Y - H / 2 + c }
    ], U.polygon(t, P, O);
  }, u;
}
f(Zf, "imageSquare");
async function Kf(e, t) {
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.labelStyle = r;
  const s = t.padding ?? 0, o = s, a = t.look === "neo" ? s * 2 : s, { shapeSvg: n, bbox: l } = await at(e, t, it(t)), h = Math.max(l.width + (a ?? 0) * 2, (t == null ? void 0 : t.width) ?? 0), c = Math.max(l.height + (o ?? 0) * 2, (t == null ? void 0 : t.height) ?? 0), u = [
    { x: 0, y: 0 },
    { x: h, y: 0 },
    { x: h + 3 * c / 6, y: -c },
    { x: -3 * c / 6, y: -c }
  ];
  let p;
  const { cssStyles: d } = t;
  if (t.look === "handDrawn") {
    const g = G.svg(n), m = Z(t, {}), y = pt(u), x = g.path(y, m);
    p = n.insert(() => x, ":first-child").attr("transform", `translate(${-h / 2}, ${c / 2})`), d && p.attr("style", d);
  } else
    p = Ke(n, h, c, u);
  return i && p.attr("style", i), t.width = h, t.height = c, Q(t, p), t.intersect = function(g) {
    return U.polygon(t, u, g);
  }, n;
}
f(Kf, "inv_trapezoid");
async function fs(e, t, r) {
  const { labelStyles: i, nodeStyles: s } = K(t);
  t.labelStyle = i;
  const { shapeSvg: o, bbox: a } = await at(e, t, it(t)), n = Math.max(a.width + r.labelPaddingX * 2, (t == null ? void 0 : t.width) || 0), l = Math.max(a.height + r.labelPaddingY * 2, (t == null ? void 0 : t.height) || 0), h = -n / 2, c = -l / 2;
  let u, { rx: p, ry: d } = t;
  const { cssStyles: g } = t;
  if (r != null && r.rx && r.ry && (p = r.rx, d = r.ry), t.look === "handDrawn") {
    const m = G.svg(o), y = Z(t, {}), x = p || d ? m.path(ar(h, c, n, l, p || 0), y) : m.rectangle(h, c, n, l, y);
    u = o.insert(() => x, ":first-child"), u.attr("class", "basic label-container").attr("style", Rt(g));
  } else
    u = o.insert("rect", ":first-child"), u.attr("class", "basic label-container").attr("style", s).attr("rx", Rt(p)).attr("ry", Rt(d)).attr("x", h).attr("y", c).attr("width", n).attr("height", l);
  return Q(t, u), t.calcIntersect = function(m, y) {
    return U.rect(m, y);
  }, t.intersect = function(m) {
    return U.rect(t, m);
  }, o;
}
f(fs, "drawRect");
async function Qf(e, t) {
  const { shapeSvg: r, bbox: i, label: s } = await at(e, t, "label"), o = r.insert("rect", ":first-child");
  return o.attr("width", 0.1).attr("height", 0.1), r.attr("class", "label edgeLabel"), s.attr(
    "transform",
    `translate(${-(i.width / 2) - (i.x - (i.left ?? 0))}, ${-(i.height / 2) - (i.y - (i.top ?? 0))})`
  ), Q(t, o), t.intersect = function(l) {
    return U.rect(t, l);
  }, r;
}
f(Qf, "labelRect");
async function Jf(e, t) {
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.labelStyle = r;
  const s = t.padding ?? 0, o = s, a = t.look === "neo" ? s * 2 : s, { shapeSvg: n, bbox: l } = await at(e, t, it(t)), h = ((t == null ? void 0 : t.height) ?? l.height) + o, c = ((t == null ? void 0 : t.width) ?? l.width) + a, u = [
    { x: 0, y: 0 },
    { x: c + 3 * h / 6, y: 0 },
    { x: c, y: -h },
    { x: -(3 * h) / 6, y: -h }
  ];
  let p;
  const { cssStyles: d } = t;
  if (t.look === "handDrawn") {
    const g = G.svg(n), m = Z(t, {}), y = pt(u), x = g.path(y, m);
    p = n.insert(() => x, ":first-child").attr("transform", `translate(${-c / 2}, ${h / 2})`), d && p.attr("style", d);
  } else
    p = Ke(n, c, h, u);
  return i && p.attr("style", i), t.width = c, t.height = h, Q(t, p), t.intersect = function(g) {
    return U.polygon(t, u, g);
  }, n;
}
f(Jf, "lean_left");
async function tg(e, t) {
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.labelStyle = r;
  const s = t.padding ?? 0, o = s, a = t.look === "neo" ? s * 2 : s, { shapeSvg: n, bbox: l } = await at(e, t, it(t)), h = ((t == null ? void 0 : t.height) ?? l.height) + o, c = ((t == null ? void 0 : t.width) ?? l.width) + a, u = [
    { x: -3 * h / 6, y: 0 },
    { x: c, y: 0 },
    { x: c + 3 * h / 6, y: -h },
    { x: 0, y: -h }
  ];
  let p;
  const { cssStyles: d } = t;
  if (t.look === "handDrawn") {
    const g = G.svg(n), m = Z(t, {}), y = pt(u), x = g.path(y, m);
    p = n.insert(() => x, ":first-child").attr("transform", `translate(${-c / 2}, ${h / 2})`), d && p.attr("style", d);
  } else
    p = Ke(n, c, h, u);
  return i && p.attr("style", i), t.width = c, t.height = h, Q(t, p), t.intersect = function(g) {
    return U.polygon(t, u, g);
  }, n;
}
f(tg, "lean_right");
function eg(e, t) {
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.label = "", t.labelStyle = r;
  const s = e.insert("g").attr("class", it(t)).attr("id", t.domId ?? t.id), { cssStyles: o } = t, a = Math.max(35, (t == null ? void 0 : t.width) ?? 0), n = Math.max(35, (t == null ? void 0 : t.height) ?? 0), l = 7, h = [
    { x: a, y: 0 },
    { x: 0, y: n + l / 2 },
    { x: a - 2 * l, y: n + l / 2 },
    { x: 0, y: 2 * n },
    { x: a, y: n - l / 2 },
    { x: 2 * l, y: n - l / 2 }
  ], c = G.svg(s), u = Z(t, {});
  t.look !== "handDrawn" && (u.roughness = 0, u.fillStyle = "solid");
  const p = pt(h), d = c.path(p, u), g = s.insert(() => d, ":first-child");
  return g.attr("class", "outer-path"), o && t.look !== "handDrawn" && g.selectAll("path").attr("style", o), i && t.look !== "handDrawn" && g.selectAll("path").attr("style", i), g.attr("transform", `translate(-${a / 2},${-n})`), Q(t, g), t.intersect = function(m) {
    return q.info("lightningBolt intersect", t, m), U.polygon(t, h, m);
  }, s;
}
f(eg, "lightningBolt");
var nS = /* @__PURE__ */ f((e, t, r, i, s, o, a) => [
  `M${e},${t + o}`,
  `a${s},${o} 0,0,0 ${r},0`,
  `a${s},${o} 0,0,0 ${-r},0`,
  `l0,${i}`,
  `a${s},${o} 0,0,0 ${r},0`,
  `l0,${-i}`,
  `M${e},${t + o + a}`,
  `a${s},${o} 0,0,0 ${r},0`
].join(" "), "createCylinderPathD"), lS = /* @__PURE__ */ f((e, t, r, i, s, o, a) => [
  `M${e},${t + o}`,
  `M${e + r},${t + o}`,
  `a${s},${o} 0,0,0 ${-r},0`,
  `l0,${i}`,
  `a${s},${o} 0,0,0 ${r},0`,
  `l0,${-i}`,
  `M${e},${t + o + a}`,
  `a${s},${o} 0,0,0 ${r},0`
].join(" "), "createOuterCylinderPathD"), hS = /* @__PURE__ */ f((e, t, r, i, s, o) => [`M${e - r / 2},${-i / 2}`, `a${s},${o} 0,0,0 ${r},0`].join(" "), "createInnerCylinderPathD"), Gh = 10, Vh = 10;
async function rg(e, t) {
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.labelStyle = r;
  const s = t.padding ?? 0, o = t.look === "neo" ? 16 : s, a = t.look === "neo" ? 24 : s;
  if (t.width || t.height) {
    const x = t.width ?? 0;
    t.width = (t.width ?? 0) - o, t.width < Vh && (t.width = Vh);
    const k = x / 2 / (2.5 + x / 50);
    t.height = (t.height ?? 0) - a - k * 3, t.height < Gh && (t.height = Gh);
  }
  const { shapeSvg: n, bbox: l, label: h } = await at(e, t, it(t)), c = (t != null && t.width ? t == null ? void 0 : t.width : l.width) + o * 2, u = c / 2, p = u / (2.5 + c / 50), d = (t != null && t.height ? t == null ? void 0 : t.height : l.height) + p + a * 2, g = d * 0.1;
  let m;
  const { cssStyles: y } = t;
  if (t.look === "handDrawn") {
    const x = G.svg(n), b = lS(0, 0, c, d, u, p, g), k = hS(0, p, c, d, u, p), w = Z(t, {}), S = x.path(b, w), L = x.path(k, w);
    n.insert(() => L, ":first-child").attr("class", "line"), m = n.insert(() => S, ":first-child"), m.attr("class", "basic label-container"), y && m.attr("style", y);
  } else {
    const x = nS(0, 0, c, d, u, p, g);
    m = n.insert("path", ":first-child").attr("d", x).attr("class", "basic label-container outer-path").attr("style", Rt(y)).attr("style", i);
  }
  return m.attr("label-offset-y", p), m.attr("transform", `translate(${-c / 2}, ${-(d / 2 + p)})`), Q(t, m), h.attr(
    "transform",
    `translate(${-(l.width / 2) - (l.x - (l.left ?? 0))}, ${-(l.height / 2) + p - (l.y - (l.top ?? 0))})`
  ), t.intersect = function(x) {
    const b = U.rect(t, x), k = b.x - (t.x ?? 0);
    if (u != 0 && (Math.abs(k) < (t.width ?? 0) / 2 || Math.abs(k) == (t.width ?? 0) / 2 && Math.abs(b.y - (t.y ?? 0)) > (t.height ?? 0) / 2 - p)) {
      let w = p * p * (1 - k * k / (u * u));
      w > 0 && (w = Math.sqrt(w)), w = p - w, x.y - (t.y ?? 0) > 0 && (w = -w), b.y += w;
    }
    return b;
  }, n;
}
f(rg, "linedCylinder");
async function ig(e, t) {
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.labelStyle = r;
  const s = t.padding ?? 0, o = t.look === "neo" ? 16 : s, a = t.look === "neo" ? 12 : s;
  if (t.width || t.height) {
    const w = t.width;
    t.width = (w ?? 0) * 10 / 11 - o * 2, t.width < 10 && (t.width = 10), t.height = ((t == null ? void 0 : t.height) ?? 0) - a * 2, t.height < 10 && (t.height = 10);
  }
  const { shapeSvg: n, bbox: l, label: h } = await at(e, t, it(t)), c = (t != null && t.width ? t == null ? void 0 : t.width : l.width) + (o ?? 0) * 2, u = (t != null && t.height ? t == null ? void 0 : t.height : l.height) + (a ?? 0) * 2, p = t.look === "neo" ? u / 4 : u / 8, d = u + p, { cssStyles: g } = t, m = G.svg(n), y = Z(t, {});
  t.look !== "handDrawn" && (y.roughness = 0, y.fillStyle = "solid");
  const x = [
    { x: -c / 2 - c / 2 * 0.1, y: -d / 2 },
    { x: -c / 2 - c / 2 * 0.1, y: d / 2 },
    ...or(
      -c / 2 - c / 2 * 0.1,
      d / 2,
      c / 2 + c / 2 * 0.1,
      d / 2,
      p,
      0.8
    ),
    { x: c / 2 + c / 2 * 0.1, y: -d / 2 },
    { x: -c / 2 - c / 2 * 0.1, y: -d / 2 },
    { x: -c / 2, y: -d / 2 },
    { x: -c / 2, y: d / 2 * 1.1 },
    { x: -c / 2, y: -d / 2 }
  ], b = m.polygon(
    x.map((w) => [w.x, w.y]),
    y
  ), k = n.insert(() => b, ":first-child");
  return k.attr("class", "basic label-container outer-path"), g && t.look !== "handDrawn" && k.selectAll("path").attr("style", g), i && t.look !== "handDrawn" && k.selectAll("path").attr("style", i), k.attr("transform", `translate(0,${-p / 2})`), h.attr(
    "transform",
    `translate(${-c / 2 + (t.padding ?? 0) + c / 2 * 0.1 / 2 - (l.x - (l.left ?? 0))},${-u / 2 + (t.padding ?? 0) - p / 2 - (l.y - (l.top ?? 0))})`
  ), Q(t, k), t.intersect = function(w) {
    return U.polygon(t, x, w);
  }, n;
}
f(ig, "linedWaveEdgedRect");
async function sg(e, t) {
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.labelStyle = r;
  const s = t.padding ?? 0, o = t.look === "neo" ? 16 : s, a = t.look === "neo" ? 12 : s, n = t.look === "neo" ? 10 : 5;
  (t.width || t.height) && (t.width = Math.max(((t == null ? void 0 : t.width) ?? 0) - o * 2 - 2 * n, 10), t.height = Math.max(((t == null ? void 0 : t.height) ?? 0) - a * 2 - 2 * n, 10));
  const { shapeSvg: l, bbox: h, label: c } = await at(e, t, it(t)), u = (t != null && t.width ? t == null ? void 0 : t.width : h.width) + o * 2 + 2 * n, p = (t != null && t.height ? t == null ? void 0 : t.height : h.height) + a * 2 + 2 * n, d = u - 2 * n, g = p - 2 * n, m = -d / 2, y = -g / 2, { cssStyles: x } = t, b = G.svg(l), k = Z(t, {}), w = [
    { x: m - n, y: y + n },
    { x: m - n, y: y + g + n },
    { x: m + d - n, y: y + g + n },
    { x: m + d - n, y: y + g },
    { x: m + d, y: y + g },
    { x: m + d, y: y + g - n },
    { x: m + d + n, y: y + g - n },
    { x: m + d + n, y: y - n },
    { x: m + n, y: y - n },
    { x: m + n, y },
    { x: m, y },
    { x: m, y: y + n }
  ], S = [
    { x: m, y: y + n },
    { x: m + d - n, y: y + n },
    { x: m + d - n, y: y + g },
    { x: m + d, y: y + g },
    { x: m + d, y },
    { x: m, y }
  ];
  t.look !== "handDrawn" && (k.roughness = 0, k.fillStyle = "solid");
  const L = pt(w);
  let T = b.path(L, k);
  const B = pt(S);
  let N = b.path(B, k);
  t.look !== "handDrawn" && (T = en(T), N = en(N));
  const O = l.insert("g", ":first-child");
  return O.insert(() => T), O.insert(() => N), O.attr("class", "basic label-container outer-path"), x && t.look !== "handDrawn" && O.selectAll("path").attr("style", x), i && t.look !== "handDrawn" && O.selectAll("path").attr("style", i), c.attr(
    "transform",
    `translate(${-(h.width / 2) - n - (h.x - (h.left ?? 0))}, ${-(h.height / 2) + n - (h.y - (h.top ?? 0))})`
  ), Q(t, O), t.intersect = function(F) {
    return U.polygon(t, w, F);
  }, l;
}
f(sg, "multiRect");
async function og(e, t) {
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.labelStyle = r;
  const { shapeSvg: s, bbox: o, label: a } = await at(e, t, it(t)), n = t.padding ?? 0, l = t.look === "neo" ? 16 : n, h = t.look === "neo" ? 12 : n;
  let c = !0;
  (t.width || t.height) && (c = !1, t.width = ((t == null ? void 0 : t.width) ?? 0) - l * 2, t.height = ((t == null ? void 0 : t.height) ?? 0) - h * 3);
  const u = Math.max(o.width, (t == null ? void 0 : t.width) ?? 0) + l * 2, p = Math.max(o.height, (t == null ? void 0 : t.height) ?? 0) + h * 3, d = t.look === "neo" ? p / 4 : p / 8, g = p + (c ? d / 2 : -d / 2), m = -u / 2, y = -g / 2, x = 10, { cssStyles: b } = t, k = or(
    m - x,
    y + g + x,
    m + u - x,
    y + g + x,
    d,
    0.8
  ), w = k == null ? void 0 : k[k.length - 1], S = [
    { x: m - x, y: y + x },
    { x: m - x, y: y + g + x },
    ...k,
    { x: m + u - x, y: w.y - x },
    { x: m + u, y: w.y - x },
    { x: m + u, y: w.y - 2 * x },
    { x: m + u + x, y: w.y - 2 * x },
    { x: m + u + x, y: y - x },
    { x: m + x, y: y - x },
    { x: m + x, y },
    { x: m, y },
    { x: m, y: y + x }
  ], L = [
    { x: m, y: y + x },
    { x: m + u - x, y: y + x },
    { x: m + u - x, y: w.y - x },
    { x: m + u, y: w.y - x },
    { x: m + u, y },
    { x: m, y }
  ], T = G.svg(s), B = Z(t, {});
  t.look !== "handDrawn" && (B.roughness = 0, B.fillStyle = "solid");
  const N = pt(S), O = T.path(N, B), F = pt(L), Y = T.path(F, B), H = s.insert(() => O, ":first-child");
  return H.insert(() => Y), H.attr("class", "basic label-container outer-path"), b && t.look !== "handDrawn" && H.selectAll("path").attr("style", b), i && t.look !== "handDrawn" && H.selectAll("path").attr("style", i), H.attr("transform", `translate(0,${-d / 2})`), a.attr(
    "transform",
    `translate(${-(o.width / 2) - x - (o.x - (o.left ?? 0))}, ${-(o.height / 2) + x - d / 2 - (o.y - (o.top ?? 0))})`
  ), Q(t, H), t.intersect = function(P) {
    return U.polygon(t, S, P);
  }, s;
}
f(og, "multiWaveEdgedRectangle");
async function ag(e, t, { config: { themeVariables: r } }) {
  const { labelStyles: i, nodeStyles: s } = K(t);
  t.labelStyle = i, t.useHtmlLabels || Kt(wt()) || (t.centerLabel = !0);
  const { shapeSvg: a, bbox: n, label: l } = await at(e, t, it(t)), h = Math.max(n.width + (t.padding ?? 0) * 2, (t == null ? void 0 : t.width) ?? 0), c = Math.max(n.height + (t.padding ?? 0) * 2, (t == null ? void 0 : t.height) ?? 0), u = -h / 2, p = -c / 2, { cssStyles: d } = t, g = G.svg(a), m = Z(t, {
    fill: r.noteBkgColor,
    stroke: r.noteBorderColor
  });
  t.look !== "handDrawn" && (m.roughness = 0, m.fillStyle = "solid");
  const y = g.rectangle(u, p, h, c, m), x = a.insert(() => y, ":first-child");
  return x.attr("class", "basic label-container outer-path"), l.attr("class", "label noteLabel"), d && t.look !== "handDrawn" && x.selectAll("path").attr("style", d), s && t.look !== "handDrawn" && x.selectAll("path").attr("style", s), l.attr(
    "transform",
    `translate(${-n.width / 2 - (n.x - (n.left ?? 0))}, ${-(n.height / 2) - (n.y - (n.top ?? 0))})`
  ), Q(t, x), t.intersect = function(b) {
    return U.rect(t, b);
  }, a;
}
f(ag, "note");
var cS = /* @__PURE__ */ f((e, t, r) => [
  `M${e + r / 2},${t}`,
  `L${e + r},${t - r / 2}`,
  `L${e + r / 2},${t - r}`,
  `L${e},${t - r / 2}`,
  "Z"
].join(" "), "createDecisionBoxPathD");
async function ng(e, t) {
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.labelStyle = r;
  const { shapeSvg: s, bbox: o } = await at(e, t, it(t)), a = o.width + (t.padding ?? 0), n = o.height + (t.padding ?? 0), l = a + n, h = 0.5, c = [
    { x: l / 2, y: 0 },
    { x: l, y: -l / 2 },
    { x: l / 2, y: -l },
    { x: 0, y: -l / 2 }
  ];
  let u;
  const { cssStyles: p } = t;
  if (t.look === "handDrawn") {
    const d = G.svg(s), g = Z(t, {}), m = cS(0, 0, l), y = d.path(m, g);
    u = s.insert(() => y, ":first-child").attr("transform", `translate(${-l / 2 + h}, ${l / 2})`), p && u.attr("style", p);
  } else
    u = Ke(s, l, l, c), u.attr("transform", `translate(${-l / 2 + h}, ${l / 2})`);
  return i && u.attr("style", i), Q(t, u), t.calcIntersect = function(d, g) {
    const m = d.width, y = [
      { x: m / 2, y: 0 },
      { x: m, y: -m / 2 },
      { x: m / 2, y: -m },
      { x: 0, y: -m / 2 }
    ], x = U.polygon(d, y, g);
    return { x: x.x - 0.5, y: x.y - 0.5 };
  }, t.intersect = function(d) {
    return this.calcIntersect(t, d);
  }, s;
}
f(ng, "question");
async function lg(e, t) {
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.labelStyle = r;
  const s = t.padding ?? 0, o = t.look === "neo" ? 21 : s ?? 0, a = t.look === "neo" ? 12 : s ?? 0, { shapeSvg: n, bbox: l, label: h } = await at(e, t, it(t)), c = ((t == null ? void 0 : t.width) ?? l.width) + (t.look === "neo" ? o * 2 : o), u = ((t == null ? void 0 : t.height) ?? l.height) + (t.look === "neo" ? a * 2 : a), p = -c / 2, d = -u / 2, g = d / 2, m = [
    { x: p + g, y: d },
    { x: p, y: 0 },
    { x: p + g, y: -d },
    { x: -p, y: -d },
    { x: -p, y: d }
  ], { cssStyles: y } = t, x = G.svg(n), b = Z(t, {});
  t.look !== "handDrawn" && (b.roughness = 0, b.fillStyle = "solid");
  const k = pt(m), w = x.path(k, b), S = n.insert(() => w, ":first-child");
  return S.attr("class", "basic label-container outer-path"), y && t.look !== "handDrawn" && S.selectAll("path").attr("style", y), i && t.look !== "handDrawn" && S.selectAll("path").attr("style", i), S.attr("transform", `translate(${-g / 2},0)`), h.attr(
    "transform",
    `translate(${-g / 2 - l.width / 2 - (l.x - (l.left ?? 0))}, ${-(l.height / 2) - (l.y - (l.top ?? 0))})`
  ), Q(t, S), t.intersect = function(L) {
    return U.polygon(t, m, L);
  }, n;
}
f(lg, "rect_left_inv_arrow");
async function hg(e, t) {
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.labelStyle = r;
  let s;
  t.cssClasses ? s = "node " + t.cssClasses : s = "node default";
  const o = e.insert("g").attr("class", s).attr("id", t.domId || t.id), a = o.insert("g"), n = o.insert("g").attr("class", "label").attr("style", i), l = t.description, h = t.label, c = await tr(n, h, t.labelStyle, !0, !0);
  let u = { width: 0, height: 0 };
  if (Kt(gt())) {
    const B = c.children[0], N = ct(c);
    u = B.getBoundingClientRect(), N.attr("width", u.width), N.attr("height", u.height);
  }
  q.info("Text 2", l);
  const p = l || [], d = c.getBBox(), g = await tr(
    n,
    Array.isArray(p) ? p.join("<br/>") : p,
    t.labelStyle,
    !0,
    !0
  ), m = g.children[0], y = ct(g);
  u = m.getBoundingClientRect(), y.attr("width", u.width), y.attr("height", u.height);
  const x = (t.padding || 0) / 2;
  ct(g).attr(
    "transform",
    "translate( " + (u.width > d.width ? 0 : (d.width - u.width) / 2) + ", " + (d.height + x + 5) + ")"
  ), ct(c).attr(
    "transform",
    "translate( " + (u.width < d.width ? 0 : -(d.width - u.width) / 2) + ", 0)"
  ), u = n.node().getBBox(), n.attr(
    "transform",
    "translate(" + -u.width / 2 + ", " + (-u.height / 2 - x + 3) + ")"
  );
  const b = u.width + (t.padding || 0), k = u.height + (t.padding || 0), w = -u.width / 2 - x, S = -u.height / 2 - x;
  let L, T;
  if (t.look === "handDrawn") {
    const B = G.svg(o), N = Z(t, {}), O = B.path(
      ar(w, S, b, k, t.rx || 0),
      N
    ), F = B.line(
      -u.width / 2 - x,
      -u.height / 2 - x + d.height + x,
      u.width / 2 + x,
      -u.height / 2 - x + d.height + x,
      N
    );
    T = o.insert(() => (q.debug("Rough node insert CXC", O), F), ":first-child"), L = o.insert(() => (q.debug("Rough node insert CXC", O), O), ":first-child");
  } else
    L = a.insert("rect", ":first-child"), T = a.insert("line"), L.attr("class", "outer title-state").attr("style", i).attr("x", -u.width / 2 - x).attr("y", -u.height / 2 - x).attr("width", u.width + (t.padding || 0)).attr("height", u.height + (t.padding || 0)), T.attr("class", "divider").attr("x1", -u.width / 2 - x).attr("x2", u.width / 2 + x).attr("y1", -u.height / 2 - x + d.height + x).attr("y2", -u.height / 2 - x + d.height + x);
  return Q(t, L), t.intersect = function(B) {
    return U.rect(t, B);
  }, o;
}
f(hg, "rectWithTitle");
async function cg(e, t, { config: { themeVariables: r } }) {
  const i = (r == null ? void 0 : r.radius) ?? 5, s = {
    rx: i,
    ry: i,
    labelPaddingX: ((t == null ? void 0 : t.padding) ?? 0) * 1,
    labelPaddingY: ((t == null ? void 0 : t.padding) ?? 0) * 1
  };
  return fs(e, t, s);
}
f(cg, "roundedRect");
var cr = 8;
async function ug(e, t) {
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.labelStyle = r;
  const s = t.look === "neo" ? 16 : t.padding ?? 0, o = t.look === "neo" ? 12 : t.padding ?? 0, { shapeSvg: a, bbox: n, label: l } = await at(e, t, it(t)), h = ((t == null ? void 0 : t.width) ?? n.width) + s * 2 + (t.look === "neo" ? cr : cr * 2), c = ((t == null ? void 0 : t.height) ?? n.height) + o * 2, u = h - cr, p = c, d = cr - h / 2, g = -c / 2, { cssStyles: m } = t, y = G.svg(a), x = Z(t, {});
  t.look !== "handDrawn" && (x.roughness = 0, x.fillStyle = "solid");
  const b = [
    { x: d, y: g },
    { x: d + u, y: g },
    { x: d + u, y: g + p },
    { x: d - cr, y: g + p },
    { x: d - cr, y: g },
    { x: d, y: g },
    { x: d, y: g + p }
  ], k = y.polygon(
    b.map((S) => [S.x, S.y]),
    x
  ), w = a.insert(() => k, ":first-child");
  return w.attr("class", "basic label-container outer-path").attr("style", Rt(m)), i && t.look !== "handDrawn" && w.selectAll("path").attr("style", i), m && t.look !== "handDrawn" && w.selectAll("path").attr("style", i), l.attr(
    "transform",
    `translate(${cr / 2 - n.width / 2 - (n.x - (n.left ?? 0))}, ${-(n.height / 2) - (n.y - (n.top ?? 0))})`
  ), Q(t, w), t.intersect = function(S) {
    return U.rect(t, S);
  }, a;
}
f(ug, "shadedProcess");
async function dg(e, t) {
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.labelStyle = r;
  const s = t.padding ?? 0, o = t.look === "neo" ? 16 : s, a = t.look === "neo" ? 12 : s;
  (t.width || t.height) && (t.width = Math.max(((t == null ? void 0 : t.width) ?? 0) - o * 2, 10), t.height = Math.max(((t == null ? void 0 : t.height) ?? 0) / 1.5 - a * 2, 10));
  const { shapeSvg: n, bbox: l, label: h } = await at(e, t, it(t)), c = (t != null && t.width ? t == null ? void 0 : t.width : l.width) + o * 2, u = ((t != null && t.height ? t == null ? void 0 : t.height : l.height) + a * 2) * 1.5, p = c, d = u / 1.5, g = -p / 2, m = -d / 2, { cssStyles: y } = t, x = G.svg(n), b = Z(t, {});
  t.look !== "handDrawn" && (b.roughness = 0, b.fillStyle = "solid");
  const k = [
    { x: g, y: m },
    { x: g, y: m + d },
    { x: g + p, y: m + d },
    { x: g + p, y: m - d / 2 }
  ], w = pt(k), S = x.path(w, b), L = n.insert(() => S, ":first-child");
  return L.attr("class", "basic label-container  outer-path"), y && t.look !== "handDrawn" && L.selectChildren("path").attr("style", y), i && t.look !== "handDrawn" && L.selectChildren("path").attr("style", i), L.attr("transform", `translate(0, ${d / 4})`), h.attr(
    "transform",
    `translate(${-p / 2 + (t.padding ?? 0) - (l.x - (l.left ?? 0))}, ${-d / 4 + (t.padding ?? 0) - (l.y - (l.top ?? 0))})`
  ), Q(t, L), t.intersect = function(T) {
    return U.polygon(t, k, T);
  }, n;
}
f(dg, "slopedRect");
async function pg(e, t) {
  const r = t.padding ?? 0, i = t.look === "neo" ? 16 : r * 2, s = t.look === "neo" ? 12 : r, o = {
    rx: 0,
    ry: 0,
    labelPaddingX: t.labelPaddingX ?? i,
    labelPaddingY: s
  };
  return fs(e, t, o);
}
f(pg, "squareRect");
async function fg(e, t) {
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.labelStyle = r;
  const s = t.padding ?? 0, o = t.look === "neo" ? 20 : s, a = t.look === "neo" ? 12 : s, { shapeSvg: n, bbox: l } = await at(e, t, it(t)), h = l.height + (t.look === "neo" ? a * 2 : a), c = l.width + h / 4 + (t.look === "neo" ? o * 2 : o), u = h / 2, { cssStyles: p } = t, d = G.svg(n), g = Z(t, {});
  t.look !== "handDrawn" && (g.roughness = 0, g.fillStyle = "solid");
  const m = [
    { x: -c / 2 + u, y: -h / 2 },
    { x: c / 2 - u, y: -h / 2 },
    ...rs(-c / 2 + u, 0, u, 50, 90, 270),
    { x: c / 2 - u, y: h / 2 },
    ...rs(c / 2 - u, 0, u, 50, 270, 450)
  ], y = pt(m), x = d.path(y, g), b = n.insert(() => x, ":first-child");
  return b.attr("class", "basic label-container outer-path"), p && t.look !== "handDrawn" && b.selectChildren("path").attr("style", p), i && t.look !== "handDrawn" && b.selectChildren("path").attr("style", i), Q(t, b), t.intersect = function(k) {
    return U.polygon(t, m, k);
  }, n;
}
f(fg, "stadium");
async function gg(e, t) {
  const r = {
    rx: t.look === "neo" ? 3 : 5,
    ry: t.look === "neo" ? 3 : 5
  };
  return fs(e, t, r);
}
f(gg, "state");
function mg(e, t, { config: { themeVariables: r } }) {
  var b, k;
  const { labelStyles: i, nodeStyles: s } = K(t);
  t.labelStyle = i;
  const { cssStyles: o } = t, { lineColor: a, stateBorder: n, nodeBorder: l, nodeShadow: h } = r;
  (t.width || t.height) && ((t.width ?? 0) < 14 && (t.width = 14), (t.height ?? 0) < 14 && (t.height = 14)), t.width || (t.width = 14), t.height || (t.height = 14);
  const c = e.insert("g").attr("class", "node default").attr("id", t.domId ?? t.id), u = G.svg(c), p = Z(t, {});
  t.look !== "handDrawn" && (p.roughness = 0, p.fillStyle = "solid");
  const d = u.circle(0, 0, t.width, {
    ...p,
    stroke: a,
    strokeWidth: 2
  }), g = n ?? l, m = (t.width ?? 0) * 5 / 14, y = u.circle(0, 0, m, {
    ...p,
    fill: g,
    stroke: g,
    strokeWidth: 2,
    fillStyle: "solid"
  }), x = c.insert(() => d, ":first-child");
  if (x.insert(() => y), t.look !== "handDrawn" && x.attr("class", "outer-path"), o && x.selectAll("path").attr("style", o), s && x.selectAll("path").attr("style", s), t.width < 25 && h && t.look !== "handDrawn") {
    const w = ((k = (b = e.node()) == null ? void 0 : b.ownerSVGElement) == null ? void 0 : k.id) ?? "", S = w ? `${w}-drop-shadow-small` : "drop-shadow-small";
    x.attr("style", `filter:url(#${S})`);
  }
  return Q(t, x), t.intersect = function(w) {
    return U.circle(t, (t.width ?? 0) / 2, w);
  }, c;
}
f(mg, "stateEnd");
function yg(e, t, { config: { themeVariables: r } }) {
  var n, l;
  const { lineColor: i, nodeShadow: s } = r;
  (t.width || t.height) && ((t.width ?? 0) < 14 && (t.width = 14), (t.height ?? 0) < 14 && (t.height = 14)), t.width || (t.width = 14), t.height || (t.height = 14);
  const o = e.insert("g").attr("class", "node default").attr("id", t.domId || t.id);
  let a;
  if (t.look === "handDrawn") {
    const c = G.svg(o).circle(0, 0, t.width, O2(i));
    a = o.insert(() => c), a.attr("class", "state-start").attr("r", (t.width ?? 7) / 2).attr("width", t.width ?? 14).attr("height", t.height ?? 14);
  } else
    a = o.insert("circle", ":first-child"), a.attr("class", "state-start").attr("r", (t.width ?? 7) / 2).attr("width", t.width ?? 14).attr("height", t.height ?? 14);
  if (t.width < 25 && s && t.look !== "handDrawn") {
    const h = ((l = (n = e.node()) == null ? void 0 : n.ownerSVGElement) == null ? void 0 : l.id) ?? "", c = h ? `${h}-drop-shadow-small` : "drop-shadow-small";
    a.attr("style", `filter:url(#${c})`);
  }
  return Q(t, a), t.intersect = function(h) {
    return U.circle(t, (t.width ?? 7) / 2, h);
  }, o;
}
f(yg, "stateStart");
var Dr = 8;
async function xg(e, t) {
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.labelStyle = r;
  const s = (t == null ? void 0 : t.padding) ?? 8, o = t.look === "neo" ? 28 : s, a = t.look === "neo" ? 12 : s, { shapeSvg: n, bbox: l } = await at(e, t, it(t)), h = ((t == null ? void 0 : t.width) ?? l.width) + 2 * Dr + o, c = ((t == null ? void 0 : t.height) ?? l.height) + a, u = h - 2 * Dr, p = c, d = -h / 2, g = -c / 2, m = [
    { x: 0, y: 0 },
    { x: u, y: 0 },
    { x: u, y: -p },
    { x: 0, y: -p },
    { x: 0, y: 0 },
    { x: -8, y: 0 },
    { x: u + 8, y: 0 },
    { x: u + 8, y: -p },
    { x: -8, y: -p },
    { x: -8, y: 0 }
  ];
  if (t.look === "handDrawn") {
    const y = G.svg(n), x = Z(t, {}), b = y.rectangle(d, g, u + 16, p, x), k = y.line(d + Dr, g, d + Dr, g + p, x), w = y.line(d + Dr + u, g, d + Dr + u, g + p, x);
    n.insert(() => k, ":first-child"), n.insert(() => w, ":first-child");
    const S = n.insert(() => b, ":first-child"), { cssStyles: L } = t;
    S.attr("class", "basic label-container").attr("style", Rt(L)), Q(t, S);
  } else {
    const y = Ke(n, u, p, m);
    i && y.attr("style", i), Q(t, y);
  }
  return t.intersect = function(y) {
    return U.polygon(t, m, y);
  }, n;
}
f(xg, "subroutine");
var la = 0.2;
async function Cg(e, t) {
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.labelStyle = r;
  const s = t.padding ?? 0, o = t.look === "neo" ? 16 : s, a = t.look === "neo" ? 12 : s;
  (t.width || t.height) && (t.height = Math.max(((t == null ? void 0 : t.height) ?? 0) - a * 2, 10), t.width = Math.max(
    ((t == null ? void 0 : t.width) ?? 0) - o * 2 - la * (t.height + a * 2),
    10
  ));
  const { shapeSvg: n, bbox: l } = await at(e, t, it(t)), h = (t != null && t.height ? t == null ? void 0 : t.height : l.height) + a * 2, c = la * h, u = la * h, d = (t != null && t.width ? t == null ? void 0 : t.width : l.width) + o * 2 + c - c, g = h, m = -d / 2, y = -g / 2, { cssStyles: x } = t, b = G.svg(n), k = Z(t, {}), w = [
    { x: m - c / 2, y },
    { x: m + d + c / 2, y },
    { x: m + d + c / 2, y: y + g },
    { x: m - c / 2, y: y + g }
  ], S = [
    { x: m + d - c / 2, y: y + g },
    { x: m + d + c / 2, y: y + g },
    { x: m + d + c / 2, y: y + g - u }
  ];
  t.look !== "handDrawn" && (k.roughness = 0, k.fillStyle = "solid");
  const L = pt(w), T = b.path(L, k), B = pt(S), N = b.path(B, { ...k, fillStyle: "solid" }), O = n.insert(() => N, ":first-child");
  return O.insert(() => T, ":first-child"), O.attr("class", "basic label-container outer-path"), x && t.look !== "handDrawn" && O.selectAll("path").attr("style", x), i && t.look !== "handDrawn" && O.selectAll("path").attr("style", i), Q(t, O), t.intersect = function(F) {
    return U.polygon(t, w, F);
  }, n;
}
f(Cg, "taggedRect");
async function bg(e, t) {
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.labelStyle = r;
  const { shapeSvg: s, bbox: o, label: a } = await at(e, t, it(t)), n = Math.max(o.width + (t.padding ?? 0) * 2, (t == null ? void 0 : t.width) ?? 0), l = Math.max(o.height + (t.padding ?? 0) * 2, (t == null ? void 0 : t.height) ?? 0), h = l / 8, c = 0.2 * n, u = 0.2 * l, p = l + h, { cssStyles: d } = t, g = G.svg(s), m = Z(t, {});
  t.look !== "handDrawn" && (m.roughness = 0, m.fillStyle = "solid");
  const y = [
    { x: -n / 2 - n / 2 * 0.1, y: p / 2 },
    ...or(
      -n / 2 - n / 2 * 0.1,
      p / 2,
      n / 2 + n / 2 * 0.1,
      p / 2,
      h,
      0.8
    ),
    { x: n / 2 + n / 2 * 0.1, y: -p / 2 },
    { x: -n / 2 - n / 2 * 0.1, y: -p / 2 }
  ], x = -n / 2 + n / 2 * 0.1, b = -p / 2 - u * 0.4, k = [
    { x: x + n - c, y: (b + l) * 1.3 },
    { x: x + n, y: b + l - u },
    { x: x + n, y: (b + l) * 0.9 },
    ...or(
      x + n,
      (b + l) * 1.25,
      x + n - c,
      (b + l) * 1.3,
      -l * 0.02,
      0.5
    )
  ], w = pt(y), S = g.path(w, m), L = pt(k), T = g.path(L, {
    ...m,
    fillStyle: "solid"
  }), B = s.insert(() => T, ":first-child");
  return B.insert(() => S, ":first-child"), B.attr("class", "basic label-container outer-path"), d && t.look !== "handDrawn" && B.selectAll("path").attr("style", d), i && t.look !== "handDrawn" && B.selectAll("path").attr("style", i), B.attr("transform", `translate(0,${-h / 2})`), a.attr(
    "transform",
    `translate(${-n / 2 + (t.padding ?? 0) - (o.x - (o.left ?? 0))},${-l / 2 + (t.padding ?? 0) - h / 2 - (o.y - (o.top ?? 0))})`
  ), Q(t, B), t.intersect = function(N) {
    return U.polygon(t, y, N);
  }, s;
}
f(bg, "taggedWaveEdgedRectangle");
async function kg(e, t) {
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.labelStyle = r;
  const { shapeSvg: s, bbox: o } = await at(e, t, it(t)), a = Math.max(o.width + (t.padding ?? 0), (t == null ? void 0 : t.width) || 0), n = Math.max(o.height + (t.padding ?? 0), (t == null ? void 0 : t.height) || 0), l = -a / 2, h = -n / 2, c = s.insert("rect", ":first-child");
  return c.attr("class", "text").attr("style", i).attr("rx", 0).attr("ry", 0).attr("x", l).attr("y", h).attr("width", a).attr("height", n), Q(t, c), t.intersect = function(u) {
    return U.rect(t, u);
  }, s;
}
f(kg, "text");
var uS = /* @__PURE__ */ f((e, t, r, i, s, o) => `M${e},${t}
    a${s},${o} 0,0,1 0,${-i}
    l${r},0
    a${s},${o} 0,0,1 0,${i}
    M${r},${-i}
    a${s},${o} 0,0,0 0,${i}
    l${-r},0`, "createCylinderPathD"), dS = /* @__PURE__ */ f((e, t, r, i, s, o) => [
  `M${e},${t}`,
  `M${e + r},${t}`,
  `a${s},${o} 0,0,0 0,${-i}`,
  `l${-r},0`,
  `a${s},${o} 0,0,0 0,${i}`,
  `l${r},0`
].join(" "), "createOuterCylinderPathD"), pS = /* @__PURE__ */ f((e, t, r, i, s, o) => [`M${e + r / 2},${-i / 2}`, `a${s},${o} 0,0,0 0,${i}`].join(" "), "createInnerCylinderPathD"), Zh = 5, Kh = 10;
async function Tg(e, t) {
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.labelStyle = r;
  const s = t.padding ?? 0, o = t.look === "neo" ? 12 : s / 2;
  if (t.width || t.height) {
    const m = t.height ?? 0;
    t.height = (t.height ?? 0) - o, t.height < Zh && (t.height = Zh);
    const x = m / 2 / (2.5 + m / 50);
    t.width = (t.width ?? 0) - o - x * 3, t.width < Kh && (t.width = Kh);
  }
  const { shapeSvg: a, bbox: n, label: l } = await at(e, t, it(t)), h = (t.height ? t.height : n.height) + o, c = h / 2, u = c / (2.5 + h / 50), p = (t.width ? t.width : n.width) + u + o, { cssStyles: d } = t;
  let g;
  if (t.look === "handDrawn") {
    const m = G.svg(a), y = dS(0, 0, p, h, u, c), x = pS(0, 0, p, h, u, c), b = m.path(y, Z(t, {})), k = m.path(x, Z(t, { fill: "none" }));
    g = a.insert(() => k, ":first-child"), g = a.insert(() => b, ":first-child"), g.attr("class", "basic label-container"), d && g.attr("style", d);
  } else {
    const m = uS(0, 0, p, h, u, c);
    g = a.insert("path", ":first-child").attr("d", m).attr("class", "basic label-container").attr("style", Rt(d)).attr("style", i), g.attr("class", "basic label-container outer-path"), d && g.selectAll("path").attr("style", d), i && g.selectAll("path").attr("style", i);
  }
  return g.attr("label-offset-x", u), g.attr("transform", `translate(${-p / 2}, ${h / 2} )`), l.attr(
    "transform",
    `translate(${-(n.width / 2) - u - (n.x - (n.left ?? 0))}, ${-(n.height / 2) - (n.y - (n.top ?? 0))})`
  ), Q(t, g), t.intersect = function(m) {
    const y = U.rect(t, m), x = y.y - (t.y ?? 0);
    if (c != 0 && (Math.abs(x) < (t.height ?? 0) / 2 || Math.abs(x) == (t.height ?? 0) / 2 && Math.abs(y.x - (t.x ?? 0)) > (t.width ?? 0) / 2 - u)) {
      let b = u * u * (1 - x * x / (c * c));
      b != 0 && (b = Math.sqrt(Math.abs(b))), b = u - b, m.x - (t.x ?? 0) > 0 && (b = -b), y.x += b;
    }
    return y;
  }, a;
}
f(Tg, "tiltedCylinder");
async function Sg(e, t) {
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.labelStyle = r;
  const s = t.padding ?? 0, o = (t.look === "neo", s), a = t.look === "neo" ? s * 2 : s, { shapeSvg: n, bbox: l } = await at(e, t, it(t)), h = ((t == null ? void 0 : t.height) ?? l.height) + o, c = ((t == null ? void 0 : t.width) ?? l.width) + a, u = [
    { x: -3 * h / 6, y: 0 },
    { x: c + 3 * h / 6, y: 0 },
    { x: c, y: -h },
    { x: 0, y: -h }
  ];
  let p;
  const { cssStyles: d } = t;
  if (t.look === "handDrawn") {
    const g = G.svg(n), m = Z(t, {}), y = pt(u), x = g.path(y, m);
    p = n.insert(() => x, ":first-child").attr("transform", `translate(${-c / 2}, ${h / 2})`), d && p.attr("style", d);
  } else
    p = Ke(n, c, h, u);
  return i && p.attr("style", i), t.width = c, t.height = h, Q(t, p), t.intersect = function(g) {
    return U.polygon(t, u, g);
  }, n;
}
f(Sg, "trapezoid");
async function wg(e, t) {
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.labelStyle = r;
  const s = t.padding ?? 0, o = t.look === "neo" ? 16 : s, a = t.look === "neo" ? 12 : s, n = 15, l = 5;
  (t.width || t.height) && (t.height = (t.height ?? 0) - a * 2, t.height < l && (t.height = l), t.width = (t.width ?? 0) - o * 2, t.width < n && (t.width = n));
  const { shapeSvg: h, bbox: c } = await at(e, t, it(t)), u = (t != null && t.width ? t == null ? void 0 : t.width : c.width) + o * 2, p = (t != null && t.height ? t == null ? void 0 : t.height : c.height) + a * 2, { cssStyles: d } = t, g = G.svg(h), m = Z(t, {});
  t.look !== "handDrawn" && (m.roughness = 0, m.fillStyle = "solid");
  const y = [
    { x: -u / 2 * 0.8, y: -p / 2 },
    { x: u / 2 * 0.8, y: -p / 2 },
    { x: u / 2, y: -p / 2 * 0.6 },
    { x: u / 2, y: p / 2 },
    { x: -u / 2, y: p / 2 },
    { x: -u / 2, y: -p / 2 * 0.6 }
  ], x = pt(y), b = g.path(x, m), k = h.insert(() => b, ":first-child");
  return k.attr("class", "basic label-container outer-path"), d && t.look !== "handDrawn" && k.selectChildren("path").attr("style", d), i && t.look !== "handDrawn" && k.selectChildren("path").attr("style", i), Q(t, k), t.intersect = function(w) {
    return U.polygon(t, y, w);
  }, h;
}
f(wg, "trapezoidalPentagon");
var Qh = 10, Jh = 10;
async function _g(e, t) {
  var w;
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.labelStyle = r;
  const s = t.padding ?? 0, o = t.look === "neo" ? s * 2 : s;
  (t.width || t.height) && (t.width = (((t == null ? void 0 : t.width) ?? 0) - o) / 2, t.width < Jh && (t.width = Jh), t.height = (t == null ? void 0 : t.height) ?? 0, t.height < Qh && (t.height = Qh));
  const { shapeSvg: a, bbox: n, label: l } = await at(e, t, it(t)), h = Ve((w = gt().flowchart) == null ? void 0 : w.htmlLabels), c = (t != null && t.width ? t == null ? void 0 : t.width : n.width) + o, u = t != null && t.height ? t == null ? void 0 : t.height : c + n.height, p = u, d = [
    { x: 0, y: 0 },
    { x: p, y: 0 },
    { x: p / 2, y: -u }
  ], { cssStyles: g } = t, m = G.svg(a), y = Z(t, {});
  t.look !== "handDrawn" && (y.roughness = 0, y.fillStyle = "solid");
  const x = pt(d), b = m.path(x, y), k = a.insert(() => b, ":first-child").attr("transform", `translate(${-u / 2}, ${u / 2})`).attr("class", "outer-path");
  return g && t.look !== "handDrawn" && k.selectChildren("path").attr("style", g), i && t.look !== "handDrawn" && k.selectChildren("path").attr("style", i), t.width = c, t.height = u, Q(t, k), l.attr(
    "transform",
    `translate(${-n.width / 2 - (n.x - (n.left ?? 0))}, ${u / 2 - (n.height + (t.padding ?? 0) / (h ? 2 : 1) - (n.y - (n.top ?? 0)))})`
  ), t.intersect = function(S) {
    return q.info("Triangle intersect", t, d, S), U.polygon(t, d, S);
  }, a;
}
f(_g, "triangle");
async function Bg(e, t) {
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.labelStyle = r;
  const s = t.padding ?? 0, o = t.look === "neo" ? 16 : s, a = t.look === "neo" ? 12 : s;
  let n = !0;
  (t.width || t.height) && (n = !1, t.width = ((t == null ? void 0 : t.width) ?? 0) - o * 2, t.width < 10 && (t.width = 10), t.height = ((t == null ? void 0 : t.height) ?? 0) - a * 2, t.height < 10 && (t.height = 10));
  const { shapeSvg: l, bbox: h, label: c } = await at(e, t, it(t)), u = (t != null && t.width ? t == null ? void 0 : t.width : h.width) + (o ?? 0) * 2, p = (t != null && t.height ? t == null ? void 0 : t.height : h.height) + (a ?? 0) * 2, d = t.look === "neo" ? p / 4 : p / 8, g = p + (n ? d : -d), { cssStyles: m } = t, x = 14 - u, b = x > 0 ? x / 2 : 0, k = G.svg(l), w = Z(t, {});
  t.look !== "handDrawn" && (w.roughness = 0, w.fillStyle = "solid");
  const S = [
    { x: -u / 2 - b, y: g / 2 },
    ...or(
      -u / 2 - b,
      g / 2,
      u / 2 + b,
      g / 2,
      d,
      0.8
    ),
    { x: u / 2 + b, y: -g / 2 },
    { x: -u / 2 - b, y: -g / 2 }
  ], L = pt(S), T = k.path(L, w), B = l.insert(() => T, ":first-child");
  return B.attr("class", "basic label-container outer-path"), m && t.look !== "handDrawn" && B.selectAll("path").attr("style", m), i && t.look !== "handDrawn" && B.selectAll("path").attr("style", i), B.attr("transform", `translate(0,${-d / 2})`), c.attr(
    "transform",
    `translate(${-u / 2 + (t.padding ?? 0) - (h.x - (h.left ?? 0))},${-p / 2 + (t.padding ?? 0) - d - (h.y - (h.top ?? 0))})`
  ), Q(t, B), t.intersect = function(N) {
    return U.polygon(t, S, N);
  }, l;
}
f(Bg, "waveEdgedRectangle");
async function vg(e, t) {
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.labelStyle = r;
  const s = t.padding ?? 0, o = t.look === "neo" ? 16 : s, a = t.look === "neo" ? 20 : s;
  if (t.width || t.height) {
    t.width = (t == null ? void 0 : t.width) ?? 0, t.width < 20 && (t.width = 20), t.height = (t == null ? void 0 : t.height) ?? 0, t.height < 10 && (t.height = 10);
    const w = Math.min(t.height * 0.2, t.height / 4);
    t.height = Math.ceil(t.height - a - w * (20 / 9)), t.width = t.width - o * 2;
  }
  const { shapeSvg: n, bbox: l } = await at(e, t, it(t)), h = (t != null && t.width ? t == null ? void 0 : t.width : l.width) + o * 2, c = (t != null && t.height ? t == null ? void 0 : t.height : l.height) + a, u = c / 8, p = c + u * 2, { cssStyles: d } = t, g = G.svg(n), m = Z(t, {});
  t.look !== "handDrawn" && (m.roughness = 0, m.fillStyle = "solid");
  const y = [
    { x: -h / 2, y: p / 2 },
    ...or(-h / 2, p / 2, h / 2, p / 2, u, 1),
    { x: h / 2, y: -p / 2 },
    ...or(h / 2, -p / 2, -h / 2, -p / 2, u, -1)
  ], x = pt(y), b = g.path(x, m), k = n.insert(() => b, ":first-child");
  return k.attr("class", "basic label-container"), d && t.look !== "handDrawn" && k.selectAll("path").attr("style", d), i && t.look !== "handDrawn" && k.selectAll("path").attr("style", i), Q(t, k), t.intersect = function(w) {
    return U.polygon(t, y, w);
  }, n;
}
f(vg, "waveRectangle");
var Bt = 10;
async function Lg(e, t) {
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.labelStyle = r;
  const s = t.look === "neo" ? 16 : t.padding ?? 0, o = t.look === "neo" ? 12 : t.padding ?? 0;
  (t.width || t.height) && (t.width = Math.max(((t == null ? void 0 : t.width) ?? 0) - s * 2 - Bt, 10), t.height = Math.max(((t == null ? void 0 : t.height) ?? 0) - o * 2 - Bt, 10));
  const { shapeSvg: a, bbox: n, label: l } = await at(e, t, it(t)), h = (t != null && t.width ? t == null ? void 0 : t.width : n.width) + s * 2 + Bt, c = (t != null && t.height ? t == null ? void 0 : t.height : n.height) + o * 2 + Bt, u = h - Bt, p = c - Bt, d = -u / 2, g = -p / 2, { cssStyles: m } = t, y = G.svg(a), x = Z(t, {}), b = [
    { x: d - Bt, y: g - Bt },
    { x: d - Bt, y: g + p },
    { x: d + u, y: g + p },
    { x: d + u, y: g - Bt }
  ], k = `M${d - Bt},${g - Bt} L${d + u},${g - Bt} L${d + u},${g + p} L${d - Bt},${g + p} L${d - Bt},${g - Bt}
                M${d - Bt},${g} L${d + u},${g}
                M${d},${g - Bt} L${d},${g + p}`;
  t.look !== "handDrawn" && (x.roughness = 0, x.fillStyle = "solid");
  const w = y.path(k, x), S = a.insert(() => w, ":first-child");
  return S.attr("transform", `translate(${Bt / 2}, ${Bt / 2})`), S.attr("class", "basic label-container outer-path"), m && t.look !== "handDrawn" && S.selectAll("path").attr("style", m), i && t.look !== "handDrawn" && S.selectAll("path").attr("style", i), l.attr(
    "transform",
    `translate(${-(n.width / 2) + Bt / 2 - (n.x - (n.left ?? 0))}, ${-(n.height / 2) + Bt / 2 - (n.y - (n.top ?? 0))})`
  ), Q(t, S), t.intersect = function(L) {
    return U.polygon(t, b, L);
  }, a;
}
f(Lg, "windowPane");
var tc = /* @__PURE__ */ new Set(["redux-color", "redux-dark-color"]), fS = /* @__PURE__ */ new Set(["redux", "redux-dark", "redux-color", "redux-dark-color"]);
async function hl(e, t) {
  var dt, xt, _t, se;
  const r = t;
  r.alias && (t.label = r.alias);
  const { theme: i, themeVariables: s } = wt(), { rowEven: o, rowOdd: a, nodeBorder: n, borderColorArray: l } = s;
  if (t.look === "handDrawn") {
    const { themeVariables: J } = wt(), { background: lt } = J, Ct = {
      ...t,
      id: t.id + "-background",
      domId: (t.domId || t.id) + "-background",
      look: "default",
      cssStyles: ["stroke: none", `fill: ${lt}`]
    };
    await hl(e, Ct);
  }
  const h = wt();
  t.useHtmlLabels = h.htmlLabels;
  let c = ((dt = h.er) == null ? void 0 : dt.diagramPadding) ?? 10, u = ((xt = h.er) == null ? void 0 : xt.entityPadding) ?? 6;
  const { cssStyles: p } = t, { labelStyles: d, nodeStyles: g } = K(t);
  if (r.attributes.length === 0 && t.label) {
    const J = {
      rx: 0,
      ry: 0,
      labelPaddingX: c,
      labelPaddingY: c * 1.5
    };
    je(t.label, h) + J.labelPaddingX * 2 < h.er.minEntityWidth && (t.width = h.er.minEntityWidth);
    const lt = await fs(e, t, J);
    if (i != null && tc.has(i)) {
      const Ct = r.colorIndex ?? 0;
      lt.attr("data-color-id", `color-${Ct % l.length}`);
    }
    if (!Ve(h.htmlLabels)) {
      const Ct = lt.select("text"), kt = (_t = Ct.node()) == null ? void 0 : _t.getBBox();
      Ct.attr("transform", `translate(${-kt.width / 2}, 0)`);
    }
    return lt;
  }
  h.htmlLabels || (c *= 1.25, u *= 1.25);
  let m = it(t);
  m || (m = "node default");
  const y = e.insert("g").attr("class", m).attr("id", t.domId || t.id), x = await qr(y, t.label ?? "", h, 0, 0, ["name"], d);
  x.height += u;
  let b = 0;
  const k = [], w = [];
  let S = 0, L = 0, T = 0, B = 0, N = !0, O = !0;
  for (const J of r.attributes) {
    const lt = await qr(
      y,
      J.type,
      h,
      0,
      b,
      ["attribute-type"],
      d
    );
    S = Math.max(S, lt.width + c);
    const Ct = await qr(
      y,
      J.name,
      h,
      0,
      b,
      ["attribute-name"],
      d
    );
    L = Math.max(L, Ct.width + c);
    const kt = await qr(
      y,
      J.keys.join(),
      h,
      0,
      b,
      ["attribute-keys"],
      d
    );
    T = Math.max(T, kt.width + c);
    const oe = await qr(
      y,
      J.comment,
      h,
      0,
      b,
      ["attribute-comment"],
      d
    );
    B = Math.max(B, oe.width + c);
    const Wt = Math.max(lt.height, Ct.height, kt.height, oe.height) + u;
    w.push({ yOffset: b, rowHeight: Wt }), b += Wt;
  }
  let F = 4;
  T <= c && (N = !1, T = 0, F--), B <= c && (O = !1, B = 0, F--);
  const Y = y.node().getBBox();
  if (x.width + c * 2 - (S + L + T + B) > 0) {
    const J = x.width + c * 2 - (S + L + T + B);
    S += J / F, L += J / F, T > 0 && (T += J / F), B > 0 && (B += J / F);
  }
  const H = S + L + T + B, P = G.svg(y), M = Z(t, {});
  t.look !== "handDrawn" && (M.roughness = 0, M.fillStyle = "solid");
  let E = 0;
  w.length > 0 && (E = w.reduce((J, lt) => J + ((lt == null ? void 0 : lt.rowHeight) ?? 0), 0));
  const D = Math.max(Y.width + c * 2, (t == null ? void 0 : t.width) || 0, H), v = Math.max((E ?? 0) + x.height, (t == null ? void 0 : t.height) || 0), R = -D / 2, z = -v / 2;
  if (y.selectAll("g:not(:first-child)").each((J, lt, Ct) => {
    const kt = ct(Ct[lt]), oe = kt.attr("transform");
    let Wt = 0, Er = 0;
    if (oe) {
      const ve = RegExp(/translate\(([^,]+),([^)]+)\)/).exec(oe);
      ve && (Wt = parseFloat(ve[1]), Er = parseFloat(ve[2]), kt.attr("class").includes("attribute-name") ? Wt += S : kt.attr("class").includes("attribute-keys") ? Wt += S + L : kt.attr("class").includes("attribute-comment") && (Wt += S + L + T));
    }
    kt.attr(
      "transform",
      `translate(${R + c / 2 + Wt}, ${Er + z + x.height + u / 2})`
    );
  }), y.select(".name").attr("transform", "translate(" + -x.width / 2 + ", " + (z + u / 2) + ")"), i != null && tc.has(i)) {
    const J = r.colorIndex ?? 0;
    y.attr("data-color-id", `color-${J % l.length}`);
  }
  const X = P.rectangle(R, z, D, v, M), ot = y.insert(() => X, ":first-child").attr("class", "outer-path").attr("style", p.join(""));
  k.push(0);
  for (const [J, lt] of w.entries()) {
    const kt = (J + 1) % 2 === 0 && lt.yOffset !== 0, oe = P.rectangle(R, x.height + z + (lt == null ? void 0 : lt.yOffset), D, lt == null ? void 0 : lt.rowHeight, {
      ...M,
      fill: kt ? o : a,
      stroke: n
    });
    y.insert(() => oe, "g.label").attr("style", p.join("")).attr("class", `row-rect-${kt ? "even" : "odd"}`);
  }
  const tt = 1e-4;
  let st = Wr(R, x.height + z, D + R, x.height + z, tt), j = P.polygon(
    st.map((J) => [J.x, J.y]),
    M
  );
  if (y.insert(() => j).attr("class", "divider"), st = Wr(S + R, x.height + z, S + R, v + z, tt), j = P.polygon(
    st.map((J) => [J.x, J.y]),
    M
  ), y.insert(() => j).attr("class", "divider"), N) {
    const J = S + L + R;
    st = Wr(J, x.height + z, J, v + z, tt), j = P.polygon(
      st.map((lt) => [lt.x, lt.y]),
      M
    ), y.insert(() => j).attr("class", "divider");
  }
  if (O) {
    const J = S + L + T + R;
    st = Wr(J, x.height + z, J, v + z, tt), j = P.polygon(
      st.map((lt) => [lt.x, lt.y]),
      M
    ), y.insert(() => j).attr("class", "divider");
  }
  for (const J of k) {
    const lt = x.height + z + J;
    st = Wr(R, lt, D + R, lt, tt), j = P.polygon(
      st.map((Ct) => [Ct.x, Ct.y]),
      M
    ), y.insert(() => j).attr("class", "divider");
  }
  if (Q(t, ot), g && t.look !== "handDrawn")
    if (i != null && fS.has(i))
      y.selectAll("path").attr("style", g);
    else {
      const J = g.split(";"), lt = (se = J == null ? void 0 : J.filter((Ct) => Ct.includes("stroke"))) == null ? void 0 : se.map((Ct) => `${Ct}`).join("; ");
      y.selectAll("path").attr("style", lt ?? ""), y.selectAll(".row-rect-even path").attr("style", g);
    }
  return t.intersect = function(J) {
    return U.rect(t, J);
  }, y;
}
f(hl, "erBox");
async function qr(e, t, r, i = 0, s = 0, o = [], a = "") {
  const n = e.insert("g").attr("class", `label ${o.join(" ")}`).attr("transform", `translate(${i}, ${s})`).attr("style", a);
  t !== eh(t) && (t = eh(t), t = t.replaceAll("<", "&lt;").replaceAll(">", "&gt;"));
  const l = n.node().appendChild(
    await Ze(
      n,
      t,
      {
        width: je(t, r) + 100,
        style: a,
        useHtmlLabels: r.htmlLabels
      },
      r
    )
  );
  if (t.includes("&lt;") || t.includes("&gt;")) {
    let c = l.children[0];
    for (c.textContent = c.textContent.replaceAll("&lt;", "<").replaceAll("&gt;", ">"); c.childNodes[0]; )
      c = c.childNodes[0], c.textContent = c.textContent.replaceAll("&lt;", "<").replaceAll("&gt;", ">");
  }
  let h = l.getBBox();
  if (Ve(r.htmlLabels)) {
    const c = l.children[0];
    c.style.textAlign = "start";
    const u = ct(l);
    h = c.getBoundingClientRect(), u.attr("width", h.width), u.attr("height", h.height);
  }
  return h;
}
f(qr, "addText");
function Wr(e, t, r, i, s) {
  return e === r ? [
    { x: e - s / 2, y: t },
    { x: e + s / 2, y: t },
    { x: r + s / 2, y: i },
    { x: r - s / 2, y: i }
  ] : [
    { x: e, y: t - s / 2 },
    { x: e, y: t + s / 2 },
    { x: r, y: i + s / 2 },
    { x: r, y: i - s / 2 }
  ];
}
f(Wr, "lineToPolygon");
async function Ag(e, t, r, i, s = r.class.padding ?? 12) {
  const o = i ? 0 : 3, a = e.insert("g").attr("class", it(t)).attr("id", t.domId || t.id);
  let n = null, l = null, h = null, c = null, u = 0, p = 0, d = 0;
  if (n = a.insert("g").attr("class", "annotation-group text"), t.annotations.length > 0) {
    const b = t.annotations[0];
    await Pi(n, { text: `«${b}»` }, 0), u = n.node().getBBox().height;
  }
  l = a.insert("g").attr("class", "label-group text"), await Pi(l, t, 0, ["font-weight: bolder"]);
  const g = l.node().getBBox();
  p = g.height, h = a.insert("g").attr("class", "members-group text");
  let m = 0;
  for (const b of t.members) {
    const k = await Pi(h, b, m, [b.parseClassifier()]);
    m += k + o;
  }
  d = h.node().getBBox().height, d <= 0 && (d = s / 2), c = a.insert("g").attr("class", "methods-group text");
  let y = 0;
  for (const b of t.methods) {
    const k = await Pi(c, b, y, [b.parseClassifier()]);
    y += k + o;
  }
  let x = a.node().getBBox();
  if (n !== null) {
    const b = n.node().getBBox();
    n.attr("transform", `translate(${-b.width / 2})`);
  }
  return l.attr("transform", `translate(${-g.width / 2}, ${u})`), x = a.node().getBBox(), h.attr(
    "transform",
    `translate(0, ${u + p + s * 2})`
  ), x = a.node().getBBox(), c.attr(
    "transform",
    `translate(0, ${u + p + (d ? d + s * 4 : s * 2)})`
  ), x = a.node().getBBox(), { shapeSvg: a, bbox: x };
}
f(Ag, "textHelper");
async function Pi(e, t, r, i = []) {
  const s = e.insert("g").attr("class", "label").attr("style", i.join("; ")), o = wt();
  let a = "useHtmlLabels" in t ? t.useHtmlLabels : Ve(o.htmlLabels) ?? !0, n = "";
  "text" in t ? n = t.text : n = t.label, !a && n.startsWith("\\") && (n = n.substring(1)), ji(n) && (a = !0);
  const l = await Ze(
    s,
    wn(_r(n)),
    {
      width: je(n, o) + 50,
      // Add room for error when splitting text into multiple lines
      classes: "markdown-node-label",
      useHtmlLabels: a
    },
    o
  );
  let h, c = 1;
  if (a) {
    const u = l.children[0], p = ct(l);
    c = u.innerHTML.split("<br>").length, u.innerHTML.includes("</math>") && (c += u.innerHTML.split("<mrow>").length - 1);
    const d = u.getElementsByTagName("img");
    if (d) {
      const g = n.replace(/<img[^>]*>/g, "").trim() === "";
      await Promise.all(
        [...d].map(
          (m) => new Promise((y) => {
            function x() {
              var b;
              if (m.style.display = "flex", m.style.flexDirection = "column", g) {
                const k = ((b = o.fontSize) == null ? void 0 : b.toString()) ?? window.getComputedStyle(document.body).fontSize, S = parseInt(k, 10) * 5 + "px";
                m.style.minWidth = S, m.style.maxWidth = S;
              } else
                m.style.width = "100%";
              y(m);
            }
            f(x, "setupImage"), setTimeout(() => {
              m.complete && x();
            }), m.addEventListener("error", x), m.addEventListener("load", x);
          })
        )
      );
    }
    h = u.getBoundingClientRect(), p.attr("width", h.width), p.attr("height", h.height);
  } else {
    i.includes("font-weight: bolder") && ct(l).selectAll("tspan").attr("font-weight", ""), c = l.children.length;
    const u = l.children[0];
    (l.textContent === "" || l.textContent.includes("&gt")) && (u.textContent = n[0] + n.substring(1).replaceAll("&gt;", ">").replaceAll("&lt;", "<").trim(), n[1] === " " && (u.textContent = u.textContent[0] + " " + u.textContent.substring(1))), u.textContent === "undefined" && (u.textContent = ""), h = l.getBBox();
  }
  return s.attr("transform", "translate(0," + (-h.height / (2 * c) + r) + ")"), h.height;
}
f(Pi, "addText");
async function Eg(e, t) {
  var P, M;
  const r = gt(), { themeVariables: i } = r, { useGradient: s } = i, o = r.class.padding ?? 12, a = o, n = t.useHtmlLabels ?? Ve(r.htmlLabels) ?? !0, l = t;
  l.annotations = l.annotations ?? [], l.members = l.members ?? [], l.methods = l.methods ?? [];
  const { shapeSvg: h, bbox: c } = await Ag(e, t, r, n, a), { labelStyles: u, nodeStyles: p } = K(t);
  t.labelStyle = u, t.cssStyles = l.styles || "";
  const d = ((P = l.styles) == null ? void 0 : P.join(";")) || p || "";
  t.cssStyles || (t.cssStyles = d.replaceAll("!important", "").split(";"));
  const g = l.members.length === 0 && l.methods.length === 0 && !((M = r.class) != null && M.hideEmptyMembersBox), m = G.svg(h), y = Z(t, {});
  t.look !== "handDrawn" && (y.roughness = 0, y.fillStyle = "solid");
  const x = Math.max(t.width ?? 0, c.width);
  let b = Math.max(t.height ?? 0, c.height);
  const k = (t.height ?? 0) > c.height;
  l.members.length === 0 && l.methods.length === 0 ? b += a : l.members.length > 0 && l.methods.length === 0 && (b += a * 2);
  const w = -x / 2, S = -b / 2;
  let L = g ? o * 2 : l.members.length === 0 && l.methods.length === 0 ? -o : 0;
  k && (L = o * 2);
  const T = m.rectangle(
    w - o,
    S - o - (g ? o : l.members.length === 0 && l.methods.length === 0 ? -o / 2 : 0),
    x + 2 * o,
    b + 2 * o + L,
    y
  ), B = h.insert(() => T, ":first-child");
  B.attr("class", "basic label-container outer-path");
  const N = B.node().getBBox(), O = h.select(".annotation-group").node().getBBox().height - (g ? o / 2 : 0) || 0, F = h.select(".label-group").node().getBBox().height - (g ? o / 2 : 0) || 0, Y = h.select(".members-group").node().getBBox().height - (g ? o / 2 : 0) || 0, H = (O + F + S + o - (S - o - (g ? o : l.members.length === 0 && l.methods.length === 0 ? -o / 2 : 0))) / 2;
  if (h.selectAll(".text").each((E, D, v) => {
    var st, j;
    const R = ct(v[D]), z = R.attr("transform");
    let X = 0;
    if (z) {
      const xt = RegExp(/translate\(([^,]+),([^)]+)\)/).exec(z);
      xt && (X = parseFloat(xt[2]));
    }
    let ot = X + S + o - (g ? o : l.members.length === 0 && l.methods.length === 0 ? -o / 2 : 0);
    if (R.attr("class").includes("methods-group")) {
      const dt = Math.max(Y, a / 2);
      k ? ot = Math.max(
        H,
        O + F + dt + S + a * 2 + o
      ) + a * 2 : ot = O + F + dt + S + a * 4 + o;
    }
    l.members.length === 0 && l.methods.length === 0 && ((st = r.class) != null && st.hideEmptyMembersBox) && (l.annotations.length > 0 ? ot = X - a : ot = X), n || (ot -= 4);
    let tt = w;
    (R.attr("class").includes("label-group") || R.attr("class").includes("annotation-group")) && (tt = -((j = R.node()) == null ? void 0 : j.getBBox().width) / 2 || 0, h.selectAll("text").each(function(dt, xt, _t) {
      window.getComputedStyle(_t[xt]).textAnchor === "middle" && (tt = 0);
    })), R.attr("transform", `translate(${tt}, ${ot})`);
  }), l.members.length > 0 || l.methods.length > 0 || g) {
    const E = O + F + S + o, D = m.line(
      N.x,
      E,
      N.x + N.width,
      E + 1e-3,
      y
    );
    h.insert(() => D).attr("class", `divider${t.look === "neo" && !s ? " neo-line" : ""}`).attr("style", d);
  }
  if (g || l.members.length > 0 || l.methods.length > 0) {
    const E = O + F + Y + S + a * 2 + o, D = m.line(
      N.x,
      k ? Math.max(H, E) : E,
      N.x + N.width,
      (k ? Math.max(H, E) : E) + 1e-3,
      y
    );
    h.insert(() => D).attr("class", `divider${t.look === "neo" && !s ? " neo-line" : ""}`).attr("style", d);
  }
  if (l.look !== "handDrawn" && h.selectAll("path").attr("style", d), B.select(":nth-child(2)").attr("style", d), h.selectAll(".divider").select("path").attr("style", d), t.labelStyle ? h.selectAll("span").attr("style", t.labelStyle) : h.selectAll("span").attr("style", d), !n) {
    const E = RegExp(/color\s*:\s*([^;]*)/), D = E.exec(d);
    if (D) {
      const v = D[0].replace("color", "fill");
      h.selectAll("tspan").attr("style", v);
    } else if (u) {
      const v = E.exec(u);
      if (v) {
        const R = v[0].replace("color", "fill");
        h.selectAll("tspan").attr("style", R);
      }
    }
  }
  return Q(t, B), t.intersect = function(E) {
    return U.rect(t, E);
  }, h;
}
f(Eg, "classBox");
async function Fg(e, t) {
  var N, O;
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.labelStyle = r;
  const s = t, o = t, a = 20, n = 20, l = "verifyMethod" in t, h = it(t), { themeVariables: c } = gt(), { borderColorArray: u, requirementEdgeLabelBackground: p } = c, d = e.insert("g").attr("class", h).attr("id", t.domId ?? t.id);
  let g;
  l ? g = await Fe(
    d,
    `&lt;&lt;${s.type}&gt;&gt;`,
    0,
    t.labelStyle
  ) : g = await Fe(d, "&lt;&lt;Element&gt;&gt;", 0, t.labelStyle);
  let m = g;
  const y = await Fe(
    d,
    s.name,
    m,
    t.labelStyle + "; font-weight: bold;"
  );
  if (m += y + n, l) {
    const F = await Fe(
      d,
      `${s.requirementId ? `ID: ${s.requirementId}` : ""}`,
      m,
      t.labelStyle
    );
    m += F;
    const Y = await Fe(
      d,
      `${s.text ? `Text: ${s.text}` : ""}`,
      m,
      t.labelStyle
    );
    m += Y;
    const H = await Fe(
      d,
      `${s.risk ? `Risk: ${s.risk}` : ""}`,
      m,
      t.labelStyle
    );
    m += H, await Fe(
      d,
      `${s.verifyMethod ? `Verification: ${s.verifyMethod}` : ""}`,
      m,
      t.labelStyle
    );
  } else {
    const F = await Fe(
      d,
      `${o.type ? `Type: ${o.type}` : ""}`,
      m,
      t.labelStyle
    );
    m += F, await Fe(
      d,
      `${o.docRef ? `Doc Ref: ${o.docRef}` : ""}`,
      m,
      t.labelStyle
    );
  }
  const x = (((N = d.node()) == null ? void 0 : N.getBBox().width) ?? 200) + a, b = (((O = d.node()) == null ? void 0 : O.getBBox().height) ?? 200) + a, k = -x / 2, w = -b / 2, S = G.svg(d), L = Z(t, {});
  t.look !== "handDrawn" && (L.roughness = 0, L.fillStyle = "solid");
  const T = S.rectangle(k, w, x, b, L), B = d.insert(() => T, ":first-child");
  if (B.attr("class", "basic label-container outer-path").attr("style", i), u != null && u.length) {
    const F = t.colorIndex ?? 0;
    d.attr("data-color-id", `color-${F % u.length}`);
  }
  if (d.selectAll(".label").each((F, Y, H) => {
    const P = ct(H[Y]), M = P.attr("transform");
    let E = 0, D = 0;
    if (M) {
      const X = RegExp(/translate\(([^,]+),([^)]+)\)/).exec(M);
      X && (E = parseFloat(X[1]), D = parseFloat(X[2]));
    }
    const v = D - b / 2;
    let R = k + a / 2;
    (Y === 0 || Y === 1) && (R = E), P.attr("transform", `translate(${R}, ${v + a})`);
  }), m > g + y + n) {
    const F = w + g + y + n;
    let Y;
    if (t.look === "neo") {
      const M = [
        [k, F],
        [k + x, F],
        [k + x, F + 1e-3],
        [k, F + 1e-3]
      ];
      Y = S.polygon(M, L);
    } else
      Y = S.line(k, F, k + x, F, L);
    d.insert(() => Y).attr("class", "divider");
  }
  return Q(t, B), t.intersect = function(F) {
    return U.rect(t, F);
  }, i && t.look !== "handDrawn" && (p || u != null && u.length) && d.selectAll("path").attr("style", i), d;
}
f(Fg, "requirementBox");
async function Fe(e, t, r, i = "") {
  if (t === "")
    return 0;
  const s = e.insert("g").attr("class", "label").attr("style", i), o = gt(), a = o.htmlLabels ?? !0, n = await Ze(
    s,
    wn(_r(t)),
    {
      width: je(t, o) + 50,
      // Add room for error when splitting text into multiple lines
      classes: "markdown-node-label",
      useHtmlLabels: a,
      style: i
    },
    o
  );
  let l;
  if (a) {
    const h = n.children[0], c = ct(n);
    l = h.getBoundingClientRect(), c.attr("width", l.width), c.attr("height", l.height);
  } else {
    const h = n.children[0];
    for (const c of h.children)
      i && c.setAttribute("style", i);
    l = n.getBBox(), l.height += 6;
  }
  return s.attr("transform", `translate(${-l.width / 2},${-l.height / 2 + r})`), l.height;
}
f(Fe, "addText");
var gS = /* @__PURE__ */ f((e) => {
  switch (e) {
    case "Very High":
      return "red";
    case "High":
      return "orange";
    case "Medium":
      return null;
    // no stroke
    case "Low":
      return "blue";
    case "Very Low":
      return "lightblue";
  }
}, "colorFromPriority");
async function Mg(e, t, { config: r }) {
  var Y, H;
  const { labelStyles: i, nodeStyles: s } = K(t);
  t.labelStyle = i || "";
  const o = 10, a = t.width;
  t.width = (t.width ?? 200) - 10;
  const {
    shapeSvg: n,
    bbox: l,
    label: h
  } = await at(e, t, it(t)), c = t.padding || 10;
  let u = "", p;
  "ticket" in t && t.ticket && ((Y = r == null ? void 0 : r.kanban) != null && Y.ticketBaseUrl) && (u = (H = r == null ? void 0 : r.kanban) == null ? void 0 : H.ticketBaseUrl.replace("#TICKET#", t.ticket), p = n.insert("svg:a", ":first-child").attr("class", "kanban-ticket-link").attr("xlink:href", u).attr("target", "_blank"));
  const d = {
    useHtmlLabels: t.useHtmlLabels,
    labelStyle: t.labelStyle || "",
    width: t.width,
    img: t.img,
    padding: t.padding || 8,
    centerLabel: !1
  };
  let g, m;
  p ? { label: g, bbox: m } = await na(
    p,
    "ticket" in t && t.ticket || "",
    d
  ) : { label: g, bbox: m } = await na(
    n,
    "ticket" in t && t.ticket || "",
    d
  );
  const { label: y, bbox: x } = await na(
    n,
    "assigned" in t && t.assigned || "",
    d
  );
  t.width = a;
  const b = 10, k = (t == null ? void 0 : t.width) || 0, w = Math.max(m.height, x.height) / 2, S = Math.max(l.height + b * 2, (t == null ? void 0 : t.height) || 0) + w, L = -k / 2, T = -S / 2;
  h.attr(
    "transform",
    "translate(" + (c - k / 2) + ", " + (-w - l.height / 2) + ")"
  ), g.attr(
    "transform",
    "translate(" + (c - k / 2) + ", " + (-w + l.height / 2) + ")"
  ), y.attr(
    "transform",
    "translate(" + (c + k / 2 - x.width - 2 * o) + ", " + (-w + l.height / 2) + ")"
  );
  let B;
  const { rx: N, ry: O } = t, { cssStyles: F } = t;
  if (t.look === "handDrawn") {
    const P = G.svg(n), M = Z(t, {}), E = N || O ? P.path(ar(L, T, k, S, N || 0), M) : P.rectangle(L, T, k, S, M);
    B = n.insert(() => E, ":first-child"), B.attr("class", "basic label-container").attr("style", F || null);
  } else {
    B = n.insert("rect", ":first-child"), B.attr("class", "basic label-container __APA__").attr("style", s).attr("rx", N ?? 5).attr("ry", O ?? 5).attr("x", L).attr("y", T).attr("width", k).attr("height", S);
    const P = "priority" in t && t.priority;
    if (P) {
      const M = n.append("line"), E = L + 2, D = T + Math.floor((N ?? 0) / 2), v = T + S - Math.floor((N ?? 0) / 2);
      M.attr("x1", E).attr("y1", D).attr("x2", E).attr("y2", v).attr("stroke-width", "4").attr("stroke", gS(P));
    }
  }
  return Q(t, B), t.height = S, t.intersect = function(P) {
    return U.rect(t, P);
  }, n;
}
f(Mg, "kanbanItem");
async function Ig(e, t) {
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.labelStyle = r;
  const { shapeSvg: s, bbox: o, halfPadding: a, label: n } = await at(
    e,
    t,
    it(t)
  ), l = o.width + 10 * a, h = o.height + 8 * a, c = 0.15 * l, { cssStyles: u } = t, p = o.width + 20, d = o.height + 20, g = Math.max(l, p), m = Math.max(h, d);
  n.attr("transform", `translate(${-o.width / 2}, ${-o.height / 2})`);
  let y;
  const x = `M0 0 
    a${c},${c} 1 0,0 ${g * 0.25},${-1 * m * 0.1}
    a${c},${c} 1 0,0 ${g * 0.25},0
    a${c},${c} 1 0,0 ${g * 0.25},0
    a${c},${c} 1 0,0 ${g * 0.25},${m * 0.1}

    a${c},${c} 1 0,0 ${g * 0.15},${m * 0.33}
    a${c * 0.8},${c * 0.8} 1 0,0 0,${m * 0.34}
    a${c},${c} 1 0,0 ${-1 * g * 0.15},${m * 0.33}

    a${c},${c} 1 0,0 ${-1 * g * 0.25},${m * 0.15}
    a${c},${c} 1 0,0 ${-1 * g * 0.25},0
    a${c},${c} 1 0,0 ${-1 * g * 0.25},0
    a${c},${c} 1 0,0 ${-1 * g * 0.25},${-1 * m * 0.15}

    a${c},${c} 1 0,0 ${-1 * g * 0.1},${-1 * m * 0.33}
    a${c * 0.8},${c * 0.8} 1 0,0 0,${-1 * m * 0.34}
    a${c},${c} 1 0,0 ${g * 0.1},${-1 * m * 0.33}
  H0 V0 Z`;
  if (t.look === "handDrawn") {
    const b = G.svg(s), k = Z(t, {}), w = b.path(x, k);
    y = s.insert(() => w, ":first-child"), y.attr("class", "basic label-container").attr("style", Rt(u));
  } else
    y = s.insert("path", ":first-child").attr("class", "basic label-container").attr("style", i).attr("d", x);
  return y.attr("transform", `translate(${-g / 2}, ${-m / 2})`), Q(t, y), t.calcIntersect = function(b, k) {
    return U.rect(b, k);
  }, t.intersect = function(b) {
    return q.info("Bang intersect", t, b), U.rect(t, b);
  }, s;
}
f(Ig, "bang");
async function $g(e, t) {
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.labelStyle = r;
  const { shapeSvg: s, bbox: o, halfPadding: a, label: n } = await at(
    e,
    t,
    it(t)
  ), l = o.width + 2 * a, h = o.height + 2 * a, c = 0.15 * l, u = 0.25 * l, p = 0.35 * l, d = 0.2 * l, { cssStyles: g } = t;
  let m;
  const y = `M0 0 
    a${c},${c} 0 0,1 ${l * 0.25},${-1 * l * 0.1}
    a${p},${p} 1 0,1 ${l * 0.4},${-1 * l * 0.1}
    a${u},${u} 1 0,1 ${l * 0.35},${l * 0.2}

    a${c},${c} 1 0,1 ${l * 0.15},${h * 0.35}
    a${d},${d} 1 0,1 ${-1 * l * 0.15},${h * 0.65}

    a${u},${c} 1 0,1 ${-1 * l * 0.25},${l * 0.15}
    a${p},${p} 1 0,1 ${-1 * l * 0.5},0
    a${c},${c} 1 0,1 ${-1 * l * 0.25},${-1 * l * 0.15}

    a${c},${c} 1 0,1 ${-1 * l * 0.1},${-1 * h * 0.35}
    a${d},${d} 1 0,1 ${l * 0.1},${-1 * h * 0.65}
  H0 V0 Z`;
  if (t.look === "handDrawn") {
    const x = G.svg(s), b = Z(t, {}), k = x.path(y, b);
    m = s.insert(() => k, ":first-child"), m.attr("class", "basic label-container").attr("style", Rt(g));
  } else
    m = s.insert("path", ":first-child").attr("class", "basic label-container").attr("style", i).attr("d", y);
  return n.attr("transform", `translate(${-o.width / 2}, ${-o.height / 2})`), m.attr("transform", `translate(${-l / 2}, ${-h / 2})`), Q(t, m), t.calcIntersect = function(x, b) {
    return U.rect(x, b);
  }, t.intersect = function(x) {
    return q.info("Cloud intersect", t, x), U.rect(t, x);
  }, s;
}
f($g, "cloud");
async function Og(e, t) {
  const { labelStyles: r, nodeStyles: i } = K(t);
  t.labelStyle = r;
  const { shapeSvg: s, bbox: o, halfPadding: a, label: n } = await at(
    e,
    t,
    it(t)
  ), l = o.width + 8 * a, h = o.height + 2 * a, c = 5, u = t.look === "neo" ? `
    M${-l / 2} ${h / 2 - c}
    v${-h + 2 * c}
    q0,-${c} ${c},-${c}
    h${l - 2 * c}
    q${c},0 ${c},${c}
    v${h - c}
    H${-l / 2}
    Z
  ` : `
    M${-l / 2} ${h / 2 - c}
    v${-h + 2 * c}
    q0,-${c} ${c},-${c}
    h${l - 2 * c}
    q${c},0 ${c},${c}
    v${h - 2 * c}
    q0,${c} ${-c},${c}
    h${-(l - 2 * c)}
    q${-c},0 ${-c},${-c}
    Z
  `;
  if (!t.domId)
    throw new Error(
      `defaultMindmapNode: node "${t.id}" is missing a domId — was render.ts domId prefixing skipped?`
    );
  const p = s.append("path").attr("id", t.domId).attr("class", "node-bkg node-" + t.type).attr("style", i).attr("d", u);
  return s.append("line").attr("class", "node-line-").attr("x1", -l / 2).attr("y1", h / 2).attr("x2", l / 2).attr("y2", h / 2), n.attr("transform", `translate(${-o.width / 2}, ${-o.height / 2})`), s.append(() => n.node()), Q(t, p), t.calcIntersect = function(d, g) {
    return U.rect(d, g);
  }, t.intersect = function(d) {
    return U.rect(t, d);
  }, s;
}
f(Og, "defaultMindmapNode");
async function Dg(e, t) {
  const r = {
    padding: t.padding ?? 0
  };
  return ll(e, t, r);
}
f(Dg, "mindmapCircle");
var mS = [
  {
    semanticName: "Process",
    name: "Rectangle",
    shortName: "rect",
    description: "Standard process shape",
    aliases: ["proc", "process", "rectangle"],
    internalAliases: ["squareRect"],
    handler: pg
  },
  {
    semanticName: "Event",
    name: "Rounded Rectangle",
    shortName: "rounded",
    description: "Represents an event",
    aliases: ["event"],
    internalAliases: ["roundedRect"],
    handler: cg
  },
  {
    semanticName: "Terminal Point",
    name: "Stadium",
    shortName: "stadium",
    description: "Terminal point",
    aliases: ["terminal", "pill"],
    handler: fg
  },
  {
    semanticName: "Subprocess",
    name: "Framed Rectangle",
    shortName: "fr-rect",
    description: "Subprocess",
    aliases: ["subprocess", "subproc", "framed-rectangle", "subroutine"],
    handler: xg
  },
  {
    semanticName: "Database",
    name: "Cylinder",
    shortName: "cyl",
    description: "Database storage",
    aliases: ["db", "database", "cylinder"],
    handler: Rf
  },
  {
    semanticName: "Start",
    name: "Circle",
    shortName: "circle",
    description: "Starting point",
    aliases: ["circ"],
    handler: ll
  },
  {
    semanticName: "Bang",
    name: "Bang",
    shortName: "bang",
    description: "Bang",
    aliases: ["bang"],
    handler: Ig
  },
  {
    semanticName: "Cloud",
    name: "Cloud",
    shortName: "cloud",
    description: "cloud",
    aliases: ["cloud"],
    handler: $g
  },
  {
    semanticName: "Decision",
    name: "Diamond",
    shortName: "diam",
    description: "Decision-making step",
    aliases: ["decision", "diamond", "question"],
    handler: ng
  },
  {
    semanticName: "Prepare Conditional",
    name: "Hexagon",
    shortName: "hex",
    description: "Preparation or condition step",
    aliases: ["hexagon", "prepare"],
    handler: Yf
  },
  {
    semanticName: "Data Input/Output",
    name: "Lean Right",
    shortName: "lean-r",
    description: "Represents input or output",
    aliases: ["lean-right", "in-out"],
    internalAliases: ["lean_right"],
    handler: tg
  },
  {
    semanticName: "Data Input/Output",
    name: "Lean Left",
    shortName: "lean-l",
    description: "Represents output or input",
    aliases: ["lean-left", "out-in"],
    internalAliases: ["lean_left"],
    handler: Jf
  },
  {
    semanticName: "Priority Action",
    name: "Trapezoid Base Bottom",
    shortName: "trap-b",
    description: "Priority action",
    aliases: ["priority", "trapezoid-bottom", "trapezoid"],
    handler: Sg
  },
  {
    semanticName: "Manual Operation",
    name: "Trapezoid Base Top",
    shortName: "trap-t",
    description: "Represents a manual task",
    aliases: ["manual", "trapezoid-top", "inv-trapezoid"],
    internalAliases: ["inv_trapezoid"],
    handler: Kf
  },
  {
    semanticName: "Stop",
    name: "Double Circle",
    shortName: "dbl-circ",
    description: "Represents a stop point",
    aliases: ["double-circle"],
    internalAliases: ["doublecircle"],
    handler: Nf
  },
  {
    semanticName: "Text Block",
    name: "Text Block",
    shortName: "text",
    description: "Text block",
    handler: kg
  },
  {
    semanticName: "Card",
    name: "Notched Rectangle",
    shortName: "notch-rect",
    description: "Represents a card",
    aliases: ["card", "notched-rectangle"],
    handler: Af
  },
  {
    semanticName: "Lined/Shaded Process",
    name: "Lined Rectangle",
    shortName: "lin-rect",
    description: "Lined process shape",
    aliases: ["lined-rectangle", "lined-process", "lin-proc", "shaded-process"],
    handler: ug
  },
  {
    semanticName: "Start",
    name: "Small Circle",
    shortName: "sm-circ",
    description: "Small starting point",
    aliases: ["start", "small-circle"],
    internalAliases: ["stateStart"],
    handler: yg
  },
  {
    semanticName: "Stop",
    name: "Framed Circle",
    shortName: "fr-circ",
    description: "Stop point",
    aliases: ["stop", "framed-circle"],
    internalAliases: ["stateEnd"],
    handler: mg
  },
  {
    semanticName: "Fork/Join",
    name: "Filled Rectangle",
    shortName: "fork",
    description: "Fork or join in process flow",
    aliases: ["join"],
    internalAliases: ["forkJoin"],
    handler: zf
  },
  {
    semanticName: "Collate",
    name: "Hourglass",
    shortName: "hourglass",
    description: "Represents a collate operation",
    aliases: ["hourglass", "collate"],
    handler: Xf
  },
  {
    semanticName: "Comment",
    name: "Curly Brace",
    shortName: "brace",
    description: "Adds a comment",
    aliases: ["comment", "brace-l"],
    handler: If
  },
  {
    semanticName: "Comment Right",
    name: "Curly Brace",
    shortName: "brace-r",
    description: "Adds a comment",
    handler: $f
  },
  {
    semanticName: "Comment with braces on both sides",
    name: "Curly Braces",
    shortName: "braces",
    description: "Adds a comment",
    handler: Of
  },
  {
    semanticName: "Com Link",
    name: "Lightning Bolt",
    shortName: "bolt",
    description: "Communication link",
    aliases: ["com-link", "lightning-bolt"],
    handler: eg
  },
  {
    semanticName: "Document",
    name: "Document",
    shortName: "doc",
    description: "Represents a document",
    aliases: ["doc", "document"],
    handler: Bg
  },
  {
    semanticName: "Delay",
    name: "Half-Rounded Rectangle",
    shortName: "delay",
    description: "Represents a delay",
    aliases: ["half-rounded-rectangle"],
    handler: Hf
  },
  {
    semanticName: "Direct Access Storage",
    name: "Horizontal Cylinder",
    shortName: "h-cyl",
    description: "Direct access storage",
    aliases: ["das", "horizontal-cylinder"],
    handler: Tg
  },
  {
    semanticName: "Disk Storage",
    name: "Lined Cylinder",
    shortName: "lin-cyl",
    description: "Disk storage",
    aliases: ["disk", "lined-cylinder"],
    handler: rg
  },
  {
    semanticName: "Display",
    name: "Curved Trapezoid",
    shortName: "curv-trap",
    description: "Represents a display",
    aliases: ["curved-trapezoid", "display"],
    handler: Df
  },
  {
    semanticName: "Divided Process",
    name: "Divided Rectangle",
    shortName: "div-rect",
    description: "Divided process shape",
    aliases: ["div-proc", "divided-rectangle", "divided-process"],
    handler: Pf
  },
  {
    semanticName: "Extract",
    name: "Triangle",
    shortName: "tri",
    description: "Extraction process",
    aliases: ["extract", "triangle"],
    handler: _g
  },
  {
    semanticName: "Internal Storage",
    name: "Window Pane",
    shortName: "win-pane",
    description: "Internal storage",
    aliases: ["internal-storage", "window-pane"],
    handler: Lg
  },
  {
    semanticName: "Junction",
    name: "Filled Circle",
    shortName: "f-circ",
    description: "Junction point",
    aliases: ["junction", "filled-circle"],
    handler: qf
  },
  {
    semanticName: "Loop Limit",
    name: "Trapezoidal Pentagon",
    shortName: "notch-pent",
    description: "Loop limit step",
    aliases: ["loop-limit", "notched-pentagon"],
    handler: wg
  },
  {
    semanticName: "Manual File",
    name: "Flipped Triangle",
    shortName: "flip-tri",
    description: "Manual file operation",
    aliases: ["manual-file", "flipped-triangle"],
    handler: Wf
  },
  {
    semanticName: "Manual Input",
    name: "Sloped Rectangle",
    shortName: "sl-rect",
    description: "Manual input step",
    aliases: ["manual-input", "sloped-rectangle"],
    handler: dg
  },
  {
    semanticName: "Multi-Document",
    name: "Stacked Document",
    shortName: "docs",
    description: "Multiple documents",
    aliases: ["documents", "st-doc", "stacked-document"],
    handler: og
  },
  {
    semanticName: "Multi-Process",
    name: "Stacked Rectangle",
    shortName: "st-rect",
    description: "Multiple processes",
    aliases: ["procs", "processes", "stacked-rectangle"],
    handler: sg
  },
  {
    semanticName: "Stored Data",
    name: "Bow Tie Rectangle",
    shortName: "bow-rect",
    description: "Stored data",
    aliases: ["stored-data", "bow-tie-rectangle"],
    handler: Lf
  },
  {
    semanticName: "Summary",
    name: "Crossed Circle",
    shortName: "cross-circ",
    description: "Summary",
    aliases: ["summary", "crossed-circle"],
    handler: Mf
  },
  {
    semanticName: "Tagged Document",
    name: "Tagged Document",
    shortName: "tag-doc",
    description: "Tagged document",
    aliases: ["tag-doc", "tagged-document"],
    handler: bg
  },
  {
    semanticName: "Tagged Process",
    name: "Tagged Rectangle",
    shortName: "tag-rect",
    description: "Tagged process",
    aliases: ["tagged-rectangle", "tag-proc", "tagged-process"],
    handler: Cg
  },
  {
    semanticName: "Paper Tape",
    name: "Flag",
    shortName: "flag",
    description: "Paper tape",
    aliases: ["paper-tape"],
    handler: vg
  },
  {
    semanticName: "Odd",
    name: "Odd",
    shortName: "odd",
    description: "Odd shape",
    internalAliases: ["rect_left_inv_arrow"],
    handler: lg
  },
  {
    semanticName: "Lined Document",
    name: "Lined Document",
    shortName: "lin-doc",
    description: "Lined document",
    aliases: ["lined-document"],
    handler: ig
  }
], yS = /* @__PURE__ */ f(() => {
  const t = [
    ...Object.entries({
      // States
      state: gg,
      choice: Ef,
      note: ag,
      // Rectangles
      rectWithTitle: hg,
      labelRect: Qf,
      // Icons
      iconSquare: Vf,
      iconCircle: jf,
      icon: Uf,
      iconRounded: Gf,
      imageSquare: Zf,
      anchor: Bf,
      // Kanban diagram
      kanbanItem: Mg,
      //Mindmap diagram
      mindmapCircle: Dg,
      defaultMindmapNode: Og,
      // class diagram
      classBox: Eg,
      // er diagram
      erBox: hl,
      // Requirement diagram
      requirementBox: Fg
    }),
    ...mS.flatMap((r) => [
      r.shortName,
      ..."aliases" in r ? r.aliases : [],
      ..."internalAliases" in r ? r.internalAliases : []
    ].map((s) => [s, r.handler]))
  ];
  return Object.fromEntries(t);
}, "generateShapeMap"), Rg = yS();
function xS(e) {
  return e in Rg;
}
f(xS, "isValidShape");
var $o = /* @__PURE__ */ new Map();
async function Pg(e, t, r) {
  let i, s;
  t.shape === "rect" && (t.rx && t.ry ? t.shape = "roundedRect" : t.shape = "squareRect");
  const o = t.shape ? Rg[t.shape] : void 0;
  if (!o)
    throw new Error(`No such shape: ${t.shape}. Please check your syntax.`);
  if (t.link) {
    let a;
    r.config.securityLevel === "sandbox" ? a = "_top" : t.linkTarget && (a = t.linkTarget || "_blank"), i = e.insert("svg:a").attr("xlink:href", t.link).attr("target", a ?? null), s = await o(i, t, r);
  } else
    s = await o(e, t, r), i = s;
  return i.attr("data-look", Rt(t.look)), t.tooltip && s.attr("title", t.tooltip), $o.set(t.id, i), t.haveCallback && i.attr("class", i.attr("class") + " clickable"), i;
}
f(Pg, "insertNode");
var GL = /* @__PURE__ */ f((e, t) => {
  $o.set(t.id, e);
}, "setNodeElem"), VL = /* @__PURE__ */ f(() => {
  $o.clear();
}, "clear"), ZL = /* @__PURE__ */ f((e) => {
  const t = $o.get(e.id);
  q.trace(
    "Transforming node",
    e.diff,
    e,
    "translate(" + (e.x - e.width / 2 - 5) + ", " + e.width / 2 + ")"
  );
  const r = 8, i = e.diff || 0;
  return e.clusterNode ? t.attr(
    "transform",
    "translate(" + (e.x + i - e.width / 2) + ", " + (e.y - e.height / 2 - r) + ")"
  ) : t.attr("transform", "translate(" + e.x + ", " + e.y + ")"), i;
}, "positionNode"), CS = /* @__PURE__ */ f((e, t, r, i, s, o = !1, a) => {
  t.arrowTypeStart && ec(
    e,
    "start",
    t.arrowTypeStart,
    r,
    i,
    s,
    o,
    a
  ), t.arrowTypeEnd && ec(e, "end", t.arrowTypeEnd, r, i, s, o, a);
}, "addEdgeMarkers"), bS = {
  arrow_cross: { type: "cross", fill: !1 },
  arrow_point: { type: "point", fill: !0 },
  arrow_barb: { type: "barb", fill: !0 },
  arrow_barb_neo: { type: "barb", fill: !0 },
  arrow_circle: { type: "circle", fill: !1 },
  aggregation: { type: "aggregation", fill: !1 },
  extension: { type: "extension", fill: !1 },
  composition: { type: "composition", fill: !0 },
  dependency: { type: "dependency", fill: !0 },
  lollipop: { type: "lollipop", fill: !1 },
  only_one: { type: "onlyOne", fill: !1 },
  zero_or_one: { type: "zeroOrOne", fill: !1 },
  one_or_more: { type: "oneOrMore", fill: !1 },
  zero_or_more: { type: "zeroOrMore", fill: !1 },
  requirement_arrow: { type: "requirement_arrow", fill: !1 },
  requirement_contains: { type: "requirement_contains", fill: !1 }
}, kS = [
  "cross",
  "point",
  "circle",
  "lollipop",
  "aggregation",
  "extension",
  "composition",
  "dependency",
  "barb"
], ec = /* @__PURE__ */ f((e, t, r, i, s, o, a = !1, n) => {
  var g;
  const l = bS[r], h = l && kS.includes(l.type);
  if (!l) {
    q.warn(`Unknown arrow type: ${r}`);
    return;
  }
  const c = l.type, d = `${s}_${o}-${c}${t === "start" ? "Start" : "End"}${a && h ? "-margin" : ""}`;
  if (n && n.trim() !== "") {
    const m = n.replace(/[^\dA-Za-z]/g, "_"), y = `${d}_${m}`;
    if (!document.getElementById(y)) {
      const x = document.getElementById(d);
      if (x) {
        const b = x.cloneNode(!0);
        b.id = y, b.querySelectorAll("path, circle, line").forEach((w) => {
          w.setAttribute("stroke", n), l.fill && w.setAttribute("fill", n);
        }), (g = x.parentNode) == null || g.appendChild(b);
      }
    }
    e.attr(`marker-${t}`, `url(${i}#${y})`);
  } else
    e.attr(`marker-${t}`, `url(${i}#${d})`);
}, "addEdgeMarker"), TS = /* @__PURE__ */ f((e) => {
  var t, r;
  return typeof e == "string" ? e : (r = (t = gt()) == null ? void 0 : t.flowchart) == null ? void 0 : r.curve;
}, "resolveEdgeCurveType"), mo = /* @__PURE__ */ new Map(), qt = /* @__PURE__ */ new Map(), KL = /* @__PURE__ */ f(() => {
  mo.clear(), qt.clear();
}, "clear"), Ei = /* @__PURE__ */ f((e) => e ? typeof e == "string" ? e : e.reduce((t, r) => t + ";" + r, "") : "", "getLabelStyles"), SS = /* @__PURE__ */ f(async (e, t) => {
  const r = gt();
  let i = Kt(r);
  const { labelStyles: s } = K(t);
  t.labelStyle = s;
  const o = e.insert("g").attr("class", "edgeLabel"), a = o.insert("g").attr("class", "label").attr("data-id", t.id), n = t.labelType === "markdown", h = await Ze(
    e,
    t.label,
    {
      style: Ei(t.labelStyle),
      useHtmlLabels: i,
      addSvgBackground: !0,
      isNode: !1,
      markdown: n,
      // Plain text edge labels should auto-wrap, markdown edge labels respect markdownAutoWrap config
      width: n ? void 0 : void 0
    },
    r
  );
  a.node().appendChild(h), q.info("abc82", t, t.labelType);
  let c = h.getBBox(), u = c;
  if (i) {
    const d = h.children[0], g = ct(h);
    c = d.getBoundingClientRect(), u = c, g.attr("width", c.width), g.attr("height", c.height);
  } else {
    const d = ct(h).select("text").node();
    d && typeof d.getBBox == "function" && (u = d.getBBox());
  }
  a.attr("transform", vi(u, i)), mo.set(t.id, o), t.width = c.width, t.height = c.height;
  let p;
  if (t.startLabelLeft) {
    const d = e.insert("g").attr("class", "edgeTerminals"), g = d.insert("g").attr("class", "inner"), m = await tr(
      g,
      t.startLabelLeft,
      Ei(t.labelStyle) || "",
      !1,
      !1
    );
    p = m;
    let y = m.getBBox();
    if (i) {
      const x = m.children[0], b = ct(m);
      y = x.getBoundingClientRect(), b.attr("width", y.width), b.attr("height", y.height);
    }
    g.attr("transform", vi(y, i)), qt.get(t.id) || qt.set(t.id, {}), qt.get(t.id).startLeft = d, Ni(p, t.startLabelLeft);
  }
  if (t.startLabelRight) {
    const d = e.insert("g").attr("class", "edgeTerminals"), g = d.insert("g").attr("class", "inner"), m = await tr(
      g,
      t.startLabelRight,
      Ei(t.labelStyle) || "",
      !1,
      !1
    );
    p = m, g.node().appendChild(m);
    let y = m.getBBox();
    if (i) {
      const x = m.children[0], b = ct(m);
      y = x.getBoundingClientRect(), b.attr("width", y.width), b.attr("height", y.height);
    }
    g.attr("transform", vi(y, i)), qt.get(t.id) || qt.set(t.id, {}), qt.get(t.id).startRight = d, Ni(p, t.startLabelRight);
  }
  if (t.endLabelLeft) {
    const d = e.insert("g").attr("class", "edgeTerminals"), g = d.insert("g").attr("class", "inner"), m = await tr(
      g,
      t.endLabelLeft,
      Ei(t.labelStyle) || "",
      !1,
      !1
    );
    p = m;
    let y = m.getBBox();
    if (i) {
      const x = m.children[0], b = ct(m);
      y = x.getBoundingClientRect(), b.attr("width", y.width), b.attr("height", y.height);
    }
    g.attr("transform", vi(y, i)), d.node().appendChild(m), qt.get(t.id) || qt.set(t.id, {}), qt.get(t.id).endLeft = d, Ni(p, t.endLabelLeft);
  }
  if (t.endLabelRight) {
    const d = e.insert("g").attr("class", "edgeTerminals"), g = d.insert("g").attr("class", "inner"), m = await tr(
      g,
      t.endLabelRight,
      Ei(t.labelStyle) || "",
      !1,
      !1
    );
    p = m;
    let y = m.getBBox();
    if (i) {
      const x = m.children[0], b = ct(m);
      y = x.getBoundingClientRect(), b.attr("width", y.width), b.attr("height", y.height);
    }
    g.attr("transform", vi(y, i)), d.node().appendChild(m), qt.get(t.id) || qt.set(t.id, {}), qt.get(t.id).endRight = d, Ni(p, t.endLabelRight);
  }
  return h;
}, "insertEdgeLabel");
function Ni(e, t) {
  Kt(gt()) && e && (e.style.width = t.length * 9 + "px", e.style.height = "12px");
}
f(Ni, "setTerminalWidth");
var wS = /* @__PURE__ */ f((e, t) => {
  q.debug("Moving label abc88 ", e.id, e.label, mo.get(e.id), t);
  let r = t.updatedPath ? t.updatedPath : t.originalPath;
  const i = gt(), { subGraphTitleTotalMargin: s } = Kn(i);
  if (e.label) {
    const o = mo.get(e.id);
    let a = e.x, n = e.y;
    if (r) {
      const l = ke.calcLabelPosition(r);
      q.debug(
        "Moving label " + e.label + " from (",
        a,
        ",",
        n,
        ") to (",
        l.x,
        ",",
        l.y,
        ") abc88"
      ), t.updatedPath && (a = l.x, n = l.y);
    }
    o.attr("transform", `translate(${a}, ${n + s / 2})`);
  }
  if (e.startLabelLeft) {
    const o = qt.get(e.id).startLeft;
    let a = e.x, n = e.y;
    if (r) {
      const l = ke.calcTerminalLabelPosition(e.arrowTypeStart ? 10 : 0, "start_left", r);
      a = l.x, n = l.y;
    }
    o.attr("transform", `translate(${a}, ${n})`);
  }
  if (e.startLabelRight) {
    const o = qt.get(e.id).startRight;
    let a = e.x, n = e.y;
    if (r) {
      const l = ke.calcTerminalLabelPosition(
        e.arrowTypeStart ? 10 : 0,
        "start_right",
        r
      );
      a = l.x, n = l.y;
    }
    o.attr("transform", `translate(${a}, ${n})`);
  }
  if (e.endLabelLeft) {
    const o = qt.get(e.id).endLeft;
    let a = e.x, n = e.y;
    if (r) {
      const l = ke.calcTerminalLabelPosition(e.arrowTypeEnd ? 10 : 0, "end_left", r);
      a = l.x, n = l.y;
    }
    o.attr("transform", `translate(${a}, ${n})`);
  }
  if (e.endLabelRight) {
    const o = qt.get(e.id).endRight;
    let a = e.x, n = e.y;
    if (r) {
      const l = ke.calcTerminalLabelPosition(e.arrowTypeEnd ? 10 : 0, "end_right", r);
      a = l.x, n = l.y;
    }
    o.attr("transform", `translate(${a}, ${n})`);
  }
}, "positionEdgeLabel"), _S = /* @__PURE__ */ f((e, t) => {
  const r = e.x, i = e.y, s = Math.abs(t.x - r), o = Math.abs(t.y - i), a = e.width / 2, n = e.height / 2;
  return s >= a || o >= n;
}, "outsideNode"), BS = /* @__PURE__ */ f((e, t, r) => {
  q.debug(`intersection calc abc89:
  outsidePoint: ${JSON.stringify(t)}
  insidePoint : ${JSON.stringify(r)}
  node        : x:${e.x} y:${e.y} w:${e.width} h:${e.height}`);
  const i = e.x, s = e.y, o = Math.abs(i - r.x), a = e.width / 2;
  let n = r.x < t.x ? a - o : a + o;
  const l = e.height / 2, h = Math.abs(t.y - r.y), c = Math.abs(t.x - r.x);
  if (Math.abs(s - t.y) * a > Math.abs(i - t.x) * l) {
    let u = r.y < t.y ? t.y - l - s : s - l - t.y;
    n = c * u / h;
    const p = {
      x: r.x < t.x ? r.x + n : r.x - c + n,
      y: r.y < t.y ? r.y + h - u : r.y - h + u
    };
    return n === 0 && (p.x = t.x, p.y = t.y), c === 0 && (p.x = t.x), h === 0 && (p.y = t.y), q.debug(`abc89 top/bottom calc, Q ${h}, q ${u}, R ${c}, r ${n}`, p), p;
  } else {
    r.x < t.x ? n = t.x - a - i : n = i - a - t.x;
    let u = h * n / c, p = r.x < t.x ? r.x + c - n : r.x - c + n, d = r.y < t.y ? r.y + u : r.y - u;
    return q.debug(`sides calc abc89, Q ${h}, q ${u}, R ${c}, r ${n}`, { _x: p, _y: d }), n === 0 && (p = t.x, d = t.y), c === 0 && (p = t.x), h === 0 && (d = t.y), { x: p, y: d };
  }
}, "intersection"), rc = /* @__PURE__ */ f((e, t) => {
  q.warn("abc88 cutPathAtIntersect", e, t);
  let r = [], i = e[0], s = !1;
  return e.forEach((o) => {
    if (q.info("abc88 checking point", o, t), !_S(t, o) && !s) {
      const a = BS(t, i, o);
      q.debug("abc88 inside", o, i, a), q.debug("abc88 intersection", a, t);
      let n = !1;
      r.forEach((l) => {
        n = n || l.x === a.x && l.y === a.y;
      }), r.some((l) => l.x === a.x && l.y === a.y) ? q.warn("abc88 no intersect", a, r) : r.push(a), s = !0;
    } else
      q.warn("abc88 outside", o, i), i = o, s || r.push(o);
  }), q.debug("returning points", r), r;
}, "cutPathAtIntersect");
function Ng(e) {
  const t = [], r = [];
  for (let i = 1; i < e.length - 1; i++) {
    const s = e[i - 1], o = e[i], a = e[i + 1];
    (s.x === o.x && o.y === a.y && Math.abs(o.x - a.x) > 5 && Math.abs(o.y - s.y) > 5 || s.y === o.y && o.x === a.x && Math.abs(o.x - s.x) > 5 && Math.abs(o.y - a.y) > 5) && (t.push(o), r.push(i));
  }
  return { cornerPoints: t, cornerPointPositions: r };
}
f(Ng, "extractCornerPoints");
var ic = /* @__PURE__ */ f(function(e, t, r) {
  const i = t.x - e.x, s = t.y - e.y, o = Math.sqrt(i * i + s * s), a = r / o;
  return { x: t.x - a * i, y: t.y - a * s };
}, "findAdjacentPoint"), vS = /* @__PURE__ */ f(function(e) {
  const { cornerPointPositions: t } = Ng(e), r = [];
  for (let i = 0; i < e.length; i++)
    if (t.includes(i)) {
      const s = e[i - 1], o = e[i + 1], a = e[i], n = ic(s, a, 5), l = ic(o, a, 5), h = l.x - n.x, c = l.y - n.y;
      r.push(n);
      const u = Math.sqrt(2) * 2;
      let p = { x: a.x, y: a.y };
      if (Math.abs(o.x - s.x) > 10 && Math.abs(o.y - s.y) >= 10) {
        q.debug(
          "Corner point fixing",
          Math.abs(o.x - s.x),
          Math.abs(o.y - s.y)
        );
        const d = 5;
        a.x === n.x ? p = {
          x: h < 0 ? n.x - d + u : n.x + d - u,
          y: c < 0 ? n.y - u : n.y + u
        } : p = {
          x: h < 0 ? n.x - u : n.x + u,
          y: c < 0 ? n.y - d + u : n.y + d - u
        };
      } else
        q.debug(
          "Corner point skipping fixing",
          Math.abs(o.x - s.x),
          Math.abs(o.y - s.y)
        );
      r.push(p, l);
    } else
      r.push(e[i]);
  return r;
}, "fixCorners"), LS = /* @__PURE__ */ f((e, t, r) => {
  const i = e - t - r, s = 2, o = 2, a = s + o, n = Math.floor(i / a), l = Array(n).fill(`${s} ${o}`).join(" ");
  return `0 ${t} ${l} ${r}`;
}, "generateDashArray"), AS = /* @__PURE__ */ f(function(e, t, r, i, s, o, a, n = !1) {
  var D;
  if (!a)
    throw new Error(
      `insertEdge: missing diagramId for edge "${t.id}" — edge IDs require a diagram prefix for uniqueness`
    );
  const { handDrawnSeed: l } = gt();
  let h = t.points, c = !1;
  const u = s;
  var p = o;
  const d = [];
  for (const v in t.cssCompiledStyles)
    Hp(v) || d.push(t.cssCompiledStyles[v]);
  q.debug("UIO intersect check", t.points, p.x, u.x), p.intersect && u.intersect && !n && (h = h.slice(1, t.points.length - 1), h.unshift(u.intersect(h[0])), q.debug(
    "Last point UIO",
    t.start,
    "-->",
    t.end,
    h[h.length - 1],
    p,
    p.intersect(h[h.length - 1])
  ), h.push(p.intersect(h[h.length - 1])));
  const g = btoa(JSON.stringify(h));
  t.toCluster && (q.info("to cluster abc88", r.get(t.toCluster)), h = rc(t.points, r.get(t.toCluster).node), c = !0), t.fromCluster && (q.debug(
    "from cluster abc88",
    r.get(t.fromCluster),
    JSON.stringify(h, null, 2)
  ), h = rc(h.reverse(), r.get(t.fromCluster).node).reverse(), c = !0);
  let m = h.filter((v) => !Number.isNaN(v.y));
  const y = TS(t.curve);
  y !== "rounded" && (m = vS(m));
  let x = Hi;
  switch (y) {
    case "linear":
      x = Hi;
      break;
    case "basis":
      x = Ia;
      break;
    case "cardinal":
      x = Ru;
      break;
    case "bumpX":
      x = Mu;
      break;
    case "bumpY":
      x = Iu;
      break;
    case "catmullRom":
      x = Nu;
      break;
    case "monotoneX":
      x = Xu;
      break;
    case "monotoneY":
      x = Uu;
      break;
    case "natural":
      x = Gu;
      break;
    case "step":
      x = Vu;
      break;
    case "stepAfter":
      x = Ku;
      break;
    case "stepBefore":
      x = Zu;
      break;
    case "rounded":
      x = Hi;
      break;
    default:
      x = Ia;
  }
  const { x: b, y: k } = p2(t), w = Zk().x(b).y(k).curve(x);
  let S;
  switch (t.thickness) {
    case "normal":
      S = "edge-thickness-normal";
      break;
    case "thick":
      S = "edge-thickness-thick";
      break;
    case "invisible":
      S = "edge-thickness-invisible";
      break;
    default:
      S = "edge-thickness-normal";
  }
  switch (t.pattern) {
    case "solid":
      S += " edge-pattern-solid";
      break;
    case "dotted":
      S += " edge-pattern-dotted";
      break;
    case "dashed":
      S += " edge-pattern-dashed";
      break;
    default:
      S += " edge-pattern-solid";
  }
  let L, T = y === "rounded" ? qg(Wg(m, t), 5) : w(m);
  const B = Array.isArray(t.style) ? t.style : [t.style];
  let N = B.find((v) => v == null ? void 0 : v.startsWith("stroke:")), O = "";
  t.animate && (O = "edge-animation-fast"), t.animation && (O = "edge-animation-" + t.animation);
  let F = !1;
  if (t.look === "handDrawn") {
    const v = G.svg(e);
    Object.assign([], m);
    const R = v.path(T, {
      roughness: 0.3,
      seed: l
    });
    S += " transition", L = ct(R).select("path").attr("id", `${a}-${t.id}`).attr(
      "class",
      " " + S + (t.classes ? " " + t.classes : "") + (O ? " " + O : "")
    ).attr("style", B ? B.reduce((X, ot) => X + ";" + ot, "") : "");
    let z = L.attr("d");
    L.attr("d", z), e.node().appendChild(L.node());
  } else {
    const v = d.join(";"), R = B ? B.reduce((j, dt) => j + dt + ";", "") : "", z = (v ? v + ";" + R + ";" : R) + ";" + (B ? B.reduce((j, dt) => j + ";" + dt, "") : "");
    L = e.append("path").attr("d", T).attr("id", `${a}-${t.id}`).attr(
      "class",
      " " + S + (t.classes ? " " + t.classes : "") + (O ? " " + O : "")
    ).attr("style", z), N = (D = z.match(/stroke:([^;]+)/)) == null ? void 0 : D[1], F = t.animate === !0 || !!t.animation || v.includes("animation");
    const X = L.node(), ot = typeof X.getTotalLength == "function" ? X.getTotalLength() : 0, tt = Lh[t.arrowTypeStart] || 0, st = Lh[t.arrowTypeEnd] || 0;
    if (t.look === "neo" && !F) {
      const dt = `stroke-dasharray: ${t.pattern === "dotted" || t.pattern === "dashed" ? LS(ot, tt, st) : `0 ${tt} ${ot - tt - st} ${st}`}; stroke-dashoffset: 0;`;
      L.attr("style", dt + L.attr("style"));
    }
  }
  L.attr("data-edge", !0), L.attr("data-et", "edge"), L.attr("data-id", t.id), L.attr("data-points", g), L.attr("data-look", Rt(t.look)), t.showPoints && m.forEach((v) => {
    e.append("circle").style("stroke", "red").style("fill", "red").attr("r", 1).attr("cx", v.x).attr("cy", v.y);
  });
  let Y = "";
  (gt().flowchart.arrowMarkerAbsolute || gt().state.arrowMarkerAbsolute) && (Y = window.location.protocol + "//" + window.location.host + window.location.pathname + window.location.search, Y = Y.replace(/\(/g, "\\(").replace(/\)/g, "\\)")), q.info("arrowTypeStart", t.arrowTypeStart), q.info("arrowTypeEnd", t.arrowTypeEnd);
  const H = !F && (t == null ? void 0 : t.look) === "neo";
  CS(L, t, Y, a, i, H, N);
  const P = Math.floor(h.length / 2), M = h[P];
  ke.isLabelCoordinateInPath(M, L.attr("d")) || (c = !0);
  let E = {};
  return c && (E.updatedPath = h), E.originalPath = t.points, E;
}, "insertEdge");
function qg(e, t) {
  if (e.length < 2)
    return "";
  let r = "";
  const i = e.length, s = 1e-5;
  for (let o = 0; o < i; o++) {
    const a = e[o], n = e[o - 1], l = e[o + 1];
    if (o === 0)
      r += `M${a.x},${a.y}`;
    else if (o === i - 1)
      r += `L${a.x},${a.y}`;
    else {
      const h = a.x - n.x, c = a.y - n.y, u = l.x - a.x, p = l.y - a.y, d = Math.hypot(h, c), g = Math.hypot(u, p);
      if (d < s || g < s) {
        r += `L${a.x},${a.y}`;
        continue;
      }
      const m = h / d, y = c / d, x = u / g, b = p / g, k = m * x + y * b, w = Math.max(-1, Math.min(1, k)), S = Math.acos(w);
      if (S < s || Math.abs(Math.PI - S) < s) {
        r += `L${a.x},${a.y}`;
        continue;
      }
      const L = Math.min(t / Math.sin(S / 2), d / 2, g / 2), T = a.x - m * L, B = a.y - y * L, N = a.x + x * L, O = a.y + b * L;
      r += `L${T},${B}`, r += `Q${a.x},${a.y} ${N},${O}`;
    }
  }
  return r;
}
f(qg, "generateRoundedPath");
function on(e, t) {
  if (!e || !t)
    return { angle: 0, deltaX: 0, deltaY: 0 };
  const r = t.x - e.x, i = t.y - e.y;
  return { angle: Math.atan2(i, r), deltaX: r, deltaY: i };
}
f(on, "calculateDeltaAndAngle");
function Wg(e, t) {
  const r = e.map((s) => ({ ...s }));
  if (e.length >= 2 && Ht[t.arrowTypeStart]) {
    const s = Ht[t.arrowTypeStart], o = e[0], a = e[1], { angle: n } = on(o, a), l = s * Math.cos(n), h = s * Math.sin(n);
    r[0].x = o.x + l, r[0].y = o.y + h;
  }
  const i = e.length;
  if (i >= 2 && Ht[t.arrowTypeEnd]) {
    const s = Ht[t.arrowTypeEnd], o = e[i - 1], a = e[i - 2], { angle: n } = on(a, o), l = s * Math.cos(n), h = s * Math.sin(n);
    r[i - 1].x = o.x - l, r[i - 1].y = o.y - h;
  }
  return r;
}
f(Wg, "applyMarkerOffsetsToPoints");
var ES = /* @__PURE__ */ f((e, t, r, i) => {
  t.forEach((s) => {
    JS[s](e, r, i);
  });
}, "insertMarkers"), FS = /* @__PURE__ */ f((e, t, r) => {
  q.trace("Making markers for ", r), e.append("defs").append("marker").attr("id", r + "_" + t + "-extensionStart").attr("class", "marker extension " + t).attr("refX", 18).attr("refY", 7).attr("markerWidth", 190).attr("markerHeight", 240).attr("orient", "auto").attr("markerUnits", "userSpaceOnUse").append("path").attr("d", "M 1,7 L18,13 V 1 Z"), e.append("defs").append("marker").attr("id", r + "_" + t + "-extensionEnd").attr("class", "marker extension " + t).attr("refX", 1).attr("refY", 7).attr("markerWidth", 20).attr("markerHeight", 28).attr("orient", "auto").append("path").attr("d", "M 1,1 V 13 L18,7 Z"), e.append("marker").attr("id", r + "_" + t + "-extensionStart-margin").attr("class", "marker extension " + t).attr("refX", 18).attr("refY", 7).attr("markerWidth", 20).attr("markerHeight", 28).attr("orient", "auto").attr("markerUnits", "userSpaceOnUse").attr("viewBox", "0 0 20 14").append("polygon").attr("points", "10,7 18,13 18,1").style("stroke-width", 2).style("stroke-dasharray", "0"), e.append("defs").append("marker").attr("id", r + "_" + t + "-extensionEnd-margin").attr("class", "marker extension " + t).attr("refX", 9).attr("refY", 7).attr("markerWidth", 20).attr("markerHeight", 28).attr("orient", "auto").attr("markerUnits", "userSpaceOnUse").attr("viewBox", "0 0 20 14").append("polygon").attr("points", "10,1 10,13 18,7").style("stroke-width", 2).style("stroke-dasharray", "0");
}, "extension"), MS = /* @__PURE__ */ f((e, t, r) => {
  e.append("defs").append("marker").attr("id", r + "_" + t + "-compositionStart").attr("class", "marker composition " + t).attr("refX", 18).attr("refY", 7).attr("markerWidth", 190).attr("markerHeight", 240).attr("orient", "auto").append("path").attr("d", "M 18,7 L9,13 L1,7 L9,1 Z"), e.append("defs").append("marker").attr("id", r + "_" + t + "-compositionEnd").attr("class", "marker composition " + t).attr("refX", 1).attr("refY", 7).attr("markerWidth", 20).attr("markerHeight", 28).attr("orient", "auto").append("path").attr("d", "M 18,7 L9,13 L1,7 L9,1 Z"), e.append("defs").append("marker").attr("id", r + "_" + t + "-compositionStart-margin").attr("class", "marker composition " + t).attr("refX", 15).attr("refY", 7).attr("markerWidth", 190).attr("markerHeight", 240).attr("orient", "auto").attr("markerUnits", "userSpaceOnUse").append("path").style("stroke-width", 0).attr("viewBox", "0 0 15 15").attr("d", "M 18,7 L9,13 L1,7 L9,1 Z"), e.append("defs").append("marker").attr("id", r + "_" + t + "-compositionEnd-margin").attr("class", "marker composition " + t).attr("refX", 3.5).attr("refY", 7).attr("markerWidth", 20).attr("markerHeight", 28).attr("orient", "auto").attr("markerUnits", "userSpaceOnUse").append("path").style("stroke-width", 0).attr("d", "M 18,7 L9,13 L1,7 L9,1 Z");
}, "composition"), IS = /* @__PURE__ */ f((e, t, r) => {
  e.append("defs").append("marker").attr("id", r + "_" + t + "-aggregationStart").attr("class", "marker aggregation " + t).attr("refX", 18).attr("refY", 7).attr("markerWidth", 190).attr("markerHeight", 240).attr("orient", "auto").append("path").attr("d", "M 18,7 L9,13 L1,7 L9,1 Z"), e.append("defs").append("marker").attr("id", r + "_" + t + "-aggregationEnd").attr("class", "marker aggregation " + t).attr("refX", 1).attr("refY", 7).attr("markerWidth", 20).attr("markerHeight", 28).attr("orient", "auto").append("path").attr("d", "M 18,7 L9,13 L1,7 L9,1 Z"), e.append("defs").append("marker").attr("id", r + "_" + t + "-aggregationStart-margin").attr("class", "marker aggregation " + t).attr("refX", 15).attr("refY", 7).attr("markerWidth", 190).attr("markerHeight", 240).attr("orient", "auto").attr("markerUnits", "userSpaceOnUse").append("path").style("stroke-width", 2).attr("d", "M 18,7 L9,13 L1,7 L9,1 Z"), e.append("defs").append("marker").attr("id", r + "_" + t + "-aggregationEnd-margin").attr("class", "marker aggregation " + t).attr("refX", 1).attr("refY", 7).attr("markerWidth", 20).attr("markerHeight", 28).attr("orient", "auto").attr("markerUnits", "userSpaceOnUse").append("path").style("stroke-width", 2).attr("d", "M 18,7 L9,13 L1,7 L9,1 Z");
}, "aggregation"), $S = /* @__PURE__ */ f((e, t, r) => {
  e.append("defs").append("marker").attr("id", r + "_" + t + "-dependencyStart").attr("class", "marker dependency " + t).attr("refX", 6).attr("refY", 7).attr("markerWidth", 190).attr("markerHeight", 240).attr("orient", "auto").append("path").attr("d", "M 5,7 L9,13 L1,7 L9,1 Z"), e.append("defs").append("marker").attr("id", r + "_" + t + "-dependencyEnd").attr("class", "marker dependency " + t).attr("refX", 13).attr("refY", 7).attr("markerWidth", 20).attr("markerHeight", 28).attr("orient", "auto").append("path").attr("d", "M 18,7 L9,13 L14,7 L9,1 Z"), e.append("defs").append("marker").attr("id", r + "_" + t + "-dependencyStart-margin").attr("class", "marker dependency " + t).attr("refX", 4).attr("refY", 7).attr("markerWidth", 190).attr("markerHeight", 240).attr("orient", "auto").attr("markerUnits", "userSpaceOnUse").append("path").style("stroke-width", 0).attr("d", "M 5,7 L9,13 L1,7 L9,1 Z"), e.append("defs").append("marker").attr("id", r + "_" + t + "-dependencyEnd-margin").attr("class", "marker dependency " + t).attr("refX", 16).attr("refY", 7).attr("markerWidth", 20).attr("markerHeight", 28).attr("orient", "auto").attr("markerUnits", "userSpaceOnUse").append("path").style("stroke-width", 0).attr("d", "M 18,7 L9,13 L14,7 L9,1 Z");
}, "dependency"), OS = /* @__PURE__ */ f((e, t, r) => {
  e.append("defs").append("marker").attr("id", r + "_" + t + "-lollipopStart").attr("class", "marker lollipop " + t).attr("refX", 13).attr("refY", 7).attr("markerWidth", 190).attr("markerHeight", 240).attr("orient", "auto").append("circle").attr("fill", "transparent").attr("cx", 7).attr("cy", 7).attr("r", 6), e.append("defs").append("marker").attr("id", r + "_" + t + "-lollipopEnd").attr("class", "marker lollipop " + t).attr("refX", 1).attr("refY", 7).attr("markerWidth", 190).attr("markerHeight", 240).attr("orient", "auto").append("circle").attr("fill", "transparent").attr("cx", 7).attr("cy", 7).attr("r", 6), e.append("defs").append("marker").attr("id", r + "_" + t + "-lollipopStart-margin").attr("class", "marker lollipop " + t).attr("refX", 13).attr("refY", 7).attr("markerWidth", 190).attr("markerHeight", 240).attr("orient", "auto").attr("markerUnits", "userSpaceOnUse").append("circle").attr("fill", "transparent").attr("cx", 7).attr("cy", 7).attr("r", 6).attr("stroke-width", 2), e.append("defs").append("marker").attr("id", r + "_" + t + "-lollipopEnd-margin").attr("class", "marker lollipop " + t).attr("refX", 1).attr("refY", 7).attr("markerWidth", 190).attr("markerHeight", 240).attr("orient", "auto").attr("markerUnits", "userSpaceOnUse").append("circle").attr("fill", "transparent").attr("cx", 7).attr("cy", 7).attr("r", 6).attr("stroke-width", 2);
}, "lollipop"), DS = /* @__PURE__ */ f((e, t, r) => {
  e.append("marker").attr("id", r + "_" + t + "-pointEnd").attr("class", "marker " + t).attr("viewBox", "0 0 10 10").attr("refX", 5).attr("refY", 5).attr("markerUnits", "userSpaceOnUse").attr("markerWidth", 8).attr("markerHeight", 8).attr("orient", "auto").append("path").attr("d", "M 0 0 L 10 5 L 0 10 z").attr("class", "arrowMarkerPath").style("stroke-width", 1).style("stroke-dasharray", "1,0"), e.append("marker").attr("id", r + "_" + t + "-pointStart").attr("class", "marker " + t).attr("viewBox", "0 0 10 10").attr("refX", 4.5).attr("refY", 5).attr("markerUnits", "userSpaceOnUse").attr("markerWidth", 8).attr("markerHeight", 8).attr("orient", "auto").append("path").attr("d", "M 0 5 L 10 10 L 10 0 z").attr("class", "arrowMarkerPath").style("stroke-width", 1).style("stroke-dasharray", "1,0"), e.append("marker").attr("id", r + "_" + t + "-pointEnd-margin").attr("class", "marker " + t).attr("viewBox", "0 0 11.5 14").attr("refX", 11.5).attr("refY", 7).attr("markerUnits", "userSpaceOnUse").attr("markerWidth", 10.5).attr("markerHeight", 14).attr("orient", "auto").append("path").attr("d", "M 0 0 L 11.5 7 L 0 14 z").attr("class", "arrowMarkerPath").style("stroke-width", 0).style("stroke-dasharray", "1,0"), e.append("marker").attr("id", r + "_" + t + "-pointStart-margin").attr("class", "marker " + t).attr("viewBox", "0 0 11.5 14").attr("refX", 1).attr("refY", 7).attr("markerUnits", "userSpaceOnUse").attr("markerWidth", 11.5).attr("markerHeight", 14).attr("orient", "auto").append("polygon").attr("points", "0,7 11.5,14 11.5,0").attr("class", "arrowMarkerPath").style("stroke-width", 0).style("stroke-dasharray", "1,0");
}, "point"), RS = /* @__PURE__ */ f((e, t, r) => {
  e.append("marker").attr("id", r + "_" + t + "-circleEnd").attr("class", "marker " + t).attr("viewBox", "0 0 10 10").attr("refX", 11).attr("refY", 5).attr("markerUnits", "userSpaceOnUse").attr("markerWidth", 11).attr("markerHeight", 11).attr("orient", "auto").append("circle").attr("cx", "5").attr("cy", "5").attr("r", "5").attr("class", "arrowMarkerPath").style("stroke-width", 1).style("stroke-dasharray", "1,0"), e.append("marker").attr("id", r + "_" + t + "-circleStart").attr("class", "marker " + t).attr("viewBox", "0 0 10 10").attr("refX", -1).attr("refY", 5).attr("markerUnits", "userSpaceOnUse").attr("markerWidth", 11).attr("markerHeight", 11).attr("orient", "auto").append("circle").attr("cx", "5").attr("cy", "5").attr("r", "5").attr("class", "arrowMarkerPath").style("stroke-width", 1).style("stroke-dasharray", "1,0"), e.append("marker").attr("id", r + "_" + t + "-circleEnd-margin").attr("class", "marker " + t).attr("viewBox", "0 0 10 10").attr("refY", 5).attr("refX", 12.25).attr("markerUnits", "userSpaceOnUse").attr("markerWidth", 14).attr("markerHeight", 14).attr("orient", "auto").append("circle").attr("cx", "5").attr("cy", "5").attr("r", "5").attr("class", "arrowMarkerPath").style("stroke-width", 0).style("stroke-dasharray", "1,0"), e.append("marker").attr("id", r + "_" + t + "-circleStart-margin").attr("class", "marker " + t).attr("viewBox", "0 0 10 10").attr("refX", -2).attr("refY", 5).attr("markerUnits", "userSpaceOnUse").attr("markerWidth", 14).attr("markerHeight", 14).attr("orient", "auto").append("circle").attr("cx", "5").attr("cy", "5").attr("r", "5").attr("class", "arrowMarkerPath").style("stroke-width", 0).style("stroke-dasharray", "1,0");
}, "circle"), PS = /* @__PURE__ */ f((e, t, r) => {
  e.append("marker").attr("id", r + "_" + t + "-crossEnd").attr("class", "marker cross " + t).attr("viewBox", "0 0 11 11").attr("refX", 12).attr("refY", 5.2).attr("markerUnits", "userSpaceOnUse").attr("markerWidth", 11).attr("markerHeight", 11).attr("orient", "auto").append("path").attr("d", "M 1,1 l 9,9 M 10,1 l -9,9").attr("class", "arrowMarkerPath").style("stroke-width", 2).style("stroke-dasharray", "1,0"), e.append("marker").attr("id", r + "_" + t + "-crossStart").attr("class", "marker cross " + t).attr("viewBox", "0 0 11 11").attr("refX", -1).attr("refY", 5.2).attr("markerUnits", "userSpaceOnUse").attr("markerWidth", 11).attr("markerHeight", 11).attr("orient", "auto").append("path").attr("d", "M 1,1 l 9,9 M 10,1 l -9,9").attr("class", "arrowMarkerPath").style("stroke-width", 2).style("stroke-dasharray", "1,0"), e.append("marker").attr("id", r + "_" + t + "-crossEnd-margin").attr("class", "marker cross " + t).attr("viewBox", "0 0 15 15").attr("refX", 17.7).attr("refY", 7.5).attr("markerUnits", "userSpaceOnUse").attr("markerWidth", 12).attr("markerHeight", 12).attr("orient", "auto").append("path").attr("d", "M 1,1 L 14,14 M 1,14 L 14,1").attr("class", "arrowMarkerPath").style("stroke-width", 2.5), e.append("marker").attr("id", r + "_" + t + "-crossStart-margin").attr("class", "marker cross " + t).attr("viewBox", "0 0 15 15").attr("refX", -3.5).attr("refY", 7.5).attr("markerUnits", "userSpaceOnUse").attr("markerWidth", 12).attr("markerHeight", 12).attr("orient", "auto").append("path").attr("d", "M 1,1 L 14,14 M 1,14 L 14,1").attr("class", "arrowMarkerPath").style("stroke-width", 2.5).style("stroke-dasharray", "1,0");
}, "cross"), NS = /* @__PURE__ */ f((e, t, r) => {
  e.append("defs").append("marker").attr("id", r + "_" + t + "-barbEnd").attr("refX", 19).attr("refY", 7).attr("markerWidth", 20).attr("markerHeight", 14).attr("markerUnits", "userSpaceOnUse").attr("orient", "auto").append("path").attr("d", "M 19,7 L9,13 L14,7 L9,1 Z");
}, "barb"), qS = /* @__PURE__ */ f((e, t, r) => {
  const i = wt(), { themeVariables: s } = i, { transitionColor: o } = s;
  e.append("defs").append("marker").attr("id", r + "_" + t + "-barbEnd").attr("refX", 19).attr("refY", 7).attr("markerWidth", 20).attr("markerHeight", 14).attr("markerUnits", "strokeWidth").attr("orient", "auto").append("path").attr("d", "M 19,7 L11,14 L13,7 L11,0 Z"), e.append("defs").append("marker").attr("id", r + "_" + t + "-barbEnd-margin").attr("refX", 17).attr("refY", 7).attr("markerWidth", 20).attr("markerHeight", 14).attr("markerUnits", "userSpaceOnUse").attr("orient", "auto").append("path").attr("d", "M 19,7 L11,14 L13,7 L11,0 Z").attr("fill", `${o}`);
}, "barbNeo"), WS = /* @__PURE__ */ f((e, t, r) => {
  e.append("defs").append("marker").attr("id", r + "_" + t + "-onlyOneStart").attr("class", "marker onlyOne " + t).attr("refX", 0).attr("refY", 9).attr("markerWidth", 18).attr("markerHeight", 18).attr("orient", "auto").append("path").attr("d", "M9,0 L9,18 M15,0 L15,18"), e.append("defs").append("marker").attr("id", r + "_" + t + "-onlyOneEnd").attr("class", "marker onlyOne " + t).attr("refX", 18).attr("refY", 9).attr("markerWidth", 18).attr("markerHeight", 18).attr("orient", "auto").append("path").attr("d", "M3,0 L3,18 M9,0 L9,18");
}, "only_one"), zS = /* @__PURE__ */ f((e, t, r) => {
  const i = e.append("defs").append("marker").attr("id", r + "_" + t + "-zeroOrOneStart").attr("class", "marker zeroOrOne " + t).attr("refX", 0).attr("refY", 9).attr("markerWidth", 30).attr("markerHeight", 18).attr("orient", "auto");
  i.append("circle").attr("fill", "white").attr("cx", 21).attr("cy", 9).attr("r", 6), i.append("path").attr("d", "M9,0 L9,18");
  const s = e.append("defs").append("marker").attr("id", r + "_" + t + "-zeroOrOneEnd").attr("class", "marker zeroOrOne " + t).attr("refX", 30).attr("refY", 9).attr("markerWidth", 30).attr("markerHeight", 18).attr("orient", "auto");
  s.append("circle").attr("fill", "white").attr("cx", 9).attr("cy", 9).attr("r", 6), s.append("path").attr("d", "M21,0 L21,18");
}, "zero_or_one"), HS = /* @__PURE__ */ f((e, t, r) => {
  e.append("defs").append("marker").attr("id", r + "_" + t + "-oneOrMoreStart").attr("class", "marker oneOrMore " + t).attr("refX", 18).attr("refY", 18).attr("markerWidth", 45).attr("markerHeight", 36).attr("orient", "auto").append("path").attr("d", "M0,18 Q 18,0 36,18 Q 18,36 0,18 M42,9 L42,27"), e.append("defs").append("marker").attr("id", r + "_" + t + "-oneOrMoreEnd").attr("class", "marker oneOrMore " + t).attr("refX", 27).attr("refY", 18).attr("markerWidth", 45).attr("markerHeight", 36).attr("orient", "auto").append("path").attr("d", "M3,9 L3,27 M9,18 Q27,0 45,18 Q27,36 9,18");
}, "one_or_more"), YS = /* @__PURE__ */ f((e, t, r) => {
  const i = e.append("defs").append("marker").attr("id", r + "_" + t + "-zeroOrMoreStart").attr("class", "marker zeroOrMore " + t).attr("refX", 18).attr("refY", 18).attr("markerWidth", 57).attr("markerHeight", 36).attr("orient", "auto");
  i.append("circle").attr("fill", "white").attr("cx", 48).attr("cy", 18).attr("r", 6), i.append("path").attr("d", "M0,18 Q18,0 36,18 Q18,36 0,18");
  const s = e.append("defs").append("marker").attr("id", r + "_" + t + "-zeroOrMoreEnd").attr("class", "marker zeroOrMore " + t).attr("refX", 39).attr("refY", 18).attr("markerWidth", 57).attr("markerHeight", 36).attr("orient", "auto");
  s.append("circle").attr("fill", "white").attr("cx", 9).attr("cy", 18).attr("r", 6), s.append("path").attr("d", "M21,18 Q39,0 57,18 Q39,36 21,18");
}, "zero_or_more"), XS = /* @__PURE__ */ f((e, t, r) => {
  const i = wt(), { themeVariables: s } = i, { strokeWidth: o } = s;
  e.append("defs").append("marker").attr("id", r + "_" + t + "-onlyOneStart").attr("class", "marker onlyOne " + t).attr("refX", 0).attr("refY", 9).attr("markerWidth", 18).attr("markerHeight", 18).attr("orient", "auto").attr("markerUnits", "userSpaceOnUse").append("path").attr("d", "M9,0 L9,18 M15,0 L15,18").attr("stroke-width", `${o}`), e.append("defs").append("marker").attr("id", r + "_" + t + "-onlyOneEnd").attr("class", "marker onlyOne " + t).attr("refX", 18).attr("refY", 9).attr("markerWidth", 18).attr("markerHeight", 18).attr("orient", "auto").attr("markerUnits", "userSpaceOnUse").append("path").attr("d", "M3,0 L3,18 M9,0 L9,18").attr("stroke-width", `${o}`);
}, "only_one_neo"), US = /* @__PURE__ */ f((e, t, r) => {
  const i = wt(), { themeVariables: s } = i, { strokeWidth: o, mainBkg: a } = s, n = e.append("defs").append("marker").attr("id", r + "_" + t + "-zeroOrOneStart").attr("class", "marker zeroOrOne " + t).attr("refX", 0).attr("refY", 9).attr("markerWidth", 30).attr("markerHeight", 18).attr("orient", "auto").attr("markerUnits", "userSpaceOnUse");
  n.append("circle").attr("fill", a ?? "white").attr("cx", 21).attr("cy", 9).attr("stroke-width", `${o}`).attr("r", 6), n.append("path").attr("d", "M9,0 L9,18").attr("stroke-width", `${o}`);
  const l = e.append("defs").append("marker").attr("id", r + "_" + t + "-zeroOrOneEnd").attr("class", "marker zeroOrOne " + t).attr("refX", 30).attr("refY", 9).attr("markerWidth", 30).attr("markerHeight", 18).attr("markerUnits", "userSpaceOnUse").attr("orient", "auto");
  l.append("circle").attr("fill", a ?? "white").attr("cx", 9).attr("cy", 9).attr("stroke-width", `${o}`).attr("r", 6), l.append("path").attr("d", "M21,0 L21,18").attr("stroke-width", `${o}`);
}, "zero_or_one_neo"), jS = /* @__PURE__ */ f((e, t, r) => {
  const i = wt(), { themeVariables: s } = i, { strokeWidth: o } = s;
  e.append("defs").append("marker").attr("id", r + "_" + t + "-oneOrMoreStart").attr("class", "marker oneOrMore " + t).attr("refX", 18).attr("refY", 18).attr("markerWidth", 45).attr("markerHeight", 36).attr("orient", "auto").attr("markerUnits", "userSpaceOnUse").append("path").attr("d", "M0,18 Q 18,0 36,18 Q 18,36 0,18 M42,9 L42,27").attr("stroke-width", `${o}`), e.append("defs").append("marker").attr("id", r + "_" + t + "-oneOrMoreEnd").attr("class", "marker oneOrMore " + t).attr("refX", 27).attr("refY", 18).attr("markerWidth", 45).attr("markerHeight", 36).attr("markerUnits", "userSpaceOnUse").attr("orient", "auto").append("path").attr("d", "M3,9 L3,27 M9,18 Q27,0 45,18 Q27,36 9,18").attr("stroke-width", `${o}`);
}, "one_or_more_neo"), GS = /* @__PURE__ */ f((e, t, r) => {
  const i = wt(), { themeVariables: s } = i, { strokeWidth: o, mainBkg: a } = s, n = e.append("defs").append("marker").attr("id", r + "_" + t + "-zeroOrMoreStart").attr("class", "marker zeroOrMore " + t).attr("refX", 18).attr("refY", 18).attr("markerWidth", 57).attr("markerHeight", 36).attr("markerUnits", "userSpaceOnUse").attr("orient", "auto");
  n.append("circle").attr("fill", a ?? "white").attr("cx", 45.5).attr("cy", 18).attr("r", 6).attr("stroke-width", `${o}`), n.append("path").attr("d", "M0,18 Q18,0 36,18 Q18,36 0,18").attr("stroke-width", `${o}`);
  const l = e.append("defs").append("marker").attr("id", r + "_" + t + "-zeroOrMoreEnd").attr("class", "marker zeroOrMore " + t).attr("refX", 39).attr("refY", 18).attr("markerWidth", 57).attr("markerHeight", 36).attr("orient", "auto").attr("markerUnits", "userSpaceOnUse");
  l.append("circle").attr("fill", a ?? "white").attr("cx", 11).attr("cy", 18).attr("r", 6).attr("stroke-width", `${o}`), l.append("path").attr("d", "M21,18 Q39,0 57,18 Q39,36 21,18").attr("stroke-width", `${o}`);
}, "zero_or_more_neo"), VS = /* @__PURE__ */ f((e, t, r) => {
  e.append("defs").append("marker").attr("id", r + "_" + t + "-requirement_arrowEnd").attr("refX", 20).attr("refY", 10).attr("markerWidth", 20).attr("markerHeight", 20).attr("orient", "auto").append("path").attr(
    "d",
    `M0,0
      L20,10
      M20,10
      L0,20`
  );
}, "requirement_arrow"), ZS = /* @__PURE__ */ f((e, t, r) => {
  const i = wt(), { themeVariables: s } = i, { strokeWidth: o } = s;
  e.append("defs").append("marker").attr("id", r + "_" + t + "-requirement_arrowEnd").attr("refX", 20).attr("refY", 10).attr("markerWidth", 20).attr("markerHeight", 20).attr("orient", "auto").attr("markerUnits", "userSpaceOnUse").attr("stroke-width", `${o}`).attr("viewBox", "0 0 25 20").append("path").attr(
    "d",
    `M0,0
      L20,10
      M20,10
      L0,20`
  ).attr("stroke-linejoin", "miter");
}, "requirement_arrow_neo"), KS = /* @__PURE__ */ f((e, t, r) => {
  const i = e.append("defs").append("marker").attr("id", r + "_" + t + "-requirement_containsStart").attr("refX", 0).attr("refY", 10).attr("markerWidth", 20).attr("markerHeight", 20).attr("orient", "auto").append("g");
  i.append("circle").attr("cx", 10).attr("cy", 10).attr("r", 9).attr("fill", "none"), i.append("line").attr("x1", 1).attr("x2", 19).attr("y1", 10).attr("y2", 10), i.append("line").attr("y1", 1).attr("y2", 19).attr("x1", 10).attr("x2", 10);
}, "requirement_contains"), QS = /* @__PURE__ */ f((e, t, r) => {
  const i = wt(), { themeVariables: s } = i, { strokeWidth: o } = s, a = e.append("defs").append("marker").attr("id", r + "_" + t + "-requirement_containsStart").attr("refX", 0).attr("refY", 10).attr("markerWidth", 20).attr("markerHeight", 20).attr("orient", "auto").attr("markerUnits", "userSpaceOnUse").append("g");
  a.append("circle").attr("cx", 10).attr("cy", 10).attr("r", 9).attr("fill", "none"), a.append("line").attr("x1", 1).attr("x2", 19).attr("y1", 10).attr("y2", 10), a.append("line").attr("y1", 1).attr("y2", 19).attr("x1", 10).attr("x2", 10), a.selectAll("*").attr("stroke-width", `${o}`);
}, "requirement_contains_neo"), JS = {
  extension: FS,
  composition: MS,
  aggregation: IS,
  dependency: $S,
  lollipop: OS,
  point: DS,
  circle: RS,
  cross: PS,
  barb: NS,
  barbNeo: qS,
  only_one: WS,
  zero_or_one: zS,
  one_or_more: HS,
  zero_or_more: YS,
  only_one_neo: XS,
  zero_or_one_neo: US,
  one_or_more_neo: jS,
  zero_or_more_neo: GS,
  requirement_arrow: VS,
  requirement_contains: KS,
  requirement_arrow_neo: ZS,
  requirement_contains_neo: QS
}, tw = ES, ew = {
  common: ls,
  getConfig: wt,
  insertCluster: QT,
  insertEdge: AS,
  insertEdgeLabel: SS,
  insertMarkers: tw,
  insertNode: Pg,
  interpolateToCurve: Xn,
  labelHelper: at,
  log: q,
  positionEdgeLabel: wS
}, is = {}, zg = /* @__PURE__ */ f((e) => {
  for (const t of e)
    is[t.name] = t;
}, "registerLayoutLoaders"), rw = /* @__PURE__ */ f(() => {
  zg([
    {
      name: "dagre",
      loader: /* @__PURE__ */ f(async () => await import("./excalidraw-dagre-KV5264BT.js"), "loader")
    },
    {
      name: "cose-bilkent",
      loader: /* @__PURE__ */ f(async () => await import("./excalidraw-cose-bilkent-S5V4N54A.js"), "loader")
    }
  ]);
}, "registerDefaultLayoutLoaders");
rw();
var QL = /* @__PURE__ */ f(async (e, t) => {
  if (!(e.layoutAlgorithm in is))
    throw new Error(`Unknown layout algorithm: ${e.layoutAlgorithm}`);
  if (e.diagramId)
    for (const c of e.nodes) {
      const u = c.domId || c.id;
      c.domId = `${e.diagramId}-${u}`;
    }
  const r = is[e.layoutAlgorithm], i = await r.loader(), { theme: s, themeVariables: o } = e.config, { useGradient: a, gradientStart: n, gradientStop: l } = o, h = t.attr("id");
  if (t.append("defs").append("filter").attr("id", `${h}-drop-shadow`).attr("height", "130%").attr("width", "130%").append("feDropShadow").attr("dx", "4").attr("dy", "4").attr("stdDeviation", 0).attr("flood-opacity", "0.06").attr("flood-color", `${s != null && s.includes("dark") ? "#FFFFFF" : "#000000"}`), t.append("defs").append("filter").attr("id", `${h}-drop-shadow-small`).attr("height", "150%").attr("width", "150%").append("feDropShadow").attr("dx", "2").attr("dy", "2").attr("stdDeviation", 0).attr("flood-opacity", "0.06").attr("flood-color", `${s != null && s.includes("dark") ? "#FFFFFF" : "#000000"}`), a) {
    const c = t.append("linearGradient").attr("id", t.attr("id") + "-gradient").attr("gradientUnits", "objectBoundingBox").attr("x1", "0%").attr("y1", "0%").attr("x2", "100%").attr("y2", "0%");
    c.append("svg:stop").attr("offset", "0%").attr("stop-color", n).attr("stop-opacity", 1), c.append("svg:stop").attr("offset", "100%").attr("stop-color", l).attr("stop-opacity", 1);
  }
  return i.render(e, t, ew, {
    algorithm: r.algorithm
  });
}, "render"), JL = /* @__PURE__ */ f((e = "", { fallback: t = "dagre" } = {}) => {
  if (e in is)
    return e;
  if (t in is)
    return q.warn(`Layout algorithm ${e} is not registered. Using ${t} as fallback.`), t;
  throw new Error(`Both layout algorithms ${e} and ${t} are not registered.`);
}, "getRegisteredLayoutAlgorithm"), Hg = "comm", Yg = "rule", Xg = "decl", iw = "@import", sw = "@namespace", ow = "@keyframes", aw = "@layer", nw = Math.abs, Xi = String.fromCharCode;
function Ug(e) {
  return e.trim();
}
function an(e, t, r) {
  return e.replace(t, r);
}
function Xr(e, t) {
  return e.charCodeAt(t) | 0;
}
function pi(e, t, r) {
  return e.slice(t, r);
}
function Ie(e) {
  return e.length;
}
function lw(e) {
  return e.length;
}
function Fs(e, t) {
  return t.push(e), e;
}
var Oo = 1, fi = 1, jg = 0, pe = 0, Et = 0, xi = "";
function cl(e, t, r, i, s, o, a, n) {
  return { value: e, root: t, parent: r, type: i, props: s, children: o, line: Oo, column: fi, length: a, return: "", siblings: n };
}
function hw() {
  return Et;
}
function cw() {
  return Et = pe > 0 ? Xr(xi, --pe) : 0, fi--, Et === 10 && (fi = 1, Oo--), Et;
}
function Se() {
  return Et = pe < jg ? Xr(xi, pe++) : 0, fi++, Et === 10 && (fi = 1, Oo++), Et;
}
function er() {
  return Xr(xi, pe);
}
function Ws() {
  return pe;
}
function Do(e, t) {
  return pi(xi, e, t);
}
function ss(e) {
  switch (e) {
    // \0 \t \n \r \s whitespace token
    case 0:
    case 9:
    case 10:
    case 13:
    case 32:
      return 5;
    // ! + , / > @ ~ isolate token
    case 33:
    case 43:
    case 44:
    case 47:
    case 62:
    case 64:
    case 126:
    // ; { } breakpoint token
    case 59:
    case 123:
    case 125:
      return 4;
    // : accompanied token
    case 58:
      return 3;
    // " ' ( [ opening delimit token
    case 34:
    case 39:
    case 40:
    case 91:
      return 2;
    // ) ] closing delimit token
    case 41:
    case 93:
      return 1;
  }
  return 0;
}
function uw(e) {
  return Oo = fi = 1, jg = Ie(xi = e), pe = 0, [];
}
function dw(e) {
  return xi = "", e;
}
function ha(e) {
  return Ug(Do(pe - 1, nn(e === 91 ? e + 2 : e === 40 ? e + 1 : e)));
}
function pw(e) {
  for (; (Et = er()) && Et < 33; )
    Se();
  return ss(e) > 2 || ss(Et) > 3 ? "" : " ";
}
function fw(e, t) {
  for (; --t && Se() && !(Et < 48 || Et > 102 || Et > 57 && Et < 65 || Et > 70 && Et < 97); )
    ;
  return Do(e, Ws() + (t < 6 && er() == 32 && Se() == 32));
}
function nn(e) {
  for (; Se(); )
    switch (Et) {
      // ] ) " '
      case e:
        return pe;
      // " '
      case 34:
      case 39:
        e !== 34 && e !== 39 && nn(Et);
        break;
      // (
      case 40:
        e === 41 && nn(e);
        break;
      // \
      case 92:
        Se();
        break;
    }
  return pe;
}
function gw(e, t) {
  for (; Se() && e + Et !== 57; )
    if (e + Et === 84 && er() === 47)
      break;
  return "/*" + Do(t, pe - 1) + "*" + Xi(e === 47 ? e : Se());
}
function mw(e) {
  for (; !ss(er()); )
    Se();
  return Do(e, pe);
}
function yw(e) {
  return dw(zs("", null, null, null, [""], e = uw(e), 0, [0], e));
}
function zs(e, t, r, i, s, o, a, n, l) {
  for (var h = 0, c = 0, u = a, p = 0, d = 0, g = 0, m = 1, y = 1, x = 1, b = 0, k = 0, w = "", S = s, L = o, T = i, B = w; y; )
    switch (g = k, k = Se()) {
      // (
      case 40:
        g != 108 && Xr(B, u - 1) == 58 ? (b++, B += "(") : B += ha(k);
        break;
      // )
      case 41:
        b--, B += ")";
        break;
      // " ' [
      case 34:
      case 39:
      case 91:
        B += ha(k);
        break;
      // \t \n \r \s
      case 9:
      case 10:
      case 13:
      case 32:
        if (b > 0) {
          B += Xi(k);
          break;
        }
        B += pw(g);
        break;
      // \
      case 92:
        B += fw(Ws() - 1, 7);
        continue;
      // /
      case 47:
        switch (er()) {
          case 42:
          case 47:
            Fs(xw(gw(Se(), Ws()), t, r, l), l), (ss(g || 1) == 5 || ss(er() || 1) == 5) && Ie(B) && pi(B, -1, void 0) !== " " && (B += " ");
            break;
          default:
            B += "/";
        }
        break;
      // {
      case 123 * m:
        n[h++] = Ie(B) * x;
      // } ; \0
      case 125 * m:
      case 59:
      case 0:
        if (b > 0 && k) {
          B += Xi(k);
          break;
        }
        switch (k) {
          // \0 }
          case 0:
          case 125:
            y = 0;
          // ;
          case 59 + c:
            x == -1 && (B = an(B, /\f/g, "")), d > 0 && (Ie(B) - u || m === 0) && Fs(d > 32 ? oc(B + ";", i, r, u - 1, l) : oc(an(B, " ", "") + ";", i, r, u - 2, l), l);
            break;
          // @ ;
          case 59:
            B += ";";
          // { rule/at-rule
          default:
            if (Fs(T = sc(B, t, r, h, c, s, n, w, S = [], L = [], u, o), o), k === 123)
              if (c === 0)
                zs(B, t, T, T, S, o, u, n, L);
              else {
                switch (p) {
                  // c(ontainer)
                  case 99:
                    if (Xr(B, 3) === 110) break;
                  // l(ayer)
                  case 108:
                    if (Xr(B, 2) === 97) break;
                  default:
                    c = 0;
                  // d(ocument) m(edia) s(upports)
                  case 100:
                  case 109:
                  case 115:
                }
                c ? zs(e, T, T, i && Fs(sc(e, T, T, 0, 0, s, n, w, s, S = [], u, L), L), s, L, u, n, i ? S : L) : zs(B, T, T, T, [""], L, 0, n, L);
              }
        }
        h = c = d = 0, m = x = 1, w = B = "", u = a;
        break;
      // :
      case 58:
        u = 1 + Ie(B), d = g;
      default:
        if (m < 1) {
          if (k == 123)
            --m;
          else if (k == 125 && m++ == 0 && cw() == 125)
            continue;
        }
        switch (B += Xi(k), k * m) {
          // &
          case 38:
            x = c > 0 ? 1 : (B += "\f", -1);
            break;
          // ,
          case 44:
            if (b > 0) break;
            n[h++] = (Ie(B) - 1) * x, x = 1;
            break;
          // @
          case 64:
            er() === 45 && (B += ha(Se())), p = er(), c = u = Ie(w = B += mw(Ws())), k++;
            break;
          // -
          case 45:
            g === 45 && Ie(B) == 2 && (m = 0);
        }
    }
  return o;
}
function sc(e, t, r, i, s, o, a, n, l, h, c, u) {
  for (var p = s - 1, d = s === 0 ? o : [""], g = lw(d), m = 0, y = 0, x = 0; m < i; ++m)
    for (var b = 0, k = pi(e, p + 1, p = nw(y = a[m])), w = e; b < g; ++b)
      (w = Ug(y > 0 ? d[b] + " " + k : an(k, /&\f/g, d[b]))) && (l[x++] = w);
  return cl(e, t, r, s === 0 ? Yg : n, l, h, c, u);
}
function xw(e, t, r, i) {
  return cl(e, t, r, Hg, Xi(hw()), pi(e, 2, -2), 0, i);
}
function oc(e, t, r, i, s) {
  return cl(e, t, r, Xg, pi(e, 0, i), pi(e, i + 1, -1), i, s);
}
function ln(e, t) {
  for (var r = "", i = 0; i < e.length; i++)
    r += t(e[i], i, e, t) || "";
  return r;
}
function Cw(e, t, r, i) {
  switch (e.type) {
    case aw:
      if (e.children.length) break;
    case iw:
    case sw:
    case Xg:
      return e.return = e.return || e.value;
    case Hg:
      return "";
    case ow:
      return e.return = e.value + "{" + ln(e.children, i) + "}";
    case Yg:
      if (!Ie(e.value = e.props.join(","))) return "";
  }
  return Ie(r = ln(e.children, i)) ? e.return = e.value + "{" + r + "}" : "";
}
var Gg = "c4", bw = /* @__PURE__ */ f((e) => /^\s*C4Context|C4Container|C4Component|C4Dynamic|C4Deployment/.test(e), "detector"), kw = /* @__PURE__ */ f(async () => {
  const { diagram: e } = await import("./excalidraw-c4Diagram-AHTNJAMY.js");
  return { id: Gg, diagram: e };
}, "loader"), Tw = {
  id: Gg,
  detector: bw,
  loader: kw
}, Sw = Tw, Vg = "flowchart", ww = /* @__PURE__ */ f((e, t) => {
  var r, i;
  return ((r = t == null ? void 0 : t.flowchart) == null ? void 0 : r.defaultRenderer) === "dagre-wrapper" || ((i = t == null ? void 0 : t.flowchart) == null ? void 0 : i.defaultRenderer) === "elk" ? !1 : /^\s*graph/.test(e);
}, "detector"), _w = /* @__PURE__ */ f(async () => {
  const { diagram: e } = await import("./excalidraw-flowDiagram-DWJPFMVM.js");
  return { id: Vg, diagram: e };
}, "loader"), Bw = {
  id: Vg,
  detector: ww,
  loader: _w
}, vw = Bw, Zg = "flowchart-v2", Lw = /* @__PURE__ */ f((e, t) => {
  var r, i, s;
  return ((r = t == null ? void 0 : t.flowchart) == null ? void 0 : r.defaultRenderer) === "dagre-d3" ? !1 : (((i = t == null ? void 0 : t.flowchart) == null ? void 0 : i.defaultRenderer) === "elk" && (t.layout = "elk"), /^\s*graph/.test(e) && ((s = t == null ? void 0 : t.flowchart) == null ? void 0 : s.defaultRenderer) === "dagre-wrapper" ? !0 : /^\s*flowchart/.test(e));
}, "detector"), Aw = /* @__PURE__ */ f(async () => {
  const { diagram: e } = await import("./excalidraw-flowDiagram-DWJPFMVM.js");
  return { id: Zg, diagram: e };
}, "loader"), Ew = {
  id: Zg,
  detector: Lw,
  loader: Aw
}, Fw = Ew, Kg = "er", Mw = /* @__PURE__ */ f((e) => /^\s*erDiagram/.test(e), "detector"), Iw = /* @__PURE__ */ f(async () => {
  const { diagram: e } = await import("./excalidraw-erDiagram-SMLLAGMA.js");
  return { id: Kg, diagram: e };
}, "loader"), $w = {
  id: Kg,
  detector: Mw,
  loader: Iw
}, Ow = $w, Qg = "gitGraph", Dw = /* @__PURE__ */ f((e) => /^\s*gitGraph/.test(e), "detector"), Rw = /* @__PURE__ */ f(async () => {
  const { diagram: e } = await import("./excalidraw-gitGraphDiagram-UUTBAWPF.js");
  return { id: Qg, diagram: e };
}, "loader"), Pw = {
  id: Qg,
  detector: Dw,
  loader: Rw
}, Nw = Pw, Jg = "gantt", qw = /* @__PURE__ */ f((e) => /^\s*gantt/.test(e), "detector"), Ww = /* @__PURE__ */ f(async () => {
  const { diagram: e } = await import("./excalidraw-ganttDiagram-T4ZO3ILL.js");
  return { id: Jg, diagram: e };
}, "loader"), zw = {
  id: Jg,
  detector: qw,
  loader: Ww
}, Hw = zw, tm = "info", Yw = /* @__PURE__ */ f((e) => /^\s*info/.test(e), "detector"), Xw = /* @__PURE__ */ f(async () => {
  const { diagram: e } = await import("./excalidraw-infoDiagram-42DDH7IO.js");
  return { id: tm, diagram: e };
}, "loader"), Uw = {
  id: tm,
  detector: Yw,
  loader: Xw
}, em = "pie", jw = /* @__PURE__ */ f((e) => /^\s*pie/.test(e), "detector"), Gw = /* @__PURE__ */ f(async () => {
  const { diagram: e } = await import("./excalidraw-pieDiagram-DEJITSTG.js");
  return { id: em, diagram: e };
}, "loader"), Vw = {
  id: em,
  detector: jw,
  loader: Gw
}, rm = "quadrantChart", Zw = /* @__PURE__ */ f((e) => /^\s*quadrantChart/.test(e), "detector"), Kw = /* @__PURE__ */ f(async () => {
  const { diagram: e } = await import("./excalidraw-quadrantDiagram-34T5L4WZ.js");
  return { id: rm, diagram: e };
}, "loader"), Qw = {
  id: rm,
  detector: Zw,
  loader: Kw
}, Jw = Qw, im = "xychart", t_ = /* @__PURE__ */ f((e) => /^\s*xychart(-beta)?/.test(e), "detector"), e_ = /* @__PURE__ */ f(async () => {
  const { diagram: e } = await import("./excalidraw-xychartDiagram-5P7HB3ND.js");
  return { id: im, diagram: e };
}, "loader"), r_ = {
  id: im,
  detector: t_,
  loader: e_
}, i_ = r_, sm = "requirement", s_ = /* @__PURE__ */ f((e) => /^\s*requirement(Diagram)?/.test(e), "detector"), o_ = /* @__PURE__ */ f(async () => {
  const { diagram: e } = await import("./excalidraw-requirementDiagram-MS252O5E.js");
  return { id: sm, diagram: e };
}, "loader"), a_ = {
  id: sm,
  detector: s_,
  loader: o_
}, n_ = a_, om = "sequence", l_ = /* @__PURE__ */ f((e) => /^\s*sequenceDiagram/.test(e), "detector"), h_ = /* @__PURE__ */ f(async () => {
  const { diagram: e } = await import("./excalidraw-sequenceDiagram-FGHM5R23.js");
  return { id: om, diagram: e };
}, "loader"), c_ = {
  id: om,
  detector: l_,
  loader: h_
}, u_ = c_, am = "class", d_ = /* @__PURE__ */ f((e, t) => {
  var r;
  return ((r = t == null ? void 0 : t.class) == null ? void 0 : r.defaultRenderer) === "dagre-wrapper" ? !1 : /^\s*classDiagram/.test(e);
}, "detector"), p_ = /* @__PURE__ */ f(async () => {
  const { diagram: e } = await import("./excalidraw-classDiagram-6PBFFD2Q.js");
  return { id: am, diagram: e };
}, "loader"), f_ = {
  id: am,
  detector: d_,
  loader: p_
}, g_ = f_, nm = "classDiagram", m_ = /* @__PURE__ */ f((e, t) => {
  var r;
  return /^\s*classDiagram/.test(e) && ((r = t == null ? void 0 : t.class) == null ? void 0 : r.defaultRenderer) === "dagre-wrapper" ? !0 : /^\s*classDiagram-v2/.test(e);
}, "detector"), y_ = /* @__PURE__ */ f(async () => {
  const { diagram: e } = await import("./excalidraw-classDiagram-v2-HSJHXN6E.js");
  return { id: nm, diagram: e };
}, "loader"), x_ = {
  id: nm,
  detector: m_,
  loader: y_
}, C_ = x_, lm = "state", b_ = /* @__PURE__ */ f((e, t) => {
  var r;
  return ((r = t == null ? void 0 : t.state) == null ? void 0 : r.defaultRenderer) === "dagre-wrapper" ? !1 : /^\s*stateDiagram/.test(e);
}, "detector"), k_ = /* @__PURE__ */ f(async () => {
  const { diagram: e } = await import("./excalidraw-stateDiagram-FHFEXIEX.js");
  return { id: lm, diagram: e };
}, "loader"), T_ = {
  id: lm,
  detector: b_,
  loader: k_
}, S_ = T_, hm = "stateDiagram", w_ = /* @__PURE__ */ f((e, t) => {
  var r;
  return !!(/^\s*stateDiagram-v2/.test(e) || /^\s*stateDiagram/.test(e) && ((r = t == null ? void 0 : t.state) == null ? void 0 : r.defaultRenderer) === "dagre-wrapper");
}, "detector"), __ = /* @__PURE__ */ f(async () => {
  const { diagram: e } = await import("./excalidraw-stateDiagram-v2-QKLJ7IA2.js");
  return { id: hm, diagram: e };
}, "loader"), B_ = {
  id: hm,
  detector: w_,
  loader: __
}, v_ = B_, cm = "journey", L_ = /* @__PURE__ */ f((e) => /^\s*journey/.test(e), "detector"), A_ = /* @__PURE__ */ f(async () => {
  const { diagram: e } = await import("./excalidraw-journeyDiagram-VCZTEJTY.js");
  return { id: cm, diagram: e };
}, "loader"), E_ = {
  id: cm,
  detector: L_,
  loader: A_
}, F_ = E_, M_ = /* @__PURE__ */ f((e, t, r) => {
  q.debug(`rendering svg for syntax error
`);
  const i = o1(t), s = i.append("g");
  i.attr("viewBox", "0 0 2412 512"), eu(i, 100, 512, !0), s.append("path").attr("class", "error-icon").attr(
    "d",
    "m411.313,123.313c6.25-6.25 6.25-16.375 0-22.625s-16.375-6.25-22.625,0l-32,32-9.375,9.375-20.688-20.688c-12.484-12.5-32.766-12.5-45.25,0l-16,16c-1.261,1.261-2.304,2.648-3.31,4.051-21.739-8.561-45.324-13.426-70.065-13.426-105.867,0-192,86.133-192,192s86.133,192 192,192 192-86.133 192-192c0-24.741-4.864-48.327-13.426-70.065 1.402-1.007 2.79-2.049 4.051-3.31l16-16c12.5-12.492 12.5-32.758 0-45.25l-20.688-20.688 9.375-9.375 32.001-31.999zm-219.313,100.687c-52.938,0-96,43.063-96,96 0,8.836-7.164,16-16,16s-16-7.164-16-16c0-70.578 57.422-128 128-128 8.836,0 16,7.164 16,16s-7.164,16-16,16z"
  ), s.append("path").attr("class", "error-icon").attr(
    "d",
    "m459.02,148.98c-6.25-6.25-16.375-6.25-22.625,0s-6.25,16.375 0,22.625l16,16c3.125,3.125 7.219,4.688 11.313,4.688 4.094,0 8.188-1.563 11.313-4.688 6.25-6.25 6.25-16.375 0-22.625l-16.001-16z"
  ), s.append("path").attr("class", "error-icon").attr(
    "d",
    "m340.395,75.605c3.125,3.125 7.219,4.688 11.313,4.688 4.094,0 8.188-1.563 11.313-4.688 6.25-6.25 6.25-16.375 0-22.625l-16-16c-6.25-6.25-16.375-6.25-22.625,0s-6.25,16.375 0,22.625l15.999,16z"
  ), s.append("path").attr("class", "error-icon").attr(
    "d",
    "m400,64c8.844,0 16-7.164 16-16v-32c0-8.836-7.156-16-16-16-8.844,0-16,7.164-16,16v32c0,8.836 7.156,16 16,16z"
  ), s.append("path").attr("class", "error-icon").attr(
    "d",
    "m496,96.586h-32c-8.844,0-16,7.164-16,16 0,8.836 7.156,16 16,16h32c8.844,0 16-7.164 16-16 0-8.836-7.156-16-16-16z"
  ), s.append("path").attr("class", "error-icon").attr(
    "d",
    "m436.98,75.605c3.125,3.125 7.219,4.688 11.313,4.688 4.094,0 8.188-1.563 11.313-4.688l32-32c6.25-6.25 6.25-16.375 0-22.625s-16.375-6.25-22.625,0l-32,32c-6.251,6.25-6.251,16.375-0.001,22.625z"
  ), s.append("text").attr("class", "error-text").attr("x", 1440).attr("y", 250).attr("font-size", "150px").style("text-anchor", "middle").text("Syntax error in text"), s.append("text").attr("class", "error-text").attr("x", 1250).attr("y", 400).attr("font-size", "100px").style("text-anchor", "middle").text(`mermaid version ${r}`);
}, "draw"), um = { draw: M_ }, I_ = um, $_ = {
  db: {},
  renderer: um,
  parser: {
    parse: /* @__PURE__ */ f(() => {
    }, "parse")
  }
}, O_ = $_, dm = "flowchart-elk", D_ = /* @__PURE__ */ f((e, t = {}) => {
  var r;
  return (
    // If diagram explicitly states flowchart-elk
    /^\s*flowchart-elk/.test(e) || // If a flowchart/graph diagram has their default renderer set to elk
    /^\s*(flowchart|graph)/.test(e) && ((r = t == null ? void 0 : t.flowchart) == null ? void 0 : r.defaultRenderer) === "elk" ? (t.layout = "elk", !0) : !1
  );
}, "detector"), R_ = /* @__PURE__ */ f(async () => {
  const { diagram: e } = await import("./excalidraw-flowDiagram-DWJPFMVM.js");
  return { id: dm, diagram: e };
}, "loader"), P_ = {
  id: dm,
  detector: D_,
  loader: R_
}, N_ = P_, pm = "timeline", q_ = /* @__PURE__ */ f((e) => /^\s*timeline/.test(e), "detector"), W_ = /* @__PURE__ */ f(async () => {
  const { diagram: e } = await import("./excalidraw-timeline-definition-GMOUNBTQ.js");
  return { id: pm, diagram: e };
}, "loader"), z_ = {
  id: pm,
  detector: q_,
  loader: W_
}, H_ = z_, fm = "mindmap", Y_ = /* @__PURE__ */ f((e) => /^\s*mindmap/.test(e), "detector"), X_ = /* @__PURE__ */ f(async () => {
  const { diagram: e } = await import("./excalidraw-mindmap-definition-QFDTVHPH.js");
  return { id: fm, diagram: e };
}, "loader"), U_ = {
  id: fm,
  detector: Y_,
  loader: X_
}, j_ = U_, gm = "kanban", G_ = /* @__PURE__ */ f((e) => /^\s*kanban/.test(e), "detector"), V_ = /* @__PURE__ */ f(async () => {
  const { diagram: e } = await import("./excalidraw-kanban-definition-6JOO6SKY.js");
  return { id: gm, diagram: e };
}, "loader"), Z_ = {
  id: gm,
  detector: G_,
  loader: V_
}, K_ = Z_, mm = "sankey", Q_ = /* @__PURE__ */ f((e) => /^\s*sankey(-beta)?/.test(e), "detector"), J_ = /* @__PURE__ */ f(async () => {
  const { diagram: e } = await import("./excalidraw-sankeyDiagram-XADWPNL6.js");
  return { id: mm, diagram: e };
}, "loader"), tB = {
  id: mm,
  detector: Q_,
  loader: J_
}, eB = tB, ym = "packet", rB = /* @__PURE__ */ f((e) => /^\s*packet(-beta)?/.test(e), "detector"), iB = /* @__PURE__ */ f(async () => {
  const { diagram: e } = await import("./excalidraw-diagram-TYMM5635.js");
  return { id: ym, diagram: e };
}, "loader"), sB = {
  id: ym,
  detector: rB,
  loader: iB
}, xm = "radar", oB = /* @__PURE__ */ f((e) => /^\s*radar-beta/.test(e), "detector"), aB = /* @__PURE__ */ f(async () => {
  const { diagram: e } = await import("./excalidraw-diagram-MMDJMWI5.js");
  return { id: xm, diagram: e };
}, "loader"), nB = {
  id: xm,
  detector: oB,
  loader: aB
}, Cm = "block", lB = /* @__PURE__ */ f((e) => /^\s*block(-beta)?/.test(e), "detector"), hB = /* @__PURE__ */ f(async () => {
  const { diagram: e } = await import("./excalidraw-blockDiagram-DXYQGD6D.js");
  return { id: Cm, diagram: e };
}, "loader"), cB = {
  id: Cm,
  detector: lB,
  loader: hB
}, uB = cB, bm = "treeView", dB = /* @__PURE__ */ f((e) => /^\s*treeView-beta/.test(e), "detector"), pB = /* @__PURE__ */ f(async () => {
  const { diagram: e } = await import("./excalidraw-diagram-5BDNPKRD.js");
  return { id: bm, diagram: e };
}, "loader"), fB = {
  id: bm,
  detector: dB,
  loader: pB
}, gB = fB, km = "architecture", mB = /* @__PURE__ */ f((e) => /^\s*architecture/.test(e), "detector"), yB = /* @__PURE__ */ f(async () => {
  const { diagram: e } = await import("./excalidraw-architectureDiagram-Q4EWVU46.js");
  return { id: km, diagram: e };
}, "loader"), xB = {
  id: km,
  detector: mB,
  loader: yB
}, CB = xB, Tm = "ishikawa", bB = /* @__PURE__ */ f((e) => /^\s*ishikawa(-beta)?\b/i.test(e), "detector"), kB = /* @__PURE__ */ f(async () => {
  const { diagram: e } = await import("./excalidraw-ishikawaDiagram-UXIWVN3A.js");
  return { id: Tm, diagram: e };
}, "loader"), TB = {
  id: Tm,
  detector: bB,
  loader: kB
}, Sm = "venn", SB = /* @__PURE__ */ f((e) => /^\s*venn-beta/.test(e), "detector"), wB = /* @__PURE__ */ f(async () => {
  const { diagram: e } = await import("./excalidraw-vennDiagram-DHZGUBPP.js");
  return { id: Sm, diagram: e };
}, "loader"), _B = {
  id: Sm,
  detector: SB,
  loader: wB
}, BB = _B, wm = "treemap", vB = /* @__PURE__ */ f((e) => /^\s*treemap/.test(e), "detector"), LB = /* @__PURE__ */ f(async () => {
  const { diagram: e } = await import("./excalidraw-diagram-G4DWMVQ6.js");
  return { id: wm, diagram: e };
}, "loader"), AB = {
  id: wm,
  detector: vB,
  loader: LB
}, _m = "wardley-beta", EB = /* @__PURE__ */ f((e) => /^\s*wardley-beta/i.test(e), "detector"), FB = /* @__PURE__ */ f(async () => {
  const { diagram: e } = await import("./excalidraw-wardleyDiagram-NUSXRM2D.js");
  return { id: _m, diagram: e };
}, "loader"), MB = {
  id: _m,
  detector: EB,
  loader: FB
}, IB = MB, ac = !1, Ro = /* @__PURE__ */ f(() => {
  ac || (ac = !0, Gs("error", O_, (e) => e.toLowerCase().trim() === "error"), Gs(
    "---",
    // --- diagram type may appear if YAML front-matter is not parsed correctly
    {
      db: {
        clear: /* @__PURE__ */ f(() => {
        }, "clear")
      },
      styles: {},
      // should never be used
      renderer: {
        draw: /* @__PURE__ */ f(() => {
        }, "draw")
      },
      parser: {
        parse: /* @__PURE__ */ f(() => {
          throw new Error(
            "Diagrams beginning with --- are not valid. If you were trying to use a YAML front-matter, please ensure that you've correctly opened and closed the YAML front-matter with un-indented `---` blocks"
          );
        }, "parse")
      },
      init: /* @__PURE__ */ f(() => null, "init")
      // no op
    },
    (e) => e.toLowerCase().trimStart().startsWith("---")
  ), Ca(N_, j_, CB), Ca(
    Sw,
    K_,
    C_,
    g_,
    Ow,
    Hw,
    Uw,
    Vw,
    n_,
    u_,
    Fw,
    vw,
    H_,
    Nw,
    v_,
    S_,
    F_,
    Jw,
    eB,
    sB,
    i_,
    uB,
    gB,
    nB,
    TB,
    AB,
    BB,
    IB
  ));
}, "addDiagrams"), $B = /* @__PURE__ */ f(async () => {
  q.debug("Loading registered diagrams");
  const t = (await Promise.allSettled(
    Object.entries(kr).map(async ([r, { detector: i, loader: s }]) => {
      if (s)
        try {
          Sa(r);
        } catch {
          try {
            const { diagram: o, id: a } = await s();
            Gs(a, o, i);
          } catch (o) {
            throw q.error(`Failed to load external diagram with key ${r}. Removing from detectors.`), delete kr[r], o;
          }
        }
    })
  )).filter((r) => r.status === "rejected");
  if (t.length > 0) {
    q.error(`Failed to load ${t.length} external diagrams`);
    for (const r of t)
      q.error(r);
    throw new Error(`Failed to load ${t.length} external diagrams`);
  }
}, "loadRegisteredDiagrams"), OB = "graphics-document document";
function Bm(e, t) {
  e.attr("role", OB), t !== "" && e.attr("aria-roledescription", t);
}
f(Bm, "setA11yDiagramInfo");
function vm(e, t, r, i) {
  if (e.insert !== void 0) {
    if (r) {
      const s = `chart-desc-${i}`;
      e.attr("aria-describedby", s), e.insert("desc", ":first-child").attr("id", s).text(r);
    }
    if (t) {
      const s = `chart-title-${i}`;
      e.attr("aria-labelledby", s), e.insert("title", ":first-child").attr("id", s).text(t);
    }
  }
}
f(vm, "addSVGa11yTitleDescription");
var br, hn = (br = class {
  constructor(t, r, i, s, o) {
    this.type = t, this.text = r, this.db = i, this.parser = s, this.renderer = o;
  }
  static async fromText(t, r = {}) {
    var h, c;
    const i = wt(), s = Cn(t, i);
    t = $2(t) + `
`;
    try {
      Sa(s);
    } catch {
      const u = wx(s);
      if (!u)
        throw new Wc(`Diagram ${s} not found.`);
      const { id: p, diagram: d } = await u();
      Gs(p, d);
    }
    const { db: o, parser: a, renderer: n, init: l } = Sa(s);
    return a.parser && (a.parser.yy = o), (h = o.clear) == null || h.call(o), l == null || l(i), r.title && ((c = o.setDiagramTitle) == null || c.call(o, r.title)), await a.parse(t), new br(s, t, o, a, n);
  }
  async render(t, r) {
    await this.renderer.draw(this.text, t, r, this);
  }
  getParser() {
    return this.parser;
  }
  getType() {
    return this.type;
  }
}, f(br, "Diagram"), br), nc = [], DB = /* @__PURE__ */ f(() => {
  nc.forEach((e) => {
    e();
  }), nc = [];
}, "attachFunctions"), RB = /* @__PURE__ */ f((e) => e.replace(/^\s*%%(?!{)[^\n]+\n?/gm, "").trimStart(), "cleanupComments");
function Lm(e) {
  const t = e.match(qc);
  if (!t)
    return {
      text: e,
      metadata: {}
    };
  let r = d2(t[1], {
    // To support config, we need JSON schema.
    // https://www.yaml.org/spec/1.2/spec.html#id2803231
    schema: u2
  }) ?? {};
  r = typeof r == "object" && !Array.isArray(r) ? r : {};
  const i = {};
  return r.displayMode && (i.displayMode = r.displayMode.toString()), r.title && (i.title = r.title.toString()), r.config && (i.config = r.config), {
    text: e.slice(t[0].length),
    metadata: i
  };
}
f(Lm, "extractFrontMatter");
var PB = /* @__PURE__ */ f((e) => e.replace(/\r\n?/g, `
`).replace(
  /<(\w+)([^>]*)>/g,
  (t, r, i) => "<" + r + i.replace(/="([^"]*)"/g, "='$1'") + ">"
), "cleanupText"), NB = /* @__PURE__ */ f((e) => {
  const { text: t, metadata: r } = Lm(e), { displayMode: i, title: s, config: o = {} } = r;
  return i && (o.gantt || (o.gantt = {}), o.gantt.displayMode = i), { title: s, config: o, text: t };
}, "processFrontmatter"), qB = /* @__PURE__ */ f((e) => {
  const t = ke.detectInit(e) ?? {}, r = ke.detectDirective(e, "wrap");
  return Array.isArray(r) ? t.wrap = r.some(({ type: i }) => i === "wrap") : (r == null ? void 0 : r.type) === "wrap" && (t.wrap = !0), {
    text: k2(e),
    directive: t
  };
}, "processDirectives");
function ul(e) {
  const t = PB(e), r = NB(t), i = qB(r.text), s = Zn(r.config, i.directive);
  return e = RB(i.text), {
    code: e,
    title: r.title,
    config: s
  };
}
f(ul, "preprocessDiagram");
function Am(e) {
  const t = new TextEncoder().encode(e), r = Array.from(t, (i) => String.fromCodePoint(i)).join("");
  return btoa(r);
}
f(Am, "toBase64");
var WB = 5e4, zB = "graph TB;a[Maximum text size in diagram exceeded];style a fill:#faa", HB = "sandbox", YB = "loose", XB = "http://www.w3.org/2000/svg", UB = "http://www.w3.org/1999/xlink", jB = "http://www.w3.org/1999/xhtml", GB = "100%", VB = "100%", ZB = "border:0;margin:0;", KB = "margin:0", QB = "allow-top-navigation-by-user-activation allow-popups", JB = 'The "iframe" tag is not supported by your browser.', tv = ["foreignobject"], ev = ["dominant-baseline"];
function dl(e) {
  const t = ul(e);
  return Us(), Qx(t.config ?? {}), t;
}
f(dl, "processAndSetConfigs");
async function Em(e, t) {
  Ro();
  try {
    const { code: r, config: i } = dl(e);
    return { diagramType: (await Mm(r)).type, config: i };
  } catch (r) {
    if (t != null && t.suppressErrors)
      return !1;
    throw r;
  }
}
f(Em, "parse");
var lc = /* @__PURE__ */ f((e, t, r = []) => `
.${e} ${t} { ${r.join(" !important; ")} !important; }`, "cssImportantStyles"), rv = /* @__PURE__ */ f((e, t = /* @__PURE__ */ new Map()) => {
  let r = "";
  if (e.themeCSS !== void 0 && (r += `
${e.themeCSS}`), e.fontFamily !== void 0 && (r += `
:root { --mermaid-font-family: ${e.fontFamily}}`), e.altFontFamily !== void 0 && (r += `
:root { --mermaid-alt-font-family: ${e.altFontFamily}}`), t instanceof Map) {
    const a = Kt(e) ? ["> *", "span"] : ["rect", "polygon", "ellipse", "circle", "path"];
    t.forEach((n) => {
      Rl(n.styles) || a.forEach((l) => {
        r += lc(n.id, l, n.styles);
      }), Rl(n.textStyles) || (r += lc(
        n.id,
        "tspan",
        ((n == null ? void 0 : n.textStyles) || []).map((l) => l.replace("color", "fill"))
      ));
    });
  }
  return r;
}, "createCssStyles"), iv = /* @__PURE__ */ f((e, t, r, i) => {
  const s = rv(e, r), o = yC(
    t,
    s,
    { ...e.themeVariables, theme: e.theme, look: e.look },
    i
  );
  return ln(yw(`${i}{${o}}`), Cw);
}, "createUserStyles"), sv = /* @__PURE__ */ f((e = "", t, r) => {
  let i = e;
  return !r && !t && (i = i.replace(
    /marker-end="url\([\d+./:=?A-Za-z-]*?#/g,
    'marker-end="url(#'
  )), i = _r(i), i = i.replace(/<br>/g, "<br/>"), i;
}, "cleanUpSvgCode"), ov = /* @__PURE__ */ f((e = "", t) => {
  var s, o;
  const r = (o = (s = t == null ? void 0 : t.viewBox) == null ? void 0 : s.baseVal) != null && o.height ? t.viewBox.baseVal.height + "px" : VB, i = Am(`<body style="${KB}">${e}</body>`);
  return `<iframe style="width:${GB};height:${r};${ZB}" src="data:text/html;charset=UTF-8;base64,${i}" sandbox="${QB}">
  ${JB}
</iframe>`;
}, "putIntoIFrame"), hc = /* @__PURE__ */ f((e, t, r, i, s) => {
  const o = e.append("div");
  o.attr("id", r), i && o.attr("style", i);
  const a = o.append("svg").attr("id", t).attr("width", "100%").attr("xmlns", XB);
  return s && a.attr("xmlns:xlink", s), a.append("g"), e;
}, "appendDivSvgG");
function cn(e, t) {
  return e.append("iframe").attr("id", t).attr("style", "width: 100%; height: 100%;").attr("sandbox", "");
}
f(cn, "sandboxedIframe");
var av = /* @__PURE__ */ f((e, t, r, i) => {
  var s, o, a;
  (s = e.getElementById(t)) == null || s.remove(), (o = e.getElementById(r)) == null || o.remove(), (a = e.getElementById(i)) == null || a.remove();
}, "removeExistingElements"), nv = /* @__PURE__ */ f(async function(e, t, r) {
  var Y, H, P, M, E, D;
  Ro();
  const i = dl(t);
  t = i.code;
  const s = wt();
  q.debug(s), t.length > ((s == null ? void 0 : s.maxTextSize) ?? WB) && (t = zB);
  const o = "#" + e, a = "i" + e, n = "#" + a, l = "d" + e, h = "#" + l, c = /* @__PURE__ */ f(() => {
    const R = ct(p ? n : h).node();
    R && "remove" in R && R.remove();
  }, "removeTempElements");
  let u = ct("body");
  const p = s.securityLevel === HB, d = s.securityLevel === YB, g = s.fontFamily;
  if (r !== void 0) {
    if (r && (r.innerHTML = ""), p) {
      const v = cn(ct(r), a);
      u = ct(v.nodes()[0].contentDocument.body), u.node().style.margin = 0;
    } else
      u = ct(r);
    hc(u, e, l, `font-family: ${g}`, UB);
  } else {
    if (av(document, e, l, a), p) {
      const v = cn(ct("body"), a);
      u = ct(v.nodes()[0].contentDocument.body), u.node().style.margin = 0;
    } else
      u = ct("body");
    hc(u, e, l);
  }
  let m, y;
  try {
    m = await hn.fromText(t, { title: i.title });
  } catch (v) {
    if (s.suppressErrorRendering)
      throw c(), v;
    m = await hn.fromText("error"), y = v;
  }
  const x = u.select(h).node(), b = m.type, k = x.firstChild, w = k.firstChild, S = (H = (Y = m.renderer).getClasses) == null ? void 0 : H.call(Y, t, m), L = iv(s, b, S, o), T = document.createElement("style");
  T.innerHTML = L, k.insertBefore(T, w);
  try {
    await m.renderer.draw(t, e, "11.14.0", m);
  } catch (v) {
    throw s.suppressErrorRendering ? c() : I_.draw(t, e, "11.14.0"), v;
  }
  const B = u.select(`${h} svg`), N = (M = (P = m.db).getAccTitle) == null ? void 0 : M.call(P), O = (D = (E = m.db).getAccDescription) == null ? void 0 : D.call(E);
  Im(b, B, N, O), u.select(`[id="${e}"]`).selectAll("foreignobject > *").attr("xmlns", jB);
  let F = u.select(h).node().innerHTML;
  if (q.debug("config.arrowMarkerAbsolute", s.arrowMarkerAbsolute), F = sv(F, p, Ve(s.arrowMarkerAbsolute)), p) {
    const v = u.select(h + " svg").node();
    F = ov(F, v);
  } else d || (F = ni.sanitize(F, {
    ADD_TAGS: tv,
    ADD_ATTR: ev,
    HTML_INTEGRATION_POINTS: { foreignobject: !0 }
  }));
  if (DB(), y)
    throw y;
  return c(), {
    diagramType: b,
    svg: F,
    bindFunctions: m.db.bindFunctions
  };
}, "render");
function Fm(e = {}) {
  var i;
  const t = $t({}, e);
  t != null && t.fontFamily && !((i = t.themeVariables) != null && i.fontFamily) && (t.themeVariables || (t.themeVariables = {}), t.themeVariables.fontFamily = t.fontFamily), Zx(t), t != null && t.theme && t.theme in Ye ? t.themeVariables = Ye[t.theme].getThemeVariables(
    t.themeVariables
  ) : t && (t.themeVariables = Ye.default.getThemeVariables(t.themeVariables));
  const r = typeof t == "object" ? Vx(t) : Uc();
  xn(r.logLevel), Ro();
}
f(Fm, "initialize");
var Mm = /* @__PURE__ */ f((e, t = {}) => {
  const { code: r } = ul(e);
  return hn.fromText(r, t);
}, "getDiagramFromText");
function Im(e, t, r, i) {
  Bm(t, e), vm(t, r, i, t.attr("id"));
}
f(Im, "addA11yInfo");
var vr = Object.freeze({
  render: nv,
  parse: Em,
  getDiagramFromText: Mm,
  initialize: Fm,
  getConfig: wt,
  setConfig: jc,
  getSiteConfig: Uc,
  updateSiteConfig: Kx,
  reset: /* @__PURE__ */ f(() => {
    Us();
  }, "reset"),
  globalReset: /* @__PURE__ */ f(() => {
    Us(li);
  }, "globalReset"),
  defaultConfig: li
});
xn(wt().logLevel);
Us(wt());
var lv = /* @__PURE__ */ f((e, t, r) => {
  q.warn(e), Vn(e) ? (r && r(e.str, e.hash), t.push({ ...e, message: e.str, error: e })) : (r && r(e), e instanceof Error && t.push({
    str: e.message,
    message: e.message,
    hash: e.name,
    error: e
  }));
}, "handleError"), $m = /* @__PURE__ */ f(async function(e = {
  querySelector: ".mermaid"
}) {
  try {
    await hv(e);
  } catch (t) {
    if (Vn(t) && q.error(t.str), ne.parseError && ne.parseError(t), !e.suppressErrors)
      throw q.error("Use the suppressErrors option to suppress these errors"), t;
  }
}, "run"), hv = /* @__PURE__ */ f(async function({ postRenderCallback: e, querySelector: t, nodes: r } = {
  querySelector: ".mermaid"
}) {
  const i = vr.getConfig();
  q.debug(`${e ? "" : "No "}Callback function found`);
  let s;
  if (r)
    s = r;
  else if (t)
    s = document.querySelectorAll(t);
  else
    throw new Error("Nodes and querySelector are both undefined");
  q.debug(`Found ${s.length} diagrams`), (i == null ? void 0 : i.startOnLoad) !== void 0 && (q.debug("Start On Load: " + (i == null ? void 0 : i.startOnLoad)), vr.updateSiteConfig({ startOnLoad: i == null ? void 0 : i.startOnLoad }));
  const o = new ke.InitIDGenerator(i.deterministicIds, i.deterministicIDSeed);
  let a;
  const n = [];
  for (const l of Array.from(s)) {
    if (q.info("Rendering diagram: " + l.id), l.getAttribute("data-processed"))
      continue;
    l.setAttribute("data-processed", "true");
    const h = `mermaid-${o.next()}`;
    a = l.innerHTML, a = rf(ke.entityDecode(a)).trim().replace(/<br\s*\/?>/gi, "<br/>");
    const c = ke.detectInit(a);
    c && q.debug("Detected early reinit: ", c);
    try {
      const { svg: u, bindFunctions: p } = await Pm(h, a, l);
      l.innerHTML = u, e && await e(h), p && p(l);
    } catch (u) {
      lv(u, n, ne.parseError);
    }
  }
  if (n.length > 0)
    throw n[0];
}, "runThrowsErrors"), Om = /* @__PURE__ */ f(function(e) {
  vr.initialize(e);
}, "initialize"), cv = /* @__PURE__ */ f(async function(e, t, r) {
  q.warn("mermaid.init is deprecated. Please use run instead."), e && Om(e);
  const i = { postRenderCallback: r, querySelector: ".mermaid" };
  typeof t == "string" ? i.querySelector = t : t && (t instanceof HTMLElement ? i.nodes = [t] : i.nodes = t), await $m(i);
}, "init"), uv = /* @__PURE__ */ f(async (e, {
  lazyLoad: t = !0
} = {}) => {
  Ro(), Ca(...e), t === !1 && await $B();
}, "registerExternalDiagrams"), Dm = /* @__PURE__ */ f(function() {
  if (ne.startOnLoad) {
    const { startOnLoad: e } = vr.getConfig();
    e && ne.run().catch((t) => q.error("Mermaid failed to initialize", t));
  }
}, "contentLoaded");
typeof document < "u" && window.addEventListener("load", Dm, !1);
var dv = /* @__PURE__ */ f(function(e) {
  ne.parseError = e;
}, "setParseErrorHandler"), yo = [], ca = !1, Rm = /* @__PURE__ */ f(async () => {
  if (!ca) {
    for (ca = !0; yo.length > 0; ) {
      const e = yo.shift();
      if (e)
        try {
          await e();
        } catch (t) {
          q.error("Error executing queue", t);
        }
    }
    ca = !1;
  }
}, "executeQueue"), pv = /* @__PURE__ */ f(async (e, t) => new Promise((r, i) => {
  const s = /* @__PURE__ */ f(() => new Promise((o, a) => {
    vr.parse(e, t).then(
      (n) => {
        o(n), r(n);
      },
      (n) => {
        var l;
        q.error("Error parsing", n), (l = ne.parseError) == null || l.call(ne, n), a(n), i(n);
      }
    );
  }), "performCall");
  yo.push(s), Rm().catch(i);
}), "parse"), Pm = /* @__PURE__ */ f((e, t, r) => new Promise((i, s) => {
  const o = /* @__PURE__ */ f(() => new Promise((a, n) => {
    vr.render(e, t, r).then(
      (l) => {
        a(l), i(l);
      },
      (l) => {
        var h;
        q.error("Error parsing", l), (h = ne.parseError) == null || h.call(ne, l), n(l), s(l);
      }
    );
  }), "performCall");
  yo.push(o), Rm().catch(s);
}), "render"), fv = /* @__PURE__ */ f(() => Object.keys(kr).map((e) => ({
  id: e
})), "getRegisteredDiagramsMetadata"), ne = {
  startOnLoad: !0,
  mermaidAPI: vr,
  parse: pv,
  render: Pm,
  init: cv,
  run: $m,
  registerExternalDiagrams: uv,
  registerLayoutLoaders: zg,
  initialize: Om,
  parseError: void 0,
  contentLoaded: Dm,
  setParseErrorHandler: dv,
  detectType: Cn,
  registerIconPacks: WT,
  getRegisteredDiagramsMetadata: fv
}, ua = ne;
/*! Check if previously processed */
/*!
 * Wait for document loaded before starting the execution
 */
const ut = (e) => e.replace(/\s*!important\s*$/i, "").trim(), gv = (e, t) => {
  let r = t;
  for (; r < e.length && /\s/.test(e[r]); )
    r += 1;
  const i = r;
  for (; r < e.length && /[a-z-]/i.test(e[r]); )
    r += 1;
  if (r === i)
    return !1;
  for (; r < e.length && /\s/.test(e[r]); )
    r += 1;
  return e[r] === ":";
}, fe = (e) => {
  const t = [];
  let r = 0;
  for (; r < e.length; ) {
    for (; r < e.length && /[\s;,]/.test(e[r]); )
      r += 1;
    if (r >= e.length)
      break;
    const i = r;
    for (; r < e.length && e[r] !== ":" && !(e[r] === ";" || e[r] === ","); )
      r += 1;
    if (r >= e.length || e[r] !== ":")
      break;
    const s = e.substring(i, r).trim().toLowerCase();
    r += 1;
    const o = r;
    let a = 0, n = null;
    for (; r < e.length; ) {
      const h = e[r];
      if (n) {
        h === n && e[r - 1] !== "\\" && (n = null), r += 1;
        continue;
      }
      if (h === '"' || h === "'") {
        n = h, r += 1;
        continue;
      }
      if (h === "(") {
        a += 1, r += 1;
        continue;
      }
      if (h === ")") {
        a = Math.max(0, a - 1), r += 1;
        continue;
      }
      if (a === 0 && (h === ";" || h === "," || /\s/.test(h) && gv(e, r)))
        break;
      r += 1;
    }
    const l = ut(e.substring(o, r));
    s && l && t.push({ property: s, value: l }), r < e.length && (e[r] === ";" || e[r] === ",") && (r += 1);
  }
  return t;
}, ge = (e) => {
  const t = ut(e);
  if (!t)
    return !1;
  if (typeof CSS < "u" && typeof CSS.supports == "function")
    return CSS.supports("color", t);
  if (typeof document < "u") {
    const r = document.createElement("div");
    return r.style.color = "", r.style.color = t, r.style.color !== "";
  }
  return !1;
}, cc = (e, t) => {
  var i;
  const r = e.getAttribute("style");
  return r && ((i = fe(r).find((s) => s.property === t)) == null ? void 0 : i.value) || "";
}, da = (...e) => {
  for (const t of e) {
    const r = ut(t || "");
    if (ge(r))
      return r;
  }
}, pl = (e, t) => {
  var a, n, l, h;
  const r = e.querySelector("text, foreignObject, div, span, p") || e, i = da((a = r.getAttribute) == null ? void 0 : a.call(r, "fill"), cc(r, "fill"), (n = r.style) == null ? void 0 : n.fill);
  if (i)
    return i;
  const s = da((l = r.getAttribute) == null ? void 0 : l.call(r, "color"), cc(r, "color"), (h = r.style) == null ? void 0 : h.color);
  if (s)
    return s;
  const o = da(t);
  if (o)
    return o;
}, fl = (e, t, r) => {
  switch (t) {
    case ft.FILL:
    case ft.STROKE:
      ge(r) && (e[t] = r);
      break;
    case ft.STROKE_WIDTH:
    case ft.STROKE_DASHARRAY:
      e[t] = r;
      break;
  }
}, xo = (e, t, r) => {
  t === jt.COLOR && ge(r) && (e[jt.COLOR] = r);
}, Co = (e, t, r) => {
  e && fe(e).forEach(({ property: i, value: s }) => {
    fl(t, i, s), xo(r, i, s);
  });
}, Nm = (e, t) => {
  e && fe(e).forEach(({ property: r, value: i }) => {
    if (r === "fill" && ge(i)) {
      t[jt.COLOR] = i;
      return;
    }
    xo(t, r, i);
  });
}, qm = (e, t) => {
  if (!e)
    return;
  [
    [ft.FILL, e.getAttribute("fill")],
    [ft.STROKE, e.getAttribute("stroke")],
    [
      ft.STROKE_WIDTH,
      e.getAttribute("stroke-width")
    ],
    [
      ft.STROKE_DASHARRAY,
      e.getAttribute("stroke-dasharray")
    ]
  ].forEach(([i, s]) => {
    const o = ut(s || "");
    o && fl(t, i, o);
  });
}, Wm = (e, t) => {
  if (!e)
    return;
  const r = e.getAttribute("fill") || e.getAttribute("color"), i = ut(r || "");
  ge(i) && (t[jt.COLOR] = i);
}, un = (e, t, r, i) => {
  var o, a;
  if (!(t instanceof Map))
    return;
  const s = t.get(e);
  s && ((o = s.styles) == null || o.forEach((n) => {
    fe(n).forEach(({ property: l, value: h }) => {
      fl(r, l, h), xo(i, l, h);
    });
  }), (a = s.textStyles) == null || a.forEach((n) => {
    fe(n).forEach(({ property: l, value: h }) => {
      xo(i, l, h);
    });
  }));
}, mv = (e, t, r) => {
  var p;
  const i = e.nodes.map((d) => d.startsWith("flowchart-") ? d.split("-")[1] : d), s = t.querySelector(`[id='${e.id}']`);
  if (!s)
    throw new Error("SubGraph element not found");
  const o = gl(s, t), a = s.getBBox(), n = {
    width: a.width,
    height: a.height
  }, l = {}, h = {}, c = s.querySelector(":scope > rect, :scope > path, :scope > polygon, :scope > ellipse") || s.querySelector(".cluster > rect, .cluster > path, .cluster > polygon, .cluster > ellipse") || s.querySelector("rect, path, polygon, ellipse");
  Co(s.getAttribute("style"), l, h), Co(c == null ? void 0 : c.getAttribute("style"), l, h), qm(c, l);
  const u = s.querySelector(".cluster-label text, .cluster-label tspan") || s.querySelector("text");
  return Nm(u == null ? void 0 : u.getAttribute("style"), h), Wm(u, h), un(e.id, r, l, h), (p = e.classes) == null || p.forEach((d) => {
    un(d, r, l, h);
  }), {
    id: e.id,
    nodeIds: i,
    text: ie(e.title),
    labelType: "text",
    ...o,
    ...n,
    containerStyle: l,
    labelStyle: h
  };
}, uc = (e, t, r) => {
  var p, d;
  const i = t.querySelector(`[id*="${e.domId}"]`);
  if (!i)
    return;
  let s;
  ((p = i.parentElement) == null ? void 0 : p.tagName.toLowerCase()) === "a" && (s = i.parentElement.getAttribute("xlink:href"));
  const o = gl(s ? i.parentElement : i, t), a = i.getBBox(), n = {
    width: a.width,
    height: a.height
  }, l = {}, h = {};
  e.classes && r instanceof Map && (Array.isArray(e.classes) ? e.classes : [e.classes]).forEach((g) => {
    un(g, r, l, h);
  }), (d = e.styles) == null || d.forEach((g) => {
    Co(g, l, h);
  });
  const c = i.querySelector(".label-container");
  return Co(c == null ? void 0 : c.getAttribute("style"), l, h), qm(c, l), Array.from(i.querySelectorAll(".label, .nodeLabel, .label text, .label tspan, .label span, .label div")).forEach((g) => {
    Nm(g.getAttribute("style"), h), Wm(g, h);
  }), {
    id: e.id,
    labelType: e.labelType,
    text: ie(e.text || ""),
    type: e.type,
    link: s || void 0,
    ...o,
    ...n,
    containerStyle: l,
    labelStyle: h
  };
}, yv = (e, t, r) => {
  const i = r.querySelector(`[id*="${e.id}"]`);
  if (!i)
    throw new Error("Edge element not found");
  const s = gl(i, r), o = $c(i, s);
  return e.length = void 0, {
    ...e,
    ...o,
    text: ie(e.text)
  };
}, gl = (e, t) => {
  var l;
  if (!e)
    throw new Error("Element not found");
  let r = (l = e.parentElement) == null ? void 0 : l.parentElement;
  const i = e.childNodes[0];
  let s = { x: 0, y: 0 };
  if (i) {
    const { transformX: h, transformY: c } = xr(i), u = i.getBBox();
    s = {
      x: Number(i.getAttribute("x")) || h + u.x || 0,
      y: Number(i.getAttribute("y")) || c + u.y || 0
    };
  }
  const { transformX: o, transformY: a } = xr(e), n = {
    x: o + s.x,
    y: a + s.y
  };
  for (; r && r.id !== t.id; ) {
    if (r.classList.value === "root" && r.hasAttribute("transform")) {
      const { transformX: h, transformY: c } = xr(r);
      n.x += h, n.y += c;
    }
    r = r.parentElement;
  }
  return n;
}, xv = (e, t) => {
  const r = e.getVertices(), i = e.getEdges(), s = e.getSubGraphs(), o = e.getClasses(), a = {}, n = o instanceof Map ? o : {};
  r instanceof Map ? r.forEach((u, p) => {
    a[p] = uc(u, t, n);
  }) : typeof r == "object" && r !== null && Object.entries(r).forEach(([u, p]) => {
    a[u] = uc(p, t, n);
  });
  const l = /* @__PURE__ */ new Map(), h = (Array.isArray(i) ? i : []).map((u) => {
    if (!t.querySelector(`[id*="${u.id}"]`))
      return null;
    const p = `${u.start}-${u.end}`, d = l.get(p) || 0;
    return l.set(p, d + 1), yv(u, d, t);
  }).filter((u) => u !== null && u.reflectionPoints.length > 1);
  return {
    type: "flowchart",
    subGraphs: (Array.isArray(s) ? s : []).map((u) => mv(u, t, n)),
    vertices: a,
    edges: h
  };
}, Cv = (e, t) => {
  const r = {};
  t != null && t.label && (r.label = { text: ie(t.label), fontSize: 16 });
  const i = e.tagName;
  if (i === "line")
    r.startX = Number(e.getAttribute("x1")), r.startY = Number(e.getAttribute("y1")), r.endX = Number(e.getAttribute("x2")), r.endY = Number(e.getAttribute("y2"));
  else if (i === "path") {
    const a = e.getAttribute("d");
    if (!a)
      throw new Error('Path element does not contain a "d" attribute');
    const n = a.split(/(?=[LC])/), l = n[0].substring(1).split(",").map((u) => parseFloat(u)), h = [];
    n.forEach((u) => {
      const p = u.substring(1).trim().split(" ").map((d) => {
        const [g, m] = d.split(",");
        return [
          parseFloat(g) - l[0],
          parseFloat(m) - l[1]
        ];
      });
      h.push(...p);
    });
    const c = h[h.length - 1];
    r.startX = l[0], r.startY = l[1], r.endX = c[0], r.endY = c[1], r.points = h;
  }
  t != null && t.label && (r.startY = r.startY - 10, r.endY = r.endY - 10);
  const s = e.getAttribute("stroke"), o = (s && s !== "none" ? s : "") || getComputedStyle(e).stroke || "";
  return r.strokeColor = o ? ut(o) : null, r.strokeWidth = Number(e.getAttribute("stroke-width")), r.type = "arrow", r.strokeStyle = (t == null ? void 0 : t.strokeStyle) || "solid", r.startArrowhead = (t == null ? void 0 : t.startArrowhead) || null, r.endArrowhead = (t == null ? void 0 : t.endArrowhead) || null, r;
}, ml = (e, t, r, i, s) => {
  const o = {};
  return o.type = "arrow", o.startX = e, o.startY = t, o.endX = r, o.endY = i, Object.assign(o, { ...s }), o;
}, bo = (e, t, r, i) => ({
  type: "text",
  x: e,
  y: t,
  text: r,
  width: (i == null ? void 0 : i.width) || 20,
  height: (i == null ? void 0 : i.height) || 20,
  fontSize: (i == null ? void 0 : i.fontSize) || as,
  id: i == null ? void 0 : i.id,
  color: i == null ? void 0 : i.color,
  groupId: i == null ? void 0 : i.groupId,
  metadata: i == null ? void 0 : i.metadata
}), zm = (e, t, r) => {
  const i = {}, s = Number(e.getAttribute("x")), o = Number(e.getAttribute("y"));
  i.type = "text", i.text = ie(t), r != null && r.id && (i.id = r.id), r != null && r.groupId && (i.groupId = r.groupId);
  const a = e.getBBox();
  i.width = a.width, i.height = a.height, i.x = s - a.width / 2, i.y = o;
  const n = parseInt(getComputedStyle(e).fontSize);
  return i.fontSize = n, i.color = pl(e), i;
}, Ge = (e, t, r = {}) => {
  const i = {};
  i.type = t;
  const { label: s, subtype: o, id: a, groupId: n } = r;
  i.id = a, n && (i.groupId = n), s && (i.label = {
    text: ie(s.text),
    fontSize: 16,
    textAlign: s == null ? void 0 : s.textAlign,
    verticalAlign: s == null ? void 0 : s.verticalAlign
  });
  const l = e.getBBox();
  switch (i.x = l.x, i.y = l.y, i.width = l.width, i.height = l.height, i.subtype = o, o) {
    case "highlight":
      const h = e.getAttribute("fill");
      h && (i.bgColor = ut(h));
      break;
    case "note":
      i.strokeStyle = "dashed";
      break;
  }
  return i;
}, os = (e, t, r, i, s, o) => {
  const a = {};
  a.startX = t, a.startY = r, a.endX = i, o != null && o.groupId && (a.groupId = o.groupId), o != null && o.id && (a.id = o.id), a.endY = s;
  const n = e.getAttribute("stroke");
  return a.strokeColor = n ? ut(n) : null, a.strokeWidth = Number(e.getAttribute("stroke-width")), a.type = "line", a;
}, dc = {
  0: "SOLID",
  1: "DOTTED",
  3: "SOLID_CROSS",
  4: "DOTTED_CROSS",
  5: "SOLID_OPEN",
  6: "DOTTED_OPEN",
  24: "SOLID_POINT",
  25: "DOTTED_POINT"
}, Me = {
  SOLID: 0,
  DOTTED: 1,
  NOTE: 2,
  SOLID_CROSS: 3,
  DOTTED_CROSS: 4,
  SOLID_OPEN: 5,
  DOTTED_OPEN: 6,
  SOLID_POINT: 24,
  DOTTED_POINT: 25,
  CRITICAL_START: 27
}, bv = (e) => {
  let t;
  switch (e) {
    case Me.SOLID:
    case Me.SOLID_CROSS:
    case Me.SOLID_OPEN:
    case Me.SOLID_POINT:
      t = "solid";
      break;
    case Me.DOTTED:
    case Me.DOTTED_CROSS:
    case Me.DOTTED_OPEN:
    case Me.DOTTED_POINT:
      t = "dotted";
      break;
    default:
      t = "solid";
      break;
  }
  return t;
}, kv = (e, t) => {
  var i, s;
  if (!!((i = e.nextElementSibling) != null && i.classList.contains("sequenceNumber"))) {
    const o = (s = e.nextElementSibling) == null ? void 0 : s.textContent;
    if (!o)
      throw new Error("sequence number not present");
    const a = 30, n = a / 2, h = {
      type: "rectangle",
      x: t.startX - 10,
      y: t.startY - n,
      label: { text: o, fontSize: 14 },
      bgColor: "#e9ecef",
      height: a,
      subtype: "sequence"
    };
    Object.assign(t, { sequenceNumber: h });
  }
}, pc = (e, t, r) => {
  if (!e)
    throw "root node not found";
  const i = ue(), s = Array.from(e.children), o = [];
  return s.forEach((a, n) => {
    const l = `${r == null ? void 0 : r.id}-${n}`;
    let h;
    switch (a.tagName) {
      case "line":
        const c = Number(a.getAttribute("x1")), u = Number(a.getAttribute("y1")), p = Number(a.getAttribute("x2")), d = Number(a.getAttribute("y2"));
        h = os(a, c, u, p, d, { groupId: i, id: l });
        break;
      case "text":
        h = zm(a, t, {
          groupId: i,
          id: l
        });
        break;
      case "circle":
        h = Ge(a, "ellipse", {
          label: a.textContent ? { text: a.textContent } : void 0,
          groupId: i,
          id: l
        });
      default:
        h = Ge(a, ay[a.tagName], {
          label: a.textContent ? { text: a.textContent } : void 0,
          groupId: i,
          id: l
        });
    }
    o.push(h);
  }), o;
}, fc = (e, t) => {
  const r = t.getAttribute("fill"), i = t.getAttribute("stroke"), s = t.getAttribute("stroke-width"), o = t.getAttribute("stroke-dasharray");
  r && r !== "none" && (e.bgColor = ut(r)), i && i !== "none" && (e.strokeColor = ut(i)), s && (e.strokeWidth = Number(s)), o && o.trim() && (e.strokeStyle = "dashed");
}, Tv = (e, t) => {
  const r = Array.from(t.querySelectorAll(".actor-top")), i = Array.from(t.querySelectorAll(".actor-bottom")), s = [], o = [], a = {}, n = e instanceof Map ? Array.from(e.values()) : Object.values(e), l = Array.from(t.querySelectorAll(".actor-line")), h = (c, u) => {
    var m;
    const p = c.name, d = l.find((y) => y.getAttribute("name") === p);
    if (d)
      return d;
    const g = c.type === "participant" ? (m = u.parentElement) == null ? void 0 : m.previousElementSibling : u.previousElementSibling;
    return g ? g.tagName === "line" ? g : g.querySelector("line") : null;
  };
  return n.forEach((c) => {
    const u = r.find((g) => g.getAttribute("name") === c.name), p = i.find((g) => g.getAttribute("name") === c.name);
    if (!u || !p)
      throw "root not found";
    const d = c.description;
    if (c.type === "participant") {
      const g = Ge(u, "rectangle", { id: `${c.name}-top`, label: { text: d }, subtype: "actor" });
      if (fc(g, u), !g)
        throw "Top Node element not found!";
      s.push([g]);
      const m = Ge(p, "rectangle", { id: `${c.name}-bottom`, label: { text: d }, subtype: "actor" });
      a[c.name] = {
        topId: `${c.name}-top`,
        bottomId: `${c.name}-bottom`,
        bindType: "rectangle"
      }, fc(m, p), s.push([m]);
      const y = h(c, u);
      if ((y == null ? void 0 : y.tagName) !== "line")
        throw "Line not found";
      const x = Number(y.getAttribute("x1"));
      if (!g.height)
        throw "Top node element height is null";
      const b = g.y + g.height, k = m.y, w = Number(y.getAttribute("x2")), S = os(y, x, b, w, k);
      o.push(S);
    } else if (c.type === "actor") {
      const g = pc(u, d, {
        id: `${c.name}-top`
      });
      s.push(g);
      const m = pc(p, d, {
        id: `${c.name}-bottom`
      });
      s.push(m);
      const y = h(c, u);
      if ((y == null ? void 0 : y.tagName) !== "line")
        throw "Line not found";
      const x = Number(y.getAttribute("x1")), b = Number(y.getAttribute("y1")), k = Number(y.getAttribute("x2")), w = m.find((T) => T.type === "ellipse");
      if (w) {
        const T = w.y, B = os(y, x, b, k, T);
        o.push(B);
      }
      const S = g.find((T) => T.type === "ellipse"), L = m.find((T) => T.type === "ellipse");
      S != null && S.id && (L != null && L.id) && (a[c.name] = {
        topId: S.id,
        bottomId: L.id,
        bindType: "ellipse"
      });
    }
  }), { nodes: s, lines: o, actorMap: a };
}, Sv = (e, t, r) => {
  const i = [], s = Array.from(t.querySelectorAll('[class*="messageLine"]')), o = Object.keys(dc), a = e.filter((n) => o.includes(n.type.toString()));
  return s.forEach((n, l) => {
    const h = a[l], c = dc[h.type], u = Cv(n, {
      label: h == null ? void 0 : h.message,
      strokeStyle: bv(h.type),
      endArrowhead: c === "SOLID_OPEN" || c === "DOTTED_OPEN" ? null : "arrow"
    }), p = r[h.from], d = r[h.to];
    p != null && p.topId && (d != null && d.topId) && (u.start = { type: p.bindType || "rectangle", id: p.topId }, u.end = { type: d.bindType || "rectangle", id: d.topId }), kv(n, u), i.push(u);
  }), i;
}, wv = (e, t) => {
  const r = Array.from(t.querySelectorAll(".note")).map((o) => o.parentElement), i = e.filter((o) => o.type === Me.NOTE), s = [];
  return r.forEach((o, a) => {
    if (!o)
      return;
    const n = o.firstChild, l = i[a].message, h = Ge(n, "rectangle", {
      label: { text: l },
      subtype: "note"
    }), c = n.getAttribute("fill"), u = n.getAttribute("stroke"), p = n.getAttribute("stroke-width"), d = n.getAttribute("stroke-dasharray");
    c && c !== "none" && (h.bgColor = ut(c)), u && u !== "none" && (h.strokeColor = ut(u)), p && (h.strokeWidth = Number(p)), d && d.trim() && (h.strokeStyle = "dashed"), s.push(h);
  }), s;
}, _v = (e) => {
  const t = Array.from(e.querySelectorAll("[class*=activation]")), r = [];
  return t.forEach((i) => {
    const s = Ge(i, "rectangle", {
      label: { text: "" },
      subtype: "activation"
    });
    (() => {
      const a = i.getAttribute("fill"), n = i.getAttribute("stroke"), l = i.getAttribute("stroke-width"), h = i.getAttribute("stroke-dasharray");
      a && a !== "none" && (s.bgColor = ut(a)), n && n !== "none" && (s.strokeColor = ut(n)), l && (s.strokeWidth = Number(l)), h && h.trim() && (s.strokeStyle = "dashed");
    })(), r.push(s);
  }), r;
}, Bv = (e, t) => {
  const r = Array.from(t.querySelectorAll(".loopLine")), i = [], s = [], o = [];
  r.forEach((c) => {
    const u = Number(c.getAttribute("x1")), p = Number(c.getAttribute("y1")), d = Number(c.getAttribute("x2")), g = Number(c.getAttribute("y2")), m = os(c, u, p, d, g);
    m.strokeStyle = "dotted", m.strokeColor = "#adb5bd", m.strokeWidth = 2, i.push(m);
  });
  const a = Array.from(t.querySelectorAll(".loopText")), n = e.filter((c) => c.type === Me.CRITICAL_START).map((c) => c.message);
  a.forEach((c) => {
    var m;
    const u = c.textContent || "", p = zm(c, u), d = ((m = u.match(/\[(.*?)\]/)) == null ? void 0 : m[1]) || "";
    n.includes(d) && (p.x += 16), s.push(p);
  });
  const l = Array.from(t == null ? void 0 : t.querySelectorAll(".labelBox")), h = Array.from(t == null ? void 0 : t.querySelectorAll(".labelText"));
  return l.forEach((c, u) => {
    var g;
    const p = ((g = h[u]) == null ? void 0 : g.textContent) || "", d = Ge(c, "rectangle", {
      label: { text: p }
    });
    d.strokeColor = "#adb5bd", d.bgColor = "#e9ecef", d.width = void 0, o.push(d);
  }), { lines: i, texts: s, nodes: o };
}, vv = (e) => {
  const t = Array.from(e.querySelectorAll(".rect")).filter((i) => {
    var s;
    return ((s = i.parentElement) == null ? void 0 : s.tagName) !== "g";
  }), r = [];
  return t.forEach((i) => {
    const s = Ge(i, "rectangle", {
      label: { text: "" },
      subtype: "highlight"
    });
    r.push(s);
  }), r;
}, Lv = (e, t) => {
  const r = e.db, i = [], o = r.getBoxes().map((y) => ({
    ...y,
    fill: ut(y.fill || "")
  })), a = vv(t), n = r.getActors(), { nodes: l, lines: h, actorMap: c } = Tv(n, t), u = r.getMessages(), p = Sv(u, t, c), d = wv(u, t), g = _v(t), m = Bv(u, t);
  return i.push(a), i.push(...l), i.push(d), i.push(g), { type: "sequence", lines: h, arrows: p, nodes: i, loops: m, groups: o };
}, Av = (e) => {
  const t = {};
  return e && e.forEach((r) => {
    fe(r).forEach(({ property: i, value: s }) => {
      i && s && (t[i] = ut(s));
    });
  }), t;
}, Ms = {
  AGGREGATION: 0,
  EXTENSION: 1,
  COMPOSITION: 2,
  DEPENDENCY: 3
}, gc = {
  LINE: 0,
  DOTTED_LINE: 1
}, mc = 16, Ev = (e) => {
  let t;
  switch (e) {
    case gc.LINE:
      t = "solid";
      break;
    case gc.DOTTED_LINE:
      t = "dotted";
      break;
    default:
      t = "solid";
  }
  return t;
}, yc = (e) => {
  let t;
  switch (e) {
    case Ms.AGGREGATION:
      t = "diamond_outline";
      break;
    case Ms.COMPOSITION:
      t = "diamond";
      break;
    case Ms.EXTENSION:
      t = "triangle_outline";
      break;
    case "none":
      t = null;
      break;
    case Ms.DEPENDENCY:
    default:
      t = "arrow";
      break;
  }
  return t;
}, pa = (e, t) => {
  let r = 0, i = 0, s = e;
  for (; s && s !== t; ) {
    const { transformX: o, transformY: a } = xr(s);
    r += o, i += a, s = s.parentElement;
  }
  return { tx: r, ty: i };
}, xc = /* @__PURE__ */ new Set([
  "triangle_outline",
  "diamond",
  "diamond_outline"
]), Hm = (e, t = 0.5) => {
  if (e.length <= 2)
    return [...e];
  const r = [e[0]];
  for (let i = 1; i < e.length - 1; i++) {
    const s = r[r.length - 1], o = e[i], a = e[i + 1], n = a.x - s.x, l = a.y - s.y, h = Math.hypot(n, l);
    if (!h)
      continue;
    const u = Math.abs(n * (o.y - s.y) - l * (o.x - s.x)) / h, p = ((o.x - s.x) * n + (o.y - s.y) * l) / (h * h);
    u <= t && p >= -t && p <= 1 + t || r.push(o);
  }
  return r.push(e[e.length - 1]), r;
}, Ym = (e) => {
  const t = mn(Ic(e).map((i) => [i.x, i.y])).map(([i, s]) => ({ x: i, y: s })), r = yn(e);
  return r && t.length >= 2 && (t[0] = {
    x: r.startX,
    y: r.startY
  }, t[t.length - 1] = {
    x: r.endX,
    y: r.endY
  }), Hm(t);
}, Cc = (e, t, r) => {
  const i = e.x - t.x, s = e.y - t.y, o = Math.hypot(i, s);
  return o ? {
    x: e.x + i / o * r,
    y: e.y + s / o * r
  } : e;
}, Fv = (e, t) => {
  const r = mn(t.map((o) => [o.x, o.y])).map(([o, a]) => ({ x: o, y: a }));
  if (r.length < 2)
    throw new Error("Arrow route must contain at least two points");
  const i = r[0], s = r[r.length - 1];
  e.startX = i.x, e.startY = i.y, e.endX = s.x, e.endY = s.y, e.points = r.map((o) => [
    o.x - i.x,
    o.y - i.y
  ]);
}, Mv = (e) => {
  var o;
  const t = (o = e.points) == null ? void 0 : o.map(([a, n]) => ({ x: e.startX + a, y: e.startY + n })).filter((a) => Number.isFinite(a.x) && Number.isFinite(a.y));
  if (!t || t.length < 2)
    return e;
  const r = [...t], i = !!e.startArrowhead && xc.has(e.startArrowhead), s = !!e.endArrowhead && xc.has(e.endArrowhead);
  if (!i && !s)
    return e;
  if (i && (r[0] = Cc(r[0], r[1], mc)), s) {
    const a = r.length - 1;
    r[a] = Cc(r[a], r[a - 1], mc);
  }
  return Fv(e, r), e;
}, Iv = (e, t) => {
  const r = ut(e.getAttribute("stroke") || getComputedStyle(e).stroke || ""), i = parseFloat(e.getAttribute("stroke-width") || getComputedStyle(e).strokeWidth || "1");
  ge(r) && r !== "none" && (t.strokeColor = r), Number.isFinite(i) && i > 0 && (t.strokeWidth = i);
}, $v = (e) => {
  const t = [];
  return e.forEach((r) => {
    Ym(r).forEach((i) => {
      const s = t[t.length - 1];
      s && s.x === i.x && s.y === i.y || t.push(i);
    });
  }), Hm(t);
}, Xm = (e, t, r) => {
  if (e.length < 2)
    throw new Error(`Class diagram edge ${(t == null ? void 0 : t.id) || "<unknown>"} is missing usable path points`);
  const i = e[0], s = e[e.length - 1], o = ml(i.x, i.y, s.x, s.y, {
    id: (t == null ? void 0 : t.getAttribute("data-id")) || (t == null ? void 0 : t.id) || void 0,
    ...r,
    points: e.map((a) => [
      a.x - i.x,
      a.y - i.y
    ])
  });
  return t && Iv(t, o), Mv(o);
}, Um = (e, t) => Xm($v(e), e[0], t), Ov = (e, t) => {
  const r = Ym(e);
  return Xm([r[0], r[r.length - 1]], e, t);
}, Dv = (e, t) => Um([e], t), Rv = (e, t) => [
  `${e}-cyclic-special-1`,
  `${e}-cyclic-special-mid`,
  `${e}-cyclic-special-2`
].map((i) => t.querySelector(`path[id="${i}"][data-edge="true"]`)).filter((i) => i !== null), Pv = (e) => {
  var t;
  return ((t = e.points) == null ? void 0 : t.map(([r, i]) => ({ x: e.startX + r, y: e.startY + i })).filter((r) => Number.isFinite(r.x) && Number.isFinite(r.y))) || [];
}, bc = (e, t) => {
  const r = Pv(e);
  if (r.length < 2)
    return null;
  const i = t === "start", s = i ? r[0] : r[r.length - 1], o = i ? r[1] : r[r.length - 2], a = o.x === s.x ? i ? -1 : 1 : Math.sign(o.x - s.x), n = o.y === s.y ? 1 : Math.sign(o.y - s.y);
  return {
    x: s.x + a * 20,
    y: s.y + (n >= 0 ? 12 : -28)
  };
}, Nv = (e, t) => {
  let r = e;
  for (; r && r !== t; ) {
    if (r.classList.contains("annotation-group") || r.classList.contains("label-group"))
      return "header";
    if (r.classList.contains("members-group"))
      return "members";
    if (r.classList.contains("methods-group"))
      return "methods";
    r = r.parentElement;
  }
  return "other";
}, qv = (e, t, r) => {
  const i = [], s = [], o = [];
  return Object.values(e).forEach((a) => {
    var D;
    const { domId: n, id: l } = a, h = ue(), c = Av(
      // @ts-ignore
      a.styles || a.cssStyles
    );
    let u;
    try {
      u = r ? r(l) : void 0;
    } catch {
      u = void 0;
    }
    const p = (v) => {
      const R = new RegExp(`^classId-${v}(?:-|$)`);
      return Array.from(t.querySelectorAll("[id]")).filter((X) => R.test(X.id))[0];
    }, d = u && t.querySelector(`#${u}`) || t.querySelector(`#${n}`) || t.querySelector(`[data-id='${l}']`) || p(l);
    if (!d)
      throw Error(`DOM Node with id ${n} not found`);
    const g = d.querySelector("rect") || d, m = g.getBBox(), { tx: y, ty: x } = pa(g, t), b = {
      type: "rectangle",
      id: l,
      groupId: h,
      x: m.x + y,
      y: m.y + x,
      width: m.width,
      height: m.height,
      metadata: { classId: l }
    }, k = g.getAttribute("fill"), w = g.getAttribute("stroke"), S = g.getAttribute("stroke-width"), L = g.getAttribute("stroke-dasharray"), T = getComputedStyle(g), B = ut(k || c.fill || (k ? T.fill : "")), N = ut(w || c.stroke || (w ? T.stroke : "")), O = S || c["stroke-width"] || (S ? T.strokeWidth : ""), F = L || c["stroke-dasharray"] || (L ? T.strokeDasharray === "none" ? "" : T.strokeDasharray : ""), Y = (v) => {
      if (!v || !ge(v))
        return !1;
      const R = v.toLowerCase();
      return !(R === "none" || R === "transparent" || R === "rgba(0, 0, 0, 0)" || R === "black" || R === "#000" || R === "#000000" || R === "rgb(0, 0, 0)" || R === "rgba(0, 0, 0, 1)");
    };
    Y(B) ? b.bgColor = B : b.bgColor = void 0, Y(N) ? b.strokeColor = N : b.strokeColor = void 0, O ? b.strokeWidth = Number(O) : b.strokeWidth = void 0, F && F.trim().length > 0 ? b.strokeStyle = "dashed" : b.strokeStyle = void 0, i.push(b), [
      ...Array.from(d.querySelectorAll("line")),
      ...Array.from(d.querySelectorAll("g.divider path"))
    ].forEach((v) => {
      const { tx: R, ty: z } = pa(v, t);
      let X, ot, tt, st;
      if (v.tagName.toLowerCase() === "line")
        X = Number(v.getAttribute("x1")) + R, ot = Number(v.getAttribute("y1")) + z, tt = Number(v.getAttribute("x2")) + R, st = Number(v.getAttribute("y2")) + z;
      else {
        const dt = v.getBBox();
        X = dt.x + R, tt = dt.x + dt.width + R;
        const xt = dt.y + dt.height / 2 + z;
        ot = xt, st = xt;
      }
      if (X === tt && ot === st)
        return;
      const j = os(
        // @ts-ignore
        v,
        X,
        ot,
        tt,
        st,
        {
          groupId: h,
          id: ue()
        }
      );
      b.strokeColor ? j.strokeColor = b.strokeColor : j.strokeColor = void 0, b.strokeWidth !== void 0 ? j.strokeWidth = b.strokeWidth : j.strokeWidth = void 0, b.strokeStyle ? j.strokeStyle = b.strokeStyle : j.strokeStyle = void 0, j.metadata = { classId: l }, s.push(j);
    });
    const P = Array.from(d.querySelectorAll("text, foreignObject")), M = [];
    P.forEach((v) => {
      var dt;
      const R = v.tagName.toLowerCase() === "foreignobject", z = R ? [] : Array.from(v.querySelectorAll("tspan")), X = z.length ? z.map((xt) => {
        var _t;
        return (_t = xt.textContent) == null ? void 0 : _t.trim();
      }).filter(Boolean).join(`
`) : ((dt = v.textContent) == null ? void 0 : dt.trim()) || "";
      if (!X)
        return;
      const ot = v.getBBox(), { ty: tt } = pa(v, t);
      let st = parseFloat(getComputedStyle(v).fontSize || "");
      if (R && (!Number.isFinite(st) || !st)) {
        const xt = v.querySelector("div, span, p");
        xt && (st = parseFloat(getComputedStyle(xt).fontSize || ""));
      }
      (!Number.isFinite(st) || st <= 0) && (st = Math.max(12, ot.height * 0.6)), st = st * 0.9;
      const j = pl(v, c.color);
      M.push({
        section: Nv(v, d),
        text: ie(X),
        x: ot.x,
        y: ot.y + tt,
        width: b && b.width ? Math.max(b.width - 8, ot.width) : ot.width,
        height: ot.height,
        fontSize: st,
        color: j
      });
    });
    const E = M.filter((v) => v.section === "header").sort((v, R) => v.y - R.y || v.x - R.x);
    if (!b.label) {
      const v = E.length === 0 && M.length === 1 ? M : E;
      v.length > 0 && (b.label = {
        text: v.map((R) => R.text).join(`
`),
        fontSize: Math.max(...v.map((R) => R.fontSize)),
        color: (D = v.find((R) => R.color)) == null ? void 0 : D.color,
        verticalAlign: "top"
      });
    }
    M.filter((v) => E.length > 0 ? v.section !== "header" : !(b.label && M.length === 1)).forEach((v) => {
      const R = bo(((b == null ? void 0 : b.x) || 0) + 4, v.y, v.text, {
        width: v.width,
        height: v.height,
        fontSize: v.fontSize,
        color: v.color,
        id: ue(),
        groupId: h,
        metadata: { classId: l }
      });
      o.push(R);
    });
  }), { nodes: i, lines: s, text: o };
}, Wv = (e, t, r, i) => {
  const s = Array.from(r.querySelectorAll('.edgePaths path[data-edge="true"]:not([id^="edgeNote"]):not([id*="-cyclic-special-"])'));
  if (e.length === 0)
    return { arrows: [], text: [] };
  const o = [], a = [];
  let n = 0;
  return e.forEach((l) => {
    const { id1: h, id2: c, relation: u } = l, p = t.find((O) => O.id === h), d = t.find((O) => O.id === c);
    if (!p)
      throw new Error(`parseRelations: Cannot find node with id ${h}`);
    if (!d)
      throw new Error(`parseRelations: Cannot find node with id ${c}`);
    const g = Ev(u.lineType), m = yc(u.type1), y = yc(u.type2);
    let x;
    if (h === c) {
      const O = Rv(h, r);
      if (!O.length)
        throw new Error(`parseRelations: Cannot find rendered SVG edge for relation ${h} -> ${c}`);
      x = Um(O, {
        strokeStyle: g,
        startArrowhead: m,
        endArrowhead: y,
        label: l.title ? { text: l.title } : void 0,
        start: { type: "rectangle", id: p.id },
        end: { type: "rectangle", id: d.id }
      });
    } else {
      const O = s[n];
      if (!O)
        throw new Error(`parseRelations: Cannot find rendered SVG edge for relation ${h} -> ${c}`);
      n += 1, x = Ov(O, {
        strokeStyle: g,
        startArrowhead: m,
        endArrowhead: y,
        label: l.title ? { text: l.title } : void 0,
        start: { type: "rectangle", id: p.id },
        end: { type: "rectangle", id: d.id }
      });
    }
    o.push(x);
    const { relationTitle1: b, relationTitle2: k } = l, w = h === c, S = 20, L = 15, T = 15;
    let B, N;
    if (b && b !== "none") {
      if (w) {
        const F = bc(x, "start");
        F && (B = F.x, N = F.y);
      } else
        switch (i) {
          case "TB":
            B = x.startX - S, x.endX < x.startX && (B -= T), N = x.startY + L;
            break;
          case "BT":
            B = x.startX + S, x.endX > x.startX && (B += T), N = x.startY - L;
            break;
          case "LR":
            B = x.startX + S, N = x.startY + L, x.endY > x.startY && (N += T);
            break;
          case "RL":
            B = x.startX - S, N = x.startY - L, x.startY > x.endY && (N -= T);
            break;
          default:
            B = x.startX - S, N = x.startY + L;
        }
      B ?? (B = x.startX - S), N ?? (N = x.startY + L);
      const O = bo(B, N, b, {
        fontSize: 16
      });
      a.push(O);
    }
    if (k && k !== "none") {
      if (w) {
        const F = bc(x, "end");
        F && (B = F.x, N = F.y);
      } else
        switch (i) {
          case "TB":
            B = x.endX + S, x.endX < x.startX && (B += T), N = x.endY - L;
            break;
          case "BT":
            B = x.endX - S, x.endX > x.startX && (B -= T), N = x.endY + L;
            break;
          case "LR":
            B = x.endX - S, N = x.endY - L, x.endY > x.startY && (N -= T);
            break;
          case "RL":
            B = x.endX + S, N = x.endY + L, x.startY > x.endY && (N += T);
            break;
          default:
            B = x.endX + S, N = x.endY - L;
        }
      B ?? (B = x.endX + S), N ?? (N = x.endY + L);
      const O = bo(B, N, k, {
        fontSize: 16
      });
      a.push(O);
    }
  }), { arrows: o, text: a };
}, zv = (e, t, r) => {
  const i = [], s = [];
  return e.forEach((o, a) => {
    const { id: n, text: l, class: h } = o, c = t.querySelector(`#${n}`);
    if (!c)
      throw new Error(`Node with id ${n} not found!`);
    const { transformX: u, transformY: p } = xr(c), d = c.firstChild, g = Ge(d, "rectangle", {
      id: n,
      subtype: "note",
      label: { text: l }
    });
    if (Object.assign(g, {
      x: g.x + u,
      y: g.y + p
    }), i.push(g), h) {
      const m = r.find((L) => L.id === h);
      if (!m)
        throw new Error(`class node with id ${h} not found!`);
      const y = t.querySelector(`path[id="edgeNote${a + 1}"][data-edge="true"]`);
      if (y) {
        s.push(Dv(y, {
          strokeStyle: "dotted",
          startArrowhead: null,
          endArrowhead: null,
          start: { id: g.id, type: "rectangle" },
          end: { id: m.id, type: "rectangle" }
        }));
        return;
      }
      const x = g.x + (g.width || 0) / 2, b = g.y + (g.height || 0), k = x, w = m.y, S = ml(x, b, k, w, {
        strokeStyle: "dotted",
        startArrowhead: null,
        endArrowhead: null,
        start: { id: g.id, type: "rectangle" },
        end: { id: m.id, type: "rectangle" }
      });
      s.push(S);
    }
  }), { notes: i, connectors: s };
}, Hv = (e, t) => {
  var x, b, k, w, S;
  const r = e.db, i = ((x = r.getDirection) == null ? void 0 : x.call(r)) || "TB", s = [], o = [], a = [], n = [], l = ((b = r.getNamespaces) == null ? void 0 : b.call(r)) || [], h = ((k = r.getClasses) == null ? void 0 : k.call(r)) || {}, c = h instanceof Map ? Object.fromEntries(h) : h;
  if (c && Object.keys(c).length) {
    const L = (
      //@ts-ignore
      typeof r.lookUpDomId == "function" ? (
        //@ts-ignore
        r.lookUpDomId.bind(r)
      ) : void 0
    ), T = qv(c, t, L);
    s.push(T.nodes), o.push(...T.lines), a.push(...T.text), n.push(...T.nodes);
  }
  const u = ((w = r.getRelations) == null ? void 0 : w.call(r)) || [], { arrows: p, text: d } = Wv(u, n, t, i), g = ((S = r.getNotes) == null ? void 0 : S.call(r)) || [], { notes: m, connectors: y } = zv(g, t, n);
  return s.push(m), p.push(...y), a.push(...d), { type: "class", nodes: s, lines: o, arrows: p, text: a, namespaces: l };
}, kc = 18, Yv = (e) => {
  const t = {};
  return e && e.forEach((r) => {
    fe(r).forEach(({ property: i, value: s }) => {
      i && s && (t[i] = ut(s));
    });
  }), t;
}, Xv = (e) => {
  if (e == null || e === "")
    return;
  const t = typeof e == "number" ? e : parseFloat(ut(e));
  if (!(!Number.isFinite(t) || t <= 0))
    return t;
}, yl = (e, t) => {
  let r = 0, i = 0, s = e;
  for (; s && s !== t; ) {
    const { transformX: o, transformY: a } = xr(s);
    r += o, i += a, s = s.parentElement;
  }
  return { tx: r, ty: i };
}, Uv = (e) => {
  var i;
  const t = Array.from(e.querySelectorAll("tspan")), r = t.length ? t.map((s) => {
    var o;
    return (o = s.textContent) == null ? void 0 : o.trim();
  }).filter(Boolean).join(`
`) : ((i = e.textContent) == null ? void 0 : i.trim()) || "";
  return ie(r);
}, jv = (e) => {
  const t = e.querySelector("text, foreignObject, div, span, p") || e;
  let r = parseFloat(getComputedStyle(t).fontSize || "");
  return (!Number.isFinite(r) || r <= 0) && (r = Math.max(12, e.getBBox().height * 0.75)), r;
}, Gv = (e, t, r) => {
  const i = Uv(e);
  if (!i)
    return null;
  const s = e.getBBox(), { tx: o, ty: a } = yl(e, t);
  return {
    className: e.getAttribute("class") || "",
    text: i,
    x: s.x + o,
    y: s.y + a,
    width: s.width,
    height: s.height,
    fontSize: jv(e),
    color: pl(e, r)
  };
}, Vv = (e, t, r, i, s, o, a) => {
  const { tx: n, ty: l } = yl(e, t);
  let h = 0, c = 0, u = 0, p = 0;
  if (e.tagName.toLowerCase() === "line")
    h = Number(e.getAttribute("x1")) + n, c = Number(e.getAttribute("y1")) + l, u = Number(e.getAttribute("x2")) + n, p = Number(e.getAttribute("y2")) + l;
  else {
    const g = yn(e);
    if (!g)
      return null;
    h = g.startX + n, c = g.startY + l, u = g.endX + n, p = g.endY + l;
  }
  const d = {
    type: "line",
    id: ue(),
    groupId: r,
    startX: h,
    startY: c,
    endX: u,
    endY: p,
    metadata: { entityId: i }
  };
  return s && ge(s) && s !== "none" && (d.strokeColor = s), o !== void 0 && (d.strokeWidth = o), a && (d.strokeStyle = a), d;
}, Tc = (e) => {
  switch (e == null ? void 0 : e.toLowerCase()) {
    case "one":
      return "cardinality_one";
    case "many":
      return "cardinality_many";
    case "only_one":
      return "cardinality_exactly_one";
    case "one_or_more":
      return "cardinality_one_or_many";
    case "zero_or_one":
      return "cardinality_zero_or_one";
    case "zero_or_more":
      return "cardinality_zero_or_many";
    default:
      return null;
  }
}, Zv = (e) => {
  switch (e) {
    case "dotted":
      return "dotted";
    case "dashed":
      return "dashed";
    default:
      return "solid";
  }
}, Kv = (e, t) => {
  const r = t.querySelector(`path[id="${e.id}"][data-edge="true"]`);
  return r ? [r] : e.start !== e.end ? [] : [
    `${e.start}-cyclic-special-1`,
    `${e.start}-cyclic-special-mid`,
    `${e.start}-cyclic-special-2`
  ].map((s) => t.querySelector(`path[id="${s}"][data-edge="true"]`)).filter((s) => s !== null);
}, Qv = (e) => {
  const t = [];
  return e.forEach((r) => {
    Ic(r).forEach((i) => {
      const s = t[t.length - 1];
      s && s.x === i.x && s.y === i.y || t.push(i);
    });
  }), t;
}, Jv = (e, t) => {
  const r = t.querySelector(`[id="${e.id}"]`);
  if (!r)
    throw new Error(`ER entity ${e.id} not found in rendered SVG`);
  const i = e.attributes.length ? ue() : void 0, s = r.getBBox(), { tx: o, ty: a } = yl(r, t), n = Yv([
    ...e.cssStyles || [],
    ...e.cssCompiledStyles || []
  ]), l = ut(n.fill || ""), h = ut(n.stroke || ""), c = Xv(n["stroke-width"]), u = ut(n["stroke-dasharray"] || ""), p = Array.from(r.querySelectorAll("g.label")).map((k) => Gv(k, t, n.color)).filter((k) => k !== null), d = p.find((k) => k.className.includes("name")) || p[0], g = p.filter((k) => k !== d), m = (d == null ? void 0 : d.text) || ie(e.alias || e.label || ""), y = {
    type: "rectangle",
    id: e.id,
    groupId: i,
    x: s.x + o,
    y: s.y + a,
    width: s.width,
    height: s.height,
    label: {
      text: m,
      fontSize: e.attributes.length ? kc : (d == null ? void 0 : d.fontSize) || 16,
      color: d == null ? void 0 : d.color,
      textAlign: "center",
      verticalAlign: e.attributes.length ? "top" : "middle"
    },
    metadata: {
      entityId: e.id,
      entityLabel: e.label,
      entityAlias: e.alias
    }
  };
  ge(l) && l !== "none" && (y.bgColor = l), ge(h) && h !== "none" && (y.strokeColor = h), c && Number.isFinite(c) && c > 0 && (y.strokeWidth = c), u && u !== "none" && (y.strokeStyle = "dashed");
  const x = Array.from(r.querySelectorAll(".divider path, path.divider, line.divider")).map((k) => Vv(k, t, i, e.id, y.strokeColor, y.strokeWidth, y.strokeStyle)).filter((k) => k !== null), b = g.map((k) => bo(k.x, k.y, k.text, {
    id: ue(),
    groupId: i,
    width: k.width,
    height: k.height,
    fontSize: kc,
    color: k.color,
    metadata: { entityId: e.id }
  }));
  return { container: y, lines: x, text: b };
}, tL = (e, t) => {
  const r = Kv(e, t);
  if (!r.length)
    throw new Error(`ER relationship ${e.id} not found in rendered SVG`);
  const i = Qv(r);
  if (i.length < 2)
    throw new Error(`ER relationship ${e.id} is missing usable path points`);
  const s = i[0], o = i[i.length - 1], a = r[0], n = ut(a.getAttribute("stroke") || getComputedStyle(a).stroke || ""), l = Number(a.getAttribute("stroke-width") || getComputedStyle(a).strokeWidth || 1), h = ml(s.x, s.y, o.x, o.y, {
    id: e.id,
    label: e.label ? {
      text: ie(e.label),
      fontSize: 16,
      textAlign: "center"
    } : void 0,
    strokeStyle: Zv(e.pattern),
    startArrowhead: Tc(e.arrowTypeStart),
    endArrowhead: Tc(e.arrowTypeEnd),
    start: { type: "rectangle", id: e.start },
    end: { type: "rectangle", id: e.end },
    points: i.map((c) => [
      c.x - s.x,
      c.y - s.y
    ])
  });
  return ge(n) && n !== "none" && (h.strokeColor = n), Number.isFinite(l) && l > 0 && (h.strokeWidth = l), h;
}, eL = (e, t) => {
  const r = e.getData(), i = r.nodes, s = r.edges, o = [], a = [], n = [];
  i.forEach((h) => {
    const c = Jv(h, t);
    o.push(c.container), a.push(...c.lines), n.push(...c.text);
  });
  const l = s.map((h) => tL(h, t));
  return {
    type: "erd",
    nodes: [o],
    lines: a,
    arrows: l,
    text: n
  };
}, Lr = (e) => {
  const t = ut(e || "");
  return !t || t === "none" || t === "transparent" || t === "rgba(0, 0, 0, 0)" || t === "rgba(0,0,0,0)" ? !1 : ge(t);
}, jm = (e, t, r) => {
  switch (t) {
    case ft.FILL:
    case ft.STROKE:
      Lr(r) && (e[t] = ut(r));
      break;
    case ft.STROKE_WIDTH:
    case ft.STROKE_DASHARRAY:
      ut(r) && (e[t] = ut(r));
      break;
  }
}, Gm = (e, t, r) => {
  t === jt.COLOR && Lr(r) && (e[jt.COLOR] = ut(r));
}, rL = (e, t, r) => {
  e && fe(e).forEach(({ property: i, value: s }) => {
    jm(t, i, s), Gm(r, i, s);
  });
}, iL = (e, t) => {
  e && fe(e).forEach(({ property: r, value: i }) => {
    if (r === ft.FILL && Lr(i)) {
      t[jt.COLOR] = ut(i);
      return;
    }
    Gm(t, r, i);
  });
}, sL = (e) => {
  const t = /* @__PURE__ */ new Set();
  return e.filter(Boolean).forEach((r) => {
    fe(r || "").forEach(({ property: i }) => {
      t.add(i);
    });
  }), t;
}, oL = (e, t, r) => {
  if (!e)
    return;
  [
    [ft.FILL, e.getAttribute("fill")],
    [ft.STROKE, e.getAttribute("stroke")],
    [
      ft.STROKE_WIDTH,
      e.getAttribute("stroke-width")
    ],
    [
      ft.STROKE_DASHARRAY,
      e.getAttribute("stroke-dasharray")
    ]
  ].forEach(([s, o]) => {
    if (!r.has(s) || t[s])
      return;
    const a = ut(o || "");
    a && jm(t, s, a);
  });
}, aL = (e, t, r) => {
  if (!e)
    return;
  const i = [
    e,
    ...Array.from(e.querySelectorAll("text, foreignObject, div, span, p"))
  ];
  for (const s of i) {
    if (t[jt.COLOR] || (r.has(jt.COLOR) || r.has(ft.FILL)) && (iL(s.getAttribute("style"), t), t[jt.COLOR]))
      break;
    const o = ut(s.getAttribute("fill") || s.getAttribute("color") || "");
    (r.has(jt.COLOR) || r.has(ft.FILL)) && Lr(o) && (t[jt.COLOR] = o);
  }
}, xl = (e, t) => {
  let r = 0, i = 0, s = e;
  for (; s && s !== t; ) {
    const { transformX: o, transformY: a } = xr(s);
    r += o, i += a, s = s.parentElement;
  }
  return { tx: r, ty: i };
}, nL = (e, t) => {
  const r = e.getBBox(), { tx: i, ty: s } = xl(e, t);
  return {
    x: r.x + i,
    y: r.y + s,
    width: r.width,
    height: r.height
  };
}, lL = (e, t) => {
  const r = e.querySelector("line.divider");
  if (!r)
    return;
  const { tx: i, ty: s } = xl(r, t);
  return {
    startX: Number(r.getAttribute("x1")) + i,
    startY: Number(r.getAttribute("y1")) + s,
    endX: Number(r.getAttribute("x2")) + i,
    endY: Number(r.getAttribute("y2")) + s
  };
}, hL = (e) => {
  const t = e.getBBox();
  return Math.abs(t.width * t.height);
}, Sc = (e, t) => {
  const r = e.getAttribute("style");
  if (!r)
    return;
  const i = fe(r).find((s) => s.property === t);
  if (i)
    return ut(i.value);
}, dn = (e, t) => {
  const r = e.map((s) => ({ element: s, area: hL(s) })).filter(({ area: s }) => Number.isFinite(s) && s > 0);
  return r.length === 0 ? null : r.sort((s, o) => t === "largest" ? o.area - s.area : s.area - o.area)[0].element;
}, cL = (e, t) => {
  if (!e || !t.has(ft.FILL) && !t.has(ft.STROKE))
    return;
  const r = ut(e.getAttribute("fill") || Sc(e, ft.FILL) || ""), i = ut(e.getAttribute("stroke") || Sc(e, ft.STROKE) || "");
  if (Lr(r))
    return r;
  if (Lr(i))
    return i;
}, uL = (e, t) => {
  const r = Array.from(e.querySelectorAll("circle, ellipse, path")), i = dn(r, "smallest");
  return cL(i, t);
}, dL = (e) => {
  if (e.length < 2)
    return e;
  const t = e.slice(1), r = t.filter((i) => i.trim().length > 0).reduce((i, s) => {
    var a;
    const o = ((a = s.match(/^\s*/)) == null ? void 0 : a[0].length) ?? 0;
    return Math.min(i, o);
  }, Number.POSITIVE_INFINITY);
  return !Number.isFinite(r) || r <= 0 ? e.map((i) => i.trimEnd()) : [
    e[0].trimEnd(),
    ...t.map((i) => i.replace(new RegExp(`^\\s{0,${r}}`), "").trimEnd())
  ];
}, pL = (e) => {
  const t = Array.isArray(e.label) ? e.label.map((i) => ie(i)) : ie(e.label || "").split(`
`);
  return dL(t).join(`
`);
}, fL = (e) => e.description ? (Array.isArray(e.description) ? e.description : [e.description]).map((r) => ie(r)).filter((r) => r.length > 0) : [], gL = (e) => {
  const t = /* @__PURE__ */ new Set(), r = (s) => (s && t.add(s), s), i = (s) => {
    const o = s.find((a) => !t.has(a));
    return r(o || null);
  };
  return (s) => {
    const o = [
      `[id='${s.domId}']`,
      `[id='${s.id}']`,
      `[data-id='${s.id}']`
    ];
    for (const a of o) {
      const n = e.querySelector(a);
      if (n)
        return r(n);
    }
    switch (s.shape) {
      case "divider":
        return i(Array.from(e.querySelectorAll("g.statediagram-cluster-alt")));
      case "stateStart":
        return i(Array.from(e.querySelectorAll("g.node.default")).filter((a) => a.querySelector("circle.state-start")));
      case "stateEnd":
        return i(Array.from(e.querySelectorAll("g.node.default")).filter((a) => !a.querySelector("circle.state-start")));
      default:
        return null;
    }
  };
}, mL = (e, t) => {
  switch (t) {
    case "roundedWithTitle":
      return e.querySelector("rect.outer") || e.querySelector("rect") || e;
    case "divider":
      return e.querySelector("rect.divider") || e.querySelector("rect") || e;
    case "rectWithTitle":
      return e.querySelector("rect.outer") || e.querySelector("rect") || e;
    case "stateStart":
      return dn(Array.from(e.querySelectorAll("circle, ellipse, path")), "largest") || e;
    case "stateEnd":
      return dn(Array.from(e.querySelectorAll("circle, ellipse, path")), "largest") || e;
    case "choice":
    case "fork":
    case "join":
    case "note":
    case "rect":
    default:
      return e.querySelector("rect, path, circle, ellipse, polygon") || e;
  }
}, yL = (e, t, r) => {
  const i = r(e);
  if (!i)
    throw new Error(`State node element not found for "${e.id}"`);
  const s = mL(i, e.shape), o = {}, a = {}, n = [
    e.labelStyle,
    ...e.cssCompiledStyles || [],
    ...e.cssStyles || []
  ], l = sL(n);
  n.filter(Boolean).forEach((c) => {
    rL(c, o, a);
  }), oL(s, o, l), aL(i, a, l);
  const h = nL(s, t);
  return {
    id: e.id,
    shape: e.shape,
    text: pL(e),
    description: fL(e),
    x: h.x,
    y: h.y,
    width: h.width,
    height: h.height,
    parentId: e.parentId,
    position: e.position,
    containerStyle: o,
    labelStyle: a,
    dividerLine: e.shape === "rectWithTitle" ? lL(i, t) : void 0,
    endInnerColor: e.shape === "stateEnd" ? uL(i, l) : void 0,
    isRenderable: e.shape !== "noteGroup"
  };
}, xL = (e, t) => {
  var h;
  const r = t.querySelector(`[id='${e.id}']`);
  if (!r)
    return null;
  const { tx: i, ty: s } = xl(r, t), o = $c(r, { x: i, y: s }, "MCL");
  if (o.reflectionPoints.length < 2)
    return null;
  const a = {}, n = (c, u) => {
    switch (c) {
      case ft.STROKE:
        Lr(u) && (a.strokeColor = ut(u));
        break;
      case ft.STROKE_WIDTH: {
        const p = parseFloat(ut(u));
        Number.isFinite(p) && p > 0 && (a.strokeWidth = p);
        break;
      }
      case ft.STROKE_DASHARRAY:
        ut(u) && (a.strokeStyle = "dashed");
        break;
    }
  };
  [e.style].filter(Boolean).forEach((c) => {
    fe(c || "").forEach(({ property: u, value: p }) => {
      n(u, p);
    });
  });
  const l = e.arrowhead === "none" || ((h = e.classes) == null ? void 0 : h.includes("note-edge"));
  return {
    id: e.id,
    start: e.start,
    end: e.end,
    text: ie(e.label || ""),
    ...o,
    strokeColor: a.strokeColor,
    strokeWidth: a.strokeWidth,
    strokeStyle: l ? "dashed" : a.strokeStyle,
    isNoteEdge: l
  };
}, CL = (e, t) => {
  const { nodes: r, edges: i } = e.getData(), s = gL(t);
  return {
    type: "state",
    nodes: r.map((o) => yL(o, t, s)),
    edges: i.map((o) => xL(o, t)).filter((o) => o !== null)
  };
};
let wc = Promise.resolve();
const bL = (e) => {
  const t = wc.then(e, e);
  return wc = t.then(() => {
  }, () => {
  }), t;
};
let _c = null, kL = 0;
const TL = (e) => JSON.stringify(e), Bc = (e) => {
  const t = e.querySelector("svg");
  if (!t)
    throw new Error("SVG element not found");
  const r = t.getBoundingClientRect(), i = r.width, s = r.height;
  t.setAttribute("width", `${i}`), t.setAttribute("height", `${s}`);
  const o = "image/svg+xml", a = unescape(encodeURIComponent(t.outerHTML)), l = `data:image/svg+xml;base64,${btoa(a)}`;
  return {
    type: "graphImage",
    mimeType: o,
    dataURL: l,
    width: i,
    height: s
  };
}, SL = async (e, t = bs) => bL(async () => {
  var h, c;
  const r = ((h = t.themeVariables) == null ? void 0 : h.fontSize) ?? bs.themeVariables.fontSize, i = {
    ...bs,
    ...t,
    fontSize: r,
    themeVariables: {
      ...bs.themeVariables,
      ...t.themeVariables,
      fontSize: r
    }
  }, s = TL(i);
  s !== _c && (ua.initialize(i), _c = s);
  const o = await ua.mermaidAPI.getDiagramFromText(Hy(e)), a = `mermaid-to-excalidraw-${kL++}`, n = document.createElement("div");
  n.setAttribute("style", "opacity: 0; position: fixed; z-index: -1; left: -99999px; top: -99999px;");
  const l = `${a}-container`;
  n.id = l, (c = document.getElementById(l)) == null || c.remove(), document.body.appendChild(n);
  try {
    const { svg: u } = await ua.render(a, e, n);
    n.innerHTML = u;
    let p;
    try {
      switch (o.type) {
        case "flowchart-v2":
        case "graph": {
          p = xv(o.db, n);
          break;
        }
        case "sequence": {
          p = Lv(o, n);
          break;
        }
        case "class":
        case "classDiagram": {
          p = Hv(o, n);
          break;
        }
        case "er": {
          p = eL(o.db, n);
          break;
        }
        case "state":
        case "stateDiagram": {
          p = CL(o.db, n);
          break;
        }
        default:
          p = Bc(n);
      }
    } catch (d) {
      console.error("Error processing Mermaid diagram:", d), p = Bc(n);
    }
    return p;
  } finally {
    n.remove();
  }
}), wL = async (e, t) => {
  var a;
  const r = t || {}, i = parseInt(((a = r.themeVariables) == null ? void 0 : a.fontSize) ?? "") || as, s = await SL(e, {
    ...r,
    themeVariables: {
      ...r.themeVariables
    }
  });
  return jy(s, {
    fontSize: i
  });
}, tA = /* @__PURE__ */ Object.freeze(/* @__PURE__ */ Object.defineProperty({
  __proto__: null,
  parseMermaidToExcalidraw: wL
}, Symbol.toStringTag, { value: "Module" }));
export {
  ji as $,
  xC as A,
  $L as B,
  Qy as C,
  wt as D,
  BC as E,
  Zn as F,
  Xc as G,
  B2 as H,
  o1 as I,
  u2 as J,
  Uk as K,
  kh as L,
  bh as M,
  HL as N,
  PL as O,
  WL as P,
  qL as Q,
  DL as R,
  Mn as S,
  zL as T,
  RL as U,
  Or as V,
  XL as W,
  YL as X,
  NL as Y,
  Ex as Z,
  f as _,
  bC as a,
  ML as a0,
  Ao as a1,
  y2 as a2,
  aC as a3,
  tu as a4,
  eh as a5,
  Zk as a6,
  Ia as a7,
  _2 as a8,
  fC as a9,
  qT as aA,
  Ln as aB,
  Qe as aC,
  Zi as aD,
  fh as aE,
  Bb as aF,
  K as aG,
  Hp as aH,
  re as aI,
  Cb as aJ,
  vn as aK,
  mu as aL,
  cs as aM,
  Cu as aN,
  OL as aO,
  Ky as aP,
  tA as aQ,
  ru as aa,
  QT as ab,
  Pg as ac,
  ZL as ad,
  p2 as ae,
  Kt as af,
  Ze as ag,
  vi as ah,
  Kn as ai,
  Pp as aj,
  _r as ak,
  zp as al,
  tw as am,
  VL as an,
  KL as ao,
  jL as ap,
  Q as aq,
  GL as ar,
  AS as as,
  wS as at,
  SS as au,
  HT as av,
  jk as aw,
  FL as ax,
  ps as ay,
  WT as az,
  CC as b,
  gt as c,
  ct as d,
  eu as e,
  $t as f,
  TC as g,
  je as h,
  we as i,
  m2 as j,
  ls as k,
  q as l,
  qp as m,
  ns as n,
  IL as o,
  JL as p,
  SC as q,
  QL as r,
  kC as s,
  wC as t,
  ke as u,
  d2 as v,
  A2 as w,
  xS as x,
  UL as y,
  ni as z
};
